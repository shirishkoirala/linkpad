#!/usr/bin/env python3
"""Build/test Linux x86_64 from a small source-only Docker context.

Run from any directory: python3 mobile/tool/test_linux_container.py
Requires Docker Desktop/Engine. Results and the GUI bundle go into bin/linux-container-test.
"""
from pathlib import Path
import shutil
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
output = repo / 'bin/linux-container-test'
output.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='linkpad-linux-context-') as temporary:
    context = Path(temporary)
    for directory in ('cmd', 'internal', 'protocol/testdata', 'mobile/lib', 'mobile/test', 'mobile/assets', 'mobile/linux'):
        shutil.copytree(repo / directory, context / directory,
                        ignore=shutil.ignore_patterns('ephemeral', 'build', '.dart_tool', '.git'))
    for filename in ('go.mod', 'go.sum', 'mobile/.metadata', 'mobile/pubspec.yaml',
                     'mobile/pubspec.lock', 'mobile/analysis_options.yaml'):
        shutil.copy2(repo / filename, context / filename)
    (context / 'mobile/tool').mkdir()
    for filename in ('linux-container.Dockerfile', 'linux-container-test.sh', 'linux-container-smoke.py'):
        shutil.copy2(repo / 'mobile/tool' / filename, context / 'mobile/tool' / filename)
    subprocess.run(['docker', 'build', '--platform', 'linux/amd64', '-f',
                    'mobile/tool/linux-container.Dockerfile', '-t', 'linkpad-linux-test', '.'],
                   cwd=context, check=True)
subprocess.run(['docker', 'run', '--rm', '--platform', 'linux/amd64',
                '--mount', f'type=bind,source={output},target=/results',
                'linkpad-linux-test'], check=True)
print(f'Linux x86_64 bundle and test logs: {output}')
