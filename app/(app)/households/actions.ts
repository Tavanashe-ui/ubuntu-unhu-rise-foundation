'use server'

import { revalidatePath } from 'next/cache'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'

export type HouseholdFormState = {
  fieldErrors?: Record<string, string>
  error?: string
  values?: Record<string, string>
} | null

function str(fd: FormData, k: string) {
  return String(fd.get(k) ?? '').trim()
}

export async function createHousehold(
  _prev: HouseholdFormState,
  formData: FormData
): Promise<HouseholdFormState> {
  const values: Record<string, string> = {}
  for (const [k, v] of formData.entries()) {
    if (typeof v === 'string') values[k] = v
  }

  const head_name = str(formData, 'head_name')
  if (!head_name) {
    return { fieldErrors: { head_name: 'Required' }, values }
  }

  const supabase = await createClient()
  const { data: auth } = await supabase.auth.getUser()
  if (!auth.user) return { error: 'Your session expired. Sign in again.', values }

  const province_id = str(formData, 'province_id')
  const district_id = str(formData, 'district_id')

  const { data, error } = await supabase
    .schema('app')
    .from('household')
    .insert({
      head_name,
      province_id: province_id ? Number(province_id) : null,
      district_id: district_id ? Number(district_id) : null,
      community: str(formData, 'community') || null,
      address: str(formData, 'address') || null,
      phone: str(formData, 'phone') || null,
      economic_status: str(formData, 'economic_status') || null,
      vulnerability_notes: str(formData, 'vulnerability_notes') || null,
      assigned_officer_id: auth.user.id,
      created_by: auth.user.id,
    })
    .select('ref')
    .single()

  if (error) return { error: `Could not save: ${error.message}`, values }

  // A guardian is optional at this point — an officer may know the household
  // before knowing who holds parental responsibility.
  const guardian_name = str(formData, 'guardian_name')
  if (guardian_name) {
    const { data: hh } = await supabase
      .schema('app')
      .from('household')
      .select('id')
      .eq('ref', data.ref)
      .single()

    if (hh) {
      await supabase.schema('app').from('guardian').insert({
        household_id: hh.id,
        full_name: guardian_name,
        relationship: str(formData, 'guardian_relationship') || null,
        phone: str(formData, 'guardian_phone') || null,
        is_primary: true,
      })
    }
  }

  revalidatePath('/households')
  redirect(`/households?created=${data.ref}`)
}

export async function linkBeneficiaryToHousehold(formData: FormData) {
  const beneficiary_id = String(formData.get('beneficiary_id') ?? '')
  const household_id = String(formData.get('household_id') ?? '')
  if (!beneficiary_id || !household_id) return

  const supabase = await createClient()
  await supabase.rpc('link_to_household', {
    p_beneficiary_id: beneficiary_id,
    p_household_id: household_id,
  })

  revalidatePath('/households')
  revalidatePath('/beneficiaries')
}