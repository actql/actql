// Trace only the independent parent boundary. The capacity validator and all
// Core/custody/common checks are real; receipts are explicitly synthetic data.
import assert from 'node:assert/strict';
import { mock } from 'node:test';
import { semanticAuditFixture } from '../capacity/semantic-audit.fixture.mjs';
import { hash } from '../inventory.mjs';
import { capacityPartIds, partRole } from '../proof-parts.mjs';

const mode = process.argv[2], events = [];
const portable = mode === 'portable';
const targets = portable ? ['js'] : ['js', 'wasm', 'native'];
const f = semanticAuditFixture('.artifacts/unused-pipeline-artifact', hash('unused'), { supportTargets: targets });
if (!portable) {
  for (const key of ['normal', 'boundaries', 'mutations']) delete f.report[key];
  Object.assign(f.report, { kind: 'capacity-part',
    part: capacityPartIds.find(id => partRole(id) === 'capacity-support'),
    targets, complete: true, executions: [], executionOwners: {} });
}
f.report.parentStartup = { version: 'synthetic-ordering-only' };
const corpus = mode === 'invalid-corpus' || portable ? [] : f.report.corpus;
Object.defineProperty(f.report, 'corpus', { get() { events.push('corpus'); return corpus; } });
const original = await import('../capacity/parent-control/audit.mjs');
mock.module(new URL('../capacity/parent-control/audit.mjs', import.meta.url).href, {
  namedExports: { auditParentStartup(parent, source, read) {
    events.push('parent'); assert.equal(parent, f.report.parentStartup); assert.equal(source, f.current);
    if (mode === 'parent-refusal') return original.auditParentStartup(parent, source, read);
    // Ordering instrumentation only; no successful Native capture is asserted.
  } },
});
mock.module(new URL('../capacity/parent-control/regression.mjs', import.meta.url).href, {
  namedExports: { rejectParentSubstitutions(parent, source) {
    events.push('substitutions'); assert.equal(parent, f.report.parentStartup); assert.equal(source, f.current);
    if (mode === 'substitution-refusal') throw new Error('OriginalSubstitutionRefusal');
  } },
});
const { validate } = await import('../capacity/audit.mjs');
if (mode === 'invalid-corpus') {
  assert.throws(() => validate(f.report, f.current, targets, f.read), /Scope must come from the reviewed corpus/);
  assert.deepEqual(events, ['corpus']);
} else if (portable) {
  assert.throws(() => validate(f.report, f.current, targets, f.read), /Native parent evidence cannot apply to a portable-only campaign/);
  assert.deepEqual(events, []);
} else if (mode === 'parent-refusal') {
  assert.throws(() => validate(f.report, f.current, targets, f.read), error =>
    error.code === 'ERR_ASSERTION' && error.message.includes('actql-current-chain-native-diagnostic/0.1'));
  assert.deepEqual(events, ['corpus', 'parent']);
} else if (mode === 'substitution-refusal') {
  assert.throws(() => validate(f.report, f.current, targets, f.read), /OriginalSubstitutionRefusal/);
  assert.deepEqual(events, ['corpus', 'parent', 'substitutions']);
} else {
  assert.equal(mode, 'healthy');
  const result = validate(f.report, f.current, targets, f.read);
  events.push('returned');
  assert.deepEqual(result, { part: f.report.part, scope: 'fragment', cases: 0, targets, unconditionalAllocationBytes: false });
  assert.deepEqual(events, ['corpus', 'parent', 'substitutions', 'returned']);
}
console.log(JSON.stringify({ mode, events, qualification: 'Real capacity validator; synthetic support receipts and traced parent ports, not Native execution.' }));
