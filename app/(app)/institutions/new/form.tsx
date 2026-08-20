'use client'

import { useActionState, useState } from 'react'
import Link from 'next/link'
import { createInstitution, type InstitutionFormState } from '../actions'

type Province = { id: number; name: string }
type District = { id: number; province_id: number; district: string }

const field =
  'mt-1 w-full rounded-md border border-stone-300 px-3 py-2 text-stone-900 outline-none focus:border-stone-900'
const label = 'block text-sm font-medium text-stone-700'

export default function InstitutionForm({
  provinces,
  districts,
}: {
  provinces: Province[]
  districts: District[]
}) {
  const [state, formAction, pending] = useActionState<InstitutionFormState, FormData>(
    createInstitution,
    null
  )
  const [provinceId, setProvinceId] = useState('')

  const v = state?.values ?? {}
  const err = state?.fieldErrors ?? {}
  const visibleDistricts = districts.filter(
    (d) => String(d.province_id) === provinceId
  )

  return (
    <main className="p-6 pb-20">
      <Link href="/institutions" className="text-sm text-stone-500 underline">
        Institutions
      </Link>
      <h1 className="mt-2 text-2xl font-semibold text-stone-900">Add an institution</h1>
      <p className="mt-1 text-sm text-stone-500">
        Record the organisation before assessing its needs.
      </p>

      {state?.error && (
        <p role="alert" className="mt-4 rounded-md bg-red-50 p-3 text-sm text-red-800">
          {state.error}
        </p>
      )}

      <form action={formAction} className="mt-6 max-w-2xl space-y-6">
        <fieldset className="space-y-4">
          <legend className="text-sm font-semibold uppercase tracking-wide text-stone-500">
            Organisation
          </legend>

          <div>
            <label htmlFor="name" className={label}>Name *</label>
            <input id="name" name="name" defaultValue={v.name} className={field} />
            {err.name && <p className="mt-1 text-xs text-red-700">{err.name}</p>}
          </div>

          <div className="grid gap-4 sm:grid-cols-2">
            <div>
              <label htmlFor="type" className={label}>Type *</label>
              <select id="type" name="type" defaultValue={v.type ?? ''} className={field}>
                <option value="">Select...</option>
                <option value="childrens_home">Children&apos;s home</option>
                <option value="orphanage">Orphanage</option>
                <option value="school">School</option>
                <option value="clinic">Clinic</option>
                <option value="community_org">Community organisation</option>
                <option value="church">Church</option>
                <option value="ngo">NGO</option>
                <option value="government">Government institution</option>
                <option value="corporate">Corporate partner</option>
              </select>
              {err.type && <p className="mt-1 text-xs text-red-700">{err.type}</p>}
            </div>

            <div>
              <label htmlFor="partnership_status" className={label}>Partnership status</label>
              <select
                id="partnership_status"
                name="partnership_status"
                defaultValue={v.partnership_status ?? 'prospective'}
                className={field}
              >
                <option value="prospective">Prospective</option>
                <option value="under_assessment">Under assessment</option>
                <option value="active">Active</option>
                <option value="paused">Paused</option>
                <option value="ended">Ended</option>
              </select>
            </div>
          </div>

          <div>
            <label htmlFor="beneficiary_count" className={label}>
              Number of children at this institution
            </label>
            <input
              id="beneficiary_count"
              name="beneficiary_count"
              type="number"
              min="0"
              defaultValue={v.beneficiary_count}
              className={field}
            />
            {err.beneficiary_count && (
              <p className="mt-1 text-xs text-red-700">{err.beneficiary_count}</p>
            )}
            <p className="mt-1 text-xs text-stone-500">
              As reported by the institution. Individual children are registered
              separately, so this is a headline figure, not a count of records.
            </p>
          </div>
        </fieldset>

        <fieldset className="space-y-4">
          <legend className="text-sm font-semibold uppercase tracking-wide text-stone-500">
            Contact
          </legend>
          <div>
            <label htmlFor="contact_person" className={label}>Contact person</label>
            <input id="contact_person" name="contact_person" defaultValue={v.contact_person} className={field} />
          </div>
          <div className="grid gap-4 sm:grid-cols-2">
            <div>
              <label htmlFor="phone" className={label}>Phone</label>
              <input id="phone" name="phone" type="tel" defaultValue={v.phone} className={field} />
            </div>
            <div>
              <label htmlFor="email" className={label}>Email</label>
              <input id="email" name="email" type="email" defaultValue={v.email} className={field} />
            </div>
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
            <label htmlFor="address" className={label}>Address or directions</label>
            <textarea id="address" name="address" rows={2} defaultValue={v.address} className={field} />
          </div>
        </fieldset>

        <fieldset className="space-y-4">
          <legend className="text-sm font-semibold uppercase tracking-wide text-stone-500">
            Engagement
          </legend>
          <div className="grid gap-4 sm:grid-cols-2">
            <div>
              <label htmlFor="first_visited_on" className={label}>First visited</label>
              <input id="first_visited_on" name="first_visited_on" type="date" defaultValue={v.first_visited_on} className={field} />
            </div>
            <div>
              <label htmlFor="next_followup_on" className={label}>Next follow-up</label>
              <input id="next_followup_on" name="next_followup_on" type="date" defaultValue={v.next_followup_on} className={field} />
              <p className="mt-1 text-xs text-stone-500">
                Flagged on the list once overdue.
              </p>
            </div>
          </div>

          <div>
            <label htmlFor="main_needs" className={label}>Main needs</label>
            <textarea id="main_needs" name="main_needs" rows={3} defaultValue={v.main_needs} className={field} />
            <p className="mt-1 text-xs text-stone-500">
              A first impression. A full needs assessment comes later.
            </p>
          </div>

          <div>
            <label htmlFor="notes" className={label}>Notes</label>
            <textarea id="notes" name="notes" rows={3} defaultValue={v.notes} className={field} />
          </div>
        </fieldset>

        <div className="flex items-center gap-3">
          <button
            type="submit"
            disabled={pending}
            className="rounded-md bg-stone-900 px-5 py-2 text-sm font-medium text-white hover:bg-stone-800 disabled:opacity-50"
          >
            {pending ? 'Saving...' : 'Add institution'}
          </button>
          <Link href="/institutions" className="text-sm text-stone-600 underline">
            Cancel
          </Link>
        </div>
      </form>
    </main>
  )
}