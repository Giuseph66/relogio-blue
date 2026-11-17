#!/usr/bin/env python3
"""Build an installable GeoNexo release, with a versioned offline shell.

Usage: python3 scripts/build_pwa.py [--base-href /app/]
Output: build/web (serve on the same origin as the Node API).
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess


def prepare_worker(output):
    resources = sorted(
        path.relative_to(output).as_posix()
        for path in output.rglob('*')
        if path.is_file() and path.name not in ('sw.js', 'flutter_service_worker.js')
        and path.suffix not in ('.map', '.symbols')
    )
    digest = hashlib.sha256()
    for resource in resources:
        digest.update(resource.encode())
        digest.update((output / resource).read_bytes())
    template = (output / 'sw.js').read_text()
    worker = template.replace('__GEONEXO_VERSION__', digest.hexdigest()[:16])
    worker = worker.replace('__GEONEXO_RESOURCES__', json.dumps(resources))
    (output / 'sw.js').write_text(worker)
    print(f'PWA pronta: {output}; {len(resources)} recursos offline.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base-href', default='/app/')
    args = parser.parse_args()
    if not args.base_href.startswith('/') or not args.base_href.endswith('/'):
        parser.error('--base-href deve começar e terminar com /')
    root = Path(__file__).resolve().parent.parent
    subprocess.run([
        'flutter', 'build', 'web', '--release', '--base-href', args.base_href,
        '--pwa-strategy=none', '--no-web-resources-cdn',
    ], cwd=root, check=True)
    prepare_worker(root / 'build' / 'web')


if __name__ == '__main__':
    main()
