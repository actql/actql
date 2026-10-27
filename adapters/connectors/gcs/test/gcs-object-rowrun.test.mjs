import {ledgerUsageSnapshot} from '../../../host-common/runtime-core.mjs';
import {ledgerUsageFieldsFor} from '../../../host-node/fixtures/ledger-usage.mjs';
// Real installed Source, RowRun, reference admission and original Ledger.
// Credential/account/HTTP ports are explicit controls; this is neither an
// installed package campaign nor a GCS service/permission acceptance result.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {inspect} from 'node:util';
import test from 'node:test';
import * as moon from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as provider from '../../../../_build/js/release/build/connectors/gcs/host_node/host_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';
import {createInstalledRowSource, rowSourceCheckEnvironment} from '../../../host-node/installed-row-source.mjs';
import {restoreGcsSourceDeclaration} from '../host/gcs-source-declaration.mjs';
import {readGcsObjects} from '../site/gcs-object-listing.mjs';
import {GCS_FILE_LIST_OPERATION} from '../site/gcs-file-listing.mjs';

const read = path => readFile(new URL(`../../../../${path}`, import.meta.url), 'utf8');
const cid = character => `sha256:${character.repeat(64)}`;
const resource = Object.freeze({$actql_ref: 'resource', version: 'actql-resource-ref/0.1',
  provider_namespace: 'gcs', resource_kind: 'file', provider_identity_cid: cid('a'),
  authority_scope_cid: cid('b'), boundary_cid: cid('c'), identity_cid: cid('d')});
const object = Object.freeze({bucket: 'actql-fixture', name: 'in/e\u0301%2F.csv',
  generation: '9007199254740993', metageneration: '2', size: '9223372036854775807',
  contentType: 'text/csv', storageClass: 'COLDLINE', updated: '2026-10-17T00:00:00Z',
  md5Hash: 'AAAAAA==', crc32c: 'crxyRA==',
  metadata: {'actql-request': 'private', '$json': 'user', 'e\u0301': 'e\u0301\r\n%2F'}});
const expected = {resource, version: '9007199254740993', name: 'in/e\u0301%2F.csv',
  size: '9223372036854775807', generation: '9007199254740993', metageneration: '2',
  content_type: 'text/csv', storage_class: 'COLDLINE', updated: '2026-10-17T00:00:00.000Z',
  md5: 'AAAAAA==', crc32c: 'crxyRA==',
  metadata: {$json: {'$json': 'user', 'e\u0301': 'e\u0301\r\n%2F'}}};

async function fixture({pages = [{kind: 'storage#objects', nextPageToken: 'next'},
  {kind: 'storage#objects', items: [object]}], admitReference = true,
  attempts = 1, holdings = 1} = {}) {
  const profile = {version: 'actql-installed-gcs-source/0.1', connectorId: 'storage',
    project: 'fixture-project', bucket: 'actql-fixture', prefix: 'in/',
    mediaType: 'text/csv', siteProfilePath: '/fixture/site.json', accountConfigurationWire: '{}',
    limits: {maxListingItems: 3, maxExaminedItems: 9, maxPages: 4, maxAttempts: 4,
      maxListingBytes: 32768, maxDurationMs: 10000, maxPathBytes: 1024,
      maxPageBytes: 8192, maxPageItems: 3, maxRequestBytes: 4096, maxContentBytes: 4096}};
  const {declaration, declared} = restoreGcsSourceDeclaration(moon, profile, undefined,
    {includeObjects: true});
  const environment = rowSourceCheckEnvironment((await read('spec/local-check-environment.json')).trimEnd(), declared);
  const checkedEnvironment = moon.clientProgramCheckEnvironment(environment.wire,
    environment.evidenceCid, false, false, true, false, false, false, false);
  assert.ok(checkedEnvironment);
  const fields = ['resource', 'version', 'name', 'size', 'content_type', 'generation',
    'metageneration', 'storage_class', 'updated', 'md5', 'crc32c', 'metadata'];
  const outcome = moon.clientProgramPrepareEffectFreeWithParameters(JSON.stringify({
    version: 'actql/0.1', id: 'gcs-object-original-capture', stages: [{id: 'scan',
      inputs: {objects: {connector: 'storage', resource: 'objects', view: 'records', request: {prefix: null}}},
      steps: [{from: 'objects', filter: 'true', as: 'listed'},
        {from: 'listed', select: fields, as: 'rows'},
        {from: 'rows', assert_rows: {unique_by: ['name']}, as: 'unique_names'},
        {from: 'unique_names', sort: [{name: 'asc'}], as: 'ordered'}],
      results: {r: {from: 'ordered', fields}}}],
    results: {r: {from: {stage: 'scan', result: 'r'}}}}), 'json', checkedEnvironment, undefined);
  const preparedProgram = moon.clientProgramPreparationReady(outcome);
  assert.ok(preparedProgram, inspect(moon.clientProgramPreparationIssue(outcome), {depth: 12}));
  const [registry, aoa] = await Promise.all([read('spec/dependencies/aoa-pipeline-registry.json'),
    read('spec/contracts/actql-aoa.json').then(JSON.parse)]);
  const state = {calls: [], grants: 0, raw: [], allowed: true, referenceReads: 0};
  const issuer = moon.clientProgramResourceReferenceIssuer((kind, wire) => {
    state.referenceReads++;
    return admitReference && kind === 'file' &&
      inspect(JSON.parse(wire), {sorted: true}) === inspect(resource, {sorted: true});
  }, () => state.allowed);
  const scope = Object.freeze({operation: GCS_FILE_LIST_OPERATION,
    resourceOrigin: 'https://storage.googleapis.com', siteGeneration: 1,
    issuerAuthority: 'fixture', principal: 'fixture', namespaceId: 'fixture',
    environment: 'fixture', siteKey: 'fixture', runtimeBundleCid: cid('e'),
    connectorRegistration: 'gcs', connectorRevision: 'gcs/0.1',
    runInvocationCid: cid('f'), taskAttempt: 1, dispatchRequestCid: cid('0')});
  const adapter = await createInstalledRowSource({moon, declaration, declared,
    environmentWire: environment.wire, connectorId: 'storage',
    connectorRegistration: 'gcs', connectorRevision: 'gcs/0.1',
    referenceIssuer: issuer, bindingCid: cid('1'),
    readOperation: {objects: GCS_FILE_LIST_OPERATION, files: GCS_FILE_LIST_OPERATION,
      contents: 'gcs:file:read'},
    site: {connection: 'gcs:fixture-project/actql-fixture',
      issueReadGrant() { state.grants++; return {grant: {}, scope}; }, close() {}},
    authorization: {authorize: async () => ({action: state.allowed ? 'dispatch' : 'deny'}),
      accountConfiguration: '{}', context: {contextCid: cid('2')}},
    physicalTarget: (name, selected) => ({resource: name, fields: selected}),
    limits: {maxPages: 4, maxPageBytes: 8192, maxPageRows: 3, maxCaptureRows: 3},
    readPages: options => readGcsObjects({...options, moon: provider,
      target: {bucket: profile.bucket, prefix: profile.prefix},
      limits: {maxPageBytes: 8192, maxPageItems: 3, maxRequestBytes: 4096,
        maxTimeMs: 1000, maxPages: 4, maxRows: 3},
      credential: {journal: {fixture: true}},
      resourceFor: target => {
        assert.deepEqual(target, {bucket: object.bucket, objectName: object.name});
        return resource;
      },
      callResource: async call => {
        state.calls.push(call);
        const body = Buffer.from(JSON.stringify(pages[state.calls.length - 1]));
        state.raw.push(body);
        return {accepted: true, statusCode: 200, headers: [], body};
      }}),
  });
  const inputs = {preparedProgram, registry,
    values: JSON.stringify(aoa.execution_contracts['REL.values']),
    fragment: JSON.stringify(aoa.execution_contracts['ACTQL.expression_fragment/0.1']),
    ordered: JSON.stringify(aoa.execution_contracts['REL.derive.ordered'])};
  const preparedSource = await adapter.prepare(inputs);
  // Independent finite component capacity, not an adopted normal Host price.
  const ledger = checked(moon.clientProgramAcquisitionLedger(attempts, holdings,
    32768n, 100000000n, 100000000n, 0));
  return {adapter, state, issuer, ledger, inputs: {...inputs, preparedSource}};
}

test('GCS ordinary metadata reaches actual accounted Source capture with exact typed rows and original raw charges', async t => {
  // Three explicit same-Ledger lifecycle attempts: acquisition, refused
  // unavailable restoration, then admitted restoration. Two cumulative
  // holding identities are issued; release does not refund those counters.
  const value = await fixture({attempts: 3, holdings: 2});
  const capture = await value.adapter.openCapture({...value.inputs, ledger: value.ledger})
    .catch(error => {
      // This fixture contains no credentials or service values. Preserve the
      // original refusal while exposing its bounded portable cause for review.
      t.diagnostic(inspect(error, {depth: 12, maxStringLength: 1000}).slice(0, 8000));
      throw error;
    });
  t.after(() => capture.close());
  assert.equal(moon.clientProgramCapturedSourceRowCount(capture.identity), 1);
  assert.equal(value.state.calls.length, 2);
  assert.equal(value.state.grants, 1);
  assert.ok(value.state.referenceReads > 0);
  assert.notEqual(capture.capture.originalRead(), undefined);
  const usage = moon.clientProgramMultiCapturedLedgerUsage(value.ledger);
  assert.equal(ledgerUsageSnapshot(usage).transferredBytes, BigInt(value.state.raw.reduce((sum, body) => sum + body.length, 0)));
  assert.ok(ledgerUsageSnapshot(usage).heldBytes > 0n, 'capture retains the original holding after temporary execution settles');
  const original = value.adapter.retainedCapture(value.inputs.preparedSource);
  const binding = 'gcs-object-original-run/task-0/input-0';
  const exported = checked(moon.clientProgramExportSourceCapture(capture.capturedSource,
    capture.requirement, binding));
  const rows = moon.clientProgramSourceCaptureExportRows(exported);
  assert.deepEqual(rows.map(JSON.parse), [expected]);
  const saved = [moon.clientProgramSourceCaptureExportRequirement(exported), binding, binding,
    moon.clientProgramSourceCaptureExportDescriptor(exported), rows];
  capture.close();
  assert.deepEqual(ledgerUsageFieldsFor(moon.clientProgramMultiCapturedLedgerUsage(value.ledger), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]),
    [0n, 0n, 0n, 0n]);
  let custodyChecks = 0;
  assert.throws(() => checked(moon.clientProgramRestoreSourceCapture(original.requirement,
    ...saved, value.ledger, original.capacity, () => { custodyChecks++; return false; },
    value.issuer, undefined)),
  {code: 'MoonBitHostFailure'});
  assert.ok(custodyChecks > 0, 'the rejection must reach original custody, not exhaust the test Ledger');
  let restored;
  try {
    restored = checked(moon.clientProgramRestoreSourceCapture(original.requirement,
      ...saved, value.ledger, original.capacity, () => true, value.issuer, undefined));
  } catch (error) {
    t.diagnostic(inspect(error, {depth: 12, maxStringLength: 1000}).slice(0, 8000));
    throw error;
  }
  t.after(() => moon.clientProgramCloseSourceCapture(restored));
  const again = checked(moon.clientProgramExportSourceCapture(
    moon.clientProgramSourceCaptureSource(restored), original.requirement, binding));
  assert.deepEqual(moon.clientProgramSourceCaptureExportRows(again), rows);
  assert.equal(value.state.calls.length, 2, 'same original saved capture restore does not reacquire GCS');
  assert.equal(moon.clientProgramCloseSourceCapture(restored), true);
  assert.equal(moon.clientProgramSourceCaptureSource(restored), undefined);
  assert.deepEqual(moon.clientProgramSourceCaptureUsage(restored), [0n, 0n, 0n]);
  assert.equal(ledgerUsageSnapshot(moon.clientProgramMultiCapturedLedgerUsage(value.ledger)).attempts, 3n);
  assert.equal(ledgerUsageSnapshot(moon.clientProgramMultiCapturedLedgerUsage(value.ledger)).holdings, 2n);
});

test('GCS ordinary Source refuses insufficient original Ledger capacity before any grant or physical call', async () => {
  const value = await fixture();
  const short = checked(moon.clientProgramAcquisitionLedger(1, 1, 32768n, 1n, 1n, 0));
  const before = moon.clientProgramMultiCapturedLedgerUsage(short);
  await assert.rejects(value.adapter.openCapture({...value.inputs, ledger: short}));
  assert.equal(value.state.grants, 0);
  assert.equal(value.state.calls.length, 0);
  assert.deepEqual(moon.clientProgramMultiCapturedLedgerUsage(short), before);
});

test('GCS ordinary Resource refusal cannot turn complete provider bytes into a capture', async () => {
  const value = await fixture({pages: [{kind: 'storage#objects', items: [object]}], admitReference: false});
  await assert.rejects(value.adapter.openCapture({...value.inputs, ledger: value.ledger}));
  assert.equal(value.state.calls.length, 1);
  assert.ok(value.state.referenceReads > 0);
  const usage = moon.clientProgramMultiCapturedLedgerUsage(value.ledger);
  assert.equal(ledgerUsageSnapshot(usage).transferredBytes, BigInt(value.state.raw[0].length));
  assert.deepEqual(ledgerUsageFieldsFor(usage, ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);
});
