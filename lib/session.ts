import { createClient } from '@/lib/supabase/server'

export type Session = {
  id: string
  email: string
  full_name: string
  job_title: string | null
  is_active: boolean
  roles: { code: string; name: string }[]
  permissions: string[]
}

export async function getSession(): Promise<Session | null> {
  const supabase = await createClient()
  const { data } = await supabase.rpc('current_session')
  return (data as Session) ?? null
}

/**
 * Mirrors app.may() in the database. This produces good error messages;
 * RLS is the barrier that holds if this check is ever forgotten.
 */
export function can(session: Session | null, resource: string, action: string) {
  if (!session) return false
  return session.permissions.some((p) => p.startsWith(`${resource}:${action}:`))
}

export function scopeFor(session: Session | null, resource: string, action: string) {
  const match = session?.permissions.find((p) => p.startsWith(`${resource}:${action}:`))
  return match ? match.split(':')[2] : null
}
