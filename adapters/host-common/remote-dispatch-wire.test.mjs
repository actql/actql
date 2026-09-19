import assert from 'node:assert/strict';
import test from 'node:test';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from './runtime-core.mjs';
import {
  admitRemoteDispatchJson,
  admitRemoteExecutionEvidenceJson,
  admitRemoteManagedOutputMeasurementJson,
  admitRemoteManagedOutputSubjectJson,
} from
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

test('managed output decoding binds canonical physical and logical facts', () => {
  const request = prepared();
  const measurement = control.prepareManagedOutputMeasurement(Object.freeze({
    rowCount: 2,
    admissionNodes: 0,
    admissionTextBytes: 0,
    admissionWork: 0,
    columnRows: Object.freeze([2]),
    columnBytes: Object.freeze([2]),
    columnNodes: Object.freeze([2]),
    columnMaxValueBytes: Object.freeze([1]),
    columnNullRows: Object.freeze([0]),
    columnAdmittedDepths: Object.freeze([10]),
  }));
  const subject = control.prepareManagedOutputSubject(request, Object.freeze({
    materialGeneration: 'material-generation-a',
    holdingEvidenceCid: cid('c'),
    managedProfileCid: cid('3'),
    resultSchemaCid: cid('5'),
    logicalViewCid: cid('6'),
    representationCodecCid: cid('7'),
    physicalManifestCid: cid('8'),
    rowCount: 2,
    retainedBytes: 8n,
  }), measurement);
  const measurementBody = control.managedOutputMeasurementJson(measurement);
  const admittedMeasurement = admitRemoteManagedOutputMeasurementJson(
    control,
    measurementBody,
    control.managedOutputMeasurementIdentity(measurement),
  );
  assert.equal(
    control.managedOutputMeasurementIdentity(admittedMeasurement),
    control.managedOutputMeasurementIdentity(measurement),
  );
  assert.throws(
    () => admitRemoteManagedOutputMeasurementJson(
      control,
      measurementBody.replace('"bytes":2', '"bytes":3'),
      control.managedOutputMeasurementIdentity(measurement),
    ),
    {code: 'InvalidRemoteManagedOutputMeasurementWire'},
  );
  const body = control.managedOutputSubjectJson(subject);
  const admitted = admitRemoteManagedOutputSubjectJson(
    control,
    body,
    control.managedOutputSubjectIdentity(subject),
    request,
  );
  assert.equal(
    control.managedOutputSubjectIdentity(admitted),
    control.managedOutputSubjectIdentity(subject),
  );
  const differentMeasurement = control.prepareManagedOutputMeasurement(
    Object.freeze({
      rowCount: 2,
      admissionNodes: 1,
      admissionTextBytes: 0,
      admissionWork: 0,
      columnRows: Object.freeze([2]),
      columnBytes: Object.freeze([2]),
      columnNodes: Object.freeze([2]),
      columnMaxValueBytes: Object.freeze([1]),
      columnNullRows: Object.freeze([0]),
      columnAdmittedDepths: Object.freeze([10]),
    }),
  );
  assert.equal(
    control.managedOutputSubjectMatchesMeasurement(
      admitted,
      differentMeasurement,
    ),
    false,
  );
  const altered = body.replace('"row_count":2', '"row_count":3');
  assert.throws(
    () => admitRemoteManagedOutputSubjectJson(
      control,
      altered,
      control.managedOutputSubjectIdentity(subject),
      request,
    ),
    {code: 'InvalidRemoteManagedOutputSubjectWire'},
  );
});
