'use client'

import { useActionState, useState } from 'react'
import Link from 'next/link'
import { createHousehold, type HouseholdFormState } from '../actions'

type Province = { id: number; name: string }
type District = { id: number; province_id: number; district: string }

const field =
  'mt-1 w-full rounded-md border border-stone-300 px-3 py-2 text-stone-900 outline-none focus:border-stone-900'
const label = 'block text-sm font-medium text-stone-700'

export default function HouseholdForm({
  provinces,
  districts,
}: {
  provinces: Province[]
  districts: District[]
}) {
  const [state, formAction, pending] = useActionState<HouseholdFormState, FormData>(
    createHousehold,
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
      <Link href="/households" className="text-sm text-stone-500 underline">
        Households
      </Link>
      <h1 className="mt-2 text-2xl font-semibold text-stone-900">Add a household</h1>
      <p className="mt-1 text-sm text-stone-500">
        Record the family unit first. Children are linked to it afterwards.
      </p>

      {state?.error && (
        <p role="alert" className="mt-4 rounded-md bg-red-50 p-3 text-sm text-red-800">
          {state.error}
        </p>
      )}

      <form action={formAction} className="mt-6 max-w-2xl space-y-6">
        <fieldset className="space-y-4">
          <legend className="text-sm font-semibold uppercase tracking-wide text-stone-500">
            Household
          </legend>

          <div>
            <label htmlFor="head_name" className={label}>Head of household *</label>
            <input id="head_name" name="head_name" defaultValue={v.head_name} className={field} />
            {err.head_name && <p className="mt-1 text-xs text-red-700">{err.head_name}</p>}
            <p className="mt-1 text-xs text-stone-500">
              The person the community would name as responsible for this home.
            </p>
          </div>

          <div>
            <label htmlFor="phone" className={label}>Phone</label>
            <input id="phone" name="phone" type="tel" defaultValue={v.phone} className={field} />
          </div>

          <div>
            <label htmlFor="economic_status" className={label}>Economic circumstances</label>
            <select id="economic_status" name="economic_status" defaultValue={v.economic_status ?? ''} className={field}>
              <option value="">Not recorded</option>
              <option value="no_income">No income</option>
              <option value="irregular_income">Irregular income</option>
              <option value="informal_trade">Informal trade</option>
              <option value="formal_employment">Formal employment</option>
              <option value="pension">Pension</option>
              <option value="other">Other</option>
              <option value="unknown">Unknown</option>
            </select>
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

          <div>
            <label htmlFor="address" className={label}>Address or directions</label>
            <textarea id="address" name="address" rows={2} defaultValue={v.address} className={field} />
            <p className="mt-1 text-xs text-stone-500">
              Written directions are often more use than a formal address.
            </p>
          </div>
        </fieldset>

        <fieldset className="space-y-4">
          <legend className="text-sm font-semibold uppercase tracking-wide text-stone-500">
            Primary guardian
          </legend>
          <p className="text-xs text-stone-500">
            Optional. This is who gives consent for the children, and may differ
            from the head of household.
          </p>
          <div className="grid gap-4 sm:grid-cols-2">
            <div>
              <label htmlFor="guardian_name" className={label}>Name</label>
              <input id="guardian_name" name="guardian_name" defaultValue={v.guardian_name} className={field} />
            </div>
            <div>
              <label htmlFor="guardian_relationship" className={label}>Relationship to children</label>
              <input
                id="guardian_relationship"
                name="guardian_relationship"
                placeholder="Mother, grandmother, aunt..."
                defaultValue={v.guardian_relationship}
                className={field}
              />
            </div>
          </div>
          <div>
            <label htmlFor="guardian_phone" className={label}>Guardian phone</label>
            <input id="guardian_phone" name="guardian_phone" type="tel" defaultValue={v.guardian_phone} className={field} />
          </div>
        </fieldset>

        <fieldset className="space-y-4">
          <legend className="text-sm font-semibold uppercase tracking-wide text-stone-500">
            Circumstances
          </legend>
          <div>
            <label htmlFor="vulnerability_notes" className={label}>Notes</label>
            <textarea
              id="vulnerability_notes"
              name="vulnerability_notes"
              rows={3}
              defaultValue={v.vulnerability_notes}
              className={field}
            />
            <p className="mt-1 text-xs text-stone-500">
              Factual and relevant to support. Avoid recording anything a family
              would be distressed to read back.
            </p>
          </div>
        </fieldset>

        <div className="flex items-center gap-3">
          <button
            type="submit"
            disabled={pending}
            className="rounded-md bg-stone-900 px-5 py-2 text-sm font-medium text-white hover:bg-stone-800 disabled:opacity-50"
          >
            {pending ? 'Saving...' : 'Create household'}
          </button>
          <Link href="/households" className="text-sm text-stone-600 underline">
            Cancel
          </Link>
        </div>
      </form>
    </main>
  )
}