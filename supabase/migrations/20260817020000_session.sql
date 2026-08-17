-- =============================================================================
-- Ubuntu/Unhu Rise Foundation
-- Migration 0004: Session endpoint
--
-- The app schema is NOT exposed to the API. Instead the application calls this
-- one function, which returns only the caller's own identity and permissions.
--
-- This keeps the attack surface to a single, auditable entry point. Tables get
-- exposed later, deliberately, once row-level security is in place.
-- =============================================================================

create or replace function public.current_session()
returns jsonb
language plpgsql
security definer
set search_path = app, public
as $$
declare
  v_user_id uuid := auth.uid();
  v_result  jsonb;
begin
  if v_user_id is null then
    return null;
  end if;

  select jsonb_build_object(
    'id',        up.id,
    'email',     up.email,
    'full_name', up.full_name,
    'job_title', up.job_title,
    'is_active', up.is_active,

    'roles', coalesce((
      select jsonb_agg(jsonb_build_object('code', r.code, 'name', r.name)
                       order by r.code)
        from app.user_role ur
        join app.role r on r.id = ur.role_id
       where ur.user_id = up.id
    ), '[]'::jsonb),

    -- Flattened as "resource:action:scope" so the client can check membership
    -- with a simple set lookup rather than walking nested objects.
    'permissions', coalesce((
      select jsonb_agg(distinct p.resource || ':' || p.action || ':' || rp.scope)
        from app.user_role ur
        join app.role_permission rp on rp.role_id = ur.role_id
        join app.permission p       on p.id = rp.permission_id
       where ur.user_id = up.id
    ), '[]'::jsonb)
  )
  into v_result
  from app.user_profile up
  where up.id = v_user_id
    and up.is_active
    and up.deleted_at is null;

  return v_result;
end;
$$;

-- Only logged-in users may call it, and it only ever returns the caller's own
-- record — auth.uid() is set by Supabase from the verified JWT and cannot be
-- forged by the client.
revoke execute on function public.current_session() from anon, public;
grant   execute on function public.current_session() to authenticated;


-- Record the login timestamp. Called by the app after a successful sign-in.
create or replace function public.record_login()
returns void
language plpgsql
security definer
set search_path = app, public
as $$
begin
  update app.user_profile
     set last_login_at = now()
   where id = auth.uid();
end;
$$;

revoke execute on function public.record_login() from anon, public;
grant   execute on function public.record_login() to authenticated;