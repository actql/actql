// Actual adapter/control connection with explicit Core port doubles. These
// tests do not issue a Resource admission, Store ACK or dispatch permission.
import test from 'node:test';
import assert from 'node:assert/strict';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {openNodeInferOperation} from './infer-operation.mjs';

const ok = value => ({$tag: 1, _0: value});
const limits = {maxWireBytes: 16384, maxNodes: 1024, maxDepth: 20};
function fixture() {
  const active = Object.freeze({kind: 'original execution double'});
  const issued = Object.freeze({name: 'model_invocation_evidence',
    identity: 'original invocation CID', wire: '{"value":"e\u0301\\r\\n"}'});
  const template = Object.freeze({name: 'template', identity: 'template CID', wire: '{}'});
  let stopped = false, cleanup = false, reads = 0, admissions = 0, next = issued;
  const moon = {
    strategyRemoteManagedOutputEvidenceKind: () => 'explicit fixture metadata',
    clientProgramStartScopedInferExecution: () => ok(active),
    clientProgramCancelInferExecution: () => { stopped = true; },
    clientProgramInferExecutionStopped: () => stopped,
    clientProgramCleanupInferExecution: () => ok(cleanup),
    clientProgramInferInvocationEvidence(execution, slot) {
      assert.strictEqual(execution, active);
      assert.equal(slot, 0);
      reads++;
      return next;
    },
    strategyRunEvidenceName: value => value.name,
    strategyRunEvidenceIdentity: value => value.identity,
    strategyRunEvidenceJson: value => value.wire,
    strategyRunEvidenceAdmit() { admissions++; return ok(template); },
    strategyIssueRunInvocation(originalTemplate, originalObservation) {
      assert.strictEqual(originalTemplate, template);
      assert.strictEqual(originalObservation, issued);
      return ok({name: 'run_invocation', identity: 'invocation CID', wire: '{}'});
    },
    strategyPublicationContractName: value => value.name,
    strategyPublicationContractIdentityField: () => 'cid',
    strategyPublicationContractIdentity: value => value.identity,
    strategyPublicationContractJson: value => value.wire,
  };
  const control = runtimeCore(moon).publicationControl;
  const operation = openNodeInferOperation({moon, provider: {}});
  return {moon, control, operation, active, issued,
    counts: () => ({reads, admissions}), setNext: value => { next = value; },
    allowCleanup: () => { cleanup = true; }};
}

test('issued invocation view preserves the exact Core token and original bytes without wire admission', async () => {
  const f = fixture();
  const view = f.operation.invocationEvidenceView(f.control, 0);
  assert.ok(Object.isFrozen(view));
  assert.deepEqual(view, f.issued);
  assert.equal(f.counts().admissions, 0);
  assert.strictEqual(f.operation.invocationEvidence(0), f.issued, 'existing raw getter is unchanged');
  const template = f.control.admitRunEvidence('template', '{}', limits);
  f.control.issueRunInvocation(template, view, limits);
  assert.equal(f.counts().admissions, 1, 'ordinary wire admission still calls the Core reader');
  assert.throws(() => f.control.issueRunInvocation(template, {...view}, limits), /Foreign Run evidence/u);
  f.allowCleanup();
  await f.operation.close();
});

test('foreign namespaces and invalid slots refuse before the original Core getter', async () => {
  const f = fixture();
  for (const [moon, slot] of [[{...f.moon}, 0], [f.moon, -1], [f.moon, 0.5],
    [f.moon, 2147483648], [f.moon, Number.NaN], [f.moon, undefined]]) {
    assert.throws(() => f.control.inspectInferInvocationEvidence(moon, f.active, slot),
      /Foreign Infer invocation evidence/u);
  }
  assert.throws(() => f.operation.invocationEvidenceView(runtimeCore({...f.moon}).publicationControl, 0),
    /Foreign Infer invocation evidence/u);
  assert.deepEqual(f.counts(), {reads: 0, admissions: 0});
  f.allowCleanup();
  await f.operation.close();
});

test('unavailable and wrong-kind values do not fall back to wire reissuance', async () => {
  const f = fixture();
  f.setNext(undefined);
  assert.equal(f.operation.invocationEvidenceView(f.control, 0), undefined);
  f.setNext({...f.issued, name: 'model_call_attempt'});
  assert.throws(() => f.operation.invocationEvidenceView(f.control, 0),
    /Foreign Infer invocation evidence/u);
  const missing = {...f.moon, clientProgramInferInvocationEvidence: undefined};
  assert.throws(() => runtimeCore(missing).publicationControl.inspectInferInvocationEvidence(
    missing, f.active, 0), /Foreign Infer invocation evidence/u);
  assert.equal(f.counts().admissions, 0);
  f.allowCleanup();
  await f.operation.close();
});

test('pending original cleanup keeps the view available and successful cleanup retires new borrows', async () => {
  const f = fixture();
  const escaped = f.operation.invocationEvidenceView(f.control, 0);
  await assert.rejects(f.operation.close(), /ClientDispatchCleanupPending/u);
  assert.equal(f.operation.cleanupPending(), true);
  assert.deepEqual(f.operation.invocationEvidenceView(f.control, 0), escaped);
  f.allowCleanup();
  assert.equal(f.operation.cleanup(), true);
  const before = f.counts();
  assert.equal(f.operation.invocationEvidenceView(f.control, 0), undefined);
  assert.deepEqual(f.counts(), before);
  assert.equal(escaped.wire, '{"value":"e\u0301\\r\\n"}');
});
