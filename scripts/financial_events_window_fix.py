from pathlib import Path

path = Path('lib/services/pb_service.dart')
text = path.read_text()
old = """    final data = await client
        .from('financial_events')
        .select()
        .eq('customer_id', customerId)
        .order('created_at', ascending: true)
        .limit(500);
    return (data as List)
        .map((row) => _financialEventRecord(
              Map<String, dynamic>.from(row as Map),
            ))
        .toList();
"""
new = """    final data = await client
        .from('financial_events')
        .select()
        .eq('customer_id', customerId)
        .order('created_at', ascending: false)
        .limit(500);
    final events = (data as List)
        .map((row) => _financialEventRecord(
              Map<String, dynamic>.from(row as Map),
            ))
        .toList();
    return events.reversed.toList(growable: false);
"""
if old in text:
    path.write_text(text.replace(old, new, 1))
elif new not in text:
    raise SystemExit('financial event window marker not found')
