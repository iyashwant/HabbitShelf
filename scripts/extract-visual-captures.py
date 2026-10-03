#!/usr/bin/env python3
"""Recover real synthetic-data UI screenshots emitted by the XCTest capture helper."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import re

parser = argparse.ArgumentParser()
parser.add_argument('log', type=Path)
parser.add_argument('--output', type=Path, default=Path('research/habitkit/07_visual_audit/native_screens'))
parser.add_argument('--commit', required=True)
parser.add_argument('--run', required=True)
parser.add_argument('--runtime', required=True)
args = parser.parse_args()
groups = {}
for name, index, total, encoded in re.findall(r'BUDDY_CAPTURE\|([a-z0-9-]+)\|(\d+)\|(\d+)\|([A-Za-z0-9+/=]+)', args.log.read_text()):
    item = groups.setdefault(name, {'total': int(total), 'parts': {}})
    item['total'] = int(total)
    item['parts'][int(index)] = encoded
args.output.mkdir(parents=True, exist_ok=True)
manifest = []
for name, group in sorted(groups.items()):
    assert set(group['parts']) == set(range(group['total'])), f'Incomplete capture: {name}'
    data = b''.join(base64.b64decode(group['parts'][i], validate=True) for i in range(group['total']))
    assert data.startswith(b'\xff\xd8') and data.endswith(b'\xff\xd9'), f'Invalid JPEG: {name}'
    file = args.output / (name + '.jpg')
    file.write_bytes(data)
    manifest.append({'file': file.name, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest(),
                     'source_commit': args.commit, 'actions_run': args.run, 'runtime': args.runtime,
                     'fixture_date': '2026-08-18', 'data': 'isolated synthetic fixtures',
                     'format': 'JPEG quality 0.8; original PNG retained in XCTest attachment'})
assert manifest, 'No native captures found'
(args.output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(f'Recovered {len(manifest)} real simulator captures.')
