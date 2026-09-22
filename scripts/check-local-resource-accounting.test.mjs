import test from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {mkdtempSync, readFileSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const script = join(root, 'scripts/check-local-resource-accounting.mjs');
const source = join(
  root,
  'docs/reviews/2026-09-23-local-resource-accounting-audit.json',
);

function run(mutator) {
  const manifest = JSON.parse(readFileSync(source, 'utf8'));
  mutator?.(manifest);
  const directory = mkdtempSync(join(tmpdir(), 'actql-resource-audit-'));
  const target = join(directory, 'manifest.json');
  writeFileSync(target, JSON.stringify(manifest));
  try {
    return execFileSync(process.execPath, [script], {
      cwd: root,
      env: {...process.env, ACTQL_LOCAL_RESOURCE_AUDIT: target},
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    });
  } catch (error) {
    return String(error.stderr);
  }
}

test('resource gate accepts every normative Local operation', () => {
  assert.match(run(), /68 operations, 5 implementation profiles gated/);
});

test('resource gate rejects an omitted operation', () => {
  assert.match(run(value => {
    value.bindings[0].operations.pop();
  }), /authoritative inventories/);
});

test('resource gate rejects a profile without allocation evidence', () => {
  assert.match(run(value => {
    value.profiles.sga_graph.evidence =
      value.profiles.sga_graph.evidence.filter(item =>
        !item.facets.includes('admission_before_allocation'));
  }), /missing admission_before_allocation evidence/);
});

test('resource gate rejects an omitted execution phase', () => {
  assert.match(run(value => {
    delete value.profiles.rela_rows.phase_inventory.value_construction;
  }), /missing specific value_construction phase accounting/);
});

test('resource gate rejects a missing fixture', () => {
  assert.match(run(value => {
    value.profiles.tea_events.evidence[0].fixture = 'missing fixture';
  }), /missing fixture/);
});

test('resource gate rejects an unknown implementation profile', () => {
  assert.match(run(value => {
    value.bindings[0].profile = 'unknown';
  }), /unknown profile/);
});
