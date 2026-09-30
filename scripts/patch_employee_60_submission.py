from pathlib import Path

path = Path('lib/screens/shared/add_user_screen.dart')
source = path.read_text()
anchor = '        canManageSubscription: _canManageSubscription,\n'
if '        canViewDashboard: _canViewDashboard,\n' in source[source.find('await PBService.createUser('):source.find('debtLimit: debtLimit')]:
    print('Patch already applied')
    raise SystemExit(0)
if anchor not in source:
    raise SystemExit('Expected createUser permission insertion point not found')
lines = [
    '        canViewDashboard: _canViewDashboard,',
    '        canViewRecentActivity: _canViewRecentActivity,',
    '        canViewTransactions: _canViewTransactions,',
    '        canEditPayments: _canEditPayments,',
    '        canDeletePayments: _canDeletePayments,',
    '        canCreateStatements: _canCreateStatements,',
    '        canManageCustomerLinks: _canManageCustomerLinks,',
    '        canPinCustomers: _canPinCustomers,',
    '        canManageVipCustomers: _canManageVipCustomers,',
    '        canMergeCustomerIdentities: _canMergeCustomerIdentities,',
    '        canViewMarketRates: _canViewMarketRates,',
    '        canViewIntelligence: _canViewIntelligence,',
    '        canManageCollections: _canManageCollections,',
    '        canViewExpiry: _canViewExpiry,',
    '        canManageExpiry: _canManageExpiry,',
    '        canManageSettings: _canManageSettings,',
]
insert = '\n'.join(lines) + '\n'
source = source.replace(anchor, anchor + insert, 1)
path.write_text(source)
print('Added 16 missing employee permission arguments')
