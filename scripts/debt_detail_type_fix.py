from pathlib import Path

path = Path('lib/screens/shared/debt_detail_screen.dart')
text = path.read_text()
old = """                    final total = (price is num ? price.toDouble() : 0) *
                        (qty is num ? qty.toDouble() : 1);"""
new = """                    final total = (price is num ? price.toDouble() : 0.0) *
                        (qty is num ? qty.toDouble() : 1.0);"""
if old not in text:
    raise SystemExit('debt item total anchor not found')
path.write_text(text.replace(old, new, 1))
