#!/usr/bin/env python3
"""Package release desktop bundles; see PACKAGING.md. Requires Python 3.10+."""
import argparse
import hashlib
import os
from pathlib import Path
import platform
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile

REPO = Path(__file__).resolve().parents[2]
MOBILE = REPO / 'mobile'


def run(*args, **kwargs):
    return subprocess.run([str(arg) for arg in args], check=True, **kwargs)


def checksum(path):
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    path.with_suffix(path.suffix + '.sha256').write_text(f'{digest}  {path.name}\n')
    print(f'Created {path}', flush=True)


def version_from_project():
    match = re.search(r'^version:\s*(\S+)', (MOBILE / 'pubspec.yaml').read_text(), re.M)
    return match.group(1).split('+')[0]


def mac(args):
    if sys.platform != 'darwin':
        raise ValueError('Create the DMG on macOS with Xcode and Flutter installed.')
    identity = args.identity
    if identity != '-' and not identity.startswith('Developer ID Application:'):
        raise ValueError('Use a Developer ID Application identity, or - for a local ad-hoc build.')
    if args.notary_profile and identity == '-':
        raise ValueError('Notarization requires a Developer ID Application identity.')
    if not args.skip_build:
        run('flutter', 'build', 'macos', '--release', cwd=MOBILE)
    app = args.app.resolve()
    helper = app / 'Contents/Resources/linkpad-server'
    if not helper.is_file():
        raise ValueError(f'The app is missing its bundled server: {helper}')
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if info['CFBundleShortVersionString'] != args.version:
        raise ValueError('Package version must match the built app. Rebuild with the requested version.')
    signed = identity != '-'
    label = 'macos' if signed else 'macos-local'
    destination = args.output / f'Linkpad-{args.version}-{label}.dmg'
    with tempfile.TemporaryDirectory(prefix='.linkpad-dmg-', dir=args.output) as temporary:
        image = Path(temporary) / destination.name
        staging = Path(temporary) / 'volume'
        staging.mkdir()
        copied = staging / 'Linkpad.app'
        # ditto preserves framework symlinks, executable modes, and bundle metadata.
        run('ditto', app, copied)
        (copied / 'Contents/embedded.provisionprofile').unlink(missing_ok=True)
        sign_options = ['--force', '--sign', identity]
        if signed:
            sign_options += ['--options', 'runtime', '--timestamp']
        code = list(copied.rglob('*.dylib')) + list(copied.rglob('*.framework'))
        code += [copied / 'Contents/Resources/linkpad-server']
        for item in sorted(code, key=lambda path: len(path.parts), reverse=True):
            if not item.is_symlink():
                run('codesign', *sign_options, item)
        run('codesign', *sign_options, '--entitlements',
            MOBILE / 'macos/Runner/Release.entitlements', copied)
        run('codesign', '--verify', '--deep', '--strict', '--verbose=2', copied)
        if args.notary_profile:
            archive = Path(temporary) / 'Linkpad.zip'
            run('ditto', '-c', '-k', '--keepParent', copied, archive)
            run('xcrun', 'notarytool', 'submit', archive, '--keychain-profile',
                args.notary_profile, '--wait')
            run('xcrun', 'stapler', 'staple', copied)
            run('spctl', '--assess', '--type', 'execute', '--verbose=2', copied)
        (staging / 'Applications').symlink_to('/Applications')
        (staging / 'Install Linkpad.txt').write_text(
            'Drag Linkpad into Applications, then open it there.\n'
            'Enable Linkpad in System Settings > Privacy & Security > Accessibility.\n'
            'Then restart its server from the app.\n' +
            ('' if args.notary_profile else
             '\nThis build has not been notarized for public distribution.\n'))
        run('hdiutil', 'create', '-volname', 'Linkpad', '-srcfolder', staging,
            '-format', 'UDZO', '-ov', image)
        if signed:
            run('codesign', *sign_options, image)
        if args.notary_profile:
            run('xcrun', 'notarytool', 'submit', image, '--keychain-profile',
                args.notary_profile, '--wait')
            run('xcrun', 'stapler', 'staple', image)
            run('xcrun', 'stapler', 'validate', image)
        run('hdiutil', 'verify', image)
        os.replace(image, destination)
    checksum(destination)
    if not args.notary_profile:
        print('Local/testing DMG only: Apple notarization was not performed.')


def linux(args):
    if args.docker:
        command = ['docker', 'run', '--rm', '--platform', 'linux/amd64',
                   '--mount', f'type=bind,source={MOBILE / "tool"},target=/work/mobile/tool,readonly',
                   '--mount', f'type=bind,source={MOBILE / "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png"},target=/icon.png,readonly',
                   '--mount', f'type=bind,source={args.output},target=/output']
        bundle = '/work/mobile/build/linux/x64/release/bundle'
        if args.bundle:
            command += ['--mount', f'type=bind,source={args.bundle.resolve()},target=/bundle,readonly']
            bundle = '/bundle'
        command += [args.image, 'python3', '/work/mobile/tool/package_desktop.py', 'linux',
                    '--bundle', bundle, '--icon', '/icon.png',
                    '--output', '/output', '--version', args.version]
        run(*command)
        return
    if sys.platform != 'linux' or platform.machine() not in ('x86_64', 'amd64'):
        raise ValueError('Build the amd64 Debian package on Linux x86_64, or use --docker.')
    bundle = (args.bundle or MOBILE / 'build/linux/x64/release/bundle').resolve()
    for name in ('linkpad_controller', 'lib/linkpad-server', 'lib/libflutter_linux_gtk.so', 'data/icudtl.dat'):
        if not (bundle / name).is_file():
            raise ValueError(f'Missing release bundle file: {bundle / name}')
    with tempfile.TemporaryDirectory(prefix='linkpad-deb-') as temporary:
        work = Path(temporary)
        root = work / 'package'
        installed = root / 'opt/linkpad'
        shutil.copytree(bundle, installed, symlinks=True)
        launcher = root / 'usr/bin/linkpad'
        launcher.parent.mkdir(parents=True)
        launcher.write_text('#!/bin/sh\nexec /opt/linkpad/linkpad_controller "$@"\n')
        launcher.chmod(0o755)
        desktop = root / 'usr/share/applications/com.shirishkoirala.linkpad.desktop'
        desktop.parent.mkdir(parents=True)
        desktop.write_text(
            '[Desktop Entry]\nType=Application\nName=Linkpad\n'
            'Comment=Use your phone as a touchpad and keyboard\n'
            'Exec=/usr/bin/linkpad\nIcon=com.shirishkoirala.linkpad\nTerminal=false\n'
            'Categories=Utility;\nStartupNotify=true\n')
        icon = root / 'usr/share/icons/hicolor/512x512/apps/com.shirishkoirala.linkpad.png'
        icon.parent.mkdir(parents=True)
        shutil.copy2(args.icon, icon)
        (work / 'debian').mkdir()
        (work / 'debian/control').write_text(
            'Source: linkpad\nSection: utils\nPriority: optional\n'
            'Maintainer: Linkpad maintainers <maintainers@linkpad.invalid>\n\n'
            'Package: linkpad\nArchitecture: amd64\nDescription: Linkpad desktop server\n')
        # Inspect every bundled ELF: plugins can require libraries absent from
        # the main executable. Own bundled libraries have no Debian shlibs entry.
        elf = []
        for path in installed.rglob('*'):
            if path.is_file() and not path.is_symlink():
                with path.open('rb') as source:
                    if source.read(4) == b'\x7fELF':
                        elf.append(path)
        result = run('dpkg-shlibdeps', '--ignore-missing-info', '-O',
                     f'-l{installed / "lib"}', *[f'-e{path}' for path in elf],
                     cwd=work, capture_output=True, text=True)
        deps = result.stdout.strip().removeprefix('shlibs:Depends=')
        if not deps or 'libc6' not in deps:
            raise ValueError(f'Could not determine runtime dependencies: {result.stdout}')
        dependencies = deps.split(', ')
        dependency_names = {item.split()[0] for item in dependencies}
        dependencies += [name for name in ('libayatana-appindicator3-1', 'libsecret-1-0')
                         if name not in dependency_names]
        dependencies = sorted(set(dependencies))
        control = root / 'DEBIAN/control'
        control.parent.mkdir()
        size = sum(p.stat().st_size for p in root.rglob('*') if p.is_file()) // 1024
        control.write_text(
            f'Package: linkpad\nVersion: {args.version}\nArchitecture: amd64\n'
            'Section: utils\nPriority: optional\n'
            'Maintainer: Linkpad maintainers <maintainers@linkpad.invalid>\n'
            f'Installed-Size: {size}\nDepends: {", ".join(dependencies)}\n'
            'Description: Phone touchpad and keyboard desktop server\n'
            ' Linkpad pairs with your phone over your local network.\n'
            ' Linux input requires a logged-in X11 desktop session.\n')
        # No service installation, autostart changes, or removal of user state.
        for directory, _, files in os.walk(root):
            Path(directory).chmod(0o755)
            for name in files:
                path = Path(directory) / name
                if not path.is_symlink():
                    path.chmod(0o755 if path.stat().st_mode & 0o111 else 0o644)
        destination = args.output / f'linkpad_{args.version}_amd64.deb'
        run('dpkg-deb', '--root-owner-group', '--build', root, destination)
        run('dpkg-deb', '--info', destination)
        checksum(destination)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='platform', required=True)
    for name in ('macos', 'linux'):
        item = sub.add_parser(name)
        item.add_argument('--version')
        item.add_argument('--output', type=Path, default=REPO / 'bin/releases')
        if name == 'macos':
            item.add_argument('--app', type=Path, default=MOBILE / 'build/macos/Build/Products/Release/Linkpad.app')
            item.add_argument('--skip-build', action='store_true')
            item.add_argument('--identity', default='-')
            item.add_argument('--notary-profile')
        else:
            item.add_argument('--bundle', type=Path)
            item.add_argument('--docker', action='store_true')
            item.add_argument('--image', default='linkpad-linux-test')
            item.add_argument('--icon', type=Path, default=MOBILE / 'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png')
    args = parser.parse_args()
    args.version = args.version or version_from_project()
    if not re.fullmatch(r'\d+\.\d+\.\d+(?:[-.][A-Za-z0-9.]+)?', args.version):
        parser.error('Use a version such as 0.1.0 or 0.1.0-beta.1.')
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    try:
        (mac if args.platform == 'macos' else linux)(args)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        if getattr(error, 'stderr', None):
            print(error.stderr, file=sys.stderr)
        parser.exit(1, f'Packaging failed: {error}\n')


if __name__ == '__main__':
    main()
