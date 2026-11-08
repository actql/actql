import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {tokens} from './portable-core.mjs';

test('existing Source current paths keep their original control constructor shape', () => {
  const source = readFileSync(new URL('../src/client_local_host/installed_source_read.mbt', import.meta.url), 'utf8');
  const start = source.indexOf('fn require_installed_source_read_current(');
  assert(start >= 0);
  const body = source.slice(start, source.indexOf('\n///|', start));
  const syntax = tokens(body, true).map(token => token.value).join(' ');
  // These are actual existing caller source controls, not emitted layout or
  // Native funding evidence. Inline post-current guards must not add another
  // Result-returning helper, closure, or allocation-bearing Array lookup.
  assert.equal((syntax.match(/Ok \( ledger \)/gu) ?? []).length, 2);
  assert.equal((syntax.match(/run \. reads \. get \(/gu) ?? []).length, 1);
  assert(!syntax.includes('check_installed_source_read_retained_ledger'));
  assert(!syntax.includes('. map'));
  assert(!syntax.includes('=> ledger'));
  assert(syntax.includes('physical_equal ( retained_child , child )'));
  assert(syntax.includes('physical_equal ( retained_run , run )'));
});

test('Source owner covers the exact current module and every operation', async () => {
  const {createHash} = await import('node:crypto');
  const {moonOperations} = await import('./moon-interface-inventory.mjs');
  const {assertInterfaceCoverage} = await import('./interface-inventory.mjs');
  const module = 'src/client_local_host/installed_source_read.mbt';
  const source = readFileSync(new URL('../' + module, import.meta.url));
  // Validate both existing owners independently: merging their declarations
  // must not hide a stale hash in one behind the other's current operation.
  for (const path of ['src/client_local_host/ordered-direct-inputs-interface-boundaries.json',
    'scripts/interface-owners/core-functional/interface-boundaries.json']) {
    const inventory = JSON.parse(readFileSync(new URL('../' + path, import.meta.url)));
    const declaration = inventory.declarations.find(value => value.module === module);
    assert.equal(declaration.responsibilityFacet, 'primary');
    assertInterfaceCoverage({root: new URL('../', import.meta.url).pathname,
      modules: [{module, sha256: createHash('sha256').update(source).digest('hex'),
        exports: [], operations: moonOperations(source.toString())}],
      declarations: [declaration]});
  }
});

test('hosted lint always runs the Source current controls without weakening failure handling', async () => {
  const {parse} = await import('yaml');
  const workflow = parse(readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8'));
  const step = workflow.jobs.lint.steps.find(value => value.name === 'Test original Source current control ownership');
  assert(step);
  assert.equal(step.run, 'node --test scripts/source-read-current-control.test.mjs');
  assert.equal(step.if, undefined);
  assert.equal(step['continue-on-error'], undefined);
});
