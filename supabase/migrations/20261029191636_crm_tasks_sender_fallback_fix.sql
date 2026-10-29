set check_function_bodies = off;

CREATE OR REPLACE FUNCTION crm.sweep_task_reminders()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_task crm.tasks;
  v_whatsapp_address text;
  v_sender_address text;
  v_template_lang text;
  v_conversation_id uuid;
  v_message_id uuid;
begin
  for v_task in
    select * from crm.tasks
    where due_at <= now() and completed_at is null and reminder_sent_at is null
      and assigned_to is not null
  loop
    v_whatsapp_address := null;
    v_sender_address := null;
    v_template_lang := null;
    v_conversation_id := null;
    v_message_id := null;

    perform crm._create_notification(
      v_task.organization_id, v_task.assigned_to, 'task_due',
      'Task due', v_task.title, v_task.lead_id
    );

    select mr.whatsapp_address into v_whatsapp_address
    from crm.member_roles mr where mr.agent_id = v_task.assigned_to;

    if v_whatsapp_address is not null then
      select ((select r.value from crm.resolve_setting(
        v_task.organization_id, 'notifications.whatsapp_sender_address'
      ) r) #>> '{}')
      into v_sender_address;

      if v_sender_address is null or v_sender_address = '' then
        select oa.address into v_sender_address
        from public.organizations_addresses oa
        where oa.organization_id = v_task.organization_id
          and oa.service = 'whatsapp' and oa.status = 'connected'
        order by oa.created_at asc
        limit 1;
      end if;
    end if;

    if v_sender_address is not null then
      select t.language into v_template_lang
      from crm.templates t
      where t.organization_id = v_task.organization_id
        and t.organization_address = v_sender_address
        and t.name = 'internal_task_reminder'
        and t.status = 'APPROVED'
      order by t.language
      limit 1;
    end if;

    if v_template_lang is not null then
      insert into public.conversations (organization_id, service, organization_address, address)
      values (v_task.organization_id, 'whatsapp', v_sender_address, v_whatsapp_address)
      on conflict (organization_id, organization_address, service, address) do nothing;

      select c.id into v_conversation_id from public.conversations c
      where c.organization_id = v_task.organization_id
        and c.organization_address = v_sender_address
        and c.service = 'whatsapp' and c.address = v_whatsapp_address;

      insert into public.messages (
        organization_id, conversation_id, service, organization_address,
        conversation_address, content
      )
      values (
        v_task.organization_id, v_conversation_id, 'whatsapp', v_sender_address,
        v_whatsapp_address,
        jsonb_build_object(
          'version', '1', 'type', 'data', 'kind', 'template',
          'data', jsonb_build_object(
            'name', 'internal_task_reminder',
            'language', jsonb_build_object('code', v_template_lang, 'policy', 'deterministic'),
            'components', jsonb_build_array(
              jsonb_build_object(
                'type', 'body',
                'parameters', jsonb_build_array(
                  jsonb_build_object('type', 'text', 'text', v_task.title)
                )
              )
            )
          )
        )
      )
      returning id into v_message_id;
    end if;

    update crm.tasks set reminder_sent_at = now() where id = v_task.id;

    perform crm.write_audit(
      v_task.organization_id, 'lead.task_reminder_sent', 'lead', v_task.lead_id::text,
      jsonb_build_object(
        'task_id', v_task.id,
        'channel', case when v_message_id is not null then 'whatsapp' else 'in_app' end,
        'message_id', v_message_id,
        'assigned_to', v_task.assigned_to
      )
    );
  end loop;
end;
$function$
;


