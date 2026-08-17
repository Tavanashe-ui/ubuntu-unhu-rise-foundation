-- =============================================================================
-- Fix: audit.log.actor_email was always null.
--
-- It read a session variable (app.actor_email) that the application never set —
-- a design that depended on every caller remembering to set it, which is exactly
-- the failure mode trigger-based auditing exists to avoid.
--
-- Now derived from the actor's id. The email is denormalised into the log
-- deliberately: if a staff member's account is later renamed or removed, the log
-- must still show who acted at the time. An audit trail that changes
-- retrospectively is not an audit trail.
-- =============================================================================

create or replace function audit.track_changes()
returns trigger
language plpgsql
security definer
as $$
declare
  v_changed jsonb;
  v_id      text;
  v_ref     text;
  v_actor   uuid;
  v_email   text;
begin
  if tg_op = 'UPDATE' then
    select jsonb_object_agg(key, jsonb_build_object('from', old_j.value, 'to', new_j.value))
      into v_changed
      from jsonb_each(to_jsonb(old)) old_j
      join jsonb_each(to_jsonb(new)) new_j using (key)
     where old_j.value is distinct from new_j.value
       and key not in ('updated_at');

    if v_changed is null then
      return new;
    end if;
  elsif tg_op = 'INSERT' then
    v_changed := to_jsonb(new);
  else
    v_changed := to_jsonb(old);
  end if;

  v_id  := coalesce(to_jsonb(new)->>'id',  to_jsonb(old)->>'id');
  v_ref := coalesce(to_jsonb(new)->>'ref', to_jsonb(old)->>'ref');

  v_actor := audit.current_actor();

  -- Explicit override wins, otherwise look it up.
  v_email := nullif(current_setting('app.actor_email', true), '');
  if v_email is null and v_actor is not null then
    select email into v_email from app.user_profile where id = v_actor;
  end if;

  insert into audit.log (
    actor_id, actor_email, action, schema_name, table_name,
    record_id, record_ref, changed, ip_address
  ) values (
    v_actor, v_email, tg_op, tg_table_schema, tg_table_name,
    v_id, v_ref, v_changed,
    nullif(current_setting('app.ip_address', true), '')::inet
  );

  return coalesce(new, old);
end;
$$;