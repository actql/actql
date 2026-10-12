// Actual continuation installation order and reference checks; the deliberately
// interrupted prepared-facts port is a double, not Core park or public startup.
import assert from 'node:assert/strict';
import test from 'node:test';
import {installNodeModelContinuation} from './installed-model-continuation.mjs';

async function fixture() {
  let selected, reads = 0;
  const control = {}, scope = {}, compiled = {}, runDefinition = {};
  const probe = new Error('PreparedFactsDiagnosticBoundary');
  let factsCalls = 0;
  const operation = {originalResourceScope: () => scope,
    preparedFacts() {factsCalls++; throw probe;}};
  const controller = await installNodeModelContinuation({control,
    getCheckpoints() {reads++; return selected;}});
  const originalPreparation = {scope, control, compiled, runDefinition};
  return {controller, probe, operation, originalPreparation,
    reads: () => reads, factsCalls: () => factsCalls,
    select: value => {selected = value;},
    open: () => controller.open({operation, originalPreparation,
      preparedCallSet: {}, plan: {compiled, runDefinition}, selected: {}})};
}

test('original journal installation never treats initial undefined as a successful selection', async () => {
  const f = await fixture();
  await assert.rejects(f.open(), {code: 'InstalledModelJournalRequired'});
  assert.equal(f.factsCalls(), 0);
  const cp = {journal: {}};
  f.select(cp);
  await assert.rejects(f.open(), error => error === f.probe);
  assert.equal(f.factsCalls(), 1);
  assert.equal(f.reads(), 2);
});

test('original journal installation rejects replacement checkpoints and journal identity before preparation', async () => {
  for (const replace of [cp => ({...cp}), cp => {cp.journal = {}; return cp;}]) {
    const f = await fixture();
    const cp = {journal: {}};
    f.select(cp);
    await assert.rejects(f.open(), error => error === f.probe);
    f.select(replace(cp));
    await assert.rejects(f.open(), {code: 'InstalledModelJournalChanged'});
    assert.equal(f.factsCalls(), 1);
  }
});

test('original journal installation uses the scope retained by the original operation', async () => {
  const f = await fixture();
  f.originalPreparation.scope = {};
  f.select({journal: {}});
  await assert.rejects(f.open(), {code: 'InstalledModelOriginalScopeMismatch'});
  assert.equal(f.reads(), 0);
  assert.equal(f.factsCalls(), 0);
});
