from pathlib import Path

source = Path("lib/services/pb_service.dart").read_text(encoding="utf-8")

required = [
    "DaftarLiveReadService.invokeMap(",
    "'get_customer_directory_page_filtered'",
    "p_filter': 'all'",
    "p_cursor_created_at",
    "p_cursor_id",
]

missing = [marker for marker in required if marker not in source]
if missing:
    raise SystemExit(f"customer directory fallback contract missing: {missing}")

block_start = source.find("static Future<Map<String, dynamic>> getCustomerDirectoryPage")
block_end = source.find("static Future<List<RecordModel>> getAllApprovedCustomers", block_start)
if block_start < 0 or block_end < 0:
    raise SystemExit("customer directory method boundaries not found")

block = source[block_start:block_end]
if "try {" not in block or "} catch" not in block:
    raise SystemExit("customer directory does not fail over from Daftar live-read")

if block.find("DaftarLiveReadService.invokeMap(") > block.find("'get_customer_directory_page_filtered'"):
    raise SystemExit("fallback order is invalid")

print("Customer directory fallback contract: OK")
