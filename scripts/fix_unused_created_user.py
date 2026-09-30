from pathlib import Path

path = Path('lib/screens/shared/add_user_screen.dart')
text = path.read_text()
old = '      final createdUser = await PBService.createUser(\n'
new = '      await PBService.createUser(\n'
if old not in text:
    raise SystemExit('createdUser assignment not found')
path.write_text(text.replace(old, new, 1))
