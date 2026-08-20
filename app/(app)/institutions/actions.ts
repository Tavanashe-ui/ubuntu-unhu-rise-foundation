'use server'

import { revalidatePath } from 'next/cache'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'

export type InstitutionFormState = {
  fieldErrors?: Record<string, string>
  error?: string
  values?: Record<string, string>
} | null

function str(fd: FormData, k: string) {
  return String(fd.get(k) ?? '').trim()
}

export async function createInstitution(
  _prev: InstitutionFormState,
  formData: FormData
): Promise<InstitutionFormState> {
  const values: Record<string, string> = {}
  for (const [k, v] of formData.entries()) {
    if (typeof v === 'string') values[k] = v
  }

  const name = str(formData, 'name')
  const type = str(formData, 'type')

  const fieldErrors: Record<string, string> = {}
  if (!name) fieldErrors.name = 'Required'
  if (!type) fieldErrors.type = 'Required'

  const count = str(formData, 'beneficiary_count')
  if (count && (isNaN(Number(count)) || Number(count) < 0)) {
    fieldErrors.beneficiary_count = 'Must be a number'
  }

  if (Object.keys(fieldErrors).length) return { fieldErrors, values }

  const supabase = await createClient()
  const { data: auth } = await supabase.auth.getUser()
  if (!auth.user) return { error: 'Your session expired. Sign in again.', values }

  const province_id = str(formData, 'province_id')
  const district_id = str(formData, 'district_id')

  const { data, error } = await supabase
    .schema('app')
    .from('institution')
    .insert({
      name,
      type,
      province_id: province_id ? Number(province_id) : null,
      district_id: district_id ? Number(district_id) : null,
      address: str(formData, 'address') || null,
      contact_person: str(formData, 'contact_person') || null,
      phone: str(formData, 'phone') || null,
      email: str(formData, 'email') || null,
      beneficiary_count: count ? Number(count) : null,
      main_needs: str(formData, 'main_needs') || null,
      partnership_status: str(formData, 'partnership_status') || 'prospective',
      first_visited_on: str(formData, 'first_visited_on') || null,
      next_followup_on: str(formData, 'next_followup_on') || null,
      notes: str(formData, 'notes') || null,
      created_by: auth.user.id,
    })
    .select('ref')
    .single()

  if (error) return { error: `Could not save: ${error.message}`, values }

  revalidatePath('/institutions')
  redirect(`/institutions?created=${data.ref}`)
}