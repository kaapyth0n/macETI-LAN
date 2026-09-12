#!/usr/bin/env python3
"""Check the staged/tracked source tree for private data and generated payloads.

This deliberately prints paths and issue categories, never matching secret values.
It supplements a human review; it is not a universal secret detector.
"""
from pathlib import PurePosixPath
import re
import subprocess
import sys

DENIED_PARTS = {'.build', '.swiftpm', '.local', 'dist', '.sync', 'Artwork', 'Runtimes', '__pycache__', 'xcuserdata'}
DENIED_NAMES = {'library.json', 'compatibility-tests.json', 'catalog-receipt.json', 'bootstrap-receipt.json', '.DS_Store'}
DENIED_SUFFIXES = {'.db', '.key', '.rsls', '.exe', '.dll', '.zip', '.dmg', '.tar', '.eti', '.pem', '.p12', '.log', '.pyc', '.icns'}
PATTERNS = {
    'literal Resilio-style key': re.compile(rb'(?<![A-Z2-7])[AB][A-Z2-7]{32}(?![A-Z2-7])'),
    'GitHub token': re.compile(rb'(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,})'),
    'private key': re.compile(rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
    'local user path': re.compile(rb'/' + rb'Users/[^/\s]+/'),
}


def main():
    names = subprocess.check_output(['git', 'ls-files', '-z']).decode().split('\0')
    if not any(names):
        print('No staged/tracked files to review.', file=sys.stderr)
        return 1
    issues = []
    for name in filter(None, names):
        path = PurePosixPath(name)
        if (set(path.parts) & DENIED_PARTS or path.name in DENIED_NAMES or path.suffix in DENIED_SUFFIXES
                or '.sqlite' in path.name or path.name == '.env' or path.name.startswith('.env.')
                or any(part.endswith('.app') or part.endswith('.iconset') for part in path.parts)):
            issues.append((name, 'private/generated payload'))
        # Read the index, not a potentially different working-tree copy.
        data = subprocess.check_output(['git', 'show', ':' + name])
        if len(data) > 5_000_000:
            issues.append((name, 'unexpectedly large source asset'))
        if b'\0' not in data[:8192]:
            for label, pattern in PATTERNS.items():
                if pattern.search(data):
                    issues.append((name, label))
    for name, label in issues:
        print(f'{name}: {label}', file=sys.stderr)
    if issues:
        return 1
    print(f'Publication check passed for {len(list(filter(None, names)))} source files.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
