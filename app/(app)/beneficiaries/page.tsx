import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'
import { getSession, can, scopeFor } from '@/lib/session'

export default async function BeneficiariesPage({
  searchParams,
}: {
  searchParams: Promise<{ created?: string }>
}) {
  const { created } = await searchParams
  const session = await getSession()
  const supabase = await createClient()

  const { data: rows, error } = await supabase
    .schema('app')
    .from('beneficiary_with_age')
    .select('id, ref, first_name, surname, preferred_name, age, gender, status, consent_on_file')
    .order('created_at', { ascending: false })
    .limit(50)

  const scope = scopeFor(session, 'beneficiary', 'read')

  return (
    <main className="mx-auto max-w-4xl p-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold text-stone-900">Beneficiaries</h1>
          <p className="mt-1 text-sm text-stone-500">
            {scope === 'assigned'
              ? 'Showing children assigned to you.'
              : scope === 'all'
              ? 'Showing all registered children.'
              : 'Limited view.'}
          </p>
        </div>
        {can(session, 'beneficiary', 'create') && (
          <Link
            href="/beneficiaries/new"
            className="rounded-md bg-stone-900 px-4 py-2 text-sm font-medium text-white hover:bg-stone-800"
          >
            Register
          </Link>
        )}
      </div>

      {created && (
        <p className="mt-4 rounded-md bg-green-50 p-3 text-sm text-green-800">
          Registered as <span className="font-mono font-medium">{created}</span>.
        </p>
      )}

      {error && (
        <p className="mt-4 rounded-md bg-red-50 p-3 text-sm text-red-800">
          {error.message}
        </p>
      )}

      {rows && rows.length === 0 && (
        <p className="mt-8 text-sm text-stone-500">No beneficiaries yet.</p>
      )}

      {rows && rows.length > 0 && (
        <div className="mt-6 overflow-hidden rounded-md border border-stone-200">
          <table className="w-full text-sm">
            <thead className="bg-stone-50 text-left text-xs uppercase tracking-wide text-stone-500">
              <tr>
                <th className="px-4 py-2">Reference</th>
                <th className="px-4 py-2">Name</th>
                <th className="px-4 py-2">Age</th>
                <th className="px-4 py-2">Status</th>
                <th className="px-4 py-2">Consent</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-stone-100">
              {rows.map((r) => (
                <tr key={r.id}>
                  <td className="px-4 py-2 font-mono text-xs">{r.ref}</td>
                  <td className="px-4 py-2">
                    {r.preferred_name || r.first_name} {r.surname}
                  </td>
                  <td className="px-4 py-2">{r.age}</td>
                  <td className="px-4 py-2 capitalize">{r.status.replace(/_/g, ' ')}</td>
                  <td className="px-4 py-2">
                    {r.consent_on_file ? (
                      <span className="text-green-700">On file</span>
                    ) : (
                      <span className="text-amber-700">Pending</span>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </main>
  )
}