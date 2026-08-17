'use client'

import { useActionState, useState } from 'react'
import Link from 'next/link'
import { createBeneficiary, type FormState } from '../actions'

type Province = { id: number; name: string }
type District = { id: number; province_id: number; district: string }

const field =
  'mt-1 w-full rounded-md border border-stone-300 px-3 py-2 text-stone-900 outline-none focus:border-stone-900'
const label = 'block text-sm font-medium text-stone-700'

export default function BeneficiaryForm({
  provinces,
  districts,
}: {
  provinces: Province[]
  districts: District[]
}) {
  const [state, formAction, pending] = useActionState<FormState, FormData>(
    createBeneficiary,
    null
  )
  const [provinceId, setProvinceId] = useState('')
  const [hasDisability, setHasDisability] = useState(false)
  const [consent, setConsent] = useState(false)

  const v = state?.values ?? {}
  const err = state?.fieldErrors ?? {}
  const visibleDistricts = districts.filter(
    (d) => String(d.province_id) === provinceId
  )

  return (
    <main className="mx-auto max-w-2xl p-6 pb-20">
      <Link href="/beneficiaries" className="text-sm text-stone-500 underline">
        Beneficiaries
      </Link>
      <h1 className="mt-2 text-2xl font-semibold text-stone-900">
        Register a beneficiary
      </h1>
      <p className="mt-1 text-sm text-stone-500">
        A reference number is assigned automatically on save.
      </p>

      {state?.error && (
        <p role="alert" className="mt-4 rounded-md bg-red-50 p-3 text-sm text-red-800">
          {state.error}
        </p>
      )}

      {state?.duplicates && (
        <div role="alert" className="mt-4 rounded-md bg-amber-50 p-4 text-sm text-amber-900">
          <p className="font-medium">This child may already be registered.</p>
          <ul className="mt-2 list-inside list-disc">
            {state.duplicates.map((d) => (
              <li key={d.ref}>
                {d.first_name} {d.surname} — {d.ref}
              </li>
            ))}
          </ul>
          <p className="mt-2">
            Check the existing record before continuing. If this is a different
            child (a twin, or the same name by coincidence), tick below to save anyway.
          </p>
        </div>
      )}

      <form action={formAction} className="mt-6 space-y-6">
        <fieldset className="space-y-4">
          <legend className="text-sm font-semibold uppercase tracking-wide text-stone-500">
            Identity
          </legend>

          <div className="grid gap-4 sm:grid-cols-2">
            <div>
              <label htmlFor="first_name" className={label}>First name *</label>
              <input id="first_name" name="first_name" defaultValue={v.first_name} className={field} />
              {err.first_name && <p className="mt-1 text-xs text-red-700">{err.first_name}</p>}
            </div>
            <div>
              <label htmlFor="surname" className={label}>Surname *</label>
              <input id="surname" name="surname" defaultValue={v.surname} className={field} />
              {err.surname && <p className="mt-1 text-xs text-red-700">{err.surname}</p>}
            </div>
          </div>

          <div>
            <label htmlFor="preferred_name" className={label}>
              Preferred name
            </label>
            <input id="preferred_name" name="preferred_name" defaultValue={v.preferred_name} className={field} />
            <p className="mt-1 text-xs text-stone-500">
              What the child is actually called. Use this in conversation.
            </p>
          </div>

          <div className="grid gap-4 sm:grid-cols-2">
            <div>
              <label htmlFor="date_of_birth" className={label}>Date of birth *</label>
              <input id="date_of_birth" name="date_of_birth" type="date" defaultValue={v.date_of_birth} className={field} />
              {err.date_of_birth && <p className="mt-1 text-xs text-red-700">{err.date_of_birth}</p>}
            </div>
            <div>
              <label htmlFor="gender" className={label}>Gender *</label>
              <select id="gender" name="gender" defaultValue={v.gender ?? ''} className={field}>
                <option value="">Select...</option>
                <option value="female">Female</option>
                <option value="male">Male</option>
                <option value="other">Other</option>
                <option value="undisclosed">Prefer not to say</option>
              </select>
              {err.gender && <p className="mt-1 text-xs text-red-700">{err.gender}</p>}
              <p className="mt-1 text-xs text-stone-500">
                Recorded for equality monitoring only. Never used to decide access
                to any programme.
              </p>
            </div>
          </div>

          <div>
            <label className="flex items-center gap-2 text-sm text-stone-700">
              <input
                type="checkbox"
                name="has_disability"
                checked={hasDisability}
                onChange={(e) => setHasDisability(e.target.checked)}
              />
              Child has a disability
            </label>
            {hasDisability && (
              <textarea
                name="disability_notes"
                rows={2}
                placeholder="Support needs, not diagnosis"
                className={field}
              />
            )}
          </div>
        </fieldset>

        <fieldset className="space-y-4">
          <legend className="text-sm font-semibold uppercase tracking-wide text-stone-500">
            Location
          </legend>
          <div className="grid gap-4 sm:grid-cols-2">
            <div>
              <label htmlFor="province_id" className={label}>Province</label>
              <select
                id="province_id"
                name="province_id"
                value={provinceId}
                onChange={(e) => setProvinceId(e.target.value)}
                className={field}
              >
                <option value="">Select...</option>
                {provinces.map((p) => (
                  <option key={p.id} value={p.id}>{p.name}</option>
                ))}
              </select>
            </div>
            <div>
              <label htmlFor="district_id" className={label}>District</label>
              <select id="district_id" name="district_id" disabled={!provinceId} className={field}>
                <option value="">{provinceId ? 'Select...' : 'Choose a province first'}</option>
                {visibleDistricts.map((d) => (
                  <option key={d.id} value={d.id}>{d.district}</option>
                ))}
              </select>
            </div>
          </div>
          <div>
            <label htmlFor="community" className={label}>Community or ward</label>
            <input id="community" name="community" defaultValue={v.community} className={field} />
          </div>
        </fieldset>

        <fieldset className="space-y-4">
          <legend className="text-sm font-semibold uppercase tracking-wide text-stone-500">
            Education
          </legend>
          <div className="grid gap-4 sm:grid-cols-2">
            <div>
              <label htmlFor="school_name" className={label}>School</label>
              <input id="school_name" name="school_name" defaultValue={v.school_name} className={field} />
            </div>
            <div>
              <label htmlFor="grade" className={label}>Grade or form</label>
              <input id="grade" name="grade" defaultValue={v.grade} className={field} />
            </div>
          </div>
        </fieldset>

        <fieldset className="space-y-4">
          <legend className="text-sm font-semibold uppercase tracking-wide text-stone-500">
            Emergency contact
          </legend>
          <div className="grid gap-4 sm:grid-cols-2">
            <div>
              <label htmlFor="emergency_contact_name" className={label}>Name</label>
              <input id="emergency_contact_name" name="emergency_contact_name" defaultValue={v.emergency_contact_name} className={field} />
            </div>
            <div>
              <label htmlFor="emergency_contact_phone" className={label}>Phone</label>
              <input id="emergency_contact_phone" name="emergency_contact_phone" type="tel" defaultValue={v.emergency_contact_phone} className={field} />
            </div>
          </div>
        </fieldset>

        <fieldset className="space-y-4 rounded-md border border-stone-200 p-4">
          <legend className="px-1 text-sm font-semibold uppercase tracking-wide text-stone-500">
            Consent
          </legend>
          <p className="text-xs text-stone-600">
            Zimbabwe&apos;s Data Protection Act requires a lawful basis for holding a
            child&apos;s information. Register the child now if consent is still being
            obtained, but the record cannot become active until it is on file.
          </p>
          <label className="flex items-center gap-2 text-sm text-stone-700">
            <input
              type="checkbox"
              name="consent_on_file"
              checked={consent}
              onChange={(e) => setConsent(e.target.checked)}
            />
            Guardian consent obtained
          </label>
          {consent && (
            <div className="grid gap-4 sm:grid-cols-2">
              <div>
                <label htmlFor="consent_given_by" className={label}>Given by</label>
                <input id="consent_given_by" name="consent_given_by" placeholder="Guardian name" className={field} />
              </div>
              <div>
                <label htmlFor="consent_date" className={label}>Date</label>
                <input id="consent_date" name="consent_date" type="date" className={field} />
              </div>
            </div>
          )}
        </fieldset>

        {state?.duplicates && (
          <label className="flex items-center gap-2 rounded-md bg-amber-50 p-3 text-sm text-amber-900">
            <input type="checkbox" name="confirm_duplicate" value="yes" />
            I have checked the existing record — this is a different child
          </label>
        )}

        <div className="flex items-center gap-3">
          <button
            type="submit"
            disabled={pending}
            className="rounded-md bg-stone-900 px-5 py-2 text-sm font-medium text-white hover:bg-stone-800 disabled:opacity-50"
          >
            {pending ? 'Saving...' : 'Register beneficiary'}
          </button>
          <Link href="/beneficiaries" className="text-sm text-stone-600 underline">
            Cancel
          </Link>
        </div>
      </form>
    </main>
  )
}