#!/usr/bin/env python3
"""Export portable source and list only binaries that actually exist."""
import hashlib
import json
import pathlib
import re
import zipfile

root = pathlib.Path(__file__).resolve().parents[1]
version = re.search(r'^version:\s*([^+\s]+)', (root / 'apps/nearloop/pubspec.yaml').read_text(), re.M)[1]
out = root / 'release' / version
(out / 'source').mkdir(parents=True, exist_ok=True)
archive = out / 'source' / f'NearLoop-{version}-source.zip'
allowed = {'.dart', '.sql', '.yaml', '.yml', '.md', '.py', '.sh', '.ps1', '.json', '.txt', '.xml', '.plist', '.entitlements', '.kt', '.swift', '.cpp', '.h', '.cmake', '.kts', '.properties', '.gradle', '.pbxproj', '.xcworkspacedata', '.xcscheme', '.xcconfig', '.storyboard', '.rc', '.manifest', '.bat', '.png', '.svg', '.podspec'}
skip = {'release', '.git', '.dart_tool', 'build', 'Pods', '.symlinks', '__pycache__', '.idea', 'ephemeral', 'xcuserdata', '.gradle', '.swiftpm', '.build'}
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as z:
    for p in sorted(root.rglob('*')):
        rel = p.relative_to(root)
        if not p.is_file() or p.is_symlink() or any(x in skip for x in rel.parts):
            continue
        if p.name in {'local.properties', 'Generated.xcconfig', 'flutter_export_environment.sh', '.flutter-plugins-dependencies'} or p.suffix in {'.pem', '.key', '.jks', '.keystore'}:
            continue
        if p.suffix in allowed or p.name in {'LICENSE', '.gitignore', '.fvmrc', '.metadata', 'pubspec.lock', 'gradlew', 'gradle-wrapper.jar', 'Podfile'}:
            z.write(p, pathlib.Path('NearLoop') / rel)
sha = hashlib.sha256(archive.read_bytes()).hexdigest()
artifacts = []
for p in sorted((out / 'apps').glob('*')):
    if p.suffix not in {'.apk', '.ipa'}: continue
    artifacts.append({'path': str(p.relative_to(out)), 'sha256': hashlib.sha256(p.read_bytes()).hexdigest(), 'type': 'android-development-apk' if p.suffix == '.apk' else 'ios-development-ipa', 'device_tested': False})
manifest = {'version': version, 'source': {'path': str(archive.relative_to(out)), 'sha256': sha}, 'artifacts': artifacts, 'builds': {p: {'status': 'artifact-present' if any(a['type'].startswith(p) for a in artifacts) else 'not-built', 'device_tested': False} for p in ['android', 'ios', 'macos', 'windows']}}
(out / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
checks = [f'{sha}  source/{archive.name}'] + [f'{a["sha256"]}  {a["path"]}' for a in artifacts]
(out / 'checksums.sha256').write_text('\n'.join(checks) + '\n')
print(archive)
