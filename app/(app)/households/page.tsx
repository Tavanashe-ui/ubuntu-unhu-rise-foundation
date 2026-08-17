import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'
import { getSession, can } from '@/lib/session'

export default async function HouseholdsPage({
  searchParams,
}: {
  searchParams: Promise<{ created?: string }>
}) {
  const { created } = await searchParams
  const session = await getSession()
  const supabase = await createClient()

  const { data: rows, error } = await supabase
    .schema('app')
    .from('household_summary')
    .select('id, ref, head_name, community, province, district, phone, child_count, active_child_count, primary_guardian')
    .order('created_at', { ascending: false })
    .limit(50)

  return (
    <main className="p-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold text-stone-900">Households</h1>
          <p className="mt-1 text-sm text-stone-500">
            Families and caregiving units. Register the household first, then link
            each child to it.
          </p>
        </div>
        {can(session, 'household', 'create') && (
          <Link
            href="/households/new"
            className="shrink-0 rounded-md bg-stone-900 px-4 py-2 text-sm font-medium text-white hover:bg-stone-800"
          >
            Add household
          </Link>
        )}
      </div>

      {created && (
        <p className="mt-4 rounded-md bg-green-50 p-3 text-sm text-green-800">
          Household created as <span className="font-mono font-medium">{created}</span>.
        </p>
      )}

      {error && (
        <p className="mt-4 rounded-md bg-red-50 p-3 text-sm text-red-800">
          {error.message}
        </p>
      )}

      {rows && rows.length === 0 && (
        <div className="mt-8 rounded-md border border-dashed border-stone-300 p-8 text-center">
          <p className="text-sm text-stone-600">No households recorded yet.</p>
          <p className="mt-1 text-xs text-stone-500">
            Recording the household is what lets the Foundation see siblings,
            shared circumstances, and support already given to a family.
          </p>
        </div>
      )}

      {rows && rows.length > 0 && (
        <div className="mt-6 overflow-x-auto rounded-md border border-stone-200 bg-white">
          <table className="w-full text-sm">
            <thead className="bg-stone-50 text-left text-xs uppercase tracking-wide text-stone-500">
              <tr>
                <th className="px-4 py-2">Reference</th>
                <th className="px-4 py-2">Head of household</th>
                <th className="px-4 py-2">Guardian</th>
                <th className="px-4 py-2">Location</th>
                <th className="px-4 py-2">Children</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-stone-100">
              {rows.map((r) => (
                <tr key={r.id} className="hover:bg-stone-50">
                  <td className="px-4 py-2 font-mono text-xs">{r.ref}</td>
                  <td className="px-4 py-2 font-medium">{r.head_name}</td>
                  <td className="px-4 py-2 text-stone-600">
                    {r.primary_guardian ?? <span className="text-stone-400">—</span>}
                  </td>
                  <td className="px-4 py-2 text-stone-600">
                    {[r.community, r.district, r.province].filter(Boolean).join(', ') || '—'}
                  </td>
                  <td className="px-4 py-2">
                    {r.child_count === 0 ? (
                      <span className="text-amber-700">None linked</span>
                    ) : (
                      <span>
                        {r.child_count}
                        {r.active_child_count !== r.child_count && (
                          <span className="text-stone-500">
                            {' '}({r.active_child_count} active)
                          </span>
                        )}
                      </span>
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