import {ledgerUsageSnapshot} from '../host-common/runtime-core.mjs';
// Actual original Program preparation, Local managed prefix, common generation
// and actual Store publication. This is not installed public dispatch or a
// whole-Run physical Ledger proof; the dispatcher must adopt these same owners.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtemp, open, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {openLocalPublicationStore} from '../store-local/publication-store.mjs';
import {runGeneratedContentPrefix, identifyGeneratedContentInput,
  writeGeneratedContent} from './generated-content-write.mjs';
import {issueStoredGeneratedContent, retainGeneratedContentEvidence} from './generated-content-holding.mjs';
import {publishCompletedEffectFreeRun} from '../host-common/completed-run-publication.mjs';
import {serializationPublicationExecution} from './serialization-result-publication.mjs';
import {serializationTaskPublicationPlan} from './local-values-plan.mjs';

const runtime = runtimeCore(moon);
const control = runtime.contentGenerationControl;
const token = byte => `sha256:${byte.repeat(64)}`;
const hash = bytes => `sha256:${createHash('sha256').update(bytes).digest('hex')}`;
const environmentWire = (await readFile(new URL('../../spec/local-check-environment.json',
  import.meta.url), 'utf8')).trim();
const environment = moon.clientProgramCheckEnvironment(environmentWire,
  JSON.parse(environmentWire).evidence_bundle_cid, false, false, true, false, false, false, false);
const registry = await readFile(new URL('../../spec/dependencies/aoa-pipeline-registry.json',
  import.meta.url), 'utf8');
const aoa = JSON.parse(await readFile(new URL('../../spec/contracts/actql-aoa.json',
  import.meta.url), 'utf8'));
const bodies = {registry, values: JSON.stringify(aoa.execution_contracts['REL.values']),
  fragment: JSON.stringify(aoa.execution_contracts['ACTQL.expression_fragment/0.1']),
  ordered: JSON.stringify(aoa.execution_contracts['REL.derive.ordered'])};
const prefixLimits = {maxRows: 3, maxWork: 100000, maxEntries: 1000,
  maxValueBytes: 4096, maxValueNodes: 1000, maxValueDepth: 16, maxFrames: 100};
const generationLimits = {maxRows: 3, maxBytes: 128, maxValueNodes: 1000,
  maxValueDepth: 16, maxFrames: 100};
const referenceLimits = {maxBytes: 4096, maxNodes: 100, maxDepth: 8, maxTextUnits: 4096};
const outputLimits = {maxNodes: 100, maxTextBytes: 4096, maxDepth: 8,
  maxWork: 10000, maxNameBytes: 512};
const resultLimits = {maxResultFields: 5, maxResultMappingWork: 10000,
  maxResultOrderWork: 10000, maxResultWorkspaceEntries: 1000, maxRows: 1,
  maxValueNodes: 1000, maxValueTextBytes: 10000, maxValueDepth: 16, maxValueWork: 100000,
  maxWireBytes: 10000, maxWireNodes: 1000, maxWireDepth: 16, maxColumns: 5,
  maxOrderWork: 10000, maxLogicalWireBytes: 10000, maxLogicalWireNodes: 1000,
  maxLogicalWireDepth: 16, maxSchemaFields: 5, maxSchemaBytes: 100000,
  maxSchemaNodes: 10000, maxSchemaDepth: 32, maxBatchBytes: 10000};

// Independently constructed ASCII fixture preimages and Node SHA-256. Neither
// the expected envelopes nor these identity vectors use the product candidate.
const referenceIdentities = {
  'jsonl/false': ['087e420a9dc750b221ec0c267c3ca19687b0983f802246cc9677108a85065217',
    '54fdf88b716581e647ae2dccc93f7a958ab20cc8a4bfb20cf2aa6fb3584358d3'],
  'jsonl/true': ['2a4d3820a33234b966fdcee9c32aab5049e9be58cd3abeea6253ab38cb57684f',
    '0d11df98e30db97f20f9154bccd2ed9141238afcbd09ac0dde74104dd8809df8'],
  'csv/false': ['44aaafe6b069957953c1237bd3f39eadfac3e8eb7171f2e97811221a90d9f141',
    '22afef4bdddd947db9540b952e35a8a2e846a643edd7a66ca18cd4eb298b98c8'],
  'csv/true': ['b181e714c63068ab2e047580493ad759831c8ed9be695aeb8929b0f661221009',
    'b17c98a0d78e2b87d44e6d890d2557abe2ecdc740925f9eeb3f8615565aeb627'],
};

function expectedReference(bytes, mediaType, workCase) {
  const [issuerCid, refCid] = referenceIdentities[workCase].map(value => `sha256:${value}`);
  return {$actql_ref: 'content', version: 'actql-content-ref/0.1', media_type: mediaType,
    content_ref_cid: refCid, metadata: {content_store_id: 'fixture', content_cid: hash(bytes),
      media_type: mediaType, storage_scope: 'workspace', retention_class: 'fixture',
      availability_evidence_cid: token('3'), capture_authority: 'read_content',
      data_classification: 'internal', effective_data_policy_cid: token('4'),
      size_bytes: Buffer.byteLength(bytes), truncated: false,
      issuer_evidence: {version: 'actql-content-issuer-evidence/0.1',
        issuer_kind: 'content_derivation', issuer_contract_cid: token('5'),
        content_store_cid: token('1'), workspace_scope_cid: token('2'),
        content_cid: hash(bytes), effective_data_policy_cid: token('4'),
        capture_authority_cid: token('6'), evidence_cid: issuerCid}}};
}

function preparation({empty = false, detour = false, format = 'jsonl'} = {}) {
  const program = {version: 'actql/0.1', id: 'local-content-input',
    stages: [{id: 'main', inputs: {}, steps: [
      {values: {schema: {id: {type: 'number', nullable: false},
        p: {type: 'number', nullable: true}},
      rows: empty ? [] : [{id: 2, p: null}, {id: 9, p: 90}, {id: 1, p: 7}]}, as: 'seed'},
      {filter: 'id < 3', as: 'selected'},
      ...(detour ? [{values: {schema: {id: {type: 'number', nullable: false}},
        rows: [{id: 99}]}, as: 'detour'}] : []),
      {from: 'selected', serialize: {format, fields: ['id', 'p'],
        name: `selected.${format}`, preserve_order: true,
        ...(format === 'csv' ? {header: true, null_marker: '\\N', line_ending: 'crlf'} : {}),
        bounds: {max_rows: 3, max_bytes: 128}}, as: 'file'},
    ], results: {file: {from: 'file', fields: ['name', 'content', 'media_type',
      'size_bytes', 'row_count']}}}],
    results: {file: {from: {stage: 'main', result: 'file'}}}};
  const prepared = moon.clientProgramPrepareEffectFreeWithParameters(
    JSON.stringify(program), 'json', environment, undefined);
  const value = moon.clientProgramPreparationReady(prepared);
  assert.ok(value, moon.clientProgramPreparationIssueCode(prepared));
  return value;
}

async function fixture(t, options = {}) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-content-write-'));
  const configuration = {directory, storeAuthorityCid: token('1'),
    capacityBytes: options.capacityBytes ?? 65536,
    maxObjectBytes: options.maxObjectBytes ?? 8192, maxObjects: options.maxObjects ?? 20,
    maxContractNodes: 1000, maxContractDepth: 32,
    privateEvidenceKey: Buffer.alloc(32, 7)};
  let store = await openLocalPublicationStore(configuration, runtime.publicationControl,
  options.durability?.(directory));
  let prefix;
  let writer;
  t.after(async () => {
    // Retire this same physical writer before closing its Store. If cleanup
    // fails, retain the directory rather than erase its pending evidence.
    if (writer) await writer.cancel();
    if (prefix) {
      control.prefixCancel(prefix);
      assert.equal(control.prefixCleanup(prefix), true);
    }
    await store.close();
    await rm(directory, {recursive: true, force: true});
  });
  const prepared = preparation(options);
  const barrier = control.prepare(prepared, 0, 2, 3);
  const capacity = control.prefixCapacity(prepared, 0, 2, bodies, prefixLimits);
  const ledger = checked(moon.clientProgramAcquisitionLedger(1, 0, 0n,
    capacity.retainedBytes, capacity.executionBytes, 0));
  prefix = control.prefix(prepared, 0, 2, bodies, prefixLimits, ledger);
  const before = moon.clientProgramMultiCapturedLedgerUsage(ledger);
  assert.equal(ledgerUsageSnapshot(before).reservedRetentionBytes, capacity.retainedBytes);
  assert.equal(ledgerUsageSnapshot(before).reservedExecutionBytes, capacity.executionBytes);
  let prefixWork = 0;
  const output = await runGeneratedContentPrefix({control, prefix, quantum: 7,
    remainingWork: () => prefixLimits.maxWork - prefixWork,
    chargeWork: work => { prefixWork += work; return prefixWork <= prefixLimits.maxWork; }});
  assert.ok(output, 'original managed prefix must complete');
  assert.ok(prefixWork > 0);
  assert.equal(control.prefixWork(prefix), BigInt(prefixWork));
  const encoder = control.encoder(barrier, options.generationLimits ?? generationLimits);
  const input = control.bindInput(barrier, output, encoder);
  writer = store.createPreparedObjectWriter(128);
  return {store, input, encoder, writer, prefix, prepared, ledger, capacity,
    async reopenStore() {
      await store.close();
      store = await openLocalPublicationStore(configuration, runtime.publicationControl);
      // This test helper reopens only an already-sealed/adopted byte writer.
      // It never forgets provisional or failed cleanup custody.
      assert.equal(writer.status().reservationHeld, false);
      writer = undefined;
      return store;
    }};
}

test('prefix transport charges reported failed work before rejecting without releasing its owner', async () => {
  const prefix = {};
  const issue = new Error('ActualProviderFailure');
  let total = 0n;
  let charged = 0;
  let polls = 0;
  const observed = [];
  const bridge = {
    prefixWork: owner => { assert.equal(owner, prefix); return total; },
    prefixAdvance: (owner, quantum) => {
      assert.equal(owner, prefix);
      assert.equal(quantum, 1);
      polls++;
      total++;
      return {work: 1n, stopped: polls === 2, ...(polls === 2 ? {issue} : {})};
    },
    prefixCleanup: () => assert.fail('transport does not own prefix cleanup'),
    prefixCancel: () => assert.fail('transport does not replace dispatch stopping'),
  };
  await assert.rejects(runGeneratedContentPrefix({control: bridge, prefix, quantum: 1,
    remainingWork: () => 3 - charged,
    chargeWork: delta => { observed.push(delta); charged += delta; return true; }}),
  {code: 'GeneratedContentPrefixFailed', cause: issue});
  assert.deepEqual(observed, [1, 1]);
  assert.equal(charged, 2);
  assert.equal(total, 2n);
  assert.equal(polls, 2);
});

test('prefix transport preserves work and original advance error across a throwing bridge', async () => {
  let total = 0n;
  let charged = 0;
  const issue = new Error('BridgeReplyFailure');
  const bridge = {prefixWork: () => total,
    prefixAdvance: () => { total = 1n; throw issue; }};
  await assert.rejects(runGeneratedContentPrefix({control: bridge, prefix: {}, quantum: 1,
    remainingWork: () => 1,
    chargeWork: delta => { charged += delta; return true; }}), error => error === issue);
  assert.equal(charged, 1);
  total = 0n;
  await assert.rejects(runGeneratedContentPrefix({control: bridge, prefix: {}, quantum: 1,
    remainingWork: () => 1, chargeWork: () => false}), error =>
    error.code === 'GeneratedContentWorkLimit' && error.executionFailure === issue);
  assert.equal(total, 1n, 'refused charge never rewinds the original work observation');
});

test('prefix transport refuses zero budget and partly advanced input without entering Compute', async () => {
  let total = 0n;
  let polls = 0;
  const bridge = {prefixWork: () => total,
    prefixAdvance: () => { polls++; assert.fail('must not enter Compute'); }};
  await assert.rejects(runGeneratedContentPrefix({control: bridge, prefix: {},
    remainingWork: () => 0, chargeWork: () => assert.fail('no fictitious work')}),
  {code: 'GeneratedContentWorkLimit'});
  total = 1n;
  await assert.rejects(runGeneratedContentPrefix({control: bridge, prefix: {},
    remainingWork: () => 10, chargeWork: () => assert.fail('no replayed charge')}),
  {code: 'GeneratedContentPrefixAlreadyAdvanced'});
  assert.equal(polls, 0);
});

test('prefix transport refuses rollback or overflowing work instead of returning a smaller total', async () => {
  for (const [total, code] of [[-1n, 'InvalidGeneratedContentAdvance'],
    [2147483648n, 'GeneratedContentWorkOverflow']]) {
    let polls = 0;
    const bridge = {prefixWork: () => polls === 0 ? 0n : total,
      prefixAdvance: () => { polls++; return {work: total, stopped: true}; }};
    await assert.rejects(runGeneratedContentPrefix({control: bridge, prefix: {},
      remainingWork: () => 10, chargeWork: () => assert.fail('invalid total is not billable')}),
    {code});
    assert.equal(polls, 1);
  }
});

test('actual stored Content closes only its compiled Run component and preserves byte lifetime', async t => {
  const value = await fixture(t, {capacityBytes: 262144, maxObjectBytes: 65536, maxObjects: 100});
  const policy = {kind: 'data_policy',
    cid: 'sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563',
    wire: '{"classification":"unknown","source_data_policy_cids":[],"source_response_policy_cids":[],"unknown_provenance":true,"version":"actql-effective-data-policy/0.1"}'};
  const publications = runtime.publicationControl;
  const graph = publications.prepareCheckedClientSerializationGraph(value.prepared,
    {task: 0, step: 2, maxRows: 3, maxBytes: 128, resultDataPolicy: policy});
  const runPolicy = {executionContextCid: token('a'), hostPolicyCid: token('b'),
    expiresAt: '2099-01-01T00:00:00.000Z'};
  const compiled = publications.prepareCheckedClientCompiledRun(value.prepared,
    'serialization', runPolicy, graph);
  const definition = publications.defineCheckedClientCompiledRun(compiled,
    {namespaceId: 'local', runId: 'content-generation',
      createdAt: '2026-10-09T00:00:00.000Z', validUntil: runPolicy.expiresAt});
  let used = 0;
  const inputEvidence = await identifyGeneratedContentInput({control, compiled,
    input: value.input, limits: {...resultLimits, maxRows: 3}, maxWorkspaceSlots: 10000,
    identityLimits: {maxWireBytes: 16384, maxNodes: 256, maxDepth: 16}, quantum: 7,
    remainingWork: () => 10000 - used,
    chargeWork: delta => { used += delta; return used <= 10000; }});
  // Two rows, two short scalar columns: each column has six cursor phases,
  // each row has opening/closing phases, then the final completion phase.
  assert.equal(used, 2 * (2 * 6 + 2) + 1);
  const inputBody = JSON.parse(inputEvidence.wire);
  assert.equal(inputBody.version, 'actql-content-input-artifact/0.1');
  assert.equal(inputBody.row_count, 2);
  assert.equal(inputBody.ordered_rows_cid, hash('[{"id":2,"p":null},{"id":1,"p":7}]'));
  assert.equal(inputBody.logical_relation_cid,
    hash('{"sort":"relation","value":[{"id":2,"p":null},{"id":1,"p":7}]}'));
  const generated = await writeGeneratedContent({...value, control,
    remainingWork: () => 10000 - used,
    chargeWork: delta => { used += delta; return used <= 10000; }});
  const expectedBytes = '{"id":2,"p":null}\n{"id":1,"p":7}\n';
  assert.equal(generated.contentCid, hash(expectedBytes));
  const binding = {content_store_id: 'fixture', content_store_cid: token('1'),
    workspace_scope_cid: token('2'), storage_scope: 'workspace', retention_class: 'fixture',
    availability_evidence_cid: token('3'), effective_data_policy_cid: policy.cid,
    data_classification: 'unknown', issuer_contract_cid: token('5'), capture_authority_cid: token('6')};
  const candidate = control.candidate(value.encoder, binding, referenceLimits);
  const description = control.inspect(candidate);
  const physical = await value.writer.seal(hash(expectedBytes));
  const holding = {version: 'actql-local-physical-holding/0.1', namespace: 'content',
    holding_cid: publications.checkedClientSerializationByteHoldingCid(compiled,
      definition, token('1')), manifest_cid: description.identity,
    objects: [{cid: physical.cid, byte_count: physical.bytes}]};
  await value.store.commitPhysicalHolding(holding, [physical.prepared]);
  let live = true;
  let retained;
  let capturedRunForStorage;
  let publishedRunKey;
  let publishedEvidence;
  let readingStore = value.store;
  try {
    const content = await issueStoredGeneratedContent({store: value.store, control,
      candidate, holdingCid: holding.holding_cid, workspaceScopeCid: token('2'),
      effectiveDataPolicyCid: policy.cid, available: () => live,
      authorize: () => live, limits: referenceLimits});
    const generation = control.complete(compiled, definition, value.input, inputEvidence, candidate,
      content, () => live, outputLimits);
    const output = control.completedOutput(compiled, generation);
    const row = JSON.parse(control.outputRowWire(output, referenceLimits));
    assert.equal(row.name, 'selected.jsonl');
    assert.equal(row.row_count, 2);
    assert.equal(row.size_bytes, Buffer.byteLength(expectedBytes));
    assert.equal(row.content.metadata.content_cid, hash(expectedBytes));
    assert.equal(row.content.metadata.effective_data_policy_cid, policy.cid);
    assert.throws(() => control.complete({...compiled}, definition, value.input, inputEvidence, candidate,
      content, () => live, outputLimits), /Foreign Client compiled Content Run/u);
    assert.throws(() => control.completedOutput(compiled, {...generation}),
      /Foreign Client Content generation/u);
    const anotherRun = publications.prepareCheckedClientCompiledRun(value.prepared,
      'serialization', runPolicy, graph);
    assert.throws(() => control.completedOutput(anotherRun, generation), /generation unavailable/u);
    control.prefixCancel(value.prefix);
    assert.equal(control.prefixCleanup(value.prefix), true);
    assert.equal(control.completedOutput(compiled, generation), output);
    const evidence = publications.checkedClientSerializationGenerationEvidence(compiled, generation);
    const body = JSON.parse(evidence.wire);
    const derivation = publications.checkedClientSerializationGenerationDerivation(compiled, generation);
    const derivationBody = JSON.parse(derivation.wire);
    assert.equal(body.version, 'actql-content-generation/0.1');
    assert.equal(body.run_definition_cid, definition.identity);
    assert.equal(body.content_evidence_cid, derivation.identity);
    assert.equal(derivationBody.version, 'actql-content-derivation-evidence/0.1');
    assert.equal(derivationBody.barrier_input_artifact_cid, inputEvidence.identity);
    assert.equal(derivationBody.content_cid, hash(expectedBytes));
    assert.equal(derivationBody.content_ref_cid, row.content.content_ref_cid);
    assert.equal(derivationBody.row_count, 2);
    assert.equal(derivationBody.byte_count, Buffer.byteLength(expectedBytes));
    assert.equal(derivationBody.media_type, 'application/x-ndjson');
    assert.equal(derivationBody.name, 'selected.jsonl');
    assert.throws(() => publications.checkedClientSerializationRecoveryBindings(
      {...compiled}, generation, token('1')), /Foreign Client Content generation/u);
    assert.throws(() => publications.checkedClientSerializationRecoveryBindings(
      anotherRun, generation, token('1')), /recovery binding unavailable/u);
    assert.throws(() => publications.checkedClientSerializationRecoveryBindings(
      compiled, generation, token('9')), /recovery binding unavailable/u);
    let custodyRegistered = false;
    let rejectedBeforeCommit = false;
    let lostAcknowledgement = false;
    let privateCommitCalls = 0;
    const evidenceStore = {...value.store, async commitPhysicalHolding(record, prepared) {
      assert.equal(custodyRegistered, true, 'custody must precede the first write');
      privateCommitCalls++;
      if (!rejectedBeforeCommit) {
        rejectedBeforeCommit = true;
        throw new Error('ContentEvidenceCommitRejected');
      }
      const result = await value.store.commitPhysicalHolding(record, prepared);
      if (!lostAcknowledgement) {
        lostAcknowledgement = true;
        throw new Error('ContentEvidenceCommitResponseLost');
      }
      return result;
    }};
    await assert.rejects(retainGeneratedContentEvidence({store: evidenceStore, publications,
      compiled, generation, retainHoldings(holdings, recovery) {
        assert.equal(holdings.length, 3);
        assert.ok(holdings.every(item => item.status().committed === false));
        retained = recovery;
        assert.equal(recovery.holdings, holdings);
        custodyRegistered = true;
      }}), /ContentEvidenceCommitRejected/u);
    const firstHandle = retained.holdings[0];
    assert.equal(firstHandle.status().preparedPending, true);
    assert.equal(firstHandle.status().committed, false);
    assert.equal(await retained.retry(), retained);
    assert.equal(retained.holdings[0], firstHandle, 'retry keeps the original custody');
    assert.equal(firstHandle.status().preparedPending, false);
    assert.ok(custodyRegistered);
    assert.deepEqual(retained.bindings.map(item => item.name),
      ['content_input_artifact', 'content_evidence', 'content_generation']);
    assert.deepEqual(retained.bindings.map(item => item.semanticCid),
      [inputEvidence.identity, derivation.identity, evidence.identity]);
    assert.equal(new Set(retained.bindings.map(item => item.holdingCid)).size, 3);
    assert.equal(lostAcknowledgement, true);
    assert.equal(privateCommitCalls, 4,
      'one proven rejection is retried; a lost durable response is only reconciled');
    for (const binding of retained.bindings) {
      // Independently specified canonical preimage, not a product-generated
      // holding expectation or a sampled physical layout.
      assert.equal(binding.holdingCid, hash(JSON.stringify({node_id: body.node_id,
        role: binding.name, run_definition_cid: definition.identity,
        store_authority_cid: token('1'), version: 'actql-content-private-holding/0.1'})));
      assert.ok(await value.store.confirmPrivateEvidence(binding));
    }
    const issued = publications.issueCheckedClientSerializationInvocation(compiled,
      definition, generation, {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 100});
    const observation = JSON.parse(issued.observation.wire);
    assert.deepEqual(observation.content_generation_cids, [evidence.identity]);
    assert.deepEqual(observation.replayability,
      {availability_evidence_cids: [token('3')], materialized: true});
    assert.equal(JSON.parse(issued.invocation.wire).observation_set_cid, issued.observation.identity);
    // Consume the original typed generation through the existing public
    // evidence controls. A valid saved envelope is not a generation token.
    const limits = {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 100};
    const resultDefinition = publications.seal('result_definition', JSON.stringify({
      version: 'actql-result-definition/0.1',
      program_definition_cid: JSON.parse(compiled.template.wire).program_definition_cid,
      result_name: 'file',
    }), limits);
    const retention = publications.seal('result_retention_policy', JSON.stringify({
      version: 'actql-result-retention-policy/0.1', retention_contract_cid: token('b'),
      effective_data_policy_cid: policy.cid, available_until: runPolicy.expiresAt,
      delete_by: runPolicy.expiresAt, extension_ceiling_at: runPolicy.expiresAt,
      metadata_retention_policy_cid: token('c'), metadata_delete_by: runPolicy.expiresAt,
      clock_contract_cid: token('d'),
    }), limits);
    const selected = control.resultStart(value.prepared, 0, output, resultLimits);
    let exported;
    try {
      let ready = false;
      for (let polls = 0; polls < 10000; polls++) {
        if (control.resultAdvance(selected, 7).ready) { ready = true; break; }
      }
      assert.equal(ready, true);
      exported = control.resultFinish(selected);
      const chunks = [];
      for (let polls = 0; polls < 10000; polls++) {
        const next = runtime.outputExportControl.next(exported);
        if (next === undefined) break;
        chunks.push(next);
      }
      chunks.push(runtime.outputExportControl.finish(exported));
      const rowsWire = chunks.join('');
      assert.deepEqual(JSON.parse(rowsWire), [row]);
      runtime.outputExportControl.issueResultEvidence(exported, {
        computationContractCid: JSON.parse(compiled.compiledPlan.wire).compiled_plan_cid,
        inputRelationCids: [inputBody.logical_relation_cid],
        scopeCid: token('2'), effectiveDataPolicyCid: policy.cid,
        authorityScopeCid: token('6'),
      }, limits);
      const artifact = publications.issueResultArtifact(exported, issued.invocation, retention, limits);
      assert.equal(JSON.parse(artifact.wire).result_definition_cid, resultDefinition.identity);
      const manifest = publications.issueResultManifest(definition, issued.invocation,
        [resultDefinition], [artifact], limits);
      const normalizationJournal = publications.sealRunEvidence('normalization_journal',
        JSON.stringify({version: 'actql-normalization-journal/0.1',
          rule_catalog_cid: token('c'), entries: []}), limits);
      const authoringContext = publications.sealRunEvidence('authoring_context',
        JSON.stringify({version: 'actql-authoring-context/0.1',
          program_definition_cid: JSON.parse(compiled.template.wire).program_definition_cid,
          annotations: []}), limits);
      const chain = {admission: compiled.admission, runDefinition: definition,
        invocation: issued.invocation, observation: issued.observation,
        definitions: [resultDefinition], artifacts: [artifact], manifest};
      const provenance = {normalizationJournal, bindings: [], sourceEvidence: [],
        modelEvidence: [], barrierAttemptReceiptCids: [], contentGenerations: [generation]};
      assert.throws(() => publications.issueEffectFreeRunReceipt(chain,
        {...provenance, contentGenerations: [{}]}, limits), /Foreign Client Content generation/u);
      assert.throws(() => publications.issueEffectFreeRunReceipt(chain,
        {...provenance, contentGenerations: []}, limits), {code: 'MoonBitHostFailure'});
      const receipt = publications.issueEffectFreeRunReceipt(chain, provenance, limits);
      assert.deepEqual(JSON.parse(receipt.wire).external_observation_evidence,
        [{evidence_cid: evidence.identity, kind: 'content_generation'}]);
      const snapshot = publications.admitCapturedResultSnapshot(resultDefinition, artifact,
        rowsWire, ['name', 'content', 'media_type', 'size_bytes', 'row_count'], limits);
      const capturedEvidence = {snapshots: [snapshot], pendingSourceStateAdvances: [],
        authoringContext, modelEvidence: [], contentGenerations: [generation]};
      await assert.rejects(publications.issueEffectFreeCapturedRun({...chain, receipt},
        {...capturedEvidence, contentGenerations: [{}]}, limits),
      /Foreign Client Content generation/u);
      const captured = await publications.issueEffectFreeCapturedRun({...chain, receipt},
        capturedEvidence, limits);
      capturedRunForStorage = captured;
      const proofs = JSON.parse(captured.wire).effect_context.content_generations;
      assert.equal(proofs.length, 1);
      assert.deepEqual(Object.keys(proofs[0]), ['content_evidence', 'content_generation',
        'content_input_artifact', 'content_reference', 'invocation_template']);
      assert.deepEqual(proofs[0].content_generation, body);
      assert.deepEqual(proofs[0].content_input_artifact, inputBody);
      assert.deepEqual(proofs[0].content_reference, row.content);
      assert.deepEqual(proofs[0].content_evidence, derivationBody);
      assert.deepEqual(proofs[0].invocation_template, JSON.parse(compiled.template.wire));
      assert.equal(publications.capturedContentGenerationCount(captured), 1);
      const storage = publications.capturedContentGenerationStorage(captured, definition, token('1'), 0);
      assert.equal(storage.holdingCid, hash(JSON.stringify({node_id: body.node_id,
        role: 'content_bytes', run_definition_cid: definition.identity,
        store_authority_cid: token('1'), version: 'actql-content-private-holding/0.1'})));
      assert.equal(storage.holdingCid, holding.holding_cid);
      assert.equal(storage.manifestCid, row.content.content_ref_cid);
      assert.equal(storage.contentCid, hash(expectedBytes));
      assert.equal(storage.byteCount, BigInt(Buffer.byteLength(expectedBytes)));
      assert.deepEqual(storage.bindings, retained.bindings);
      assert.deepEqual(await value.store.confirmCapturedContentHoldings(captured, definition),
        [holding.holding_cid, ...retained.bindings.map(item => item.holdingCid)].sort());
      assert.throws(() => publications.capturedContentGenerationStorage(captured, definition,
        token('9'), 0), /storage binding unavailable/u);
      assert.throws(() => publications.capturedContentGenerationStorage(captured, definition,
        token('1'), 1), /storage binding unavailable/u);
      await assert.rejects(value.store.confirmCapturedContentHoldings(captured, resultDefinition),
        /storage binding unavailable/u);
      // The real completed publisher owns contract issuance, prepared Result
      // adoption and the atomic index. This adapter only exports the original
      // already-completed port; it is not installed Run dispatch acceptance.
      const execution = serializationPublicationExecution({moon, core: runtime,
        compiled, preparedProgram: value.prepared, generation, contractLimits: limits,
        remainingWork: () => 10000 - used,
        chargeWork: delta => { used += delta; return used <= 10000; }, quantum: 7});
      assert.deepEqual(execution.resultInventory.map(item => [item.name, item.task,
        item.definitionContract.identity]), [['file', 0, resultDefinition.identity]]);
      assert.throws(() => serializationPublicationExecution({moon, core: runtime,
        compiled: anotherRun, preparedProgram: value.prepared, generation, contractLimits: limits,
        remainingWork: () => 10000, chargeWork: () => true}), /generation unavailable/u);
      let indexResponsesLost = 0;
      const uncertainStore = {...value.store, async commitIndex(...args) {
        const result = await value.store.commitIndex(...args);
        if (indexResponsesLost === 0) {
          indexResponsesLost++;
          throw new Error('ContentPublicationCommitResponseLost');
        }
        return result;
      }};
      const options = {moon, control: publications, preparedProgram: value.prepared,
        admitted: {...compiled, compiled, runDefinition: definition,
          createdAt: '2026-10-09T00:00:00.000Z'}, generation, authorityScopeCid: token('6'),
        namespaceId: 'local', storeAuthorityCid: token('1'), outputLimits: resultLimits,
        now: () => '2026-10-09T00:00:03.000Z'};
      const publicationPlan = serializationTaskPublicationPlan(options);
      assert.equal(publicationPlan.invocation.identity, issued.invocation.identity);
      assert.equal(publicationPlan.observation.identity, issued.observation.identity);
      assert.equal(publicationPlan.receiptEvidence.contentGenerations[0], generation);
      assert.equal(publicationPlan.captureEvidence.contentGenerations[0], generation);
      assert.deepEqual(publicationPlan.results[0].evidenceContext.inputRelationCids,
        [inputBody.logical_relation_cid]);
      assert.equal(publicationPlan.results[0].evidenceContext.effectiveDataPolicyCid, policy.cid);
      assert.throws(() => serializationTaskPublicationPlan({...options,
        storeAuthorityCid: token('9')}), /recovery binding unavailable/u);
      const resultRequest = {outputLimits: resultLimits, contractLimits: limits,
        runDefinition: definition, invocation: publicationPlan.invocation,
        ...publicationPlan.results[0]};
      const beforeDeniedView = value.store.status();
      const deniedView = serializationPublicationExecution({moon, core: runtime,
        compiled, preparedProgram: value.prepared, generation, contractLimits: limits,
        remainingWork: () => 0, chargeWork: () => assert.fail('no work was granted')});
      await assert.rejects(deniedView.storePublicationResult(0, value.store, resultRequest),
        {code: 'GeneratedContentWorkLimit'});
      const aborted = new AbortController();
      aborted.abort(new Error('ContentPublicationCancelled'));
      await assert.rejects(execution.storePublicationResult(0, value.store, resultRequest,
        aborted.signal), /ContentPublicationCancelled/u);
      let refusedWork = 0;
      const refusedCharge = serializationPublicationExecution({moon, core: runtime,
        compiled, preparedProgram: value.prepared, generation, contractLimits: limits,
        remainingWork: () => 1000, quantum: 1,
        chargeWork(delta) { refusedWork += delta; return false; }});
      await assert.rejects(refusedCharge.storePublicationResult(0, value.store, resultRequest),
        {code: 'GeneratedContentWorkLimit'});
      assert.equal(refusedWork, 1, 'the first granted mapping step is retained on refusal');
      let failedViewWork = 0;
      const shortMapper = serializationPublicationExecution({moon, core: runtime,
        compiled, preparedProgram: value.prepared, generation, contractLimits: limits,
        remainingWork: () => 1000, quantum: 64,
        chargeWork(delta) { failedViewWork += delta; return true; }});
      await assert.rejects(shortMapper.storePublicationResult(0, value.store,
        {...resultRequest, outputLimits: {...resultLimits, maxResultMappingWork: 5}}),
      {code: 'GeneratedContentResultFailed'});
      // The existing Result schema uses canonical field order: content first,
      // not the authored projection's name first. One initial search frame,
      // name/content mismatch frame, then seven content spelling/binding frames
      // execute. The last frame refuses binding but still counts its work.
      assert.equal(failedViewWork, 1 + 1 + 'content'.length);
      let failedExportWork = 0;
      let exportPolls = 0;
      const boundedExportCore = {...runtime, outputExportControl: {
        ...runtime.outputExportControl,
        next() { assert.fail('Content publication must not use blocking export'); },
        advance(handle, quantum) {
          exportPolls++;
          const progress = runtime.outputExportControl.advance(handle, quantum);
          assert.ok(progress.work <= quantum);
          return progress;
        },
      }};
      const shortExport = serializationPublicationExecution({moon, core: boundedExportCore,
        compiled, preparedProgram: value.prepared, generation, contractLimits: limits,
        remainingWork: () => 1000, quantum: 1,
        chargeWork(delta) { failedExportWork += delta; return true; }});
      await assert.rejects(shortExport.storePublicationResult(0, value.store,
        {...resultRequest, outputLimits: {...resultLimits, maxValueWork: 1}}),
      error => {
        assert.equal(error.code, 'DurableResultPayloadFailed');
        assert.equal(error.cause?.code, 'GeneratedContentResultFailed');
        assert.equal(error.cleanupPending, false);
        return true;
      });
      assert.ok(exportPolls > 0, 'the actual export, not the projection, refuses');
      assert.ok(failedExportWork > failedViewWork, 'failed export work reaches the same Run allowance');
      assert.equal(value.store.status().storedBytes, beforeDeniedView.storedBytes);
      assert.equal(value.store.status().reservedBytes, beforeDeniedView.reservedBytes);
      assert.equal(control.completedOutput(compiled, generation), output,
        'cancelling a Result view does not revoke the original byte custody');
      const assembled = await publishCompletedEffectFreeRun({...publicationPlan,
        execution, store: uncertainStore, control: publications, signal: undefined});
      assert.equal(indexResponsesLost, 1);
      assert.equal(assembled.publication.state, 'succeeded');
      publishedRunKey = {namespaceId: 'local', authorityScopeCid: token('6'),
        runDefinitionCid: definition.identity};
      publishedEvidence = assembled.evidence;
      assert.equal(await value.store.validateCommittedEvidence(assembled.publication.index,
        publishedEvidence), true);
    } finally {
      if (exported) runtime.outputExportControl.cancel(exported);
      control.resultCancel(selected);
    }
    const anotherDefinition = publications.defineCheckedClientCompiledRun(compiled,
      {namespaceId: 'local', runId: 'another-content-run',
        createdAt: '2026-10-09T00:00:00.000Z', validUntil: runPolicy.expiresAt});
    assert.throws(() => publications.issueCheckedClientSerializationInvocation(compiled,
      anotherDefinition, generation, {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 100}),
    /RunHostContentInvocationRejected/u);
    // Reopening the actual Store verifies disk custody, not separate-process
    // Run recovery or a reissued ContentRef. The public dispatcher must still
    // adopt the original immutable inventory and validate current authority.
    readingStore = await value.reopenStore();
    for (const binding of retained.bindings) {
      const stored = await readingStore.readPrivateEvidence(binding.name,
        binding.semanticCid, binding.holdingCid);
      assert.equal(stored.toString('utf8'), binding.wire);
      assert.ok(await readingStore.confirmPrivateEvidence(binding));
    }
    const chunks = [];
    await readingStore.consumePhysicalHolding(holding.holding_cid, 0,
      chunk => chunks.push(Buffer.from(chunk)));
    assert.equal(Buffer.concat(chunks).toString(), expectedBytes);
    assert.deepEqual(await readingStore.confirmCapturedContentHoldings(capturedRunForStorage, definition),
      [holding.holding_cid, ...retained.bindings.map(item => item.holdingCid)].sort());
    const committed = await readingStore.confirmCommittedIndex(publishedRunKey);
    assert.ok(committed);
    const committedIndex = await readingStore.readPublicationContract(
      committed.public_index_entry_cid, 'public_index_entry');
    assert.equal(await readingStore.validateCommittedEvidence(committedIndex,
      publishedEvidence), true);
    // Retiring one original proof cannot be hidden by its copy in the
    // CapturedRun; the byte holding alone is not a complete saved inventory.
    const retiredProof = await readingStore.retirePhysicalHolding(retained.bindings[0].holdingCid);
    assert.equal(retiredProof.deleted, true);
    await assert.rejects(readingStore.confirmCapturedContentHoldings(capturedRunForStorage, definition),
      /PublicationContentEvidenceUnavailable/u);
    live = false;
    await assert.rejects(retained.retry(), /recovery binding unavailable/u);
    assert.equal(privateCommitCalls, 4, 'revoked generation cannot restart Store writes');
    assert.throws(() => control.completedOutput(compiled, generation), /generation unavailable/u);
    assert.throws(() => publications.issueCheckedClientSerializationInvocation(compiled,
      definition, generation, {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 100}),
    /RunHostContentInvocationRejected/u);
    assert.ok(readingStore.status().storedBytes > Buffer.byteLength(expectedBytes));
  } finally {
    if (publishedRunKey !== undefined) {
      const retired = await readingStore.retireCommittedPublicationMetadata(publishedRunKey,
        '2026-10-09T00:00:04.000Z');
      assert.equal(retired.deleted, true);
    }
    for (const binding of retained?.bindings ?? []) {
      await readingStore.retirePhysicalHolding(binding.holdingCid);
    }
    await readingStore.retirePhysicalHolding(holding.holding_cid);
  }
  assert.equal(readingStore.status().storedBytes, 0);
});

test('Content transport writes the actual filtered completion with exact bytes and work', async t => {
  const invariantWork = new Map();
  for (const {quantum, format, empty, expected} of [
    ...[1, 7, 64].map(quantum => ({quantum, format: 'jsonl', empty: false,
      expected: '{"id":2,"p":null}\n{"id":1,"p":7}\n'})),
    {quantum: 7, format: 'jsonl', empty: true, expected: ''},
    {quantum: 7, format: 'csv', empty: false, expected: 'id,p\r\n2,\\N\r\n1,7\r\n'},
    {quantum: 7, format: 'csv', empty: true, expected: 'id,p\r\n'},
  ]) {
    await t.test(`${format} ${empty ? 'empty' : 'filtered'} quantum ${quantum}`, async t => {
      const value = await fixture(t, {format, empty});
      const rowCount = empty ? 0 : 2;
      const mediaType = format === 'csv' ? 'text/csv' : 'application/x-ndjson';
      assert.equal(control.inputRows(value.input), rowCount);
      let used = 0;
      const completed = await writeGeneratedContent({...value, control, quantum,
        remainingWork: () => 10000 - used,
        chargeWork: delta => { used += delta; return used <= 10000; }});
      assert.deepEqual(completed, {name: `selected.${format}`, mediaType,
        sizeBytes: Buffer.byteLength(expected), rowCount, contentCid: hash(expected)});
      assert.ok(used > 0);
      const workCase = `${format}/${empty}`;
      if (!invariantWork.has(workCase)) invariantWork.set(workCase, used);
      else assert.equal(used, invariantWork.get(workCase));
      const binding = {content_store_id: 'fixture', content_store_cid: token('1'),
        workspace_scope_cid: token('2'), storage_scope: 'workspace', retention_class: 'fixture',
        availability_evidence_cid: token('3'), effective_data_policy_cid: token('4'),
        data_classification: 'internal', issuer_contract_cid: token('5'), capture_authority_cid: token('6')};
      const candidate = control.candidate(value.encoder, binding, referenceLimits);
      const expectedContent = expectedReference(expected, mediaType, workCase);
      assert.equal(control.inspect(candidate).identity, expectedContent.content_ref_cid);
      assert.deepEqual(JSON.parse(control.inspect(candidate).wire), expectedContent);
      const physical = await value.writer.seal(completed.contentCid);
      const holding = {version: 'actql-local-physical-holding/0.1', namespace: 'content',
        holding_cid: hash(`original Content transport ${format} ${empty} ${quantum}`),
        manifest_cid: control.inspect(candidate).identity,
        objects: [{cid: physical.cid, byte_count: physical.bytes}]};
      await value.store.commitPhysicalHolding(holding, [physical.prepared]);
      try {
        const content = await issueStoredGeneratedContent({store: value.store, control, candidate,
          holdingCid: holding.holding_cid, workspaceScopeCid: token('2'),
          effectiveDataPolicyCid: token('4'), available: () => true, authorize: () => true,
          limits: referenceLimits});
        assert.ok(content);
        let outputLive = true;
        const output = control.output(value.input, candidate, content, () => outputLive, outputLimits);
        assert.equal(control.outputAvailable(output), true);
        const row = JSON.parse(control.outputRowWire(output, referenceLimits));
        assert.deepEqual(Object.keys(row), ['content', 'media_type', 'name', 'row_count', 'size_bytes']);
        assert.deepEqual(row, {content: expectedContent,
          media_type: mediaType, name: `selected.${format}`,
          row_count: rowCount, size_bytes: Buffer.byteLength(expected)});
        if (format === 'jsonl' && !empty && quantum === 1) {
          const foreign = await fixture(t);
          await writeGeneratedContent({...foreign, control,
            remainingWork: () => 10000, chargeWork: () => true});
          const equalCandidate = control.candidate(foreign.encoder, binding, referenceLimits);
          assert.equal(control.inspect(equalCandidate).identity, control.inspect(candidate).identity);
          assert.throws(() => control.output(value.input, equalCandidate, content,
            () => true, outputLimits), {code: 'MoonBitHostFailure', causeCode: 'GenerationIncomplete'},
          'equal bytes and Ref CID cannot substitute another generation occurrence');
        }
        assert.throws(() => control.resultStart(preparation(), 0, output, resultLimits),
          {code: 'MoonBitHostFailure'}, 'equal Program text cannot replace the exact producer owner');
        const selected = control.resultStart(value.prepared, 0, output, resultLimits);
        let resultWork = 0;
        try {
          let done = false;
          for (let polls = 0; polls < 10000; polls++) {
            const next = control.resultAdvance(selected, quantum);
            assert.ok(next.work >= 0 && next.work <= quantum);
            resultWork += next.work;
            if (next.ready) { done = true; break; }
          }
          assert.equal(done, true);
          assert.ok(resultWork > 0);
          const exported = control.resultFinish(selected);
          try {
            const chunks = [];
            for (let polls = 0; polls < 10000; polls++) {
              const next = runtime.outputExportControl.next(exported);
              if (next === undefined) break;
              chunks.push(next);
            }
            chunks.push(runtime.outputExportControl.finish(exported));
            const published = JSON.parse(chunks.join(''));
            assert.deepEqual(published, [row]);
            assert.deepEqual(runtime.outputExportControl.identity(exported).resultFields,
              ['name', 'content', 'media_type', 'size_bytes', 'row_count']);
          } finally { runtime.outputExportControl.cancel(exported); }
        } finally { control.resultCancel(selected); }
        assert.throws(() => control.output(value.input, candidate, {}, () => true, outputLimits),
          /Foreign issued Content/u);
        assert.throws(() => control.output(value.input, candidate, content, () => false, outputLimits),
          {code: 'MoonBitHostFailure'});
        assert.throws(() => control.output(value.input, candidate, content, () => true,
          {...outputLimits, maxWork: 1}), {code: 'MoonBitHostFailure'});
        // A completed generated reference no longer borrows input rows. Its
        // own existing output/byte lifetime still revokes all subsequent reads.
        control.prefixCancel(value.prefix);
        assert.equal(control.prefixCleanup(value.prefix), true);
        assert.equal(control.outputAvailable(output), true);
        outputLive = false;
        assert.equal(control.outputAvailable(output), false);
        assert.throws(() => control.outputRowWire(output, referenceLimits),
          {code: 'MoonBitHostFailure'});
        const pieces = [];
        await value.store.consumePhysicalHolding(holding.holding_cid, 0,
          bytes => pieces.push(Buffer.from(bytes)));
        assert.equal(Buffer.concat(pieces).toString('utf8'), expected);
      } finally { await value.store.retirePhysicalHolding(holding.holding_cid); }
      assert.equal(value.store.status().storedBytes, 0);
    });
  }
});

test('Content input identity work shortage and cancellation retain the original input', async t => {
  const limits = {...resultLimits, maxRows: 3};
  const identityLimits = {maxWireBytes: 16384, maxNodes: 256, maxDepth: 16};
  for (const quantum of [1, 7, 64]) {
    const value = await fixture(t);
    let used = 0;
    // The independent exact bound above is 29. One short cannot issue the
    // input Artifact, and consumed work remains charged after stopping.
    await assert.rejects(identifyGeneratedContentInput({control, compiled: {},
      input: value.input, limits, identityLimits, maxWorkspaceSlots: 10000,
      quantum, remainingWork: () => 28 - used,
      chargeWork: delta => { used += delta; return used <= 28; }}),
    {code: 'GeneratedContentWorkLimit'});
    assert.equal(used, 28);
    assert.equal(control.inputRows(value.input), 2);
    const abort = new AbortController();
    used = 0;
    await assert.rejects(identifyGeneratedContentInput({control, compiled: {},
      input: value.input, limits, identityLimits, maxWorkspaceSlots: 10000,
      quantum: 1, signal: abort.signal, remainingWork: () => 10000 - used,
      chargeWork: delta => { used += delta; abort.abort(); return true; }}),
    {name: 'AbortError'});
    assert.equal(used, 1);
    assert.equal(control.inputRows(value.input), 2);
    const generated = await writeGeneratedContent({...value, control,
      remainingWork: () => 10000 - used,
      chargeWork: delta => { used += delta; return used <= 10000; }});
    assert.equal(generated.contentCid, hash('{"id":2,"p":null}\n{"id":1,"p":7}\n'));
  }
});

test('Content transport requires the actual typed empty completion', async t => {
  const value = await fixture(t, {empty: true});
  assert.equal(control.inputRows(value.input), 0);
  let used = 0;
  const completed = await writeGeneratedContent({...value, control,
    remainingWork: () => 100 - used, chargeWork: delta => { used += delta; return true; }});
  assert.equal(used, 1);
  assert.equal(completed.rowCount, 0);
  assert.equal(completed.sizeBytes, 0);
  assert.equal(completed.contentCid, hash(''));
  await value.writer.cancel();
  assert.equal(value.store.status().reservedBytes, 0);
  assert.throws(() => control.inputRows({}), /Foreign Content input/u);
});

test('Content transport retains the original sink reservation after cancellation', async t => {
  const value = await fixture(t);
  const abort = new AbortController();
  let used = 0;
  let appended = 0;
  const writer = {async append(piece) {
    await value.writer.append(piece);
    appended += Buffer.byteLength(piece);
    abort.abort(new Error('cancel after a real sink append'));
  }};
  await assert.rejects(writeGeneratedContent({...value, writer, control,
    remainingWork: () => 10000 - used,
    chargeWork: delta => { used += delta; return true; }, signal: abort.signal, quantum: 1}),
  /cancel after a real sink append/u);
  assert.ok(used > 0);
  assert.ok(appended > 0);
  assert.equal(value.store.status().reservedBytes, 128);
  assert.throws(() => control.finish(value.encoder), {code: 'MoonBitHostFailure'});
  await value.writer.cancel();
  assert.equal(value.store.status().reservedBytes, 0);
});

test('Content transport refuses an exhausted allowance without refunding work', async t => {
  const value = await fixture(t);
  let used = 0;
  await assert.rejects(writeGeneratedContent({...value, control, quantum: 64,
    remainingWork: () => 2 - used,
    chargeWork: delta => { used += delta; return used <= 2; }}),
  {code: 'GeneratedContentWorkLimit'});
  assert.equal(used, 2);
  assert.equal(value.store.status().reservedBytes, 128);
  assert.throws(() => control.finish(value.encoder), {code: 'MoonBitHostFailure'});
  await value.writer.cancel();
  assert.equal(value.store.status().reservedBytes, 0);
});

test('Content transport charges a failed encoder poll before refusing completion', async t => {
  const value = await fixture(t, {generationLimits: {...generationLimits, maxBytes: 2}});
  let used = 0;
  await assert.rejects(writeGeneratedContent({...value, control, quantum: 64,
    remainingWork: () => 10000 - used,
    chargeWork: delta => { used += delta; return true; }}),
  {code: 'GeneratedContentEncodingFailed'});
  assert.ok(used > 0, 'the failing poll itself reports consumed work');
  assert.equal(value.store.status().reservedBytes, 128);
  assert.throws(() => control.finish(value.encoder), {code: 'MoonBitHostFailure'});
  await value.writer.cancel();
  assert.equal(value.store.status().reservedBytes, 0);
});

test('Content sink failure retains capacity through failed cleanup and exact retry', async t => {
  let failCleanup = false;
  const value = await fixture(t, {durability: directory => ({
    async syncDirectory(path) {
      if (failCleanup && path === join(directory, 'staging')) {
        failCleanup = false;
        throw Object.assign(new Error('original sink cleanup not durable'), {code: 'EIO'});
      }
      const handle = await open(path, 'r');
      try { await handle.sync(); } finally { await handle.close(); }
    },
  })});
  const originalFailure = new Error('sink failed after actual append');
  let used = 0;
  const writer = {async append(piece) {
    await value.writer.append(piece);
    throw originalFailure;
  }};
  await assert.rejects(writeGeneratedContent({...value, writer, control, quantum: 7,
    remainingWork: () => 10000 - used,
    chargeWork: delta => { used += delta; return true; }}), error => error === originalFailure);
  assert.ok(used > 0);
  assert.ok(value.writer.status().bytes > 0);
  assert.equal(value.store.status().reservedBytes, 128);
  assert.throws(() => control.finish(value.encoder), {code: 'MoonBitHostFailure'});
  failCleanup = true;
  await assert.rejects(value.writer.cancel(), {code: 'EIO'});
  assert.equal(value.writer.status().cleanupPending, true);
  assert.equal(value.writer.status().reservationHeld, true);
  assert.equal(value.store.status().reservedBytes, 128);
  assert.equal(await value.writer.cancel(), true);
  assert.equal(value.writer.status().cleanupPending, false);
  assert.equal(value.store.status().reservedBytes, 0);
  assert.equal(await value.writer.cancel(), false);
});

test('Content prefix refuses earlier ports instead of pruning authored work', () => {
  const prepared = preparation({detour: true});
  assert.throws(() => control.prefix(prepared, 0, 3, bodies, prefixLimits),
    /Content prefix unavailable/u);
  assert.throws(() => control.prefix(prepared, 0, 3, bodies,
    {...prefixLimits, maxWork: 2147483648}), /Invalid Content prefix limits/u);
});

test('actual Content prefix reserves the Run ledger before start and holds it until cleanup', async t => {
  const value = await fixture(t);
  const {capacity, ledger} = value;
  assert.ok(capacity.retainedBytes > 0n && capacity.executionBytes > 0n);
  const usage = () => moon.clientProgramMultiCapturedLedgerUsage(ledger);
  assert.equal(ledgerUsageSnapshot(usage()).reservedRetentionBytes, capacity.retainedBytes,
    'Completed input remains reserved while serialization borrows it');
  for (const [retained, execution] of [
    [capacity.retainedBytes - 1n, capacity.executionBytes],
    [capacity.retainedBytes, capacity.executionBytes - 1n],
  ]) {
    const short = checked(moon.clientProgramAcquisitionLedger(1, 0, 0n,
      retained, execution, 0));
    assert.throws(() => control.prefix(value.prepared, 0, 2, bodies, prefixLimits, short),
      {code: 'MoonBitHostFailure'});
    assert.equal(ledgerUsageSnapshot(moon.clientProgramMultiCapturedLedgerUsage(short)).attempts, 0n,
      'Rejected reservation must not start or consume an attempt');
  }
  assert.throws(() => control.prefix(value.prepared, 0, 2, bodies, prefixLimits),
    /requires the Run ledger/u);
  assert.equal(control.prefixCleanup(value.prefix), true);
  assert.equal(ledgerUsageSnapshot(usage()).reservedRetentionBytes, 0n);
  assert.equal(ledgerUsageSnapshot(usage()).reservedExecutionBytes, 0n);
  assert.equal(control.prefixCleanup(value.prefix), true);
  assert.equal(control.prefixAdvance(value.prefix, 1).output, undefined);
  assert.equal(control.prefixAdvance(value.prefix, 1).work, 0n);
});
