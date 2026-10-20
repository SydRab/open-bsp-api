
export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[]

export type Database = {
  
  "billing": {
          Tables: {
            "accounts": {
                  Row: {
                    "created_at": string,"id": string,"name": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"id"?: string,"name": string,"updated_at"?: string
                  }
                  Update: {
                    "created_at"?: string,"id"?: string,"name"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    
                  ]
                },"costs": {
                  Row: {
                    "created_at": string,"effective_at": string,"pricing": NonNullable<Json>,"product": string,"provider": string,"quantity": number,"unit": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"effective_at"?: string,"pricing": NonNullable<Json>,"product": string,"provider": string,"quantity": number,"unit": string,"updated_at"?: string
                  }
                  Update: {
                    "created_at"?: string,"effective_at"?: string,"pricing"?: NonNullable<Json>,"product"?: string,"provider"?: string,"quantity"?: number,"unit"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    
                  ]
                },"invoices": {
                  Row: {
                    "created_at": string,"id": string,"organization_id": string,"period_end": string | null,"period_start": string | null,"status": string,"subtotal": number,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"id"?: string,"organization_id": string,"period_end"?: string | null,"period_start"?: string | null,"status"?: string,"subtotal"?: number,"updated_at"?: string
                  }
                  Update: {
                    "created_at"?: string,"id"?: string,"organization_id"?: string,"period_end"?: string | null,"period_start"?: string | null,"status"?: string,"subtotal"?: number,"updated_at"?: string
                  }
                  Relationships: [
                    
                  ]
                },"invoices_items": {
                  Row: {
                    "amount": number,"created_at": string,"id": string,"invoice_id": string,"ledger_id": string | null,"plan_id": string | null,"product_id": string | null,"quantity": number,"type": string,"unit_price": number,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "amount": number,"created_at"?: string,"id"?: string,"invoice_id": string,"ledger_id"?: string | null,"plan_id"?: string | null,"product_id"?: string | null,"quantity": number,"type": string,"unit_price": number,"updated_at"?: string
                  }
                  Update: {
                    "amount"?: number,"created_at"?: string,"id"?: string,"invoice_id"?: string,"ledger_id"?: string | null,"plan_id"?: string | null,"product_id"?: string | null,"quantity"?: number,"type"?: string,"unit_price"?: number,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "invoices_items_invoice_id_fkey"
      columns: ["invoice_id"]
isOneToOne: false
      referencedRelation: "invoices"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "invoices_items_ledger_id_fkey"
      columns: ["ledger_id"]
isOneToOne: false
      referencedRelation: "ledger"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "invoices_items_plan_id_fkey"
      columns: ["plan_id"]
isOneToOne: false
      referencedRelation: "plans"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "invoices_items_product_id_fkey"
      columns: ["product_id"]
isOneToOne: false
      referencedRelation: "products"
      referencedColumns: ["id"]
    }
                  ]
                },"ledger": {
                  Row: {
                    "agent_id": string | null,"billable": boolean | null,"created_at": string,"id": string,"message_id": string | null,"metadata": Json | null,"model": string | null,"organization_id": string,"product_id": string,"provider": string | null,"quantity": number,"type": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "agent_id"?: string | null,"billable"?: boolean | null,"created_at"?: string,"id"?: string,"message_id"?: string | null,"metadata"?: Json | null,"model"?: string | null,"organization_id": string,"product_id": string,"provider"?: string | null,"quantity": number,"type": string,"updated_at"?: string
                  }
                  Update: {
                    "agent_id"?: string | null,"billable"?: boolean | null,"created_at"?: string,"id"?: string,"message_id"?: string | null,"metadata"?: Json | null,"model"?: string | null,"organization_id"?: string,"product_id"?: string,"provider"?: string | null,"quantity"?: number,"type"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "ledger_product_id_fkey"
      columns: ["product_id"]
isOneToOne: false
      referencedRelation: "products"
      referencedColumns: ["id"]
    }
                  ]
                },"payments": {
                  Row: {
                    "account_id": string | null,"amount": number,"created_at": string,"external_id": string | null,"id": string,"invoice_id": string,"method": string | null,"organization_id": string,"status": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "account_id"?: string | null,"amount": number,"created_at"?: string,"external_id"?: string | null,"id"?: string,"invoice_id": string,"method"?: string | null,"organization_id": string,"status"?: string,"updated_at"?: string
                  }
                  Update: {
                    "account_id"?: string | null,"amount"?: number,"created_at"?: string,"external_id"?: string | null,"id"?: string,"invoice_id"?: string,"method"?: string | null,"organization_id"?: string,"status"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "payments_account_id_fkey"
      columns: ["account_id"]
isOneToOne: false
      referencedRelation: "accounts"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "payments_invoice_id_fkey"
      columns: ["invoice_id"]
isOneToOne: false
      referencedRelation: "invoices"
      referencedColumns: ["id"]
    }
                  ]
                },"plans": {
                  Row: {
                    "active": boolean,"billing_cycle": string | null,"created_at": string,"id": string,"is_default": boolean,"min_tier": number,"price": number,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "active"?: boolean,"billing_cycle"?: string | null,"created_at"?: string,"id": string,"is_default"?: boolean,"min_tier": number,"price": number,"updated_at"?: string
                  }
                  Update: {
                    "active"?: boolean,"billing_cycle"?: string | null,"created_at"?: string,"id"?: string,"is_default"?: boolean,"min_tier"?: number,"price"?: number,"updated_at"?: string
                  }
                  Relationships: [
                    
                  ]
                },"plans_products": {
                  Row: {
                    "created_at": string,"included": number | null,"interval": string,"plan_id": string,"product_id": string,"unit_price": number | null,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"included"?: number | null,"interval": string,"plan_id": string,"product_id": string,"unit_price"?: number | null,"updated_at"?: string
                  }
                  Update: {
                    "created_at"?: string,"included"?: number | null,"interval"?: string,"plan_id"?: string,"product_id"?: string,"unit_price"?: number | null,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "plans_products_plan_id_fkey"
      columns: ["plan_id"]
isOneToOne: false
      referencedRelation: "plans"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "plans_products_product_id_fkey"
      columns: ["product_id"]
isOneToOne: false
      referencedRelation: "products"
      referencedColumns: ["id"]
    }
                  ]
                },"products": {
                  Row: {
                    "created_at": string,"id": string,"kind": string,"name": string,"unit": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"id": string,"kind": string,"name": string,"unit": string,"updated_at"?: string
                  }
                  Update: {
                    "created_at"?: string,"id"?: string,"kind"?: string,"name"?: string,"unit"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    
                  ]
                },"subscriptions": {
                  Row: {
                    "account_id": string | null,"created_at": string,"current_period_end": string | null,"current_period_start": string | null,"organization_id": string,"plan_id": string | null,"tier_id": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "account_id"?: string | null,"created_at"?: string,"current_period_end"?: string | null,"current_period_start"?: string | null,"organization_id": string,"plan_id"?: string | null,"tier_id": string,"updated_at"?: string
                  }
                  Update: {
                    "account_id"?: string | null,"created_at"?: string,"current_period_end"?: string | null,"current_period_start"?: string | null,"organization_id"?: string,"plan_id"?: string | null,"tier_id"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "subscriptions_account_id_fkey"
      columns: ["account_id"]
isOneToOne: false
      referencedRelation: "accounts"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "subscriptions_plan_id_fkey"
      columns: ["plan_id"]
isOneToOne: false
      referencedRelation: "plans"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "subscriptions_tier_id_fkey"
      columns: ["tier_id"]
isOneToOne: false
      referencedRelation: "tiers"
      referencedColumns: ["id"]
    }
                  ]
                },"tiers": {
                  Row: {
                    "active": boolean,"created_at": string,"id": string,"level": number,"name": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "active"?: boolean,"created_at"?: string,"id": string,"level"?: number,"name": string,"updated_at"?: string
                  }
                  Update: {
                    "active"?: boolean,"created_at"?: string,"id"?: string,"level"?: number,"name"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    
                  ]
                },"tiers_products": {
                  Row: {
                    "cap": number | null,"created_at": string,"interval": string,"product_id": string,"tier_id": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "cap"?: number | null,"created_at"?: string,"interval": string,"product_id": string,"tier_id": string,"updated_at"?: string
                  }
                  Update: {
                    "cap"?: number | null,"created_at"?: string,"interval"?: string,"product_id"?: string,"tier_id"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "tiers_products_product_id_fkey"
      columns: ["product_id"]
isOneToOne: false
      referencedRelation: "products"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "tiers_products_tier_id_fkey"
      columns: ["tier_id"]
isOneToOne: false
      referencedRelation: "tiers"
      referencedColumns: ["id"]
    }
                  ]
                },"usage": {
                  Row: {
                    "created_at": string,"interval": string,"organization_id": string,"period": string,"product_id": string,"quantity": number,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"interval"?: string,"organization_id": string,"period"?: string,"product_id": string,"quantity"?: number,"updated_at"?: string
                  }
                  Update: {
                    "created_at"?: string,"interval"?: string,"organization_id"?: string,"period"?: string,"product_id"?: string,"quantity"?: number,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "usage_product_id_fkey"
      columns: ["product_id"]
isOneToOne: false
      referencedRelation: "products"
      referencedColumns: ["id"]
    }
                  ]
                }
          }
          Views: {
            [_ in never]: never
          }
          Functions: {
            "check_limit":
{ Args: { "_amount"?: number,"_organization_id": string,"_product_id": string }; Returns: boolean
                           },
"update_usage":
{ Args: { "_organization_id": string,"_product_id": string,"_quantity"?: number }; Returns: undefined
                           }
          }
          Enums: {
            [_ in never]: never
          }
          CompositeTypes: {
            [_ in never]: never
          }
        },"crm": {
          Tables: {
            "audit_log": {
                  Row: {
                    "action": string,"actor_agent_id": string | null,"actor_api_key_id": string | null,"actor_type": string,"actor_user_id": string | null,"created_at": string,"details": NonNullable<Json>,"id": number,"organization_id": string,"request_id": string | null,"target_id": string | null,"target_type": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "action": string,"actor_agent_id"?: string | null,"actor_api_key_id"?: string | null,"actor_type": string,"actor_user_id"?: string | null,"created_at"?: string,"details"?: NonNullable<Json>,"id"?: never,"organization_id": string,"request_id"?: string | null,"target_id"?: string | null,"target_type"?: string | null
                  }
                  Update: {
                    "action"?: string,"actor_agent_id"?: string | null,"actor_api_key_id"?: string | null,"actor_type"?: string,"actor_user_id"?: string | null,"created_at"?: string,"details"?: NonNullable<Json>,"id"?: never,"organization_id"?: string,"request_id"?: string | null,"target_id"?: string | null,"target_type"?: string | null
                  }
                  Relationships: [
                    
                  ]
                },"invitation_roles": {
                  Row: {
                    "created_at": string,"invitation_id": string,"organization_id": string,"role_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"invitation_id": string,"organization_id": string,"role_id": string
                  }
                  Update: {
                    "created_at"?: string,"invitation_id"?: string,"organization_id"?: string,"role_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "invitation_roles_role_fkey"
      columns: ["organization_id","role_id"]
isOneToOne: false
      referencedRelation: "roles"
      referencedColumns: ["organization_id","id"]
    }
                  ]
                },"member_address_access": {
                  Row: {
                    "address": string,"agent_id": string,"created_at": string,"organization_id": string,"service": Database["public"]['Enums']["service"]
                  }
                  ComputedFields: never
                  Insert: {
                    "address": string,"agent_id": string,"created_at"?: string,"organization_id": string,"service": Database["public"]['Enums']["service"]
                  }
                  Update: {
                    "address"?: string,"agent_id"?: string,"created_at"?: string,"organization_id"?: string,"service"?: Database["public"]['Enums']["service"]
                  }
                  Relationships: [
                    
                  ]
                },"member_permission_overrides": {
                  Row: {
                    "agent_id": string,"created_at": string,"granted": boolean,"organization_id": string,"permission": string
                  }
                  ComputedFields: never
                  Insert: {
                    "agent_id": string,"created_at"?: string,"granted": boolean,"organization_id": string,"permission": string
                  }
                  Update: {
                    "agent_id"?: string,"created_at"?: string,"granted"?: boolean,"organization_id"?: string,"permission"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "member_permission_overrides_permission_fkey"
      columns: ["permission"]
isOneToOne: false
      referencedRelation: "permissions"
      referencedColumns: ["key"]
    }
                  ]
                },"member_roles": {
                  Row: {
                    "agent_id": string,"created_at": string,"lead_scope": string | null,"organization_id": string,"role_id": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "agent_id": string,"created_at"?: string,"lead_scope"?: string | null,"organization_id": string,"role_id": string,"updated_at"?: string
                  }
                  Update: {
                    "agent_id"?: string,"created_at"?: string,"lead_scope"?: string | null,"organization_id"?: string,"role_id"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "member_roles_role_fkey"
      columns: ["organization_id","role_id"]
isOneToOne: false
      referencedRelation: "roles"
      referencedColumns: ["organization_id","id"]
    }
                  ]
                },"organization_pack_items": {
                  Row: {
                    "created_at": string,"id": string,"is_customized": boolean,"item_key": string,"kind": string,"organization_id": string,"pack_value": Json | null,"pack_version": number,"removed_from_pack": boolean,"sort_order": number,"updated_at": string,"value": NonNullable<Json>
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"id"?: string,"is_customized"?: boolean,"item_key": string,"kind": string,"organization_id": string,"pack_value"?: Json | null,"pack_version": number,"removed_from_pack"?: boolean,"sort_order"?: number,"updated_at"?: string,"value": NonNullable<Json>
                  }
                  Update: {
                    "created_at"?: string,"id"?: string,"is_customized"?: boolean,"item_key"?: string,"kind"?: string,"organization_id"?: string,"pack_value"?: Json | null,"pack_version"?: number,"removed_from_pack"?: boolean,"sort_order"?: number,"updated_at"?: string,"value"?: NonNullable<Json>
                  }
                  Relationships: [
                    
                  ]
                },"organization_packs": {
                  Row: {
                    "applied_at": string,"organization_id": string,"pack_key": string,"upgraded_at": string | null,"version": number
                  }
                  ComputedFields: never
                  Insert: {
                    "applied_at"?: string,"organization_id": string,"pack_key": string,"upgraded_at"?: string | null,"version": number
                  }
                  Update: {
                    "applied_at"?: string,"organization_id"?: string,"pack_key"?: string,"upgraded_at"?: string | null,"version"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "organization_packs_version_fkey"
      columns: ["pack_key","version"]
isOneToOne: false
      referencedRelation: "pack_versions"
      referencedColumns: ["pack_key","version"]
    }
                  ]
                },"organization_profiles": {
                  Row: {
                    "created_at": string,"deletion_requested_at": string | null,"deletion_requested_by": string | null,"locale": string,"organization_id": string,"purge_after": string | null,"require_mfa_for_admins": boolean,"slug": string,"status": string,"suspended_at": string | null,"suspended_reason": string | null,"timezone": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"deletion_requested_at"?: string | null,"deletion_requested_by"?: string | null,"locale"?: string,"organization_id": string,"purge_after"?: string | null,"require_mfa_for_admins"?: boolean,"slug": string,"status"?: string,"suspended_at"?: string | null,"suspended_reason"?: string | null,"timezone"?: string,"updated_at"?: string
                  }
                  Update: {
                    "created_at"?: string,"deletion_requested_at"?: string | null,"deletion_requested_by"?: string | null,"locale"?: string,"organization_id"?: string,"purge_after"?: string | null,"require_mfa_for_admins"?: boolean,"slug"?: string,"status"?: string,"suspended_at"?: string | null,"suspended_reason"?: string | null,"timezone"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    
                  ]
                },"pack_versions": {
                  Row: {
                    "checksum": string,"definition": NonNullable<Json>,"pack_key": string,"published_at": string,"version": number
                  }
                  ComputedFields: never
                  Insert: {
                    "checksum": string,"definition": NonNullable<Json>,"pack_key": string,"published_at"?: string,"version": number
                  }
                  Update: {
                    "checksum"?: string,"definition"?: NonNullable<Json>,"pack_key"?: string,"published_at"?: string,"version"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "pack_versions_pack_key_fkey"
      columns: ["pack_key"]
isOneToOne: false
      referencedRelation: "vertical_packs"
      referencedColumns: ["key"]
    }
                  ]
                },"permissions": {
                  Row: {
                    "category": string,"created_at": string,"description": string,"key": string,"min_tier": Database["public"]['Enums']["role"],"sort_order": number
                  }
                  ComputedFields: never
                  Insert: {
                    "category": string,"created_at"?: string,"description": string,"key": string,"min_tier"?: Database["public"]['Enums']["role"],"sort_order"?: number
                  }
                  Update: {
                    "category"?: string,"created_at"?: string,"description"?: string,"key"?: string,"min_tier"?: Database["public"]['Enums']["role"],"sort_order"?: number
                  }
                  Relationships: [
                    
                  ]
                },"preset_role_permissions": {
                  Row: {
                    "permission": string,"role_key": string
                  }
                  ComputedFields: never
                  Insert: {
                    "permission": string,"role_key": string
                  }
                  Update: {
                    "permission"?: string,"role_key"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "preset_role_permissions_permission_fkey"
      columns: ["permission"]
isOneToOne: false
      referencedRelation: "permissions"
      referencedColumns: ["key"]
    },{
      foreignKeyName: "preset_role_permissions_role_key_fkey"
      columns: ["role_key"]
isOneToOne: false
      referencedRelation: "preset_roles"
      referencedColumns: ["key"]
    }
                  ]
                },"preset_roles": {
                  Row: {
                    "description": string,"key": string,"lead_scope": string,"name": string,"sort_order": number,"tier": Database["public"]['Enums']["role"]
                  }
                  ComputedFields: never
                  Insert: {
                    "description": string,"key": string,"lead_scope"?: string,"name": string,"sort_order"?: number,"tier": Database["public"]['Enums']["role"]
                  }
                  Update: {
                    "description"?: string,"key"?: string,"lead_scope"?: string,"name"?: string,"sort_order"?: number,"tier"?: Database["public"]['Enums']["role"]
                  }
                  Relationships: [
                    
                  ]
                },"role_permissions": {
                  Row: {
                    "created_at": string,"organization_id": string,"permission": string,"role_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"organization_id": string,"permission": string,"role_id": string
                  }
                  Update: {
                    "created_at"?: string,"organization_id"?: string,"permission"?: string,"role_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "role_permissions_permission_fkey"
      columns: ["permission"]
isOneToOne: false
      referencedRelation: "permissions"
      referencedColumns: ["key"]
    },{
      foreignKeyName: "role_permissions_role_fkey"
      columns: ["organization_id","role_id"]
isOneToOne: false
      referencedRelation: "roles"
      referencedColumns: ["organization_id","id"]
    }
                  ]
                },"roles": {
                  Row: {
                    "created_at": string,"description": string | null,"id": string,"is_locked": boolean,"is_preset": boolean,"key": string,"lead_scope": string,"name": string,"organization_id": string,"sort_order": number,"tier": Database["public"]['Enums']["role"],"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"description"?: string | null,"id"?: string,"is_locked"?: boolean,"is_preset"?: boolean,"key": string,"lead_scope"?: string,"name": string,"organization_id": string,"sort_order"?: number,"tier": Database["public"]['Enums']["role"],"updated_at"?: string
                  }
                  Update: {
                    "created_at"?: string,"description"?: string | null,"id"?: string,"is_locked"?: boolean,"is_preset"?: boolean,"key"?: string,"lead_scope"?: string,"name"?: string,"organization_id"?: string,"sort_order"?: number,"tier"?: Database["public"]['Enums']["role"],"updated_at"?: string
                  }
                  Relationships: [
                    
                  ]
                },"setting_definitions": {
                  Row: {
                    "category": string,"created_at": string,"description": string | null,"edit_permission": string,"is_locked": boolean,"key": string,"label": string,"pack_item_key": string | null,"pack_item_kind": string | null,"pack_item_path": (string)[],"platform_default": NonNullable<Json>,"schema": NonNullable<Json>,"scopes": (string)[],"sort_order": number
                  }
                  ComputedFields: never
                  Insert: {
                    "category": string,"created_at"?: string,"description"?: string | null,"edit_permission"?: string,"is_locked"?: boolean,"key": string,"label": string,"pack_item_key"?: string | null,"pack_item_kind"?: string | null,"pack_item_path"?: (string)[],"platform_default": NonNullable<Json>,"schema": NonNullable<Json>,"scopes"?: (string)[],"sort_order"?: number
                  }
                  Update: {
                    "category"?: string,"created_at"?: string,"description"?: string | null,"edit_permission"?: string,"is_locked"?: boolean,"key"?: string,"label"?: string,"pack_item_key"?: string | null,"pack_item_kind"?: string | null,"pack_item_path"?: (string)[],"platform_default"?: NonNullable<Json>,"schema"?: NonNullable<Json>,"scopes"?: (string)[],"sort_order"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "setting_definitions_edit_permission_fkey"
      columns: ["edit_permission"]
isOneToOne: false
      referencedRelation: "permissions"
      referencedColumns: ["key"]
    }
                  ]
                },"setting_values": {
                  Row: {
                    "agent_id": string | null,"created_at": string,"id": string,"organization_id": string,"scope": string,"setting_key": string,"team_id": string | null,"updated_at": string,"updated_by": string | null,"value": NonNullable<Json>
                  }
                  ComputedFields: never
                  Insert: {
                    "agent_id"?: string | null,"created_at"?: string,"id"?: string,"organization_id": string,"scope": string,"setting_key": string,"team_id"?: string | null,"updated_at"?: string,"updated_by"?: string | null,"value": NonNullable<Json>
                  }
                  Update: {
                    "agent_id"?: string | null,"created_at"?: string,"id"?: string,"organization_id"?: string,"scope"?: string,"setting_key"?: string,"team_id"?: string | null,"updated_at"?: string,"updated_by"?: string | null,"value"?: NonNullable<Json>
                  }
                  Relationships: [
                    {
      foreignKeyName: "setting_values_setting_key_fkey"
      columns: ["setting_key"]
isOneToOne: false
      referencedRelation: "setting_definitions"
      referencedColumns: ["key"]
    },{
      foreignKeyName: "setting_values_team_fkey"
      columns: ["organization_id","team_id"]
isOneToOne: false
      referencedRelation: "teams"
      referencedColumns: ["organization_id","id"]
    }
                  ]
                },"team_members": {
                  Row: {
                    "agent_id": string,"created_at": string,"organization_id": string,"team_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "agent_id": string,"created_at"?: string,"organization_id": string,"team_id": string
                  }
                  Update: {
                    "agent_id"?: string,"created_at"?: string,"organization_id"?: string,"team_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "team_members_team_fkey"
      columns: ["organization_id","team_id"]
isOneToOne: false
      referencedRelation: "teams"
      referencedColumns: ["organization_id","id"]
    }
                  ]
                },"teams": {
                  Row: {
                    "created_at": string,"id": string,"name": string,"organization_id": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"id"?: string,"name": string,"organization_id": string,"updated_at"?: string
                  }
                  Update: {
                    "created_at"?: string,"id"?: string,"name"?: string,"organization_id"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    
                  ]
                },"vertical_packs": {
                  Row: {
                    "created_at": string,"description": string | null,"is_default": boolean,"key": string,"name": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"description"?: string | null,"is_default"?: boolean,"key": string,"name": string
                  }
                  Update: {
                    "created_at"?: string,"description"?: string | null,"is_default"?: boolean,"key"?: string,"name"?: string
                  }
                  Relationships: [
                    
                  ]
                }
          }
          Views: {
            [_ in never]: never
          }
          Functions: {
            "apply_default_pack":
{ Args: { "p_organization_id": string }; Returns: undefined
                           },
"apply_pack":
{ Args: { "p_organization_id": string,"p_pack_key": string,"p_version": number }; Returns: undefined
                           },
"assert_can_edit_role":
{ Args: { "p_role_id": string }; Returns: {
              "created_at": string,
"description": string | null,
"id": string,
"is_locked": boolean,
"is_preset": boolean,
"key": string,
"lead_scope": string,
"name": string,
"organization_id": string,
"sort_order": number,
"tier": Database["public"]['Enums']["role"],
"updated_at": string
            }
                          SetofOptions: {
        from: "*"
        to: "roles"
        isOneToOne: true
        isSetofReturn: false
      } },
"assert_can_manage_member":
{ Args: { "p_agent_id": string }; Returns: Database["public"]['Tables']["agents"]['Row']
                          SetofOptions: {
        from: "*"
        to: "agents"
        isOneToOne: true
        isSetofReturn: false
      } },
"assert_can_read_settings":
{ Args: { "p_organization_id": string }; Returns: string
                           },
"caller_agent":
{ Args: { "p_organization_id": string }; Returns: Database["public"]['Tables']["agents"]['Row']
                          SetofOptions: {
        from: "*"
        to: "agents"
        isOneToOne: true
        isSetofReturn: false
      } },
"cancel_organization_deletion":
{ Args: { "p_organization_id": string }; Returns: undefined
                           },
"create_preset_roles":
{ Args: { "p_organization_id": string }; Returns: undefined
                           },
"create_team":
{ Args: { "p_name": string,"p_organization_id": string }; Returns: string
                           },
"deactivate_member":
{ Args: { "p_agent_id": string }; Returns: undefined
                           },
"default_role_key":
{ Args: { "p_tier": Database["public"]['Enums']["role"] }; Returns: string
                           },
"delete_team":
{ Args: { "p_team_id": string }; Returns: undefined
                           },
"deletion_grace_period":
{ Args: Record<PropertyKey, never>; Returns: string
                           },
"generate_slug":
{ Args: { "p_name": string }; Returns: string
                           },
"get_audit_log":
{ Args: { "p_actor"?: string,"p_area"?: string,"p_before_id"?: number,"p_from"?: string,"p_limit"?: number,"p_organization_id": string,"p_to"?: string }; Returns: {
              "action": string,"actor_agent_id": string,"actor_name": string,"actor_type": string,"created_at": string,"details": Json,"id": number,"target_id": string,"target_name": string,"target_type": string
            }[]
                           },
"get_hidden_addresses":
{ Args: Record<PropertyKey, never>; Returns: {
              "address": string,"organization_id": string,"service": Database["public"]['Enums']["service"]
            }[]
                           },
"get_my_invitation_roles":
{ Args: Record<PropertyKey, never>; Returns: {
              "invitation_id": string,"role_key": string,"role_name": string
            }[]
                           },
"get_my_organization_statuses":
{ Args: Record<PropertyKey, never>; Returns: {
              "can_cancel_deletion": boolean,"name": string,"organization_id": string,"purge_after": string,"status": string,"suspended_reason": string
            }[]
                           },
"get_permitted_orgs":
{ Args: { "p_permission": string }; Returns: string[]
                           },
"get_setting":
{ Args: { "p_agent_id"?: string,"p_key": string,"p_organization_id": string }; Returns: Json
                           },
"get_settings":
{ Args: { "p_organization_id": string }; Returns: {
              "can_edit": boolean,"category": string,"description": string,"is_locked": boolean,"key": string,"label": string,"schema": Json,"scopes": (string)[],"sort_order": number,"source": string,"team_conflict": boolean,"tenant_value": Json,"value": Json
            }[]
                           },
"has_permission":
{ Args: { "p_organization_id": string,"p_permission": string }; Returns: boolean
                           },
"invite_member":
{ Args: { "p_email": string,"p_organization_id": string,"p_role_key": string }; Returns: string
                           },
"my_permissions":
{ Args: { "p_organization_id": string }; Returns: string[]
                           },
"pack_items":
{ Args: { "p_definition": Json }; Returns: {
              "item_key": string,"kind": string,"sort_order": number,"value": Json
            }[]
                           },
"purge_organizations":
{ Args: Record<PropertyKey, never>; Returns: number
                           },
"reactivate_organization":
{ Args: { "p_organization_id": string }; Returns: undefined
                           },
"rename_team":
{ Args: { "p_name": string,"p_team_id": string }; Returns: undefined
                           },
"request_organization_deletion":
{ Args: { "p_organization_id": string }; Returns: string
                           },
"require_permission":
{ Args: { "p_organization_id": string,"p_permission": string }; Returns: undefined
                           },
"reset_pack_item":
{ Args: { "p_item_id": string }; Returns: undefined
                           },
"reset_role_permissions":
{ Args: { "p_role_id": string }; Returns: undefined
                           },
"reset_setting":
{ Args: { "p_key": string,"p_organization_id": string,"p_scope"?: string,"p_target"?: string }; Returns: undefined
                           },
"resolve_setting":
{ Args: { "p_agent_id"?: string,"p_key": string,"p_organization_id": string }; Returns: {
              "source": string,"team_conflict": boolean,"value": Json
            }[]
                           },
"revoke_invitation":
{ Args: { "p_invitation_id": string }; Returns: undefined
                           },
"set_member_address_access":
{ Args: { "p_address": string,"p_agent_id": string,"p_allowed": boolean,"p_service": Database["public"]['Enums']["service"] }; Returns: undefined
                           },
"set_member_lead_scope":
{ Args: { "p_agent_id": string,"p_lead_scope": string }; Returns: undefined
                           },
"set_member_permission_override":
{ Args: { "p_agent_id": string,"p_granted": boolean,"p_permission": string }; Returns: undefined
                           },
"set_member_role":
{ Args: { "p_agent_id": string,"p_role_key": string }; Returns: undefined
                           },
"set_require_mfa_for_admins":
{ Args: { "p_organization_id": string,"p_required": boolean }; Returns: undefined
                           },
"set_role_permission":
{ Args: { "p_enabled": boolean,"p_permission": string,"p_role_id": string }; Returns: undefined
                           },
"set_setting":
{ Args: { "p_key": string,"p_organization_id": string,"p_scope"?: string,"p_target"?: string,"p_value": Json }; Returns: undefined
                           },
"set_team_member":
{ Args: { "p_agent_id": string,"p_member": boolean,"p_team_id": string }; Returns: undefined
                           },
"setting_target":
{ Args: { "p_key": string,"p_organization_id": string,"p_scope": string,"p_target": string }; Returns: Record<string, unknown>
                           },
"suspend_organization":
{ Args: { "p_organization_id": string,"p_reason"?: string }; Returns: undefined
                           },
"tier_rank":
{ Args: { "tier": Database["public"]['Enums']["role"] }; Returns: number
                           },
"upgrade_organization_pack":
{ Args: { "p_organization_id": string,"p_version"?: number }; Returns: number
                           },
"validate_setting_value":
{ Args: { "p_path"?: string,"p_schema": Json,"p_value": Json }; Returns: string
                           },
"write_audit":
{ Args: { "p_action": string,"p_details"?: Json,"p_organization_id": string,"p_target_id"?: string,"p_target_type"?: string }; Returns: undefined
                           }
          }
          Enums: {
            [_ in never]: never
          }
          CompositeTypes: {
            [_ in never]: never
          }
        },"public": {
          Tables: {
            "agents": {
                  Row: {
                    "created_at": string,"deleted_at": string | null,"extra": Json | null,"id": string,"name": string,"organization_id": string,"picture": string | null,"role": Database["public"]['Enums']["role"],"updated_at": string,"user_id": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"deleted_at"?: string | null,"extra"?: Json | null,"id"?: string,"name": string,"organization_id": string,"picture"?: string | null,"role"?: Database["public"]['Enums']["role"],"updated_at"?: string,"user_id"?: string | null
                  }
                  Update: {
                    "created_at"?: string,"deleted_at"?: string | null,"extra"?: Json | null,"id"?: string,"name"?: string,"organization_id"?: string,"picture"?: string | null,"role"?: Database["public"]['Enums']["role"],"updated_at"?: string,"user_id"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "agents_organization_id_fkey"
      columns: ["organization_id"]
isOneToOne: false
      referencedRelation: "organizations"
      referencedColumns: ["id"]
    }
                  ]
                },"api_keys": {
                  Row: {
                    "created_at": string,"id": string,"key": string,"name": string,"organization_id": string,"role": Database["public"]['Enums']["role"],"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"id"?: string,"key": string,"name": string,"organization_id": string,"role"?: Database["public"]['Enums']["role"],"updated_at"?: string
                  }
                  Update: {
                    "created_at"?: string,"id"?: string,"key"?: string,"name"?: string,"organization_id"?: string,"role"?: Database["public"]['Enums']["role"],"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "api_keys_organization_id_fkey"
      columns: ["organization_id"]
isOneToOne: false
      referencedRelation: "organizations"
      referencedColumns: ["id"]
    }
                  ]
                },"contacts_addresses": {
                  Row: {
                    "address": string,"created_at": string,"extra": Json | null,"organization_address": string,"organization_id": string,"service": Database["public"]['Enums']["service"],"status": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "address": string,"created_at"?: string,"extra"?: Json | null,"organization_address": string,"organization_id": string,"service": Database["public"]['Enums']["service"],"status"?: string,"updated_at"?: string
                  }
                  Update: {
                    "address"?: string,"created_at"?: string,"extra"?: Json | null,"organization_address"?: string,"organization_id"?: string,"service"?: Database["public"]['Enums']["service"],"status"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "contacts_addresses_organization_address_fkey"
      columns: ["organization_id","service","organization_address"]
isOneToOne: false
      referencedRelation: "organizations_addresses"
      referencedColumns: ["organization_id","service","address"]
    },{
      foreignKeyName: "contacts_addresses_organization_id_fkey"
      columns: ["organization_id"]
isOneToOne: false
      referencedRelation: "organizations"
      referencedColumns: ["id"]
    }
                  ]
                },"conversations": {
                  Row: {
                    "address": string,"created_at": string,"extra": Json | null,"id": string,"name": string | null,"organization_address": string,"organization_id": string,"service": Database["public"]['Enums']["service"],"type": string | null,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "address": string,"created_at"?: string,"extra"?: Json | null,"id"?: string,"name"?: string | null,"organization_address": string,"organization_id": string,"service": Database["public"]['Enums']["service"],"type"?: string | null,"updated_at"?: string
                  }
                  Update: {
                    "address"?: string,"created_at"?: string,"extra"?: Json | null,"id"?: string,"name"?: string | null,"organization_address"?: string,"organization_id"?: string,"service"?: Database["public"]['Enums']["service"],"type"?: string | null,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "conversations_organization_address_fkey"
      columns: ["organization_id","service","organization_address"]
isOneToOne: false
      referencedRelation: "organizations_addresses"
      referencedColumns: ["organization_id","service","address"]
    },{
      foreignKeyName: "conversations_organization_id_fkey"
      columns: ["organization_id"]
isOneToOne: false
      referencedRelation: "organizations"
      referencedColumns: ["id"]
    }
                  ]
                },"conversations_agents": {
                  Row: {
                    "agent_id": string,"conversation_id": string,"created_at": string,"extra": Json | null,"organization_address": string,"organization_id": string,"service": Database["public"]['Enums']["service"],"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "agent_id": string,"conversation_id": string,"created_at"?: string,"extra"?: Json | null,"organization_address": string,"organization_id": string,"service": Database["public"]['Enums']["service"],"updated_at"?: string
                  }
                  Update: {
                    "agent_id"?: string,"conversation_id"?: string,"created_at"?: string,"extra"?: Json | null,"organization_address"?: string,"organization_id"?: string,"service"?: Database["public"]['Enums']["service"],"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "conversations_agents_agent_id_fkey"
      columns: ["organization_id","agent_id"]
isOneToOne: false
      referencedRelation: "agents"
      referencedColumns: ["organization_id","id"]
    },{
      foreignKeyName: "conversations_agents_conversation_id_fkey"
      columns: ["organization_id","conversation_id"]
isOneToOne: false
      referencedRelation: "conversations"
      referencedColumns: ["organization_id","id"]
    },{
      foreignKeyName: "conversations_agents_organization_address_fkey"
      columns: ["organization_id","service","organization_address"]
isOneToOne: false
      referencedRelation: "organizations_addresses"
      referencedColumns: ["organization_id","service","address"]
    },{
      foreignKeyName: "conversations_agents_organization_id_fkey"
      columns: ["organization_id"]
isOneToOne: false
      referencedRelation: "organizations"
      referencedColumns: ["id"]
    }
                  ]
                },"invitations": {
                  Row: {
                    "created_at": string,"email": string,"id": string,"invited_by": string | null,"invited_by_email": string | null,"invited_by_name": string | null,"organization_id": string,"organization_name": string | null,"role": Database["public"]['Enums']["role"],"status": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"email": string,"id"?: string,"invited_by"?: string | null,"invited_by_email"?: string | null,"invited_by_name"?: string | null,"organization_id": string,"organization_name"?: string | null,"role"?: Database["public"]['Enums']["role"],"status"?: string,"updated_at"?: string
                  }
                  Update: {
                    "created_at"?: string,"email"?: string,"id"?: string,"invited_by"?: string | null,"invited_by_email"?: string | null,"invited_by_name"?: string | null,"organization_id"?: string,"organization_name"?: string | null,"role"?: Database["public"]['Enums']["role"],"status"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "invitations_invited_by_fkey"
      columns: ["invited_by"]
isOneToOne: false
      referencedRelation: "agents"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "invitations_organization_id_fkey"
      columns: ["organization_id"]
isOneToOne: false
      referencedRelation: "organizations"
      referencedColumns: ["id"]
    }
                  ]
                },"logs": {
                  Row: {
                    "category": string,"created_at": string,"id": string,"level": Database["public"]['Enums']["log_level"],"message": string,"metadata": Json | null,"organization_address": string | null,"organization_id": string,"service": Database["public"]['Enums']["service"] | null
                  }
                  ComputedFields: never
                  Insert: {
                    "category": string,"created_at"?: string,"id"?: string,"level": Database["public"]['Enums']["log_level"],"message": string,"metadata"?: Json | null,"organization_address"?: string | null,"organization_id": string,"service"?: Database["public"]['Enums']["service"] | null
                  }
                  Update: {
                    "category"?: string,"created_at"?: string,"id"?: string,"level"?: Database["public"]['Enums']["log_level"],"message"?: string,"metadata"?: Json | null,"organization_address"?: string | null,"organization_id"?: string,"service"?: Database["public"]['Enums']["service"] | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "logs_organization_address_fkey"
      columns: ["organization_id","service","organization_address"]
isOneToOne: false
      referencedRelation: "organizations_addresses"
      referencedColumns: ["organization_id","service","address"]
    },{
      foreignKeyName: "logs_organization_id_fkey"
      columns: ["organization_id"]
isOneToOne: false
      referencedRelation: "organizations"
      referencedColumns: ["id"]
    }
                  ]
                },"messages": {
                  Row: {
                    "agent_id": string | null,"content": NonNullable<Json>,"conversation_address": string | null,"conversation_id": string,"created_at": string,"external_id": string | null,"id": string,"organization_address": string,"organization_id": string,"sender_address": string | null,"service": Database["public"]['Enums']["service"],"status": NonNullable<Json>,"thread_id": string | null,"timestamp": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "agent_id"?: string | null,"content": NonNullable<Json>,"conversation_address"?: string | null,"conversation_id": string,"created_at"?: string,"external_id"?: string | null,"id"?: string,"organization_address": string,"organization_id": string,"sender_address"?: string | null,"service": Database["public"]['Enums']["service"],"status"?: NonNullable<Json>,"thread_id"?: string | null,"timestamp"?: string,"updated_at"?: string
                  }
                  Update: {
                    "agent_id"?: string | null,"content"?: NonNullable<Json>,"conversation_address"?: string | null,"conversation_id"?: string,"created_at"?: string,"external_id"?: string | null,"id"?: string,"organization_address"?: string,"organization_id"?: string,"sender_address"?: string | null,"service"?: Database["public"]['Enums']["service"],"status"?: NonNullable<Json>,"thread_id"?: string | null,"timestamp"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "messages_agent_id_fkey"
      columns: ["agent_id"]
isOneToOne: false
      referencedRelation: "agents"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "messages_conversation_id_fkey"
      columns: ["conversation_id"]
isOneToOne: false
      referencedRelation: "conversations"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "messages_organization_id_fkey"
      columns: ["organization_id"]
isOneToOne: false
      referencedRelation: "organizations"
      referencedColumns: ["id"]
    }
                  ]
                },"onboarding_tokens": {
                  Row: {
                    "callback_url": string | null,"created_at": string,"expires_at": string,"id": string,"name": string,"organization_id": string,"service": Database["public"]['Enums']["service"],"status": string,"used_at": string | null,"verify_token": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "callback_url"?: string | null,"created_at"?: string,"expires_at": string,"id"?: string,"name": string,"organization_id": string,"service": Database["public"]['Enums']["service"],"status"?: string,"used_at"?: string | null,"verify_token"?: string | null
                  }
                  Update: {
                    "callback_url"?: string | null,"created_at"?: string,"expires_at"?: string,"id"?: string,"name"?: string,"organization_id"?: string,"service"?: Database["public"]['Enums']["service"],"status"?: string,"used_at"?: string | null,"verify_token"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "onboarding_tokens_organization_id_fkey"
      columns: ["organization_id"]
isOneToOne: false
      referencedRelation: "organizations"
      referencedColumns: ["id"]
    }
                  ]
                },"organizations": {
                  Row: {
                    "created_at": string,"extra": Json | null,"id": string,"name": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"extra"?: Json | null,"id"?: string,"name": string,"updated_at"?: string
                  }
                  Update: {
                    "created_at"?: string,"extra"?: Json | null,"id"?: string,"name"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    
                  ]
                },"organizations_addresses": {
                  Row: {
                    "address": string,"agent_id": string | null,"created_at": string,"extra": Json | null,"organization_id": string,"service": Database["public"]['Enums']["service"],"status": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "address": string,"agent_id"?: string | null,"created_at"?: string,"extra"?: Json | null,"organization_id": string,"service": Database["public"]['Enums']["service"],"status"?: string,"updated_at"?: string
                  }
                  Update: {
                    "address"?: string,"agent_id"?: string | null,"created_at"?: string,"extra"?: Json | null,"organization_id"?: string,"service"?: Database["public"]['Enums']["service"],"status"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "organizations_addresses_agent_id_fkey"
      columns: ["agent_id"]
isOneToOne: false
      referencedRelation: "agents"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "organizations_addresses_organization_id_fkey"
      columns: ["organization_id"]
isOneToOne: false
      referencedRelation: "organizations"
      referencedColumns: ["id"]
    }
                  ]
                },"webhooks": {
                  Row: {
                    "created_at": string,"id": string,"operations": (Database["public"]['Enums']["webhook_operation"])[],"organization_id": string,"table_name": Database["public"]['Enums']["webhook_table"],"token": string | null,"updated_at": string,"url": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"id"?: string,"operations": (Database["public"]['Enums']["webhook_operation"])[],"organization_id": string,"table_name": Database["public"]['Enums']["webhook_table"],"token"?: string | null,"updated_at"?: string,"url": string
                  }
                  Update: {
                    "created_at"?: string,"id"?: string,"operations"?: (Database["public"]['Enums']["webhook_operation"])[],"organization_id"?: string,"table_name"?: Database["public"]['Enums']["webhook_table"],"token"?: string | null,"updated_at"?: string,"url"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "webhooks_organization_id_fkey"
      columns: ["organization_id"]
isOneToOne: false
      referencedRelation: "organizations"
      referencedColumns: ["id"]
    }
                  ]
                }
          }
          Views: {
            [_ in never]: never
          }
          Functions: {
            "accept_invitation":
{ Args: { "invitation_id": string }; Returns: string
                           },
"agent_identity_and_role_unchanged":
{ Args: { "p_id": string,"p_organization_id": string,"p_role": Database["public"]['Enums']["role"],"p_user_id": string }; Returns: boolean
                           },
"agent_identity_unchanged":
{ Args: { "p_id": string,"p_organization_id": string,"p_user_id": string }; Returns: boolean
                           },
"get_authorized_orgs":
{ Args: { "role"?: Database["public"]['Enums']["role"] }; Returns: string[]
                           },
"get_own_agents":
{ Args: Record<PropertyKey, never>; Returns: string[]
                           },
"get_participant_conversations":
{ Args: Record<PropertyKey, never>; Returns: string[]
                           },
"get_restricted_conversations":
{ Args: Record<PropertyKey, never>; Returns: string[]
                           },
"get_visible_addresses":
{ Args: Record<PropertyKey, never>; Returns: {
              "address": string,"organization_id": string,"service": Database["public"]['Enums']["service"]
            }[]
                           },
"init_data":
{ Args: { "p_limit"?: number,"p_organization_id": string,"p_per_conversation"?: number,"p_since"?: string,"p_until"?: string }; Returns: Json
                           },
"is_conversation_visible":
{ Args: { "conv_addr": string,"conv_id": string,"conv_org": string,"conv_service": Database["public"]['Enums']["service"] }; Returns: boolean
                           },
"is_media_visible":
{ Args: { "object_name": string }; Returns: boolean
                           },
"merge_update_jsonb":
{ Args: { "object": Json,"path": (string)[],"target": Json }; Returns: Json
                           },
"reject_invitation":
{ Args: { "invitation_id": string }; Returns: undefined
                           }
          }
          Enums: {
            "log_level": "info"|"warning"|"error","role": "owner"|"admin"|"member","service": "whatsapp"|"instagram"|"local"|"slack"|"discord"|"teams"|"whatsapp-web","webhook_operation": "insert"|"update","webhook_table": "messages"|"conversations"|"organizations_addresses"|"contacts_addresses"|"logs"
          }
          CompositeTypes: {
            [_ in never]: never
          }
        },"storage": {
          Tables: {
            "buckets": {
                  Row: {
                    "allowed_mime_types": (string)[] | null,"avif_autodetection": boolean | null,"created_at": string | null,"file_size_limit": number | null,"id": string,"lifecycle_configuration": Json | null,"lifecycle_configuration_generation": string | null,"name": string,"owner": string | null,"owner_id": string | null,"public": boolean | null,"type": Database["storage"]['Enums']["buckettype"],"updated_at": string | null,"versioning_status": string
                  }
                  ComputedFields: never
                  Insert: {
                    "allowed_mime_types"?: (string)[] | null,"avif_autodetection"?: boolean | null,"created_at"?: string | null,"file_size_limit"?: number | null,"id": string,"lifecycle_configuration"?: Json | null,"lifecycle_configuration_generation"?: string | null,"name": string,"owner"?: string | null,"owner_id"?: string | null,"public"?: boolean | null,"type"?: Database["storage"]['Enums']["buckettype"],"updated_at"?: string | null,"versioning_status"?: string
                  }
                  Update: {
                    "allowed_mime_types"?: (string)[] | null,"avif_autodetection"?: boolean | null,"created_at"?: string | null,"file_size_limit"?: number | null,"id"?: string,"lifecycle_configuration"?: Json | null,"lifecycle_configuration_generation"?: string | null,"name"?: string,"owner"?: string | null,"owner_id"?: string | null,"public"?: boolean | null,"type"?: Database["storage"]['Enums']["buckettype"],"updated_at"?: string | null,"versioning_status"?: string
                  }
                  Relationships: [
                    
                  ]
                },"buckets_analytics": {
                  Row: {
                    "created_at": string,"deleted_at": string | null,"format": string,"id": string,"name": string,"type": Database["storage"]['Enums']["buckettype"],"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"deleted_at"?: string | null,"format"?: string,"id"?: string,"name": string,"type"?: Database["storage"]['Enums']["buckettype"],"updated_at"?: string
                  }
                  Update: {
                    "created_at"?: string,"deleted_at"?: string | null,"format"?: string,"id"?: string,"name"?: string,"type"?: Database["storage"]['Enums']["buckettype"],"updated_at"?: string
                  }
                  Relationships: [
                    
                  ]
                },"buckets_vectors": {
                  Row: {
                    "created_at": string,"id": string,"type": Database["storage"]['Enums']["buckettype"],"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"id": string,"type"?: Database["storage"]['Enums']["buckettype"],"updated_at"?: string
                  }
                  Update: {
                    "created_at"?: string,"id"?: string,"type"?: Database["storage"]['Enums']["buckettype"],"updated_at"?: string
                  }
                  Relationships: [
                    
                  ]
                },"iceberg_namespaces": {
                  Row: {
                    "bucket_name": string,"catalog_id": string,"created_at": string,"id": string,"metadata": NonNullable<Json>,"name": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "bucket_name": string,"catalog_id": string,"created_at"?: string,"id"?: string,"metadata"?: NonNullable<Json>,"name": string,"updated_at"?: string
                  }
                  Update: {
                    "bucket_name"?: string,"catalog_id"?: string,"created_at"?: string,"id"?: string,"metadata"?: NonNullable<Json>,"name"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "iceberg_namespaces_catalog_id_fkey"
      columns: ["catalog_id"]
isOneToOne: false
      referencedRelation: "buckets_analytics"
      referencedColumns: ["id"]
    }
                  ]
                },"iceberg_tables": {
                  Row: {
                    "bucket_name": string,"catalog_id": string,"created_at": string,"id": string,"location": string,"name": string,"namespace_id": string,"remote_table_id": string | null,"shard_id": string | null,"shard_key": string | null,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "bucket_name": string,"catalog_id": string,"created_at"?: string,"id"?: string,"location": string,"name": string,"namespace_id": string,"remote_table_id"?: string | null,"shard_id"?: string | null,"shard_key"?: string | null,"updated_at"?: string
                  }
                  Update: {
                    "bucket_name"?: string,"catalog_id"?: string,"created_at"?: string,"id"?: string,"location"?: string,"name"?: string,"namespace_id"?: string,"remote_table_id"?: string | null,"shard_id"?: string | null,"shard_key"?: string | null,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "iceberg_tables_catalog_id_fkey"
      columns: ["catalog_id"]
isOneToOne: false
      referencedRelation: "buckets_analytics"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "iceberg_tables_namespace_id_fkey"
      columns: ["namespace_id"]
isOneToOne: false
      referencedRelation: "iceberg_namespaces"
      referencedColumns: ["id"]
    }
                  ]
                },"migrations": {
                  Row: {
                    "executed_at": string | null,"hash": string,"id": number,"name": string
                  }
                  ComputedFields: never
                  Insert: {
                    "executed_at"?: string | null,"hash": string,"id": number,"name": string
                  }
                  Update: {
                    "executed_at"?: string | null,"hash"?: string,"id"?: number,"name"?: string
                  }
                  Relationships: [
                    
                  ]
                },"objects": {
                  Row: {
                    "archived_at": string | null,"bucket_id": string | null,"created_at": string | null,"id": string,"is_delete_marker": boolean,"is_versioned": boolean,"last_accessed_at": string | null,"metadata": Json | null,"name": string | null,"owner": string | null,"owner_id": string | null,"path_tokens": (string)[] | null,"updated_at": string | null,"user_metadata": Json | null,"version": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "archived_at"?: string | null,"bucket_id"?: string | null,"created_at"?: string | null,"id"?: string,"is_delete_marker"?: boolean,"is_versioned"?: boolean,"last_accessed_at"?: string | null,"metadata"?: Json | null,"name"?: string | null,"owner"?: string | null,"owner_id"?: string | null,"path_tokens"?: never,"updated_at"?: string | null,"user_metadata"?: Json | null,"version"?: string | null
                  }
                  Update: {
                    "archived_at"?: string | null,"bucket_id"?: string | null,"created_at"?: string | null,"id"?: string,"is_delete_marker"?: boolean,"is_versioned"?: boolean,"last_accessed_at"?: string | null,"metadata"?: Json | null,"name"?: string | null,"owner"?: string | null,"owner_id"?: string | null,"path_tokens"?: never,"updated_at"?: string | null,"user_metadata"?: Json | null,"version"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "objects_bucketId_fkey"
      columns: ["bucket_id"]
isOneToOne: false
      referencedRelation: "buckets"
      referencedColumns: ["id"]
    }
                  ]
                },"s3_multipart_uploads": {
                  Row: {
                    "bucket_id": string,"created_at": string,"id": string,"in_progress_size": number,"key": string,"metadata": Json | null,"owner_id": string | null,"upload_signature": string,"user_metadata": Json | null,"version": string
                  }
                  ComputedFields: never
                  Insert: {
                    "bucket_id": string,"created_at"?: string,"id": string,"in_progress_size"?: number,"key": string,"metadata"?: Json | null,"owner_id"?: string | null,"upload_signature": string,"user_metadata"?: Json | null,"version": string
                  }
                  Update: {
                    "bucket_id"?: string,"created_at"?: string,"id"?: string,"in_progress_size"?: number,"key"?: string,"metadata"?: Json | null,"owner_id"?: string | null,"upload_signature"?: string,"user_metadata"?: Json | null,"version"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "s3_multipart_uploads_bucket_id_fkey"
      columns: ["bucket_id"]
isOneToOne: false
      referencedRelation: "buckets"
      referencedColumns: ["id"]
    }
                  ]
                },"s3_multipart_uploads_parts": {
                  Row: {
                    "bucket_id": string,"created_at": string,"etag": string,"id": string,"key": string,"owner_id": string | null,"part_number": number,"size": number,"upload_id": string,"version": string
                  }
                  ComputedFields: never
                  Insert: {
                    "bucket_id": string,"created_at"?: string,"etag": string,"id"?: string,"key": string,"owner_id"?: string | null,"part_number": number,"size"?: number,"upload_id": string,"version": string
                  }
                  Update: {
                    "bucket_id"?: string,"created_at"?: string,"etag"?: string,"id"?: string,"key"?: string,"owner_id"?: string | null,"part_number"?: number,"size"?: number,"upload_id"?: string,"version"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "s3_multipart_uploads_parts_bucket_id_fkey"
      columns: ["bucket_id"]
isOneToOne: false
      referencedRelation: "buckets"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "s3_multipart_uploads_parts_upload_id_fkey"
      columns: ["upload_id"]
isOneToOne: false
      referencedRelation: "s3_multipart_uploads"
      referencedColumns: ["id"]
    }
                  ]
                },"vector_indexes": {
                  Row: {
                    "bucket_id": string,"created_at": string,"data_type": string,"dimension": number,"distance_metric": string,"id": string,"metadata_configuration": Json | null,"name": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "bucket_id": string,"created_at"?: string,"data_type": string,"dimension": number,"distance_metric": string,"id"?: string,"metadata_configuration"?: Json | null,"name": string,"updated_at"?: string
                  }
                  Update: {
                    "bucket_id"?: string,"created_at"?: string,"data_type"?: string,"dimension"?: number,"distance_metric"?: string,"id"?: string,"metadata_configuration"?: Json | null,"name"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "vector_indexes_bucket_id_fkey"
      columns: ["bucket_id"]
isOneToOne: false
      referencedRelation: "buckets_vectors"
      referencedColumns: ["id"]
    }
                  ]
                }
          }
          Views: {
            [_ in never]: never
          }
          Functions: {
            "allow_any_operation":
{ Args: { "expected_operations": (string)[] }; Returns: boolean
                           },
"allow_only_operation":
{ Args: { "expected_operation": string }; Returns: boolean
                           },
"can_insert_object":
{ Args: { "bucketid": string,"metadata": Json,"name": string,"owner": string }; Returns: undefined
                           },
"extension":
{ Args: { "name": string }; Returns: string
                           },
"filename":
{ Args: { "name": string }; Returns: string
                           },
"foldername":
{ Args: { "name": string }; Returns: (string)[]
                           },
"get_common_prefix":
{ Args: { "p_delimiter": string,"p_key": string,"p_prefix": string }; Returns: string
                           },
"get_size_by_bucket":
{ Args: { "delete_markers"?: string,"noncurrent_versions"?: string }; Returns: {
              "bucket_id": string,"size": number
            }[]
                           },
"list_multipart_uploads_with_delimiter":
{ Args: { "bucket_id": string,"delimiter_param": string,"max_keys"?: number,"next_key_token"?: string,"next_upload_token"?: string,"prefix_param": string,"raw_prefix_param"?: string }; Returns: {
              "created_at": string,"id": string,"key": string
            }[]
                           },
"list_objects_with_delimiter":
{ Args: { "_bucket_id": string,"delete_markers"?: string,"delimiter_param": string,"max_keys"?: number,"next_token"?: string,"next_token_archived_at"?: string,"next_token_version"?: string,"noncurrent_versions"?: string,"prefix_param": string,"sort_order"?: string,"start_after"?: string }; Returns: {
              "archived_at": string,"created_at": string,"id": string,"is_delete_marker": boolean,"is_versioned": boolean,"last_accessed_at": string,"metadata": Json,"name": string,"updated_at": string,"version": string
            }[]
                           },
"operation":
{ Args: Record<PropertyKey, never>; Returns: string
                           },
"search":
{ Args: { "bucketname": string,"delete_markers"?: string,"levels"?: number,"limits"?: number,"noncurrent_versions"?: string,"offsets"?: number,"prefix": string,"search"?: string,"sortcolumn"?: string,"sortorder"?: string }; Returns: {
              "archived_at": string,"created_at": string,"id": string,"is_delete_marker": boolean,"is_versioned": boolean,"last_accessed_at": string,"metadata": Json,"name": string,"updated_at": string,"version": string
            }[]
                           },
"search_by_timestamp":
{ Args: { "delete_markers"?: string,"noncurrent_versions"?: string,"p_bucket_id": string,"p_level": number,"p_limit": number,"p_prefix": string,"p_sort_column": string,"p_sort_column_after": string,"p_sort_order": string,"p_start_after": string,"p_start_after_version"?: string }; Returns: {
              "archived_at": string,"created_at": string,"id": string,"is_delete_marker": boolean,"is_versioned": boolean,"key": string,"last_accessed_at": string,"metadata": Json,"name": string,"updated_at": string,"version": string
            }[]
                           },
"search_v2":
{ Args: { "bucket_name": string,"delete_markers"?: string,"levels"?: number,"limits"?: number,"noncurrent_versions"?: string,"prefix": string,"sort_column"?: string,"sort_column_after"?: string,"sort_order"?: string,"start_after"?: string,"start_after_archived_at"?: string,"start_after_is_continuation"?: boolean,"start_after_version"?: string }; Returns: {
              "archived_at": string,"created_at": string,"id": string,"is_delete_marker": boolean,"is_versioned": boolean,"key": string,"last_accessed_at": string,"metadata": Json,"name": string,"updated_at": string,"version": string
            }[]
                           }
          }
          Enums: {
            "buckettype": "STANDARD"|"ANALYTICS"|"VECTOR"
          }
          CompositeTypes: {
            [_ in never]: never
          }
        }
}

type DatabaseWithoutInternals = Omit<Database, '__InternalSupabase'>

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
  ? (DefaultSchema["Tables"] & DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
      Row: infer R
    }
    ? R
    : never
  : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
  ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
      Insert: infer I
    }
    ? I
    : never
  : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
  ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
      Update: infer U
    }
    ? U
    : never
  : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never
> = DefaultSchemaEnumNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
  ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
  : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never
> = PublicCompositeTypeNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
  ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
  : never

export const Constants = {
  "billing": {
          Enums: {
            
          }
        },"crm": {
          Enums: {
            
          }
        },"public": {
          Enums: {
            "log_level": ["info", "warning", "error"],"role": ["owner", "admin", "member"],"service": ["whatsapp", "instagram", "local", "slack", "discord", "teams", "whatsapp-web"],"webhook_operation": ["insert", "update"],"webhook_table": ["messages", "conversations", "organizations_addresses", "contacts_addresses", "logs"]
          }
        },"storage": {
          Enums: {
            "buckettype": ["STANDARD", "ANALYTICS", "VECTOR"]
          }
        }
} as const
