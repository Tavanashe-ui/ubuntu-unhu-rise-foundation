import { redirect } from 'next/navigation'
import { getSession, can } from '@/lib/session'
import Nav, { type NavItem } from '@/components/nav'

// Each entry declares what it needs. A user who cannot read beneficiaries never
// sees a Beneficiaries link — the nav reflects the permission matrix rather than
// offering doors that open onto a refusal.
const NAV: (NavItem & { resource: string; action: string })[] = [
  { href: '/dashboard',     label: 'Dashboard',     resource: 'report',      action: 'read' },
  { href: '/beneficiaries', label: 'Beneficiaries', resource: 'beneficiary', action: 'read' },
  { href: '/households',    label: 'Households',    resource: 'household',   action: 'read' },
  { href: '/institutions',  label: 'Institutions',  resource: 'institution', action: 'read' },
  { href: '/assessments',   label: 'Assessments',   resource: 'assessment',  action: 'read' },
]

export default async function AppLayout({
  children,
}: {
  children: React.ReactNode
}) {
  const session = await getSession()

  // The proxy already blocks unauthenticated requests. This catches the other
  // case: a valid login whose profile is deactivated or missing.
  if (!session) redirect('/login')

  const items: NavItem[] = NAV.filter((i) => can(session, i.resource, i.action)).map(
    ({ href, label }) => ({ href, label })
  )

  // Dashboard is always reachable, even for a user with minimal grants.
  if (!items.some((i) => i.href === '/dashboard')) {
    items.unshift({ href: '/dashboard', label: 'Dashboard' })
  }

  return (
    <div className="min-h-screen bg-stone-50">
      <Nav
        items={items}
        fullName={session.full_name}
        roleName={session.roles[0]?.name ?? 'No role assigned'}
      />
      <div className="mx-auto max-w-5xl">{children}</div>
    </div>
  )
}