"""Stage MSYS2 package files for the standalone Windows gateway build."""
import pathlib
import shutil
import sys
import pefile

prefix = pathlib.Path(sys.argv[1]).resolve()
target = pathlib.Path(__file__).resolve().parent / 'ocr'
target.mkdir(exist_ok=True)
binaries = {p.name.lower(): p for p in (prefix/'bin').iterdir() if p.is_file()}
pending = ['tesseract.exe']
seen = set()
while pending:
    name = pending.pop().lower()
    if name in seen:
        continue
    seen.add(name)
    source = binaries.get(name)
    if source is None:
        continue  # System DLLs are supplied by Windows.
    shutil.copy2(source, target/source.name)
    with pefile.PE(str(source)) as pe:
        for group in ('DIRECTORY_ENTRY_IMPORT', 'DIRECTORY_ENTRY_DELAY_IMPORT'):
            pending.extend(item.dll.decode('ascii') for item in getattr(pe, group, []))
(target/'tessdata').mkdir(exist_ok=True)
shutil.copy2(prefix/'share/tessdata/eng.traineddata', target/'tessdata/eng.traineddata')
shutil.copytree(prefix/'share/licenses', target/'licenses', dirs_exist_ok=True)
(target/'SOURCES.txt').write_text('Tesseract and dependency binaries are native MSYS2 UCRT64 packages.\nPackage recipes and source links: https://github.com/msys2/MINGW-packages\nPackage versions are recorded in OCR-PACKAGES.txt beside the release.\n',encoding='utf-8')
print('Staged', len(list(target.glob('*.dll'))), 'OCR dependency DLLs')
