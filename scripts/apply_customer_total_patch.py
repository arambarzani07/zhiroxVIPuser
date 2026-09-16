from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f'{label} anchor missing')
    return text.replace(old, new, 1)


# Customer dashboard: use the explicit customer-wide total from the finance RPC.
p = Path('lib/screens/customer/customer_dashboard.dart')
s = p.read_text()
s = replace_once(
    s,
    "  double _totalRemainingAmount = 0;\n  bool _totalsComplete = true;",
    "  double _totalRemainingAmount = 0;\n  double _totalPaidAmount = 0;\n  bool _totalsComplete = true;",
    'dashboard state',
)
s = replace_once(
    s,
    "  double get _totalDebt => _totalDebtAmount;",
    "  double get _totalDebt => _totalDebtAmount;\n\n  double get _totalPaid => _totalPaidAmount;",
    'dashboard getter',
)
s = replace_once(
    s,
    "        _totalRemainingAmount = snapshot['totalRemainingIqd'] as double;\n        _totalsComplete = snapshot['complete'] == true;",
    "        _totalRemainingAmount = snapshot['totalRemainingIqd'] as double;\n        _totalPaidAmount = snapshot['totalPaidIqd'] as double;\n        _totalsComplete = snapshot['complete'] == true;",
    'dashboard snapshot',
)
s = replace_once(
    s,
    "        totalPaid: _totalDebt - _totalRemaining,",
    "        totalPaid: _totalPaid,",
    'dashboard statement total',
)
s = replace_once(
    s,
    "    final totalPaid = _totalDebt - _totalRemaining;",
    "    final totalPaid = _totalPaid;",
    'dashboard display total',
)
p.write_text(s)

# Customer account statement: show all customer-wide totals explicitly.
p = Path('lib/services/pdf_service.dart')
s = p.read_text()
old = """            // ══════════════════════════════════════════════
            // SUMMARY - Total Debt Only
            // ══════════════════════════════════════════════
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(
                vertical: 14,
                horizontal: 16,
              ),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(
                  color: PdfColor.fromHex('#c62828'),
                  width: 1.5,
                ),
                borderRadius: pw.BorderRadius.circular(4),
                color: PdfColor.fromHex('#ffebee'),
              ),
              child: pw.Column(
                children: [
                  pw.Text(
                    _reshape('کۆی گشتی قەرز'),
                    style: pw.TextStyle(
                      font: ttf,
                      fontSize: 11,
                      color: PdfColor.fromHex('#c62828'),
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    _reshape('د.ع ${formatter.format(totalRemaining)}'),
                    style: pw.TextStyle(
                      font: ttfBold,
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColor.fromHex('#c62828'),
                    ),
                    textDirection: pw.TextDirection.ltr,
                  ),
                ],
              ),
            ),
"""
new = """            // ══════════════════════════════════════════════
            // CUSTOMER-WIDE SUMMARY
            // ══════════════════════════════════════════════
            pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.blue400),
                      borderRadius: pw.BorderRadius.circular(4),
                      color: PdfColor.fromHex('#e8eaf6'),
                    ),
                    child: pw.Column(
                      children: [
                        pw.Text(
                          _reshape('کۆی هەموو قەرزەکان'),
                          style: pw.TextStyle(font: ttf, fontSize: 9, color: PdfColors.blue800),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          _reshape('د.ع ${formatter.format(totalDebt)}'),
                          style: pw.TextStyle(font: ttfBold, fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800),
                          textDirection: pw.TextDirection.ltr,
                        ),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 8),
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.green400),
                      borderRadius: pw.BorderRadius.circular(4),
                      color: PdfColor.fromHex('#e8f5e9'),
                    ),
                    child: pw.Column(
                      children: [
                        pw.Text(
                          _reshape('کۆی هەموو پارەدانەوەکان'),
                          style: pw.TextStyle(font: ttf, fontSize: 9, color: PdfColors.green800),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          _reshape('د.ع ${formatter.format(totalPaid)}'),
                          style: pw.TextStyle(font: ttfBold, fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.green800),
                          textDirection: pw.TextDirection.ltr,
                        ),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 8),
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColor.fromHex('#c62828'), width: 1.5),
                      borderRadius: pw.BorderRadius.circular(4),
                      color: PdfColor.fromHex('#ffebee'),
                    ),
                    child: pw.Column(
                      children: [
                        pw.Text(
                          _reshape('کۆی قەرزی ماوە'),
                          style: pw.TextStyle(font: ttf, fontSize: 9, color: PdfColor.fromHex('#c62828')),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          _reshape('د.ع ${formatter.format(totalRemaining)}'),
                          style: pw.TextStyle(font: ttfBold, fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#c62828')),
                          textDirection: pw.TextDirection.ltr,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
"""
s = replace_once(s, old, new, 'customer statement summary')
p.write_text(s)

# Regression verifier created alongside the source patch.
Path('scripts/verify_customer_payment_totals.py').write_text("""from pathlib import Path

dashboard = Path('lib/screens/customer/customer_dashboard.dart').read_text()
pdf = Path('lib/services/pdf_service.dart').read_text()
assert \"_totalPaidAmount = snapshot['totalPaidIqd'] as double\" in dashboard
assert 'totalPaid: _totalPaid' in dashboard
assert 'final totalPaid = _totalPaid;' in dashboard
assert 'totalPaid: _totalDebt - _totalRemaining' not in dashboard
assert 'final totalPaid = _totalDebt - _totalRemaining' not in dashboard
assert 'کۆی هەموو پارەدانەوەکان' in pdf
assert 'formatter.format(totalPaid)' in pdf
print('Customer cumulative payment total verification passed.')
""")

print('Customer cumulative payment total patch applied.')
