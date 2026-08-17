import { createClient } from '@/lib/supabase/server'
import { getSession, can } from '@/lib/session'
import HouseholdForm from './form'
import Link from 'next/link'

export default async function NewHouseholdPage() {
  const session = await getSession()

  if (!can(session, 'household', 'create')) {
    return (
      <main className="p-8">
        <h1 className="text-xl font-semibold">Not permitted</h1>
        <p className="mt-2 text-sm text-stone-600">
          Your role does not include creating households.
        </p>
        <Link href="/households" className="mt-4 inline-block text-sm underline">
          Back to households
        </Link>
      </main>
    )
  }

  const supabase = await createClient()
  const [{ data: provinces }, { data: districts }] = await Promise.all([
    supabase.schema('app').from('province').select('id, name').order('name'),
    supabase.schema('app').from('district_lookup').select('id, province_id, district'),
  ])

  return <HouseholdForm provinces={provinces ?? []} districts={districts ?? []} />
}