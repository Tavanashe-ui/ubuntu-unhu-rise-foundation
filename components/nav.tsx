'use client'

import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { useState } from 'react'
import { logout } from '@/app/login/actions'

export type NavItem = { href: string; label: string }

export default function Nav({
  items,
  fullName,
  roleName,
}: {
  items: NavItem[]
  fullName: string
  roleName: string
}) {
  const pathname = usePathname()
  const [open, setOpen] = useState(false)

  const linkClass = (href: string) => {
    const active = pathname === href || pathname.startsWith(href + '/')
    return [
      'block rounded-md px-3 py-2 text-sm',
      active
        ? 'bg-stone-900 text-white'
        : 'text-stone-700 hover:bg-stone-100',
    ].join(' ')
  }

  return (
    <header className="border-b border-stone-200 bg-white">
      <div className="mx-auto flex max-w-5xl items-center justify-between gap-4 px-4 py-3">
        <Link href="/dashboard" className="shrink-0">
          <span className="block text-sm font-semibold leading-tight text-stone-900">
            Ubuntu/Unhu Rise
          </span>
          <span className="block text-xs text-stone-500">Foundation System</span>
        </Link>

        {/* Desktop nav */}
        <nav className="hidden items-center gap-1 sm:flex">
          {items.map((i) => (
            <Link key={i.href} href={i.href} className={linkClass(i.href)}>
              {i.label}
            </Link>
          ))}
        </nav>

        <div className="hidden items-center gap-3 sm:flex">
          <div className="text-right">
            <p className="text-xs font-medium text-stone-900">{fullName}</p>
            <p className="text-xs text-stone-500">{roleName}</p>
          </div>
          <form action={logout}>
            <button className="text-xs text-stone-500 underline hover:text-stone-900">
              Sign out
            </button>
          </form>
        </div>

        {/* Mobile toggle — field officers work on phones */}
        <button
          onClick={() => setOpen(!open)}
          aria-expanded={open}
          aria-label="Menu"
          className="rounded-md border border-stone-300 px-3 py-1.5 text-sm sm:hidden"
        >
          Menu
        </button>
      </div>

      {open && (
        <div className="border-t border-stone-200 px-4 py-3 sm:hidden">
          <nav className="space-y-1">
            {items.map((i) => (
              <Link
                key={i.href}
                href={i.href}
                onClick={() => setOpen(false)}
                className={linkClass(i.href)}
              >
                {i.label}
              </Link>
            ))}
          </nav>
          <div className="mt-3 border-t border-stone-200 pt-3">
            <p className="text-xs font-medium text-stone-900">{fullName}</p>
            <p className="text-xs text-stone-500">{roleName}</p>
            <form action={logout} className="mt-2">
              <button className="text-xs text-stone-500 underline">Sign out</button>
            </form>
          </div>
        </div>
      )}
    </header>
  )
}