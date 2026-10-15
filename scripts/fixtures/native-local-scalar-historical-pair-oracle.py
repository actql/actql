"""Independent read-only Python oracle for the retained historical pair.

Reads source-bound complete fixtures and scalar implementations, not product
output. It never rewrites an old vector or installation/Run/DB/attempt.
"""
from pathlib import Path
import gzip
import hashlib
import json
import sys

assert sys.argv[1:] == ['--check']
ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / 'scripts/fixtures/native-local-scalar-predecessor'

def sha(value):
    return hashlib.sha256(value).hexdigest()

def canonical(value):
    return json.dumps(value, ensure_ascii=False, separators=(',', ':'), sort_keys=True)

def cid(value):
    return 'sha256:' + sha(canonical(value).encode())

def differences(a, b, path=''):
    if a == b:
        return []
    if isinstance(a, dict) and isinstance(b, dict):
        assert set(a) == set(b)
        return sum((differences(a[k], b[k], path + '/' + k.replace('~', '~0').replace('/', '~1')) for k in sorted(a)), [])
    if isinstance(a, list) and isinstance(b, list):
        assert len(a) == len(b)
        return sum((differences(x, y, path + '/' + str(i)) for i, (x, y) in enumerate(zip(a, b))), [])
    return [{'path': path, 'original': a, 'current': b}]

raw_index = (FIXTURE / 'manifest.json').read_bytes()
assert sha(raw_index) == '75bee505552e9e6958be5a20bac877b2d69664ba70aad7f7970bc506bfbc992b'
index = json.loads(raw_index)
packed = (ROOT / 'scripts/fixtures/native-local-scalar-reviewed-current.json.gz').read_bytes()
assert sha(packed) == '934bb2c194ff7c668fe91d6b30e8b5b2167a3cb542d38f7de751cba10cfa81d1'
raw_reviewed = gzip.decompress(packed)
assert sha(raw_reviewed) == '0cfad9f8abef5795b79b6be2e8078ffc06423cabef90027e0fb17b19ff41cc3b'
reviewed = json.loads(raw_reviewed)
assert reviewed['source'] == 'd062aa0f5992d3e2bf3fe4b9acac1f0ff34d26d0'
old = {}
for row in index['records']:
    raw = gzip.decompress((FIXTURE / row['fixture']).read_bytes())
    assert len(raw) == row['bytes'] and sha(raw) == row['sha256']
    old[row['role']] = json.loads(raw)
current = reviewed['bodies']
roles = ['registry', 'values', 'fragment', 'ordered', 'expression', 'value-contract', 'text-time', 'text-time-dependencies', 'unicode-data', 'derive-binding', 'rows-to-graph']
assert set(old) == set(current) == set(roles)
implementations = []
for row in index['implementation_records']:
    original = gzip.decompress((FIXTURE / row['fixture']).read_bytes())
    assert sha(original) == row['sha256']
    assert original == (ROOT / row['path']).read_bytes()
    implementations.append({'path': row['path'], 'sha256': sha(original)})
changes = [{'role': role, 'differences': differences(old[role], current[role])} for role in sorted(roles)]
for row in changes:
    for change in row['differences']:
        assert ((change['original'] == 'artifact_ref' and change['current'] == 'content_ref') or
                (isinstance(change['original'], str) and change['original'].startswith('sha256:') and change['current'].startswith('sha256:')))
asset_roles = ['environment', 'registry', 'values', 'fragment', 'ordered', 'result-policy']
asset_pairs = []
for role in asset_roles:
    before = gzip.decompress((FIXTURE / (role + '.json.gz')).read_bytes())
    after = reviewed['assets'][role].encode()
    asset_pairs.append({'role': role, 'original_sha256': sha(before), 'current_sha256': sha(after)})
original_runtime = gzip.decompress((FIXTURE / 'local-runtime.json.gz').read_bytes())
assert sha(original_runtime) == '80731853b15f4d600ef391b3778c734bc40bfb6caed246c0c145916b419e49bd'
evidence = {'version': 'actql-native-local-scalar-pair-evidence/0.1', 'predecessor_source_sha': index['source'], 'predecessor_runtime_sha256': sha(original_runtime), 'profile': 'primitive-scalar-values', 'reachable_operations': ['REL.values', 'REL.derive', 'REL.where', 'REL.select'], 'excluded': ['references', 'json', 'containers', 'graph', 'vector', 'event', 'infer', 'effect', 'serialization', 'unknown', 'unresolved-obligations'], 'body_pairs': [{'role': r, 'original_cid': cid(old[r]), 'current_cid': cid(current[r]), 'original_canonical_body_sha256': sha(canonical(old[r]).encode()), 'current_canonical_body_sha256': sha(canonical(current[r]).encode())} for r in roles], 'exact_difference_cid': cid(changes), 'implementation_evidence_cid': cid(implementations), 'asset_pairs': asset_pairs}
assert cid(evidence) == 'sha256:8bdf483589d04809f0e2e198708adc8335b38179f332e58d25a8a09497633a22'
historical_runtime = (ROOT / 'scripts/fixtures/native-local-scalar-historical-a3b-runtime.json').read_bytes()
assert len(historical_runtime) == 2289 and sha(historical_runtime) == '585e5959c972a801335103217d2dede6cb12f72333a58f6b88bf88c85075fd85'
expected = json.loads(original_runtime)
expected['sourceSha'] = 'a3b1643fbedc5180db38b6e08459a188f05b1135'
for asset in expected['assets']:
    raw = reviewed['assets'][asset['role']].encode()
    asset.update(bytes=len(raw), sha256=sha(raw))
assert json.loads(historical_runtime) == expected
body = {'current_manifest_sha256': sha(historical_runtime), 'current_source_sha': expected['sourceSha'], 'evidence_cid': cid(evidence), 'original_manifest_sha256': sha(original_runtime), 'original_source_sha': index['source'], 'platform': 'darwin-arm64', 'profile': 'primitive-scalar-values', 'version': 'actql-native-local-scalar-runtime-pair/0.1'}
vector = json.loads((ROOT / 'scripts/fixtures/native-local-scalar-historical-pair-vector.json').read_bytes())
assert vector == {'body': canonical(body), 'sha256': sha(canonical(body).encode()), 'cid': cid(body)}
assert vector['sha256'] == '2b06a81d8266f98c954a76556c3312e3abba0acb8615f19c501ce3df920d367b'
print(json.dumps({'historical_pair_body_bytes': len(vector['body'].encode()), 'historical_pair_sha256': vector['sha256'], 'evidence_cid': cid(evidence), 'full_body_pairs': len(roles), 'assets': len(asset_roles), 'installation_or_Run_materials_issued': 0, 'writes': 0, 'public_e2e': 0}))
