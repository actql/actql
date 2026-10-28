import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync}
  from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import test from 'node:test';
import {machineCid} from './actql-spec-family.mjs';

// Source fixtures only: execute the existing validator, never a compiler,
// planner, installed Host or policy writer from the product runtime.
const inputs = [
  'scripts/check-policy-candidates.mjs',
  'scripts/actql-spec-family.mjs',
  'scripts/actql-requirement-extraction.mjs',
  'scripts/check-canonical-json.mjs',
  'spec/contracts/actql-expressions.json',
  'portability/corpus/policy-candidates.json',
  'portability/corpus/policy-candidates-history.json',
  'src/query_integration/policy_candidates_body_wbtest.mbt',
];

function runCheck(root) {
  const result = spawnSync(process.execPath,
    [join(root, 'scripts/check-policy-candidates.mjs')],
    {cwd: root, encoding: 'utf8', timeout: 10_000, maxBuffer: 1024 * 1024});
  assert.equal(result.error, undefined);
  assert.equal(result.signal, null);
  return result;
}

function withFixture(mutate) {
  const root = mkdtempSync(join(tmpdir(), 'actql-policy-candidate-control-'));
  try {
    for (const path of inputs) {
      const output = join(root, path);
      mkdirSync(dirname(output), {recursive: true});
      copyFileSync(new URL('../' + path, import.meta.url), output);
    }
    const healthy = runCheck(root);
    assert.equal(healthy.status, 0, healthy.stderr);
    assert.equal(healthy.stdout.trim(),
      'Policy candidate initial-contract body, CID and consuming vector verified.');
    mutate(root);
    const refused = runCheck(root);
    assert.equal(refused.status, 1, refused.stderr);
    assert.match(refused.stderr, /AssertionError \[ERR_ASSERTION\]/u);
    assert.match(refused.stderr, /check-policy-candidates\.mjs:\d+/u);
    assert.doesNotMatch(refused.stdout, /consuming vector verified/u);
  } finally {
    rmSync(root, {recursive: true, force: true});
  }
}

test('complete historical policy preimages cannot change under retained pins', () => {
  withFixture(root => {
    const path = join(root, 'portability/corpus/policy-candidates-history.json');
    const history = JSON.parse(readFileSync(path, 'utf8'));
    history.snapshots[0].stage_semantics[0].local_body.steps[0].filter.gt[0].field =
      'another_field';
    writeFileSync(path, JSON.stringify(history));
  });
});

test('a self-consistent historical Program pin is not the current policy fixture', () => {
  withFixture(root => {
    const path = join(root, 'portability/corpus/policy-candidates.json');
    const fixture = JSON.parse(readFileSync(path, 'utf8'));
    fixture.body[1] =
      'sha256:63af34b702f8d1b719cc9492d220c9c6929b2b047cd0e4837d70d1ef9d3a0dfd';
    fixture.expected_cid = machineCid(fixture.body);
    writeFileSync(path, JSON.stringify(fixture));
  });
});
