import test from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {mkdtempSync, readFileSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const script = join(root, 'scripts/check-rela-differential-coverage.mjs');
const source = join(
  root,
  'docs/reviews/2026-09-23-rela-differential-coverage.json',
);

function run(mutator) {
  const manifest = JSON.parse(readFileSync(source, 'utf8'));
  mutator?.(manifest);
  const directory = mkdtempSync(join(tmpdir(), 'actql-rela-differential-'));
  const target = join(directory, 'manifest.json');
  writeFileSync(target, JSON.stringify(manifest));
  try {
    return execFileSync(process.execPath, [script], {
      cwd: root,
      env: {...process.env, ACTQL_RELA_DIFFERENTIAL_MANIFEST: target},
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    });
  } catch (error) {
    return String(error.stderr);
  }
}

test('RelA differential gate accepts the complete operation classification', () => {
  assert.match(run(), /29 classified, 6 overlapping operations gated/);
});

test('RelA differential gate rejects an omitted normative operation', () => {
  assert.match(run(value => value.operations.pop()), /normative RelA order/);
});

test('RelA differential gate rejects agreement without an independent oracle', () => {
  assert.match(run(value => {
    value.operations.find(entry => entry.operation === 'filter').evidence =
      value.operations.find(entry => entry.operation === 'filter').evidence
        .filter(item => !item.role.includes('independent_expectation'));
  }), /required differential role is missing/);
});

test('RelA differential gate rejects missing observation coverage', () => {
  assert.match(run(value => {
    value.required_observations.push('uncovered-observation');
  }), /missing observation coverage/);
});
