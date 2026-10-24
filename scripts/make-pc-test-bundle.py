#!/usr/bin/env python3
"""Package the shared source and PC build tools, excluding local builds and saves."""
import hashlib
import json
from pathlib import Path
import zipfile

root = Path(__file__).resolve().parent.parent
version = (root / 'VERSION').read_text().strip()
name = f'Lofty-Ambitions-PC-Test-{version}'
output = root / 'dist' / f'{name}.zip'
files = []
for directory in ('Sources', 'Tests', 'Vendor/stb', 'Assets/Tokyo/Runtime', 'Examples', 'scripts', 'docs', '.github'):
    files.extend(p for p in (root / directory).rglob('*') if p.is_file() and not any(part in ('.DS_Store', '__pycache__') for part in p.parts))
for filename in ('Package.swift', 'VERSION', 'README.md', '.gitignore', 'WINDOWS-START-HERE.txt', 'Assets/Tokyo/README.md', 'Assets/Tokyo/Branding/lofty-ambitions-splash-v3.png'):
    path = root / filename
    if path.is_file(): files.append(path)
files = sorted(set(files))
manifest = {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
output.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
    for path in files:
        info = zipfile.ZipInfo(f'{name}/{path.relative_to(root).as_posix()}')
        info.compress_type = zipfile.ZIP_DEFLATED
        info.external_attr = (0o100755 if path.stat().st_mode & 0o111 else 0o100644) << 16
        archive.writestr(info, path.read_bytes())
    archive.writestr(f'{name}/SOURCE-SHA256.json', json.dumps(manifest, indent=2) + '\n')
with zipfile.ZipFile(output) as archive:
    assert archive.testzip() is None
    for path, digest in manifest.items():
        assert hashlib.sha256(archive.read(f'{name}/{path}')).hexdigest() == digest
    assert f'{name}/Assets/Tokyo/Runtime/Sheets/Structure/fire-engine.png' in archive.namelist()
digest = hashlib.sha256(output.read_bytes()).hexdigest()
output.with_suffix('.zip.sha256').write_text(f'{digest}  {output.name}\n')
print(f'Verified {len(files)} source files: {output} ({output.stat().st_size / 1048576:.1f} MiB)')
