import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';

const root = fileURLToPath(new URL('../', import.meta.url));
const script = join(root, 'scripts/managed-runtime-vectors.mjs');
const profilePath = 'spec/contracts/actql-managed-retained-execution.json';
const capacityPath = 'spec/contracts/actql-fixed-compute-capacity.json';
const outputs = ['src/execution_relation/managed_profile_pin.generated.mbt',
  'src/execution_relation/managed_profile_body.generated_wbtest.mbt'];
const canonical = value => Array.isArray(value) ? '[' + value.map(canonical).join(',') + ']'
  : value !== null && typeof value === 'object'
    ? '{' + Object.keys(value).sort().map(key => JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}'
    : JSON.stringify(value);
const cid = value => 'sha256:' + createHash('sha256').update(canonical(value)).digest('hex');

function fixture(t) {
  const cwd = mkdtempSync(join(tmpdir(), 'actql-managed-profile-vectors-'));
  t.after(() => rmSync(cwd, {recursive: true, force: true}));
  const profile = JSON.parse(readFileSync(join(root, profilePath), 'utf8'));
  const capacity = JSON.parse(readFileSync(join(root, capacityPath), 'utf8'));
  const write = (path, body) => {
    mkdirSync(dirname(join(cwd, path)), {recursive: true});
    writeFileSync(join(cwd, path), JSON.stringify(body, null, 2) + '\n');
  };
  write(profilePath, profile);
  write(capacityPath, capacity);
  for (const path of outputs) {
    mkdirSync(dirname(join(cwd, path)), {recursive: true});
    writeFileSync(join(cwd, path), 'untouched output\n');
  }
  const run = (...args) => spawnSync(process.execPath, [script, ...args],
    {cwd, encoding: 'utf8', timeout: 10_000});
  return {cwd, profile, capacity, write, run};
}

test('managed runtime profile identity is derived from the exact dependency body', t => {
  const f = fixture(t);
  assert.equal(f.profile.dependencies.fixed_compute_capacity.cid, cid(f.capacity));
  const result = f.run('--write');
  assert.equal(result.status, 0, result.stderr);
  assert.ok(readFileSync(join(f.cwd, outputs[0]), 'utf8').includes(JSON.stringify(cid(f.profile))));
  assert.equal(f.run().status, 0);
});

test('managed vector check and write refuse stale dependency pins before output changes', t => {
  const f = fixture(t);
  f.profile.dependencies.fixed_compute_capacity.cid = 'sha256:' + '0'.repeat(64);
  f.write(profilePath, f.profile);
  for (const args of [[], ['--write']]) {
    const result = f.run(...args);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /fixed-compute capacity dependency is stale/u);
    for (const path of outputs) assert.equal(readFileSync(join(f.cwd, path), 'utf8'), 'untouched output\n');
  }
});

test('managed runtime generation follows a changed source dependency without a literal profile pin', t => {
  const f = fixture(t);
  f.capacity.scope += '_independent_fixture';
  f.write(capacityPath, f.capacity);
  const stale = f.run('--write');
  assert.notEqual(stale.status, 0);
  assert.match(stale.stderr, /fixed-compute capacity dependency is stale/u);
  f.profile.dependencies.fixed_compute_capacity.cid = cid(f.capacity);
  f.write(profilePath, f.profile);
  const result = f.run('--write');
  assert.equal(result.status, 0, result.stderr);
  assert.ok(readFileSync(join(f.cwd, outputs[0]), 'utf8').includes(JSON.stringify(cid(f.profile))));
  assert.equal(f.run().status, 0);
});


test('managed dependency regressions remain part of specification documentation checks', () => {
  const scripts = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8')).scripts;
  assert.ok(scripts['test:docs'].includes('scripts/managed-runtime-vectors.test.mjs'));
  assert.ok(scripts['check:spec-after-preflight'].includes('npm run test:docs'));
});
