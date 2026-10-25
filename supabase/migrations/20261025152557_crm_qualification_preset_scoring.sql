-- Preset qualification scoring for the trading_institute pack (P3-04).
-- Confirmed with the user 2026-10-25: only capital_range and learning_goal
-- signal buying intent -- experience_level, preferred_market, and
-- batch_timing are useful for routing/course-fit but intentionally don't
-- affect the score. Total range is 2-7; junk_invalid is a manual staff
-- override, never produced by this scoring (crm.lead_qualities, P3-02).
insert into crm.preset_qualification_question_scores (pack_key, field_key, answer_value, points) values
  ('trading_institute', 'capital_range', 'under_50k', 1),
  ('trading_institute', 'capital_range', 'not_sure', 1),
  ('trading_institute', 'capital_range', 'between_50k_2l', 2),
  ('trading_institute', 'capital_range', 'between_2l_10l', 3),
  ('trading_institute', 'capital_range', 'above_10l', 4),
  ('trading_institute', 'learning_goal', 'understand_basics', 1),
  ('trading_institute', 'learning_goal', 'part_time', 2),
  ('trading_institute', 'learning_goal', 'full_time', 3);

insert into crm.preset_qualification_score_thresholds (pack_key, min_score, quality_key, status) values
  ('trading_institute', 2, 'low_intent', 'unqualified'),
  ('trading_institute', 4, 'medium_intent', 'qualified'),
  ('trading_institute', 6, 'high_intent', 'qualified');
