import assert from 'node:assert/strict';
import test from 'node:test';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from './runtime-core.mjs';
import {admitRemoteDispatchJson, admitRemoteExecutionEvidenceJson} from
  './remote-dispatch-wire.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;

const runtime = runtimeCore(moon);
const control = runtime.remoteSiteControl;

const prepared = () => control.prepare(Object.freeze({
  coordinatorAuthority: 'coordinator-a',
  runDefinitionCid: cid('0'),
  taskKey: 'task-a',
  taskAttempt: 1,
  dispatchId: 'dispatch-a',
  siteKey: 'site-a',
  siteGeneration: 1,
  runtimeBundleCid: cid('a'),
  connectorRegistration: 'local',
  connectorRevision: 'local/1',
  strategyRevision: 'strategy/1',
  inputBindingCid: cid('1'),
  obligationsCid: cid('2'),
  budgetCid: cid('3'),
  grantCid: cid('4'),
}));

test('HTTP decoding preserves transport-independent dispatch identity', () => {
  const request = prepared();
  const body = control.requestJson(request);
  const admitted = admitRemoteDispatchJson(
    control,
    body,
    control.identity(request),
  );
  assert.equal(control.identity(admitted), control.identity(request));
  assert.equal(control.requestJson(admitted), body);
});

test('HTTP decoding rejects altered identity and noncanonical JSON', () => {
  const request = prepared();
  const body = control.requestJson(request);
  assert.throws(
    () => admitRemoteDispatchJson(control, body, cid('f')),
    {code: 'InvalidRemoteDispatchWire'},
  );
  assert.throws(
    () => admitRemoteDispatchJson(
      control,
      `${body.slice(0, -1)},"extra":true}`,
      control.identity(request),
    ),
    {code: 'NonCanonicalRemoteDispatchWire'},
  );
  assert.throws(
    () => admitRemoteDispatchJson(
      control,
      body,
      control.identity(request),
      8,
    ),
    {code: 'InvalidRemoteDispatchWire'},
  );
});

test('evidence decoding recomputes identity and exact dispatch binding', () => {
  const request = prepared();
  const site = runtime.siteControl.create(Object.freeze({
    key: 'site-a',
    generation: 1,
    runtimeRevision: cid('a'),
    maxConcurrentOperations: 1,
    maxConcurrentTransfers: 1,
    maxRetainedBytes: 1024n,
    maxExecutionBytes: 1024n,
  }));
  const journal = control.createJournal(site);
  const record = control.commitAdmission(
    control.prepareAdmission(journal, request),
    true,
  );
  const capability = control.registerExecutionCapability({
    site,
    runtimeBundleCid: cid('a'),
    connectorRegistration: 'local',
    connectorRevision: 'local/1',
    strategyRevision: 'strategy/1',
    operationCapabilityCid: cid('4'),
  });
  control.commitTransition(
    control.prepareProvisioning(record, capability),
    true,
  );
  control.commitTransition(control.prepareExecution(record), true);
  control.commitTransition(control.prepareSettled(record), true);
  control.commitTransition(control.prepareRetained(
    record,
    'material-generation-a',
    cid('c'),
  ), true);
  const issuer = control.registerEvidenceIssuer({
    site,
    runtimeBundleCid: cid('a'),
    connectorRegistration: 'local',
    connectorRevision: 'local/1',
    strategyRevision: 'strategy/1',
    evidenceKind: 'actql.remote.physical-output/0.1',
    issuerCapabilityCid: cid('b'),
  });
  const evidence = control.issueExecutionEvidence(issuer, record, cid('d'));
  const body = control.evidenceJson(evidence);
  const admitted = admitRemoteExecutionEvidenceJson(
    control,
    body,
    control.evidenceIdentity(evidence),
    request,
  );
  assert.equal(
    control.evidenceIdentity(admitted),
    control.evidenceIdentity(evidence),
  );
  assert.throws(
    () => admitRemoteExecutionEvidenceJson(
      control,
      body,
      cid('f'),
      request,
    ),
    {code: 'InvalidRemoteExecutionEvidenceWire'},
  );
  const other = control.prepare(Object.freeze({
    coordinatorAuthority: 'coordinator-a',
    runDefinitionCid: cid('0'),
    taskKey: 'task-a',
    taskAttempt: 2,
    dispatchId: 'dispatch-b',
    siteKey: 'site-a',
    siteGeneration: 1,
    runtimeBundleCid: cid('a'),
    connectorRegistration: 'local',
    connectorRevision: 'local/1',
    strategyRevision: 'strategy/1',
    inputBindingCid: cid('1'),
    obligationsCid: cid('2'),
    budgetCid: cid('3'),
    grantCid: cid('4'),
  }));
  assert.throws(
    () => admitRemoteExecutionEvidenceJson(
      control,
      body,
      control.evidenceIdentity(evidence),
      other,
    ),
    {code: 'NonCanonicalRemoteExecutionEvidenceWire'},
  );
});
