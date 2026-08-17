import { createClient } from '@/lib/supabase/server'
import { logout } from '../login/actions'

export default async function DashboardPage() {
  const supabase = await createClient()
  const { data: session } = await supabase.rpc('current_session')

  if (!session) {
    return (
      <main className="p-10">
        <p className="text-stone-700">
          Your account exists but has no active profile. Contact an administrator.
        </p>
      </main>
    )
  }

  const roles: { code: string; name: string }[] = session.roles ?? []
  const permissions: string[] = session.permissions ?? []

  return (
    <main className="mx-auto max-w-3xl p-10">
      <div className="flex items-start justify-between">
        <div>
          <h1 className="text-2xl font-semibold text-stone-900">
            {session.full_name}
          </h1>
          <p className="text-sm text-stone-500">{session.email}</p>
        </div>
        <form action={logout}>
          <button className="text-sm text-stone-600 underline hover:text-stone-900">
            Sign out
          </button>
        </form>
      </div>

      <section className="mt-8">
        <h2 className="text-sm font-medium uppercase tracking-wide text-stone-500">
          Roles
        </h2>
        <ul className="mt-2 flex flex-wrap gap-2">
          {roles.map((r) => (
            <li key={r.code}
                className="rounded-full bg-stone-900 px-3 py-1 text-xs text-white">
              {r.name}
            </li>
          ))}
        </ul>
      </section>

      <section className="mt-8">
        <h2 className="text-sm font-medium uppercase tracking-wide text-stone-500">
          Permissions ({permissions.length})
        </h2>
        <div className="mt-2 max-h-80 overflow-y-auto rounded-md border border-stone-200 p-3">
          <ul className="grid grid-cols-2 gap-x-4 gap-y-1 text-xs text-stone-600">
            {permissions.sort().map((p) => (
              <li key={p} className="font-mono">{p}</li>
            ))}
          </ul>
        </div>
      </section>
    </main>
  )
}
