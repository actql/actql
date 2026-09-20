// Benchmark-owned semantic projection for acquisition evidence comparison.
// Per-leg authority identities remain distinct and are checked within each
// evidence chain; they are never normalized into a shared fake identity.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {benchmarkEnvironment} from
  '../../../../../benchmarks/retained-results/environment.mjs';
import {workloads} from '../../../../../benchmarks/retained-results/fixtures.mjs';
import {canonicalText} from '../../../../../scripts/check-canonical-json.mjs';

const cidPattern = /^sha256:[0-9a-f]{64}$/;
const hash = value => `sha256:${createHash('sha256')
  .update(canonicalText(value)).digest('hex')}`;
const evidenceContractCid = hash(JSON.parse(readFileSync(new URL(
  '../../../../../spec/contracts/actql-query-two-receipt.json',
  import.meta.url,
), 'utf8')));

function assertCid(value, label) {
  assert.equal(typeof value, 'string', label);
  assert.match(value, cidPattern, label);
}

function fixtureMaterial(fixture) {
  const environment = JSON.parse(benchmarkEnvironment(fixture).text);
  assert.equal(environment.source_views.length, 1);
  const view = environment.source_views[0];
  const contract = cid => environment.contract_registry.find(value =>
    value.cid === cid);
  const rowContract = contract(view.output.schema.cid);
  const policyContract = contract(view.output.data_policy.cid);
  assert(rowContract && policyContract, 'MissingBenchmarkAcquisitionContract');
  const fields = fixture.workload === workloads[2]
    ? fixture.fields : ['id'];
  const outputContractCid = hash(Object.fromEntries(fields.map(name => {
    const value = rowContract.body.fields[name];
    assert(value, `MissingBenchmarkField:${name}`);
    return [name, value];
  })));
  const parameterValuesCid = hash({
    values: {minimum: fixture.minimum},
    version: 'actql-parameter-values/0.1',
  });
  const resolvedRequestCid = hash({});
  const sourceRef = policyContract.body.source_ref;
  const sourceContractCid = view.contract_cid;
  const scopeCid = hash({
    resolved_request_cid: resolvedRequestCid,
    source_contract_cid: sourceContractCid,
    source_ref: sourceRef,
    version: 'actql-query-scan-scope/0.1',
  });
  return Object.freeze({
    fields: Object.freeze([...fields]),
    outputContractCid,
    parameterValuesCid,
    resolvedRequestCid,
    sourceRef,
    sourceContractCid,
    scopeCid,
  });
}

function receiptProjection(receipt) {
  return Object.freeze({
    receivedRowsCid: receipt.received_rows_cid,
    receivedRows: receipt.received_rows,
    receivedFields: Object.freeze([...receipt.received_fields]),
    receivedBytes: receipt.received_bytes,
  });
}

function projection(material, validation, output) {
  for (const [label, value] of [['validation', validation], ['output', output]]) {
    assert(value && Number.isSafeInteger(value.rows) && value.rows >= 0,
      `InvalidAcquisition${label}Rows`);
    assert(value && Number.isSafeInteger(value.bytes) && value.bytes >= 0,
      `InvalidAcquisition${label}Bytes`);
    assertCid(value.cid, `InvalidAcquisition${label}Cid`);
    assert(Array.isArray(value.fields) && value.fields.every(field =>
      typeof field === 'string' && field.length),
    `InvalidAcquisition${label}Fields`);
  }
  return Object.freeze({
    version: 'actql-query-two-receipt-observation/0.1',
    evidenceContractCid,
    owner: Object.freeze({stage: 'acquire', input: 'remote'}),
    sourceRef: material.sourceRef,
    sourceContractCid: material.sourceContractCid,
    parameterValuesCid: material.parameterValuesCid,
    resolvedRequestCid: material.resolvedRequestCid,
    snapshot: null,
    scopeCid: material.scopeCid,
    receiptRoles: Object.freeze(['validation_scan', 'native_result']),
    recordRoles: Object.freeze(['source_validation', 'filter', 'select']),
    validationScan: Object.freeze({
      receivedRowsCid: validation.cid,
      receivedRows: validation.rows,
      receivedFields: Object.freeze([...validation.fields]),
      receivedBytes: validation.bytes,
    }),
    nativeResult: Object.freeze({
      receivedRowsCid: output.cid,
      receivedRows: output.rows,
      receivedFields: Object.freeze([...output.fields]),
      receivedBytes: output.bytes,
    }),
    output: Object.freeze({
      contractCid: material.outputContractCid,
      rowsCid: output.cid,
      rowCount: output.rows,
    }),
    retention: 'process',
  });
}

export function equivalentAcquisitionMetadata(fixture, validation, output) {
  const material = fixtureMaterial(fixture);
  return projection(material, {
    ...validation,
    fields: fixture.fields,
  }, {
    ...output,
    fields: material.fields,
  });
}

export function productAcquisitionMetadata(fixture, evidence) {
  assert(evidence && Array.isArray(evidence.receipts) &&
    Array.isArray(evidence.records) && evidence.observation,
  'MissingProductAcquisitionEvidence');
  const material = fixtureMaterial(fixture);
  const receipts = evidence.receipts;
  const records = evidence.records;
  const observation = evidence.observation;
  assert.deepEqual(receipts.map(value => value.role),
    ['validation_scan', 'native_result']);
  assert.deepEqual(records.map(value => value.role),
    ['source_validation', 'filter', 'select']);
  const all = [...receipts, ...records];
  for (const value of all) {
    assert.equal(value.version, receipts.includes(value)
      ? 'actql-query-receipt/0.1'
      : 'actql-query-two-receipt-evidence/0.1');
    assert.equal(value.snapshot, null);
    assert.equal(value.issuer, observation.execution.issuer);
    assert.equal(value.attempt, observation.execution.attempt);
    assert.equal(value.read_view, observation.execution.read_view);
    assert.equal(value.requirement_cid, observation.requirement_cid);
    assert.equal(value.scan_scope_cid, material.scopeCid);
  }
  assert(observation.execution.issuer.length > 0);
  assert(observation.execution.attempt.length > 0);
  assert(observation.execution.read_view.length > 0);
  assertCid(observation.requirement_cid, 'InvalidAcquisitionRequirementCid');
  assertCid(observation.owner.program_source_cid,
    'InvalidAcquisitionProgramSourceCid');
  const receiptCids = receipts.map(hash);
  const accesses = {
    native_result_cid: receiptCids[1],
    validation_scan_cid: receiptCids[0],
  };
  for (const record of records) {
    assert.equal(canonicalText(record.accesses), canonicalText(accesses));
    assert.equal(canonicalText(record.output), canonicalText(observation.output));
  }
  assert.equal(canonicalText(observation.accesses), canonicalText(accesses));
  const recordCids = records.map(hash);
  assert.equal(canonicalText(observation.coverage), canonicalText({
    complete: true,
    filter_evidence_cid: recordCids[1],
    scope_cid: material.scopeCid,
    select_evidence_cid: recordCids[2],
    source_validation_evidence_cid: recordCids[0],
  }));
  assert.equal(observation.version,
    'actql-query-two-receipt-observation/0.1');
  assert.equal(observation.evidence_contract_cid, evidenceContractCid);
  assert.deepEqual(observation.owner.stage, 'acquire');
  assert.deepEqual(observation.owner.input, 'remote');
  assert.equal(observation.source_ref, material.sourceRef);
  assert.equal(observation.source_contract_cid, material.sourceContractCid);
  assert.equal(observation.parameter_values_cid, material.parameterValuesCid);
  assert.equal(observation.resolved_request_cid, material.resolvedRequestCid);
  assert.equal(observation.snapshot, null);
  assert.equal(observation.retention, 'process');
  assert.equal(canonicalText(observation.output), canonicalText({
    contract_cid: material.outputContractCid,
    row_count: receipts[1].received_rows,
    rows_cid: receipts[1].received_rows_cid,
  }));
  return Object.freeze({
    version: observation.version,
    evidenceContractCid: observation.evidence_contract_cid,
    owner: Object.freeze({
      stage: observation.owner.stage,
      input: observation.owner.input,
    }),
    sourceRef: observation.source_ref,
    sourceContractCid: observation.source_contract_cid,
    parameterValuesCid: observation.parameter_values_cid,
    resolvedRequestCid: observation.resolved_request_cid,
    snapshot: observation.snapshot,
    scopeCid: observation.coverage.scope_cid,
    receiptRoles: Object.freeze(receipts.map(value => value.role)),
    recordRoles: Object.freeze(records.map(value => value.role)),
    validationScan: receiptProjection(receipts[0]),
    nativeResult: receiptProjection(receipts[1]),
    output: Object.freeze({
      contractCid: observation.output.contract_cid,
      rowsCid: observation.output.rows_cid,
      rowCount: observation.output.row_count,
    }),
    retention: observation.retention,
  });
}
