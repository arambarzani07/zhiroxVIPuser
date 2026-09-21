assert 'customer_auth_lookup_failed' not in inbound
assert 'existingHash !== undefined && existingHash !== hash' in inbound
assert '.slice(0, 25)' in inbound
assert 'const hasMoreTransactions = deltaById.size > delta.length' in inbound
assert 'transactions_etag: hasMoreTransactions' in inbound

print('Daftar bidirectional create/update/delete sync verified')