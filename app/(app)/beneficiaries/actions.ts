'use server'

import { revalidatePath } from 'next/cache'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'

export type FormState = {
  fieldErrors?: Record<string, string>
  error?: string
  duplicates?: { ref: string; first_name: string; surname: string }[]
  values?: Record<string, string>
} | null

function str(fd: FormData, k: string) {
  return String(fd.get(k) ?? '').trim()
}

export async function createBeneficiary(
  _prev: FormState,
  formData: FormData
): Promise<FormState> {
  const values: Record<string, string> = {}
  for (const [k, v] of formData.entries()) {
    if (typeof v === 'string') values[k] = v
  }

  const first_name = str(formData, 'first_name')
  const surname = str(formData, 'surname')
  const date_of_birth = str(formData, 'date_of_birth')
  const gender = str(formData, 'gender')

  const fieldErrors: Record<string, string> = {}
  if (!first_name) fieldErrors.first_name = 'Required'
  if (!surname) fieldErrors.surname = 'Required'
  if (!date_of_birth) fieldErrors.date_of_birth = 'Required'
  if (!gender) fieldErrors.gender = 'Required'

  if (date_of_birth) {
    const dob = new Date(date_of_birth)
    const now = new Date()
    if (dob > now) fieldErrors.date_of_birth = 'Cannot be in the future'
    const years = (now.getTime() - dob.getTime()) / 31557600000
    if (years > 25) fieldErrors.date_of_birth = 'Over 25 — check this is correct'
  }

  if (Object.keys(fieldErrors).length) return { fieldErrors, values }

  const supabase = await createClient()
  const { data: auth } = await supabase.auth.getUser()
  if (!auth.user) return { error: 'Your session expired. Sign in again.', values }

  // Duplicate detection (PRD §31). Same name and same date of birth is almost
  // always the same child — most often a sibling registered by another officer.
  // We warn rather than block: twins exist, and so do genuine name collisions.
  if (str(formData, 'confirm_duplicate') !== 'yes') {
    const { data: dupes } = await supabase
      .schema('app')
      .from('beneficiary')
      .select('ref, first_name, surname')
      .eq('date_of_birth', date_of_birth)
      .ilike('first_name', first_name)
      .ilike('surname', surname)
      .is('deleted_at', null)

    if (dupes && dupes.length > 0) {
      return { duplicates: dupes, values }
    }
  }

  const province_id = str(formData, 'province_id')
  const district_id = str(formData, 'district_id')
  const consent = formData.get('consent_on_file') === 'on'

  const { data, error } = await supabase
    .schema('app')
    .from('beneficiary')
    .insert({
      first_name,
      surname,
      preferred_name: str(formData, 'preferred_name') || null,
      date_of_birth,
      gender,
      has_disability: formData.get('has_disability') === 'on',
      disability_notes: str(formData, 'disability_notes') || null,
      household_id: str(formData, 'household_id') || null,
      school_name: str(formData, 'school_name') || null,
      grade: str(formData, 'grade') || null,
      province_id: province_id ? Number(province_id) : null,
      district_id: district_id ? Number(district_id) : null,
      community: str(formData, 'community') || null,
      emergency_contact_name: str(formData, 'emergency_contact_name') || null,
      emergency_contact_phone: str(formData, 'emergency_contact_phone') || null,
      consent_on_file: consent,
      consent_given_by: consent ? str(formData, 'consent_given_by') || null : null,
      consent_date: consent ? str(formData, 'consent_date') || null : null,
      // The registering officer owns the record by default. This is what makes
      // 'assigned' scope work for field officers.
      assigned_officer_id: auth.user.id,
      created_by: auth.user.id,
    })
    .select('ref')
    .single()

  if (error) {
    return { error: `Could not save: ${error.message}`, values }
  }

  revalidatePath('/beneficiaries')
  revalidatePath('/households')
  redirect(`/beneficiaries?created=${data.ref}`)
}