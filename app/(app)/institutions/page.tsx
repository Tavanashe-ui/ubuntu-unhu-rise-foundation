import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'
import { getSession, can } from '@/lib/session'

const TYPE_LABELS: Record<string, string> = {
  childrens_home: "Children's home",
  orphanage: 'Orphanage',
  school: 'School',
  clinic: 'Clinic',
  community_org: 'Community organisation',
  church: 'Church',
  ngo: 'NGO',
  government: 'Government',
  corporate: 'Corporate partner',
}

const STATUS_STYLES: Record<string, string> = {
  prospective: 'text-stone-600',
  under_assessment: 'text-blue-700',
  active: 'text-green-700',
  paused: 'text-amber-700',
  ended: 'text-stone-400',
}

export default async function InstitutionsPage({
  searchParams,
}: {
  searchParams: Promise<{ created?: string }>
}) {
  const { created } = await searchParams
  const session = await getSession()
  const supabase = await createClient()

  const { data: rows, error } = await supabase
    .schema('app')
    .from('institution')
    .select('id, ref, name, type, contact_person, phone, beneficiary_count, partnership_status, next_followup_on')
    .is('deleted_at', null)
    .order('created_at', { ascending: false })
    .limit(100)

  const today = new Date().toISOString().slice(0, 10)
  const overdue = (rows ?? []).filter(
    (r) => r.next_followup_on && r.next_followup_on < today
  )

  return (
    <main className="p-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold text-stone-900">Institutions</h1>
          <p className="mt-1 text-sm text-stone-500">
            Children&apos;s homes, schools, clinics and partner organisations.
          </p>
        </div>
        {can(session, 'institution', 'create') && (
          <Link
            href="/institutions/new"
            className="shrink-0 rounded-md bg-stone-900 px-4 py-2 text-sm font-medium text-white hover:bg-stone-800"
          >
            Add institution
          </Link>
        )}
      </div>

      {created && (
        <p className="mt-4 rounded-md bg-green-50 p-3 text-sm text-green-800">
          Institution added as <span className="font-mono font-medium">{created}</span>.
        </p>
      )}

      {overdue.length > 0 && (
        <p className="mt-4 rounded-md bg-amber-50 p-3 text-sm text-amber-900">
          {overdue.length} institution{overdue.length > 1 ? 's have' : ' has'} an
          overdue follow-up.
        </p>
      )}

      {error && (
        <p className="mt-4 rounded-md bg-red-50 p-3 text-sm text-red-800">
          {error.message}
        </p>
      )}

      {rows && rows.length === 0 && (
        <div className="mt-8 rounded-md border border-dashed border-stone-300 p-8 text-center">
          <p className="text-sm text-stone-600">No institutions recorded yet.</p>
        </div>
      )}

      {rows && rows.length > 0 && (
        <div className="mt-6 overflow-x-auto rounded-md border border-stone-200 bg-white">
          <table className="w-full text-sm">
            <thead className="bg-stone-50 text-left text-xs uppercase tracking-wide text-stone-500">
              <tr>
                <th className="px-4 py-2">Reference</th>
                <th className="px-4 py-2">Name</th>
                <th className="px-4 py-2">Type</th>
                <th className="px-4 py-2">Contact</th>
                <th className="px-4 py-2">Children</th>
                <th className="px-4 py-2">Status</th>
                <th className="px-4 py-2">Follow-up</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-stone-100">
              {rows.map((r) => {
                const isOverdue = r.next_followup_on && r.next_followup_on < today
                return (
                  <tr key={r.id} className="hover:bg-stone-50">
                    <td className="px-4 py-2 font-mono text-xs">{r.ref}</td>
                    <td className="px-4 py-2 font-medium">{r.name}</td>
                    <td className="px-4 py-2 text-stone-600">
                      {TYPE_LABELS[r.type] ?? r.type}
                    </td>
                    <td className="px-4 py-2 text-stone-600">
                      {r.contact_person ?? <span className="text-stone-400">—</span>}
                      {r.phone && (
                        <span className="block text-xs text-stone-400">{r.phone}</span>
                      )}
                    </td>
                    <td className="px-4 py-2">
                      {r.beneficiary_count ?? <span className="text-stone-400">—</span>}
                    </td>
                    <td className={`px-4 py-2 capitalize ${STATUS_STYLES[r.partnership_status] ?? ''}`}>
                      {r.partnership_status.replace(/_/g, ' ')}
                    </td>
                    <td className="px-4 py-2">
                      {r.next_followup_on ? (
                        <span className={isOverdue ? 'font-medium text-amber-700' : 'text-stone-600'}>
                          {r.next_followup_on}
                        </span>
                      ) : (
                        <span className="text-stone-400">—</span>
                      )}
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>
      )}
    </main>
  )
}