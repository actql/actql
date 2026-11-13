import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'yaml';

test('temporary Linux Crypto validation preserves all three modes and excludes normal producers', () => {
  const workflow = parse(readFileSync(new URL('../.github/workflows/performance-matrix.yml', import.meta.url), 'utf8'));
  assert.deepEqual(Object.keys(workflow.on), ['workflow_dispatch']);
  assert.deepEqual(Object.keys(workflow.jobs), ['crypto-context']);
  const job = workflow.jobs['crypto-context'];
  assert.equal(job['runs-on'], 'ubuntu-24.04');
  assert.deepEqual(job.permissions, {contents: 'read'});
  const run = job.steps.map(step => step.run ?? '').join('\n');
  assert(run.includes('python3 scripts/test-native-crypto-allocator.py'));
  assert.equal((run.match(/--openssl-package-archive /gu) ?? []).length, 2);
  assert(!/(?:node|python3?)\s+scripts\/produce-native|npm (?:run|ci)|moon (?:build|test)|--crypto-producer/u.test(run));
  const result = spawnSync('python3', ['-c', String.raw`
import ast, hashlib, json
from pathlib import Path
path=Path('scripts/test-native-crypto-allocator.py')
tree=ast.parse(path.read_text())
modes=[n.value for n in tree.body if isinstance(n,ast.Assign) and any(isinstance(x,ast.Name) and x.id=='MODES' for x in n.targets)]
assert len(modes)==1 and ast.literal_eval(modes[0])==('bounded-search','split-merge-membership','partial')
recipe_path=Path('packages/python-local-runtime/native/crypto-component/source.json')
recipe=json.loads(recipe_path.read_text())
for name, expected in recipe['local'].items():
    raw=(recipe_path.parent/name).read_bytes()
    assert {'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest()}==expected
source=path.read_text()
assert "len(report['cases']) == 3 and all(case['passed']" in source
assert "result.returncode == 0 and len(selected) == 1" in source
assert "selected[0].get('original_cleanup') is True" in source
assert 'P.prepare_linux_package_inputs(prefix, args.openssl_package_archive, selected)' in source
print('exact current Source pins, original three case and cleanup gates retained')
`], {cwd: new URL('..', import.meta.url), encoding: 'utf8', timeout: 10000});
  assert.equal(result.status, 0, result.stdout + result.stderr);
});
