from pathlib import Path

path = Path('lib/screens/shared/user_list_screen.dart')
text = path.read_text(encoding='utf-8')

layout_import = "import 'package:zhirox/services/user_list_layout.dart';\n"
import_anchor = "import 'package:zhirox/services/connectivity_service.dart';\n"
if layout_import not in text:
    if import_anchor not in text:
        raise SystemExit('connectivity import anchor not found')
    text = text.replace(import_anchor, import_anchor + layout_import, 1)

build_anchor = "    final isDark = Theme.of(context).brightness == Brightness.dark;\n\n    return Scaffold("
if build_anchor not in text:
    raise SystemExit('build anchor not found')
text = text.replace(
    build_anchor,
    "    final isDark = Theme.of(context).brightness == Brightness.dark;\n"
    "    final pinHeader = shouldPinUserListHeader(widget.role);\n"
    "    final header = _buildDirectoryHeader(canAdd: canAdd, isDark: isDark);\n\n"
    "    return Scaffold(",
    1,
)

header_prefix = (
    "          // ───── Gradient Header ─────\n"
    "          SliverToBoxAdapter(\n"
    "            child: "
)
list_marker = "\n\n          // ───── List ─────"
start = text.find(header_prefix)
if start < 0:
    raise SystemExit('header start not found')
end = text.find(list_marker, start)
if end < 0:
    raise SystemExit('list marker not found')

header_block = text[start:end]
header_expr = header_block[len(header_prefix):]
sliver_close = "\n          ),"
if not header_expr.endswith(sliver_close):
    raise SystemExit('unexpected header wrapper ending')
header_expr = header_expr[:-len(sliver_close)].rstrip()
if not header_expr.endswith(','):
    raise SystemExit('header expression does not end with comma')
header_expr = header_expr[:-1] + ';'

text = text[:start] + (
    "          // ───── Header (scrolls only for non-customer lists) ─────\n"
    "          if (!pinHeader) SliverToBoxAdapter(child: header),"
) + text[end:]

body_anchor = "      body: Scrollbar(\n"
if body_anchor not in text:
    raise SystemExit('scrollbar body anchor not found')
text = text.replace(
    body_anchor,
    "      body: Column(\n"
    "        children: [\n"
    "          if (pinHeader) header,\n"
    "          Expanded(\n"
    "            child: Scrollbar(\n",
    1,
)

old_tail = (
    "          const SliverPadding(padding: EdgeInsets.only(bottom: 50)),\n"
    "          ],\n"
    "        ),\n"
    "      ),\n"
    "    );\n"
    "  }\n"
)
new_tail = (
    "          const SliverPadding(padding: EdgeInsets.only(bottom: 50)),\n"
    "          ],\n"
    "        ),\n"
    "            ),\n"
    "          ),\n"
    "        ],\n"
    "      ),\n"
    "    );\n"
    "  }\n"
)
if old_tail not in text:
    raise SystemExit('build tail not found')
text = text.replace(old_tail, new_tail, 1)

widgets_marker = (
    "\n  // ═══════════════════════════════════════════\n"
    "  // ── Widgets ──\n"
    "  // ═══════════════════════════════════════════\n"
)
if widgets_marker not in text:
    raise SystemExit('widgets marker not found')

method = (
    "\n  Widget _buildDirectoryHeader({\n"
    "    required bool canAdd,\n"
    "    required bool isDark,\n"
    "  }) {\n"
    "    return " + header_expr.lstrip() + "\n"
    "  }\n"
)
text = text.replace(widgets_marker, method + widgets_marker, 1)

path.write_text(text, encoding='utf-8')
print('Patched customer directory so the customer header stays pinned.')
