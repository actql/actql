import test from 'node:test';
import assert from 'node:assert/strict';
import {
  chmod,
  mkdir,
  mkdtemp,
  open,
  readdir,
  readFile,
  rm,
  unlink,
  writeFile,
} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {spawn} from 'node:child_process';
import {once} from 'node:events';
import {createPublicationContractControlFixture} from
  '../host-common/publication-contract-control.fixture.mjs';
import {openLocalPublicationStore} from './publication-store.mjs';

const contractControl = createPublicationContractControlFixture();
const limits = Object.freeze({
  maxWireBytes: 64 * 1024,
  maxNodes: 4096,
  maxDepth: 64,
});
const seal = (name, value) => JSON.parse(
  contractControl.seal(name, JSON.stringify(value), limits).wire,
);
const wire = value => JSON.stringify(value);

const digest = value => `sha256:${createHash('sha256')
  .update(value).digest('hex')}`;
const resultSchemaWire =
  '{"answer":{"nullable":false,"type":"string"}}';
const cids = Object.freeze({
  authority: digest('authority'),
  scope: digest('scope'),
  run: digest('run'),
  template: digest('template'),
  observations: digest('observations'),
  policy: digest('policy'),
  target: digest('target'),
  result: digest('result'),
  schema: digest(resultSchemaWire),
  manifest: digest('manifest'),
  receipt: digest('receipt'),
  captured: digest('captured'),
  fence: digest('fence'),
});
const code = expected => error => error?.code === expected;

async function runStoreChild(source) {
  const child = spawn(process.execPath, [
    '--input-type=module', '--eval', source,
  ], {stdio: ['ignore', 'pipe', 'pipe']});
  const stdout = [];
  const stderr = [];
  child.stdout.on('data', chunk => stdout.push(chunk));
  child.stderr.on('data', chunk => stderr.push(chunk));
  const [exitCode, signal] = await once(child, 'exit');
  return Object.freeze({
    exitCode,
    signal,
    stdout: Buffer.concat(stdout).toString('utf8'),
    stderr: Buffer.concat(stderr).toString('utf8'),
  });
}

async function fixture(t, options = {}) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-publication-store-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const configuration = {
    directory,
    storeAuthorityCid: cids.authority,
    capacityBytes: 1024 * 1024,
    maxObjectBytes: 64 * 1024,
    maxObjects: 100,
    maxContractNodes: limits.maxNodes,
    maxContractDepth: limits.maxDepth,
    ...options,
  };
  const store = await openLocalPublicationStore(configuration, contractControl);
  t.after(async () => { await store.close(); });
  return {
    directory,
    configuration,
    store,
  };
}

test('unmarked and prior-format Stores are refused without changing files',
  async t => {
    const parent = await mkdtemp(join(tmpdir(), 'actql-store-format-'));
    t.after(() => rm(parent, {recursive: true, force: true}));
    const configuration = directory => ({
      directory, storeAuthorityCid: cids.authority,
      capacityBytes: 1024 * 1024, maxObjectBytes: 64 * 1024,
      maxObjects: 100, maxContractNodes: limits.maxNodes,
      maxContractDepth: limits.maxDepth,
    });
    for (const [name, entry, content, expected] of [
      ['prior', 'store.json', JSON.stringify({
        version: 'actql-local-publication-store/0.1',
        store_authority_cid: cids.authority,
      }), 'LegacyPublicationStoreFormat'],
      ['unmarked', 'other-file', 'unrecognized-content',
        'UnknownPublicationStoreFormat'],
    ]) {
      const directory = join(parent, name);
      await mkdir(directory);
      await writeFile(join(directory, entry), content);
      const original = await readFile(join(directory, entry));
      const names = await readdir(directory);
      await assert.rejects(openLocalPublicationStore(configuration(directory),
        contractControl), error => error.code === expected &&
          error.target === directory);
      assert.deepEqual(await readFile(join(directory, entry)), original);
      assert.deepEqual(await readdir(directory), names);
    }
  });

function invocation() {
  return seal('run_invocation', {
    version: 'actql-run-invocation/0.1',
    invocation_template_cid: cids.template,
    observation_set_cid: cids.observations,
  });
}

function resultDefinition(name = 'answer') {
  const identities = Object.freeze({
    answer:
      'sha256:74499be8f8edb305751bf9d6e4416221358fdf4ebfaf0622fcd6b42a5f7ecfea',
    other:
      'sha256:754a2835ca0889f487152547a046ef480a1adc94d5370f6836acc9f9e98d91da',
  });
  return Object.freeze({
    version: 'actql-result-definition/0.1',
    program_definition_cid: cids.run,
    result_name: name,
    result_definition_cid: identities[name],
  });
}

function publicationRequest(result = resultDefinition(),
  runDefinitionCid = cids.run) {
  return seal('publication_request', {
    version: 'actql-publication-request/0.1',
    namespace_id: 'namespace-a',
    authority_scope_cid: cids.scope,
    run_definition_cid: runDefinitionCid,
    inventory: [{
      result_name: result.result_name,
      result_definition_cid: result.result_definition_cid,
    }],
    publication_policy_cid: cids.policy,
    publication_target_cid: cids.target,
    requested_at: '2026-09-18T00:00:00.000Z',
  });
}

function publicationAttempt(request, attemptId = 'attempt-1') {
  return seal('publication_attempt', {
    version: 'actql-publication-attempt/0.1',
    publication_request_cid: request.publication_request_cid,
    run_definition_cid: request.run_definition_cid,
    attempt_id: attemptId,
    fence_cid: cids.fence,
    started_at: '2026-09-18T00:00:01.000Z',
  });
}

function publicationRecord(attempt, sequence, state, prior, extra = {}) {
  return seal('publication_record', {
    version: 'actql-publication-record/0.1',
    publication_attempt_cid: attempt.publication_attempt_cid,
    ...(prior === undefined ? {} : {
      prior_record_cid: prior.publication_record_cid,
    }),
    sequence,
    state,
    observed_at: `2026-09-18T00:00:0${sequence + 2}.000Z`,
    cleanup_owner_cids: [],
    ...extra,
  });
}

function deliveryFixture(maxUses = 2) {
  const artifactCid = digest('delivery artifact');
  const manifestCid = digest('delivery manifest');
  const grant = seal('result_read_grant', {
    version: 'actql-result-read-grant/0.1',
    namespace_id: 'namespace-a',
    authority_scope_cid: cids.scope,
    principal_id: 'principal-a',
    run_definition_cid: cids.run,
    result_manifest_cid: manifestCid,
    purpose: 'download',
    data_ceiling_cid: cids.policy,
    max_bytes: 4096,
    max_uses: maxUses,
    expires_at: '2026-09-19T00:00:00.000Z',
    authorization_context_cid: cids.scope,
    results: [{
      result_name: 'answer',
      result_artifact_cid: artifactCid,
    }],
    formats: ['json', 'jsonl', 'csv'],
    egress_admission_cid: cids.target,
  });
  return {artifactCid, manifestCid, grant};
}

function manifestReadGrant(maxUses = 2) {
  return seal('manifest_read_grant', {
    version: 'actql-manifest-read-grant/0.1',
    namespace_id: 'namespace-a',
    authority_scope_cid: cids.scope,
    principal_id: 'principal-a',
    run_definition_cid: cids.run,
    result_manifest_cid: cids.manifest,
    purpose: 'inspect',
    data_ceiling_cid: cids.policy,
    max_bytes: 4096,
    max_uses: maxUses,
    expires_at: '2026-09-19T00:00:00.000Z',
    authorization_context_cid: cids.scope,
  });
}

function deliveryAttempt(root, attemptId) {
  return seal('delivery_attempt', {
    version: 'actql-delivery-attempt/0.1',
    attempt_id: attemptId,
    result_read_grant_cid: root.grant.result_read_grant_cid,
    run_definition_cid: cids.run,
    result_manifest_cid: root.manifestCid,
    result_name: 'answer',
    result_artifact_cid: root.artifactCid,
    serialization_contract_cid: cids.captured,
    requested_at: '2026-09-18T01:00:00.000Z',
  });
}

function deliveryRecord(attempt, sequence, state, prior, extra = {}) {
  return seal('delivery_record', {
    version: 'actql-delivery-record/0.1',
    delivery_attempt_cid: attempt.delivery_attempt_cid,
    ...(prior === undefined ? {} : {
      prior_record_cid: prior.delivery_record_cid,
    }),
    sequence,
    state,
    confirmed_byte_count: extra.confirmed_byte_count ?? 0,
    exposure: extra.exposure ?? 'exact',
    observed_at: `2026-09-18T01:00:0${sequence}.000Z`,
    cleanup_owner_cids: [],
    ...extra,
  });
}

function indexEntry(request, attempt, invocationValue, values = {}) {
  return seal('public_index_entry', {
    version: 'actql-public-index-entry/0.1',
    namespace_id: 'namespace-a',
    authority_scope_cid: cids.scope,
    run_definition_cid: request.run_definition_cid,
    invocation_cid: invocationValue.invocation_cid,
    result_manifest_cid: invocationValue.invocation_cid,
    run_receipt_cid: invocationValue.invocation_cid,
    captured_run_cid: invocationValue.invocation_cid,
    durable_result_binding_cids: values.durable_result_binding_cids ??
      [invocationValue.invocation_cid],
    publication_request_cid: request.publication_request_cid,
    publication_attempt_cid: attempt.publication_attempt_cid,
    committed_at: '2026-09-18T00:00:09.000Z',
    ...values,
  });
}

const indexKey = Object.freeze({
  namespaceId: 'namespace-a',
  authorityScopeCid: cids.scope,
  runDefinitionCid: cids.run,
});

const indexKeyFor = request => Object.freeze({
  namespaceId: request.namespace_id,
  authorityScopeCid: request.authority_scope_cid,
  runDefinitionCid: request.run_definition_cid,
});

function physicalCommitEvidence(invocationValue, binding) {
  // This suite isolates filesystem durability and CAS behavior with the
  // independent contract-control fixture. The product integration suite uses
  // distinct real contracts and the MoonBit commit-chain verdict.
  const contract = contractControl.admit(
    'run_invocation', wire(invocationValue), limits,
  );
  return Object.freeze({
    runDefinition: contract,
    invocation: contract,
    definitions: Object.freeze([contract]),
    artifacts: Object.freeze([contract]),
    derivations: Object.freeze([contract]),
    orderings: Object.freeze([contract]),
    retentions: Object.freeze([contract]),
    durableBindings: Object.freeze([binding]),
    manifest: contract,
    receipt: contract,
    capturedRun: contract,
  });
}

async function prepareCommit(
  store,
  request,
  attempt,
  invocationValue,
  retentionPolicyCid = cids.policy,
  preparedSchema = false,
) {
  await store.putPublicationContract(
    'run_invocation', wire(invocationValue),
  );
  const schema = preparedSchema
    ? await store.putPreparedResultSchema(
      resultSchemaWire, cids.schema, request.run_definition_cid,
    )
    : await store.putSemantic(resultSchemaWire, cids.schema);
  const payload = Buffer.from('fixture durable Result payload', 'utf8');
  const writer = store.createPreparedObjectWriter(payload.byteLength);
  await writer.append(payload);
  const physical = await writer.seal(digest(payload));
  const bindingValue = seal('durable_result_binding', {
    version: 'actql-durable-result-binding/0.1',
    run_definition_cid: request.run_definition_cid,
    result_definition_cid: request.inventory[0].result_definition_cid,
    invocation_cid: invocationValue.invocation_cid,
    logical_result_cid: cids.result,
    result_schema_cid: cids.schema,
    ordering_evidence_cid: cids.receipt,
    codec_contract_cid: cids.captured,
    result_fields: ['answer'],
    material_generation_cid: physical.cid,
    store_authority_cid: store.storeAuthorityCid,
    effective_retention_policy_cid: retentionPolicyCid,
    row_count: 1,
    byte_count: physical.bytes,
    physical_sha256: physical.cid.slice('sha256:'.length),
  });
  const binding = contractControl.admit(
    'durable_result_binding', wire(bindingValue), limits,
  );
  await store.putPublicationContract(
    'durable_result_binding', wire(bindingValue),
  );
  const evidence = physicalCommitEvidence(invocationValue, binding);
  await store.putPublicationContract('publication_request', wire(request));
  await store.createAttempt(wire(attempt));
  const preparing = publicationRecord(attempt, 0, 'preparing');
  await store.appendRecord(wire(preparing), {uncommittedConfirmed: false});
  const committing = publicationRecord(attempt, 1, 'committing', preparing);
  await store.appendRecord(wire(committing), {uncommittedConfirmed: false});
  return {
    preparing,
    committing,
    evidence,
    required: [...new Set([
      invocationValue.invocation_cid,
      binding.identity,
      request.publication_request_cid,
      attempt.publication_attempt_cid,
    ])],
    binding,
    prepared: physical.prepared,
    schemaPrepared: schema.prepared,
  };
}

test('bounded object writes are durable, streamed, and physically addressed',
  async t => {
    const {store, configuration} = await fixture(t);
    const writer = store.createObjectWriter(6);
    await writer.append('abc');
    await writer.append(Buffer.from('def'));
    await assert.rejects(writer.append('g'), code('PublicationObjectLimit'));
    const stored = await writer.seal(digest('abcdef'));
    assert.deepEqual(stored, {
      cid: digest('abcdef'), bytes: 6, created: true,
    });
    assert.equal(store.status().reservedBytes, 0);
    const chunks = [];
    await store.consumeObject(stored.cid, chunk => chunks.push(Buffer.from(chunk)));
    assert.equal(Buffer.concat(chunks).toString('utf8'), 'abcdef');
    await store.close();
    const reopened = await openLocalPublicationStore(
      configuration, contractControl,
    );
    t.after(async () => { await reopened.close(); });
    assert.deepEqual(await reopened.verifyObject(stored.cid), {
      cid: stored.cid, bytes: 6,
    });
    assert.equal(reopened.status().storedBytes, 6);
  });

test('private evidence is encrypted, bound, and readable after restart',
  async t => {
    const suppliedKey = Buffer.alloc(32, 7);
    const {store, configuration} = await fixture(t, {
      privateEvidenceKey: suppliedKey,
    });
    const cid = digest('private-effect-preview');
    const holdingCid = digest('private-effect-preview-holding');
    const wire = '{"sensitivity":"private","value":"secret-marker"}';
    suppliedKey.fill(0);
    const prepared = await store.preparePrivateEvidence(
      'effect_preview', wire, cid,
    );
    const stored = await store.verifyObject(prepared.physicalCid);
    assert.equal(stored.bytes, prepared.bytes);
    const ciphertext = [];
    await store.consumeObject(prepared.physicalCid,
      chunk => ciphertext.push(Buffer.from(chunk)));
    assert.equal(Buffer.concat(ciphertext).includes(
      Buffer.from('secret-marker')), false);
    assert.equal(prepared.prepared.status().pending, true);
    await assert.rejects(store.readSemanticBytes(cid),
      code('PublicationContractMissing'));
    await store.commitPhysicalHolding({
      version: 'actql-local-physical-holding/0.1',
      namespace: 'publication-private',
      holding_cid: holdingCid,
      manifest_cid: cid,
      objects: [{cid: prepared.physicalCid, byte_count: prepared.bytes}],
    }, [prepared.prepared]);
    assert.equal(prepared.prepared.status().pending, false);
    assert.deepEqual(await store.readPrivateEvidence(
      'effect_preview', cid, holdingCid,
    ), Buffer.from(wire));
    await assert.rejects(store.readPrivateEvidence(
      'effect_preview', digest('foreign-preview'), holdingCid,
    ), code('PublicationPrivateEvidenceUnavailable'));
    await assert.rejects(store.readPrivateEvidence(
      'review_projection', cid, holdingCid,
    ), code('PublicationPrivateEvidenceCorrupt'));
    await store.close();

    const reopened = await openLocalPublicationStore({
      ...configuration, privateEvidenceKey: Buffer.alloc(32, 7),
    }, contractControl);
    t.after(async () => { await reopened.close(); });
    assert.deepEqual(await reopened.readPrivateEvidence(
      'effect_preview', cid, holdingCid,
    ), Buffer.from(wire));
    const binding = Object.freeze({
      name: 'effect_preview', semanticCid: cid, holdingCid, wire,
    });
    assert.deepEqual(await reopened.confirmPrivateEvidence(binding), {
      version: 'actql-local-physical-holding/0.1',
      namespace: 'publication-private',
      holding_cid: holdingCid,
      manifest_cid: cid,
      objects: [{cid: prepared.physicalCid, byte_count: prepared.bytes}],
    });
    await assert.rejects(reopened.confirmPrivateEvidence({
      ...binding, wire: '{"value":"different"}',
    }), code('PublicationPrivateEvidenceConflict'));
    assert.equal((await reopened.inspectPhysicalHolding(holdingCid))
      .objects[0].cid, prepared.physicalCid);
    await reopened.close();

    let rejectConfirmationSync = false;
    const durability = Object.freeze({
      async syncDirectory(path) {
        if (path === join(configuration.directory, 'physical-holdings') &&
            rejectConfirmationSync) {
          rejectConfirmationSync = false;
          const error = new Error('injected private holding sync failure');
          error.code = 'EIO';
          throw error;
        }
        const handle = await open(path, 'r');
        try { await handle.sync(); }
        finally { await handle.close(); }
      },
    });
    const uncertain = await openLocalPublicationStore({
      ...configuration, privateEvidenceKey: Buffer.alloc(32, 7),
    }, contractControl, durability);
    t.after(async () => { await uncertain.close(); });
    rejectConfirmationSync = true;
    await assert.rejects(uncertain.confirmPrivateEvidence(binding),
      code('EIO'));
    assert.equal((await uncertain.confirmPrivateEvidence(binding))
      .objects[0].cid, prepared.physicalCid);
    await uncertain.close();

    const wrongKey = await openLocalPublicationStore({
      ...configuration, privateEvidenceKey: Buffer.alloc(32, 8),
    }, contractControl);
    t.after(async () => { await wrongKey.close(); });
    await assert.rejects(wrongKey.readPrivateEvidence(
      'effect_preview', cid, holdingCid,
    ),
      code('PublicationPrivateEvidenceCorrupt'));
    await wrongKey.close();
    const withoutKey = await openLocalPublicationStore({
      ...configuration, privateEvidenceKey: undefined,
    }, contractControl);
    t.after(async () => { await withoutKey.close(); });
    await assert.rejects(withoutKey.readPrivateEvidence(
      'effect_preview', cid, holdingCid,
    ), code('PublicationPrivateEvidenceKeyUnavailable'));
    const retired = await withoutKey.retirePhysicalHolding(holdingCid);
    assert.equal(retired.deleted, true);
    assert.equal(withoutKey.status().storedBytes, 0);
  });

test('Local continuation evidence has its own private holding namespace',
  async t => {
    const {store} = await fixture(t, {
      privateEvidenceKey: Buffer.alloc(32, 6),
    });
    const wire = '{"minimum":"local-secret-marker"}';
    const semanticCid = digest(wire);
    const hold = async (name, namespace, holdingCid) => {
      const prepared = await store.preparePrivateEvidence(
        name, wire, semanticCid,
      );
      await store.commitPhysicalHolding({
        version: 'actql-local-physical-holding/0.1',
        namespace,
        holding_cid: holdingCid,
        manifest_cid: semanticCid,
        objects: [{cid: prepared.physicalCid, byte_count: prepared.bytes}],
      }, [prepared.prepared]);
      return prepared;
    };
    const local = digest('local-continuation-holding');
    const prepared = await hold('captured_input',
      'local-continuation-private', local);
    assert.deepEqual(await store.readPrivateEvidence(
      'captured_input', semanticCid, local,
    ), Buffer.from(wire));
    const ciphertext = [];
    await store.consumeObject(prepared.physicalCid,
      chunk => ciphertext.push(Buffer.from(chunk)));
    assert.equal(Buffer.concat(ciphertext).includes(
      Buffer.from('local-secret-marker')), false);
    // A shared holding of the same ciphertext keeps it through one retirement.
    const shared = digest('local-continuation-shared');
    await store.sharePhysicalHolding(local, {
      ...(await store.inspectPhysicalHolding(local)), holding_cid: shared,
    });
    assert.equal((await store.retirePhysicalHolding(local)).deleted, true);
    assert.deepEqual(await store.readPrivateEvidence(
      'captured_input', semanticCid, shared,
    ), Buffer.from(wire));
    // Publication evidence names are not admitted in the Local namespace.
    const foreign = digest('local-continuation-foreign');
    await hold('effect_preview', 'local-continuation-private', foreign);
    await assert.rejects(store.readPrivateEvidence(
      'effect_preview', semanticCid, foreign,
    ), code('PublicationPrivateEvidenceUnavailable'));
    assert.equal((await store.retirePhysicalHolding(foreign)).deleted, true);
    assert.equal((await store.retirePhysicalHolding(shared)).deleted, true);
    assert.equal(store.status().storedBytes, 0);
  });

test('uncommitted private evidence retains a recoverable prepared owner',
  async t => {
    const {store, configuration} = await fixture(t, {
      privateEvidenceKey: Buffer.alloc(32, 5),
    });
    const semanticCid = digest('uncommitted-private-preview');
    const first = await store.preparePrivateEvidence(
      'effect_preview', '{"value":"private"}', semanticCid,
    );
    assert.equal(first.prepared.status().pending, true);
    assert.equal(store.status().storedBytes, first.bytes);
    await assert.rejects(store.readPrivateEvidence(
      'effect_preview', semanticCid, digest('no-holding'),
    ), code('PublicationPrivateEvidenceUnavailable'));
    await first.prepared.release();
    assert.equal(store.status().storedBytes, 0);
    assert.equal(store.status().objectCount, 0);
    await store.close();
    const reopened = await openLocalPublicationStore({
      ...configuration, privateEvidenceKey: Buffer.alloc(32, 5),
    }, contractControl);
    t.after(async () => { await reopened.close(); });
    assert.equal(reopened.status().storedBytes, 0);
  });

test('trusted clock high-water mark survives restart and rejects rollback',
  async t => {
    const {store, configuration} = await fixture(t);
    assert.deepEqual(await store.observeTrustedClock(
      cids.scope, '2026-09-18T01:00:00.000Z',
    ), {
      clockContractCid: cids.scope,
      observedAt: '2026-09-18T01:00:00.000Z',
    });
    await store.close();
    const reopened = await openLocalPublicationStore(
      configuration, contractControl,
    );
    t.after(async () => { await reopened.close(); });
    await assert.rejects(reopened.observeTrustedClock(
      cids.scope, '2026-09-18T00:59:59.999Z',
    ), code('PublicationClockUncertain'));
    assert.deepEqual(await reopened.observeTrustedClock(
      cids.scope, '2026-09-18T01:00:00.000Z',
    ), {
      clockContractCid: cids.scope,
      observedAt: '2026-09-18T01:00:00.000Z',
    });
    assert.deepEqual(await reopened.observeTrustedClock(
      cids.scope, '2026-09-18T01:00:00.001Z',
    ), {
      clockContractCid: cids.scope,
      observedAt: '2026-09-18T01:00:00.001Z',
    });
  });

test('prepared payload holdings reclaim only the final uncommitted owner',
  async t => {
    const {store} = await fixture(t);
    const firstWriter = store.createPreparedObjectWriter(7);
    await firstWriter.append('payload');
    const first = await firstWriter.seal(digest('payload'));
    const secondWriter = store.createPreparedObjectWriter(7);
    await secondWriter.append('payload');
    const second = await secondWriter.seal(digest('payload'));
    assert.equal(first.created, true);
    assert.equal(second.created, false);
    assert.equal(store.status().storedBytes, 7);
    assert.equal(await first.prepared.release(), true);
    assert.equal(first.prepared.status().pending, false);
    assert.equal(second.prepared.status().pending, true);
    assert.equal(store.status().storedBytes, 7);
    assert.equal(await second.prepared.release(), true);
    assert.equal(second.prepared.status().pending, false);
    assert.equal(store.status().storedBytes, 0);
    await assert.rejects(
      store.verifyObject(digest('payload')),
      code('PublicationObjectMissing'),
    );
  });

test('prepared Result schemas retain independent owners and shared bytes',
  async t => {
    const {store} = await fixture(t);
    const first = await store.putPreparedResultSchema(
      resultSchemaWire, cids.schema, cids.run,
    );
    const second = await store.putPreparedResultSchema(
      resultSchemaWire, cids.schema, cids.result,
    );
    assert.equal(store.status().storedBytes,
      Buffer.byteLength(resultSchemaWire));
    assert.equal(store.status().objectCount, 1);
    assert.equal(await first.prepared.release(), true);
    assert.equal(second.prepared.status().pending, true);
    assert.equal(store.status().objectCount, 1);
    assert.equal((await store.readSemanticBytes(cids.schema)).toString(),
      resultSchemaWire);
    assert.equal(await second.prepared.release(), true);
    assert.equal(store.status().storedBytes, 0);
    assert.equal(store.status().objectCount, 0);
    await assert.rejects(store.readSemanticBytes(cids.schema),
      code('PublicationContractMissing'));
  });

test('prepared schema release preserves an existing semantic owner',
  async t => {
    const {store} = await fixture(t);
    await store.putSemantic(resultSchemaWire, cids.schema);
    const prepared = await store.putPreparedResultSchema(
      resultSchemaWire, cids.schema, cids.run,
    );
    assert.equal(prepared.created, false);
    assert.equal(await prepared.prepared.release(), true);
    assert.equal(store.status().objectCount, 1);
    assert.equal((await store.readSemanticBytes(cids.schema)).toString(),
      resultSchemaWire);
  });

test('restart reclaims an unpublished prepared Result schema', async t => {
  const directory = await mkdtemp(join(
    tmpdir(), 'actql-publication-schema-crash-',
  ));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const configuration = {
    directory,
    storeAuthorityCid: cids.authority,
    capacityBytes: 1024 * 1024,
    maxObjectBytes: 64 * 1024,
    maxObjects: 100,
    maxContractNodes: limits.maxNodes,
    maxContractDepth: limits.maxDepth,
  };
  const storeUrl = new URL('./publication-store.mjs', import.meta.url).href;
  const controlUrl = new URL(
    '../host-common/publication-contract-control.fixture.mjs',
    import.meta.url,
  ).href;
  const child = await runStoreChild(`
    import {openLocalPublicationStore} from ${JSON.stringify(storeUrl)};
    import {createPublicationContractControlFixture} from
      ${JSON.stringify(controlUrl)};
    const store = await openLocalPublicationStore(
      ${JSON.stringify(configuration)},
      createPublicationContractControlFixture(),
    );
    await store.putPreparedResultSchema(
      ${JSON.stringify(resultSchemaWire)}, ${JSON.stringify(cids.schema)},
      ${JSON.stringify(cids.run)},
    );
  `);
  assert.equal(child.exitCode, 0, child.stderr);
  const reopened = await openLocalPublicationStore(
    configuration, contractControl,
  );
  t.after(async () => { await reopened.close(); });
  assert.equal(reopened.status().storedBytes, 0);
  assert.equal(reopened.status().objectCount, 0);
  await assert.rejects(reopened.readSemanticBytes(cids.schema),
    code('PublicationContractMissing'));
});

test('restart resumes schema cleanup after alias unlink before sync',
  async t => {
    const directory = await mkdtemp(join(
      tmpdir(), 'actql-publication-schema-unlink-crash-',
    ));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const configuration = {
      directory,
      storeAuthorityCid: cids.authority,
      capacityBytes: 1024 * 1024,
      maxObjectBytes: 64 * 1024,
      maxObjects: 100,
      maxContractNodes: limits.maxNodes,
      maxContractDepth: limits.maxDepth,
    };
    const storeUrl = new URL('./publication-store.mjs', import.meta.url).href;
    const controlUrl = new URL(
      '../host-common/publication-contract-control.fixture.mjs',
      import.meta.url,
    ).href;
    const child = await runStoreChild(`
      import {open} from 'node:fs/promises';
      import {join} from 'node:path';
      import {openLocalPublicationStore} from ${JSON.stringify(storeUrl)};
      import {createPublicationContractControlFixture} from
        ${JSON.stringify(controlUrl)};
      const configuration = ${JSON.stringify(configuration)};
      let armed = false;
      const durability = Object.freeze({async syncDirectory(path) {
        if (armed && path === join(configuration.directory, 'contracts')) {
          process.exit(43);
        }
        const handle = await open(path, 'r');
        try { await handle.sync(); }
        finally { await handle.close(); }
      }});
      const store = await openLocalPublicationStore(
        configuration, createPublicationContractControlFixture(),
        durability,
      );
      const schema = await store.putPreparedResultSchema(
        ${JSON.stringify(resultSchemaWire)}, ${JSON.stringify(cids.schema)},
        ${JSON.stringify(cids.run)},
      );
      armed = true;
      await schema.prepared.release();
    `);
    assert.equal(child.exitCode, 43, child.stderr);
    const reopened = await openLocalPublicationStore(
      configuration, contractControl,
    );
    t.after(async () => { await reopened.close(); });
    assert.equal(reopened.status().storedBytes, 0);
    assert.equal(reopened.status().objectCount, 0);
    await assert.rejects(reopened.readSemanticBytes(cids.schema),
      code('PublicationContractMissing'));
  });

test('prepared schema cleanup retains capacity across sync failure',
  async t => {
    const directory = await mkdtemp(join(
      tmpdir(), 'actql-publication-schema-sync-',
    ));
    t.after(() => rm(directory, {recursive: true, force: true}));
    let failContractSync = false;
    const durability = Object.freeze({
      async syncDirectory(path) {
        if (failContractSync && path === join(directory, 'contracts')) {
          failContractSync = false;
          const error = new Error('injected contract sync failure');
          error.code = 'EIO';
          throw error;
        }
        const handle = await open(path, 'r');
        try { await handle.sync(); }
        finally { await handle.close(); }
      },
    });
    const store = await openLocalPublicationStore({
      directory,
      storeAuthorityCid: cids.authority,
      capacityBytes: 1024,
      maxObjectBytes: 1024,
      maxObjects: 10,
      maxContractNodes: limits.maxNodes,
      maxContractDepth: limits.maxDepth,
    }, contractControl, durability);
    const schema = await store.putPreparedResultSchema(
      resultSchemaWire, cids.schema, cids.run,
    );
    failContractSync = true;
    await assert.rejects(schema.prepared.release(), code('EIO'));
    assert.equal(schema.prepared.status().pending, true);
    assert.equal(store.status().storedBytes,
      Buffer.byteLength(resultSchemaWire));
    await assert.rejects(store.close(),
      code('PublicationStoreCleanupPending'));
    assert.equal((await schema.prepared.retry()).pending, false);
    assert.equal(store.status().storedBytes, 0);
    assert.equal(store.status().objectCount, 0);
    assert.equal(await store.close(), true);
  });

test('schema preparation failure keeps exact retryable cleanup custody',
  async t => {
    const directory = await mkdtemp(join(
      tmpdir(), 'actql-publication-schema-prepare-fault-',
    ));
    t.after(() => rm(directory, {recursive: true, force: true}));
    let failContractSync = false;
    const durability = Object.freeze({
      async syncDirectory(path) {
        if (failContractSync && path === join(directory, 'contracts')) {
          failContractSync = false;
          const error = new Error('injected contract sync failure');
          error.code = 'EIO';
          throw error;
        }
        const handle = await open(path, 'r');
        try { await handle.sync(); }
        finally { await handle.close(); }
      },
    });
    const store = await openLocalPublicationStore({
      directory,
      storeAuthorityCid: cids.authority,
      capacityBytes: 1024,
      maxObjectBytes: 1024,
      maxObjects: 10,
      maxContractNodes: limits.maxNodes,
      maxContractDepth: limits.maxDepth,
    }, contractControl, durability);
    failContractSync = true;
    let failure;
    try {
      await store.putPreparedResultSchema(
        resultSchemaWire, cids.schema, cids.run,
      );
    } catch (error) { failure = error; }
    assert.equal(failure?.cleanupPending, true);
    assert.equal(failure.cleanupHandle.status().pending, true);
    await assert.rejects(store.close(),
      code('PublicationStoreCleanupPending'));
    assert.equal((await failure.cleanupHandle.retry()).pending, false);
    assert.equal(store.status().storedBytes, 0);
    assert.equal(store.status().objectCount, 0);
    assert.equal(await store.close(), true);
  });

test('schema cleanup retry never deletes a replacement allocation',
  async t => {
    const directory = await mkdtemp(join(
      tmpdir(), 'actql-publication-schema-replacement-',
    ));
    t.after(() => rm(directory, {recursive: true, force: true}));
    let failObjectSync = false;
    const durability = Object.freeze({
      async syncDirectory(path) {
        if (failObjectSync && path === join(directory, 'objects')) {
          failObjectSync = false;
          const error = new Error('injected object sync failure');
          error.code = 'EIO';
          throw error;
        }
        const handle = await open(path, 'r');
        try { await handle.sync(); }
        finally { await handle.close(); }
      },
    });
    const store = await openLocalPublicationStore({
      directory,
      storeAuthorityCid: cids.authority,
      capacityBytes: 1024,
      maxObjectBytes: 1024,
      maxObjects: 10,
      maxContractNodes: limits.maxNodes,
      maxContractDepth: limits.maxDepth,
    }, contractControl, durability);
    const old = await store.putPreparedResultSchema(
      resultSchemaWire, cids.schema, cids.run,
    );
    failObjectSync = true;
    await assert.rejects(old.prepared.release(), code('EIO'));
    const replacement = await store.putSemantic(resultSchemaWire, cids.schema);
    assert.equal(replacement.created, true);
    assert.equal((await old.prepared.retry()).pending, false);
    assert.equal(store.status().storedBytes,
      Buffer.byteLength(resultSchemaWire));
    assert.equal(store.status().objectCount, 1);
    assert.equal((await store.readSemanticBytes(cids.schema)).toString(),
      resultSchemaWire);
    assert.equal(await store.close(), true);
  });

test('prepared payload cleanup retains ownership and capacity until retry',
  async t => {
    const {store, directory} = await fixture(t);
    const writer = store.createPreparedObjectWriter(7);
    await writer.append('payload');
    const stored = await writer.seal(digest('payload'));
    const objects = join(directory, 'objects');
    await chmod(objects, 0o500);
    try {
      await assert.rejects(stored.prepared.release());
      assert.equal(stored.prepared.status().pending, true);
      assert.equal(store.status().storedBytes, 7);
      await assert.rejects(
        store.close(),
        code('PublicationStoreCleanupPending'),
      );
    } finally {
      await chmod(objects, 0o700);
    }
    const retried = await stored.prepared.retry();
    assert.equal(retried.pending, false);
    assert.equal(retried.errors.length, 1);
    assert.equal(retried.errors[0].code, 'EACCES');
    assert.equal(store.status().storedBytes, 0);
    assert.equal(await store.close(), true);
  });

test('prepared cleanup resumes directory sync after its exact unlink',
  async t => {
    const directory = await mkdtemp(join(
      tmpdir(), 'actql-publication-cleanup-sync-',
    ));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const objects = join(directory, 'objects');
    let failObjectSync = false;
    let objectSyncs = 0;
    const durability = Object.freeze({
      async syncDirectory(path) {
        if (path === objects) {
          objectSyncs++;
          if (failObjectSync) {
            failObjectSync = false;
            const error = new Error('injected object directory sync failure');
            error.code = 'EIO';
            throw error;
          }
        }
        const handle = await open(path, 'r');
        try { await handle.sync(); }
        finally { await handle.close(); }
      },
    });
    const store = await openLocalPublicationStore({
      directory,
      storeAuthorityCid: cids.authority,
      capacityBytes: 1024,
      maxObjectBytes: 1024,
      maxObjects: 10,
      maxContractNodes: limits.maxNodes,
      maxContractDepth: limits.maxDepth,
    }, contractControl, durability);
    const writer = store.createPreparedObjectWriter(7);
    await writer.append('payload');
    const stored = await writer.seal(digest('payload'));
    const beforeReleaseSyncs = objectSyncs;
    failObjectSync = true;
    await assert.rejects(stored.prepared.release(), code('EIO'));
    assert.equal(stored.prepared.status().pending, true);
    assert.equal(store.status().storedBytes, 7);
    await assert.rejects(
      store.verifyObject(digest('payload')),
      code('PublicationObjectMissing'),
    );
    const replacementWriter = store.createPreparedObjectWriter(7);
    await replacementWriter.append('payload');
    const replacement = await replacementWriter.seal(digest('payload'));
    assert.equal(replacement.created, true);
    assert.equal(store.status().storedBytes, 14);
    const beforeRetrySyncs = objectSyncs;
    const retried = await stored.prepared.retry();
    assert.equal(retried.pending, false);
    assert.equal(objectSyncs, beforeRetrySyncs + 1);
    assert.equal(objectSyncs > beforeReleaseSyncs + 2, true);
    assert.equal(store.status().storedBytes, 7);
    assert.equal(store.status().objectCount, 1);
    assert.equal(await replacement.prepared.release(), true);
    assert.equal(store.status().storedBytes, 0);
    assert.equal(await store.close(), true);
  });

test('seal failure removes its staging alias before reclaiming custody',
  async t => {
    const directory = await mkdtemp(join(
      tmpdir(), 'actql-publication-seal-custody-',
    ));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const objects = join(directory, 'objects');
    let remainingObjectSyncFailures = 0;
    const durability = Object.freeze({
      async syncDirectory(path) {
        if (path === objects && remainingObjectSyncFailures > 0) {
          remainingObjectSyncFailures--;
          const error = new Error('injected object directory sync failure');
          error.code = 'EIO';
          throw error;
        }
        const handle = await open(path, 'r');
        try { await handle.sync(); }
        finally { await handle.close(); }
      },
    });
    const store = await openLocalPublicationStore({
      directory,
      storeAuthorityCid: cids.authority,
      capacityBytes: 1024,
      maxObjectBytes: 1024,
      maxObjects: 10,
      maxContractNodes: limits.maxNodes,
      maxContractDepth: limits.maxDepth,
    }, contractControl, durability);

    const recoveredWriter = store.createPreparedObjectWriter(7);
    await recoveredWriter.append('payload');
    remainingObjectSyncFailures = 1;
    await assert.rejects(
      recoveredWriter.seal(digest('payload')),
      code('EIO'),
    );
    assert.equal(recoveredWriter.status().custodyPending, false);
    assert.equal(recoveredWriter.status().reservationHeld, false);
    assert.equal(store.status().storedBytes, 0);
    assert.deepEqual(await readdir(join(directory, 'staging')), []);
    assert.deepEqual(await readdir(join(directory, 'prepared-custody')), []);
    assert.deepEqual(await readdir(objects), []);

    const retriedWriter = store.createPreparedObjectWriter(7);
    await retriedWriter.append('payload');
    remainingObjectSyncFailures = 2;
    await assert.rejects(
      retriedWriter.seal(digest('payload')),
      code('EIO'),
    );
    assert.equal(retriedWriter.status().custodyPending, true);
    assert.equal(retriedWriter.status().cleanupPending, true);
    assert.equal(retriedWriter.status().reservationHeld, false);
    assert.equal(store.status().storedBytes, 7);
    assert.equal((await readdir(join(
      directory, 'prepared-custody',
    ))).length, 1);
    assert.deepEqual(await readdir(objects), []);
    assert.equal(await retriedWriter.cancel(), true);
    assert.equal(retriedWriter.status().custodyPending, false);
    assert.equal(retriedWriter.status().cleanupPending, false);
    assert.equal(store.status().storedBytes, 0);
    assert.deepEqual(await readdir(join(
      directory, 'prepared-custody',
    )), []);
    assert.equal(await store.close(), true);
  });

test('writer retains capacity and cleanup identity until unlink succeeds',
  async t => {
    const {store, directory} = await fixture(t, {
      capacityBytes: 8,
      maxObjectBytes: 8,
    });
    const staging = join(directory, 'staging');
    const writer = store.createObjectWriter(8);
    await writer.append('retained');
    assert.equal((await readdir(staging)).length, 1);
    await chmod(staging, 0o500);
    try {
      await assert.rejects(writer.seal(digest('retained')));
    } finally {
      await chmod(staging, 0o700);
    }
    assert.deepEqual(store.status(), {
      storedBytes: 8,
      reservedBytes: 8,
      objectCount: 1,
      reservedObjects: 1,
      capacityBytes: 8,
      closed: false,
    });
    assert.equal(writer.status().cleanupPending, true);
    await assert.rejects(store.close(),
      code('PublicationStoreCleanupPending'));
    assert.equal(await writer.cancel(), true);
    assert.equal(writer.status().cleanupPending, false);
    assert.equal(store.status().reservedBytes, 0);
    assert.equal(store.status().reservedObjects, 0);
    assert.deepEqual(await readdir(staging), []);
    assert.deepEqual(await store.verifyObject(digest('retained')), {
      cid: digest('retained'), bytes: 8,
    });
  });

test('concurrent writers share one Store capacity and release exactly once',
  async t => {
    const {store} = await fixture(t, {
      capacityBytes: 10,
      maxObjectBytes: 10,
      maxObjects: 3,
    });
    const first = store.createObjectWriter(6);
    const second = store.createObjectWriter(4);
    assert.equal(store.status().reservedBytes, 10);
    assert.equal(store.status().reservedObjects, 2);
    assert.throws(() => store.createObjectWriter(1),
      code('PublicationStoreCapacity'));
    await assert.rejects(store.close(),
      code('PublicationStoreCleanupPending'));
    await Promise.all([first.append('aaaaaa'), second.append('bbbb')]);
    assert.deepEqual(await first.seal(digest('aaaaaa')), {
      cid: digest('aaaaaa'), bytes: 6, created: true,
    });
    assert.equal(await first.cancel(), false);
    assert.equal(store.status().storedBytes, 6);
    assert.equal(store.status().reservedBytes, 4);
    assert.throws(() => store.createObjectWriter(1),
      code('PublicationStoreCapacity'));
    assert.equal(await second.cancel(), true);
    assert.equal(await second.cancel(), false);
    assert.equal(store.status().reservedBytes, 0);
    const third = store.createObjectWriter(4);
    await third.append('cccc');
    await third.seal(digest('cccc'));
    assert.equal(store.status().storedBytes, 10);
    assert.equal(store.status().reservedBytes, 0);
    assert.equal(store.status().reservedObjects, 0);
    assert.equal(await store.close(), true);
  });

test('writer checks exact byte length before copying caller-owned input',
  async t => {
    const {store} = await fixture(t, {
      capacityBytes: 16,
      maxObjectBytes: 16,
    });
    const writer = store.createObjectWriter(16);
    const oversized = Buffer.alloc(2 * 1024 * 1024, 7);
    const originalFrom = Buffer.from;
    let copied = false;
    Buffer.from = function(value, ...arguments_) {
      if (value === oversized) copied = true;
      return Reflect.apply(originalFrom, Buffer, [value, ...arguments_]);
    };
    try {
      await assert.rejects(writer.append(oversized),
        code('PublicationObjectLimit'));
    } finally {
      Buffer.from = originalFrom;
    }
    assert.equal(copied, false);
    assert.equal(writer.status().bytes, 0);
    assert.equal(writer.status().reservationHeld, true);
    assert.equal(await writer.cancel(), true);

    const snapshot = store.createObjectWriter(3);
    const mutable = new Uint8Array([97, 98, 99]);
    const appended = snapshot.append(mutable);
    mutable.fill(120);
    await appended;
    assert.deepEqual(await snapshot.seal(digest('abc')), {
      cid: digest('abc'), bytes: 3, created: true,
    });
  });

test('one live Store owns the complete directory capacity authority',
  async t => {
    const {store, configuration} = await fixture(t, {
      capacityBytes: 1024,
      maxObjectBytes: 1024,
    });
    await store.putBytes(Buffer.alloc(600));
    await assert.rejects(
      openLocalPublicationStore(configuration, contractControl),
      code('PublicationStoreBusy'),
    );
    await store.close();
    const reopened = await openLocalPublicationStore(
      configuration, contractControl,
    );
    t.after(async () => { await reopened.close(); });
    assert.equal(reopened.status().storedBytes, 600);
    await assert.rejects(reopened.putBytes(Buffer.alloc(600, 1)),
      code('PublicationStoreCapacity'));
  });

test('a dead local Store owner is reclaimed without weakening live exclusion',
  async t => {
    const {store, configuration, directory} = await fixture(t);
    await store.close();
    const owner = join(directory, 'owner');
    await mkdir(owner, {mode: 0o700});
    await writeFile(join(owner, 'owner.json'), JSON.stringify({
      version: 'actql-local-publication-store-owner/0.1',
      pid: 2_147_483_647,
      token: 'dead-owner',
    }));
    const reopened = await openLocalPublicationStore(
      configuration, contractControl,
    );
    t.after(async () => { await reopened.close(); });
    await assert.rejects(
      openLocalPublicationStore(configuration, contractControl),
      code('PublicationStoreBusy'),
    );
  });

test('restart reclaims a prepared payload abandoned by process exit',
  async t => {
    const directory = await mkdtemp(join(
      tmpdir(), 'actql-publication-prepared-crash-',
    ));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const configuration = {
      directory,
      storeAuthorityCid: cids.authority,
      capacityBytes: 1024 * 1024,
      maxObjectBytes: 64 * 1024,
      maxObjects: 100,
      maxContractNodes: limits.maxNodes,
      maxContractDepth: limits.maxDepth,
    };
    const storeUrl = new URL('./publication-store.mjs', import.meta.url).href;
    const controlUrl = new URL(
      '../host-common/publication-contract-control.fixture.mjs',
      import.meta.url,
    ).href;
    const payload = 'prepared payload abandoned by process exit';
    const child = await runStoreChild(`
      import {openLocalPublicationStore} from ${JSON.stringify(storeUrl)};
      import {createPublicationContractControlFixture} from
        ${JSON.stringify(controlUrl)};
      const store = await openLocalPublicationStore(
        ${JSON.stringify(configuration)},
        createPublicationContractControlFixture(),
      );
      const writer = store.createPreparedObjectWriter(
        Buffer.byteLength(${JSON.stringify(payload)}, 'utf8'),
      );
      await writer.append(${JSON.stringify(payload)});
      const sealed = await writer.seal();
      process.stdout.write(sealed.cid);
    `);
    assert.equal(child.exitCode, 0, child.stderr);
    assert.equal(child.signal, null);
    const abandonedCid = child.stdout;
    const store = await openLocalPublicationStore(
      configuration, contractControl,
    );
    t.after(async () => { await store.close(); });
    await assert.rejects(
      store.verifyObject(abandonedCid),
      code('PublicationObjectMissing'),
    );
    assert.equal(store.status().storedBytes, 0);
    assert.equal(store.status().objectCount, 0);
    assert.deepEqual(await readdir(join(directory, 'prepared-custody')), []);
    assert.deepEqual(await readdir(join(directory, 'staging')), []);
  });

test('restart reclaims a semantic object from a pre-link process crash',
  async t => {
    const directory = await mkdtemp(join(
      tmpdir(), 'actql-publication-semantic-crash-',
    ));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const configuration = {
      directory,
      storeAuthorityCid: cids.authority,
      capacityBytes: 1024 * 1024,
      maxObjectBytes: 64 * 1024,
      maxObjects: 100,
      maxContractNodes: limits.maxNodes,
      maxContractDepth: limits.maxDepth,
    };
    const storeUrl = new URL('./publication-store.mjs', import.meta.url).href;
    const controlUrl = new URL(
      '../host-common/publication-contract-control.fixture.mjs',
      import.meta.url,
    ).href;
    const value = invocation();
    const admitted = contractControl.admit(
      'run_invocation', wire(value), limits,
    );
    const physicalCid = digest(admitted.wire);
    const child = await runStoreChild(`
      import {constants} from 'node:fs';
      import {open} from 'node:fs/promises';
      import {join} from 'node:path';
      import {openLocalPublicationStore} from ${JSON.stringify(storeUrl)};
      import {createPublicationContractControlFixture} from
        ${JSON.stringify(controlUrl)};
      const directory = ${JSON.stringify(directory)};
      const durability = Object.freeze({async syncDirectory(path) {
        const handle = await open(path, constants.O_RDONLY);
        try { await handle.sync(); } finally { await handle.close(); }
        if (path === join(directory, 'objects')) process.exit(73);
      }});
      const store = await openLocalPublicationStore(
        ${JSON.stringify(configuration)},
        createPublicationContractControlFixture(),
        durability,
      );
      await store.putPublicationContract(
        'run_invocation', ${JSON.stringify(admitted.wire)},
      );
    `);
    assert.equal(child.exitCode, 73, child.stderr);
    assert.equal(child.signal, null);
    const store = await openLocalPublicationStore(
      configuration, contractControl,
    );
    t.after(async () => { await store.close(); });
    await assert.rejects(
      store.verifyObject(physicalCid),
      code('PublicationObjectMissing'),
    );
    await assert.rejects(
      store.readJsonObject(value.invocation_cid, 'run_invocation'),
      code('PublicationContractMissing'),
    );
    assert.deepEqual(await readdir(join(directory, 'prepared-custody')), []);
    assert.deepEqual(await readdir(join(directory, 'staging')), []);
  });

test('crash custody cannot reclaim a committed shared allocation',
  async t => {
    const directory = await mkdtemp(join(
      tmpdir(), 'actql-publication-shared-custody-crash-',
    ));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const configuration = {
      directory,
      storeAuthorityCid: cids.authority,
      capacityBytes: 1024 * 1024,
      maxObjectBytes: 64 * 1024,
      maxObjects: 100,
      maxContractNodes: limits.maxNodes,
      maxContractDepth: limits.maxDepth,
    };
    const initial = await openLocalPublicationStore(
      configuration, contractControl,
    );
    const invocationValue = invocation();
    const request = publicationRequest(
      resultDefinition(), invocationValue.invocation_cid,
    );
    const attempt = publicationAttempt(request);
    const prepared = await prepareCommit(
      initial, request, attempt, invocationValue,
    );
    const entry = indexEntry(request, attempt, invocationValue, {
      durable_result_binding_cids: [prepared.binding.identity],
    });
    await initial.commitIndex(
      wire(entry), prepared.required, prepared.evidence,
    );
    const materialCid = JSON.parse(
      prepared.binding.wire,
    ).material_generation_cid;
    await initial.close();

    const storeUrl = new URL('./publication-store.mjs', import.meta.url).href;
    const controlUrl = new URL(
      '../host-common/publication-contract-control.fixture.mjs',
      import.meta.url,
    ).href;
    const payload = 'fixture durable Result payload';
    const child = await runStoreChild(`
      import {openLocalPublicationStore} from ${JSON.stringify(storeUrl)};
      import {createPublicationContractControlFixture} from
        ${JSON.stringify(controlUrl)};
      const store = await openLocalPublicationStore(
        ${JSON.stringify(configuration)},
        createPublicationContractControlFixture(),
      );
      const writer = store.createPreparedObjectWriter(
        Buffer.byteLength(${JSON.stringify(payload)}, 'utf8'),
      );
      await writer.append(${JSON.stringify(payload)});
      await writer.seal(${JSON.stringify(materialCid)});
    `);
    assert.equal(child.exitCode, 0, child.stderr);
    assert.equal(child.signal, null);

    const reopened = await openLocalPublicationStore(
      configuration, contractControl,
    );
    t.after(async () => { await reopened.close(); });
    assert.equal((await reopened.verifyObject(materialCid)).cid, materialCid);
    const consumed = [];
    await reopened.consumeCommittedResult(
      indexKeyFor(request),
      request.inventory[0].result_definition_cid,
      () => true,
      chunk => consumed.push(Buffer.from(chunk)),
    );
    assert.equal(Buffer.concat(consumed).toString('utf8'), payload);
    assert.deepEqual(await readdir(join(directory, 'prepared-custody')), []);
  });

test('semantic contract identity remains distinct from physical body digest',
  async t => {
    const {store} = await fixture(t);
    const value = invocation();
    const stored = await store.putPublicationContract(
      'run_invocation', wire(value),
    );
    assert.equal(stored.semanticCid, value.invocation_cid);
    assert.notEqual(stored.physical.cid, stored.semanticCid);
    assert.deepEqual(await store.readJsonObject(
      value.invocation_cid, 'run_invocation',
    ), value);
    await assert.rejects(store.putSemantic(
      wire({...value, observation_set_cid: cids.result}),
      value.invocation_cid,
    ), code('PublicationSemanticIdentityConflict'));
  });

test('Store persists admitted Result Definition wire without reimplementing it',
  async t => {
    const {store} = await fixture(t);
    const definition = resultDefinition();
    const stored = await store.putPublicationContract(
      'result_definition', wire(resultDefinition()),
    );
    assert.equal(stored.semanticCid, definition.result_definition_cid);
    assert.deepEqual(await store.readJsonObject(
      definition.result_definition_cid, 'result_definition',
    ), definition);
  });

test('publication records are append-only and sequence creation is CAS',
  async t => {
    const {store} = await fixture(t);
    const request = publicationRequest();
    const attempt = publicationAttempt(request);
    await store.putPublicationContract('publication_request', wire(request));
    await store.createAttempt(wire(attempt));
    const first = publicationRecord(attempt, 0, 'preparing');
    await store.appendRecord(wire(first), {uncommittedConfirmed: false});
    const committing = publicationRecord(attempt, 1, 'committing', first);
    const cancelled = publicationRecord(attempt, 1, 'cancelled', first);
    const results = await Promise.allSettled([
      store.appendRecord(wire(committing), {uncommittedConfirmed: false}),
      store.appendRecord(wire(cancelled), {uncommittedConfirmed: false}),
    ]);
    assert.equal(results.filter(result => result.status === 'fulfilled').length, 1);
    assert.equal(results.filter(result => result.status === 'rejected').length, 1);
    const latest = await store.latestRecord(attempt.publication_attempt_cid);
    assert.equal(latest.sequence, 1);
    assert.ok(['committing', 'cancelled'].includes(latest.state));
  });

test('delivery attempts and records remain append-only after restart',
  async t => {
    const {store, configuration} = await fixture(t);
    const root = deliveryFixture();
    const attempt = deliveryAttempt(root, 'delivery-1');
    assert.deepEqual(
      await store.createDeliveryAttempt(wire(attempt), wire(root.grant)),
      {attempt, created: true},
    );
    assert.deepEqual(
      await store.createDeliveryAttempt(wire(attempt), wire(root.grant)),
      {attempt, created: false},
    );
    const streaming = deliveryRecord(attempt, 0, 'streaming');
    await store.appendDeliveryRecord(wire(streaming));
    const failed = deliveryRecord(attempt, 1, 'failed', streaming, {
      confirmed_byte_count: 7,
      failure_cid: digest('delivery failure'),
    });
    await store.appendDeliveryRecord(wire(failed));
    await store.close();

    const reopened = await openLocalPublicationStore(
      configuration, contractControl,
    );
    t.after(async () => { await reopened.close(); });
    assert.deepEqual(
      await reopened.latestDeliveryRecord(attempt.delivery_attempt_cid),
      failed,
    );
    const lookup = {
      indexKey: {namespaceId: 'namespace-a',
        authorityScopeCid: cids.scope, runDefinitionCid: cids.run},
      principalId: 'principal-a', purpose: 'download',
      resultName: 'answer', attemptId: 'delivery-1',
    };
    assert.deepEqual(await reopened.lookupDeliveryAttempt(lookup),
      {attempt, record: failed, hostReleaseReceipt: undefined});
    assert.equal(await reopened.lookupDeliveryAttempt({...lookup,
      principalId: 'different-principal'}), undefined);
    assert.equal(await reopened.lookupDeliveryAttempt({...lookup,
      attemptId: 'missing'}), undefined);
    assert.deepEqual(
      await reopened.appendDeliveryRecord(wire(failed)),
      failed,
    );
  });

test('delivery record durability retries the exact visible record', async t => {
  const directory = await mkdtemp(join(
    tmpdir(), 'actql-delivery-record-durability-',
  ));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const deliveries = join(directory, 'deliveries');
  let failRecordSync = false;
  let recordSyncFailures = 0;
  const durability = Object.freeze({
    async syncDirectory(path) {
      if (failRecordSync && path.startsWith(`${deliveries}/`)) {
        failRecordSync = false;
        recordSyncFailures++;
        const error = new Error('injected delivery directory sync failure');
        error.code = 'EIO';
        throw error;
      }
      const handle = await open(path, 'r');
      try { await handle.sync(); }
      finally { await handle.close(); }
    },
  });
  const store = await openLocalPublicationStore({
    directory,
    storeAuthorityCid: cids.authority,
    capacityBytes: 1024 * 1024,
    maxObjectBytes: 64 * 1024,
    maxObjects: 100,
    maxContractNodes: limits.maxNodes,
    maxContractDepth: limits.maxDepth,
  }, contractControl, durability);
  t.after(async () => { await store.close(); });
  const root = deliveryFixture();
  const attempt = deliveryAttempt(root, 'delivery-durability-retry');
  await store.createDeliveryAttempt(wire(attempt), wire(root.grant));
  const streaming = deliveryRecord(attempt, 0, 'streaming');
  await store.appendDeliveryRecord(wire(streaming));
  const failed = deliveryRecord(attempt, 1, 'failed', streaming, {
    confirmed_byte_count: 7,
    failure_cid: digest('delivery failure'),
  });
  failRecordSync = true;
  await assert.rejects(
    store.appendDeliveryRecord(wire(failed)),
    code('EIO'),
  );
  assert.equal(recordSyncFailures, 1);
  assert.deepEqual(
    await store.latestDeliveryRecord(attempt.delivery_attempt_cid),
    failed,
  );
  assert.deepEqual(
    await store.appendDeliveryRecord(wire(failed)),
    failed,
  );
  assert.deepEqual(
    await store.confirmDeliveryRecord(wire(failed)),
    failed,
  );
});

test('delivery grant use limit is durable and concurrent attempts are CAS',
  async t => {
    const {store, configuration} = await fixture(t);
    const root = deliveryFixture(1);
    const attempts = [
      deliveryAttempt(root, 'delivery-a'),
      deliveryAttempt(root, 'delivery-b'),
    ];
    const outcomes = await Promise.allSettled(attempts.map(attempt =>
      store.createDeliveryAttempt(wire(attempt), wire(root.grant))));
    assert.equal(
      outcomes.filter(outcome => outcome.status === 'fulfilled').length,
      1,
    );
    assert.equal(
      outcomes.filter(outcome => outcome.status === 'rejected' &&
        outcome.reason?.code === 'DeliveryGrantUseLimit').length,
      1,
    );
    const accepted = attempts[outcomes.findIndex(
      outcome => outcome.status === 'fulfilled',
    )];
    assert.equal((await store.createDeliveryAttempt(
      wire(accepted), wire(root.grant),
    )).created, false);
    await store.close();

    const reopened = await openLocalPublicationStore(
      configuration, contractControl,
    );
    t.after(async () => { await reopened.close(); });
    await assert.rejects(reopened.createDeliveryAttempt(
      wire(deliveryAttempt(root, 'delivery-c')),
      wire(root.grant),
    ), code('DeliveryGrantUseLimit'));
  });

test('Manifest grant use is durable idempotent and bounded across restart',
  async t => {
    const {store, configuration} = await fixture(t);
    const grant = manifestReadGrant(1);
    assert.deepEqual(
      await store.consumeManifestReadGrant(wire(grant), 'manifest-read-a'),
      {grant, created: true, idempotent: false},
    );
    assert.deepEqual(
      await store.consumeManifestReadGrant(wire(grant), 'manifest-read-a'),
      {grant, created: false, idempotent: true},
    );
    await assert.rejects(
      store.consumeManifestReadGrant(wire(grant), 'manifest-read-b'),
      code('ManifestReadGrantUseLimit'),
    );
    await store.close();
    const reopened = await openLocalPublicationStore(
      configuration, contractControl,
    );
    t.after(async () => { await reopened.close(); });
    assert.equal((await reopened.consumeManifestReadGrant(
      wire(grant), 'manifest-read-a',
    )).idempotent, true);
    await assert.rejects(
      reopened.consumeManifestReadGrant(wire(grant), 'manifest-read-c'),
      code('ManifestReadGrantUseLimit'),
    );
  });

test('unknown publication cannot become failed without confirmed non-commit',
  async t => {
    const {store} = await fixture(t);
    const request = publicationRequest();
    const attempt = publicationAttempt(request);
    await store.putPublicationContract('publication_request', wire(request));
    await store.createAttempt(wire(attempt));
    const first = publicationRecord(attempt, 0, 'preparing');
    const second = publicationRecord(attempt, 1, 'committing', first);
    const unknown = publicationRecord(attempt, 2, 'publication_unknown', second);
    for (const record of [first, second, unknown]) {
      await store.appendRecord(wire(record), {uncommittedConfirmed: false});
    }
    const failed = publicationRecord(attempt, 3, 'failed', unknown, {
      failure_cid: digest('failure'),
    });
    await assert.rejects(store.appendRecord(
      wire(failed), {uncommittedConfirmed: false},
    ), code('InvalidPublicationRecordTransition'));
    await store.appendRecord(wire(failed), {uncommittedConfirmed: true});
  });

test('public index is invisible before commit and survives a lost response',
  async t => {
    const {store, configuration} = await fixture(t);
    const invocationValue = invocation();
    const request = publicationRequest(
      resultDefinition(), invocationValue.invocation_cid,
    );
    const attempt = publicationAttempt(request);
    const prepared = await prepareCommit(
      store, request, attempt, invocationValue,
    );
    assert.equal(await store.inspectCommittedIndex(
      indexKeyFor(request),
    ), undefined);
    const entry = indexEntry(request, attempt, invocationValue, {
      durable_result_binding_cids: [prepared.binding.identity],
    });
    const committed = await store.commitIndex(
      wire(entry), prepared.required, prepared.evidence,
    );
    assert.equal(committed.committed, true);
    assert.equal(prepared.prepared.status().pending, false);
    // Simulate losing the response after the durable commit by closing without
    // appending the terminal attempt record, then reconcile after restart.
    await store.close();
    const reopened = await openLocalPublicationStore(
      configuration, contractControl,
    );
    t.after(async () => { await reopened.close(); });
    assert.deepEqual(await reopened.inspectCommittedIndex(
      indexKeyFor(request),
    ), entry);
    const chunks = [];
    let authorizationChecks = 0;
    const consumed = await reopened.consumeCommittedResult(
      indexKeyFor(request),
      request.inventory[0].result_definition_cid,
      authorization => {
        authorizationChecks++;
        return authorization.resultDefinitionCid ===
          request.inventory[0].result_definition_cid;
      },
      chunk => chunks.push(Buffer.from(chunk)),
    );
    assert.equal(authorizationChecks, 2);
    assert.equal(Buffer.concat(chunks).toString('utf8'),
      'fixture durable Result payload');
    assert.deepEqual(consumed, {
      durableResultBindingCid: prepared.binding.identity,
      logicalResultCid: cids.result,
      resultSchemaCid: cids.schema,
      resultSchemaWire,
      resultFields: ['answer'],
      rowCount: 1,
      bytes: Buffer.byteLength('fixture durable Result payload', 'utf8'),
    });
    const succeeded = publicationRecord(attempt, 2, 'succeeded',
      prepared.committing, {public_index_entry_cid: entry.public_index_entry_cid});
    await reopened.appendRecord(
      wire(succeeded), {uncommittedConfirmed: false},
    );
    assert.equal((await reopened.latestRecord(
      attempt.publication_attempt_cid,
    )).state, 'succeeded');
  });

test('durable commit adopts prepared schema without deleting shared bytes',
  async t => {
    const {store, configuration} = await fixture(t);
    const invocationValue = invocation();
    const request = publicationRequest(
      resultDefinition(), invocationValue.invocation_cid,
    );
    const attempt = publicationAttempt(request);
    const prepared = await prepareCommit(
      store, request, attempt, invocationValue, cids.policy, true,
    );
    const otherRun = await store.putPreparedResultSchema(
      resultSchemaWire, cids.schema, cids.result,
    );
    assert.equal(prepared.schemaPrepared.status().pending, true);
    const entry = indexEntry(request, attempt, invocationValue, {
      durable_result_binding_cids: [prepared.binding.identity],
    });
    const committed = await store.commitIndex(
      wire(entry), prepared.required, prepared.evidence,
    );
    assert.equal(committed.committed, true);
    assert.equal(prepared.schemaPrepared.status().pending, false);
    assert.equal(otherRun.prepared.status().pending, true);
    assert.equal(await otherRun.prepared.release(), true);
    assert.equal((await store.readSemanticBytes(cids.schema)).toString(),
      resultSchemaWire);
    const before = store.status().storedBytes;
    await store.close();
    const reopened = await openLocalPublicationStore(
      configuration, contractControl,
    );
    t.after(async () => { await reopened.close(); });
    assert.equal(reopened.status().storedBytes, before);
    assert.equal((await reopened.readSemanticBytes(cids.schema)).toString(),
      resultSchemaWire);
    assert.deepEqual(await reopened.inspectCommittedIndex(
      indexKeyFor(request),
    ), entry);
  });

test('metadata retirement preserves a second Run prepared schema owner',
  async t => {
    const {store} = await fixture(t);
    const invocationValue = invocation();
    const request = publicationRequest(
      resultDefinition(), invocationValue.invocation_cid,
    );
    const attempt = publicationAttempt(request);
    const prepared = await prepareCommit(
      store, request, attempt, invocationValue, cids.policy, true,
    );
    const otherRun = await store.putPreparedResultSchema(
      resultSchemaWire, cids.schema, cids.result,
    );
    const entry = indexEntry(request, attempt, invocationValue, {
      durable_result_binding_cids: [prepared.binding.identity],
    });
    await store.commitIndex(wire(entry), prepared.required,
      prepared.evidence);
    assert.equal(otherRun.prepared.status().pending, true);
    const result = await store.retireCommittedResult(
      indexKeyFor(request), request.inventory[0].result_definition_cid,
    );
    assert.equal(result.cleanup.status().pending, false);
    const metadata = await store.retireCommittedPublicationMetadata(
      indexKeyFor(request), '2026-09-18T04:00:00.000Z',
    );
    assert.equal(metadata.cleanup.status().pending, false);
    assert.equal((await store.readSemanticBytes(cids.schema)).toString(),
      resultSchemaWire);
    await otherRun.prepared.release();
    await assert.rejects(store.readSemanticBytes(cids.schema),
      code('PublicationContractMissing'));
  });

test('durable Result retirement blocks new reads and waits for active readers',
  async t => {
    const {store, configuration} = await fixture(t);
    const invocationValue = invocation();
    const request = publicationRequest(
      resultDefinition(), invocationValue.invocation_cid,
    );
    const attempt = publicationAttempt(request);
    const prepared = await prepareCommit(
      store, request, attempt, invocationValue,
    );
    const entry = indexEntry(request, attempt, invocationValue, {
      durable_result_binding_cids: [prepared.binding.identity],
    });
    await store.commitIndex(
      wire(entry), prepared.required, prepared.evidence,
    );
    let enterReader;
    const readerEntered = new Promise(resolve => { enterReader = resolve; });
    let finishReader;
    const readerFinished = new Promise(resolve => { finishReader = resolve; });
    const reading = store.withCommittedResult(
      indexKeyFor(request),
      request.inventory[0].result_definition_cid,
      () => true,
      async () => {
        enterReader();
        await readerFinished;
      },
    );
    await readerEntered;
    const retired = await store.retireCommittedResult(
      indexKeyFor(request), request.inventory[0].result_definition_cid,
    );
    assert.equal(retired.cleanup.status().pending, true);
    await assert.rejects(store.consumeCommittedResult(
      indexKeyFor(request),
      request.inventory[0].result_definition_cid,
      () => true,
      () => assert.fail('retired Result exposed bytes'),
    ), code('PublicationObjectMissing'));
    await assert.rejects(
      store.close(), code('PublicationStoreCleanupPending'),
    );
    finishReader();
    await reading;
    assert.deepEqual(await retired.cleanup.retry(), {
      pending: false,
      errors: [],
    });
    await store.close();
    const reopened = await openLocalPublicationStore(
      configuration, contractControl,
    );
    t.after(async () => { await reopened.close(); });
    await assert.rejects(reopened.consumeCommittedResult(
      indexKeyFor(request),
      request.inventory[0].result_definition_cid,
      () => true,
      () => assert.fail('retired Result survived restart'),
    ), code('PublicationObjectMissing'));
  });

test('metadata retirement hides the Run and reclaims its durable chain',
  async t => {
    const {store, configuration} = await fixture(t);
    const invocationValue = invocation();
    const request = publicationRequest(
      resultDefinition(), invocationValue.invocation_cid,
    );
    const attempt = publicationAttempt(request);
    const prepared = await prepareCommit(
      store, request, attempt, invocationValue,
    );
    const entry = indexEntry(request, attempt, invocationValue, {
      durable_result_binding_cids: [prepared.binding.identity],
    });
    await store.commitIndex(
      wire(entry), prepared.required, prepared.evidence,
    );
    const retiredResult = await store.retireCommittedResult(
      indexKeyFor(request), request.inventory[0].result_definition_cid,
    );
    assert.equal(retiredResult.cleanup.status().pending, false);
    const retiredMetadata = await store.retireCommittedPublicationMetadata(
      indexKeyFor(request), '2026-09-18T04:00:00.000Z',
    );
    assert.equal(retiredMetadata.cleanup.status().pending, false);
    const deletionNames = await readdir(join(
      configuration.directory, 'metadata-deletions',
    ));
    assert.equal(deletionNames.length, 1);
    assert.deepEqual(JSON.parse(await readFile(join(
      configuration.directory,
      'metadata-deletions',
      deletionNames[0],
    ), 'utf8')), {
      version: 'actql-local-publication-metadata-retired/0.1',
      run_definition_cid: request.run_definition_cid,
    });
    assert.equal(await store.inspectCommittedIndex(
      indexKeyFor(request),
    ), undefined);
    await assert.rejects(store.readPublicationContract(
      entry.public_index_entry_cid, 'public_index_entry',
    ), code('PublicationContractMissing'));
    await store.close();
    const reopened = await openLocalPublicationStore(
      configuration, contractControl,
    );
    t.after(async () => { await reopened.close(); });
    assert.equal(await reopened.confirmCommittedIndex(
      indexKeyFor(request),
    ), undefined);
    await assert.rejects(reopened.createAttempt(wire(
      publicationAttempt(request, 'after-metadata-deletion'),
    )), code('PublicationMetadataDeleted'));
  });

test('metadata retirement retains capacity until durability retry', async t => {
  const directory = await mkdtemp(join(
    tmpdir(), 'actql-publication-metadata-retry-',
  ));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const objects = join(directory, 'objects');
  let objectSyncFailures = 0;
  const durability = Object.freeze({
    async syncDirectory(path) {
      if (path === objects && objectSyncFailures > 0) {
        objectSyncFailures--;
        const error = new Error('injected object directory sync failure');
        error.code = 'EIO';
        throw error;
      }
      const handle = await open(path, 'r');
      try { await handle.sync(); }
      finally { await handle.close(); }
    },
  });
  const configuration = {
    directory,
    storeAuthorityCid: cids.authority,
    capacityBytes: 1024 * 1024,
    maxObjectBytes: 64 * 1024,
    maxObjects: 100,
    maxContractNodes: limits.maxNodes,
    maxContractDepth: limits.maxDepth,
  };
  const store = await openLocalPublicationStore(
    configuration, contractControl, durability,
  );
  t.after(async () => { await store.close(); });
  const invocationValue = invocation();
  const request = publicationRequest(
    resultDefinition(), invocationValue.invocation_cid,
  );
  const attempt = publicationAttempt(request);
  const prepared = await prepareCommit(
    store, request, attempt, invocationValue,
  );
  const entry = indexEntry(request, attempt, invocationValue, {
    durable_result_binding_cids: [prepared.binding.identity],
  });
  await store.commitIndex(
    wire(entry), prepared.required, prepared.evidence,
  );
  const chargedBefore = store.status().storedBytes;
  objectSyncFailures = 2;
  const retired = await store.retireCommittedPublicationMetadata(
    indexKeyFor(request), '2026-09-18T04:00:00.000Z',
  );
  assert.equal(retired.cleanup.status().pending, true);
  assert.equal(retired.cleanup.status().errors[0].code, 'EIO');
  assert.equal(store.status().storedBytes, chargedBefore);
  const pendingMarker = JSON.parse(await readFile(join(
    directory,
    'metadata-deletions',
    (await readdir(join(directory, 'metadata-deletions')))[0],
  ), 'utf8'));
  assert.equal(
    pendingMarker.version,
    'actql-local-publication-metadata-deletion/0.1',
  );
  assert.equal(await store.inspectCommittedIndex(
    indexKeyFor(request),
  ), undefined);
  await assert.rejects(
    store.close(), code('PublicationStoreCleanupPending'),
  );
  const retried = await retired.cleanup.retry();
  assert.equal(retried.pending, false);
  assert.equal(retried.errors.length, 1);
  assert.equal(store.status().storedBytes, 0);
  assert.equal(store.status().objectCount, 0);
  const retiredMarker = JSON.parse(await readFile(join(
    directory,
    'metadata-deletions',
    (await readdir(join(directory, 'metadata-deletions')))[0],
  ), 'utf8'));
  assert.deepEqual(retiredMarker, {
    version: 'actql-local-publication-metadata-retired/0.1',
    run_definition_cid: request.run_definition_cid,
  });
  assert.equal(await store.close(), true);
});

test('restart resumes metadata retirement after an interrupted unlink',
  async t => {
    const {store, configuration, directory} = await fixture(t);
    const invocationValue = invocation();
    const request = publicationRequest(
      resultDefinition(), invocationValue.invocation_cid,
    );
    const attempt = publicationAttempt(request);
    const prepared = await prepareCommit(
      store, request, attempt, invocationValue,
    );
    const entry = indexEntry(request, attempt, invocationValue, {
      durable_result_binding_cids: [prepared.binding.identity],
    });
    await store.commitIndex(
      wire(entry), prepared.required, prepared.evidence,
    );
    await store.close();

    const storeUrl = new URL('./publication-store.mjs', import.meta.url).href;
    const controlUrl = new URL(
      '../host-common/publication-contract-control.fixture.mjs',
      import.meta.url,
    ).href;
    const child = await runStoreChild(`
      import {open} from 'node:fs/promises';
      import {join} from 'node:path';
      import {openLocalPublicationStore} from ${JSON.stringify(storeUrl)};
      import {createPublicationContractControlFixture} from
        ${JSON.stringify(controlUrl)};
      const directory = ${JSON.stringify(directory)};
      let armed = false;
      const durability = Object.freeze({async syncDirectory(path) {
        const handle = await open(path, 'r');
        try { await handle.sync(); } finally { await handle.close(); }
        if (armed && path === join(directory, 'objects')) process.exit(73);
      }});
      const store = await openLocalPublicationStore(
        ${JSON.stringify(configuration)},
        createPublicationContractControlFixture(),
        durability,
      );
      armed = true;
      await store.retireCommittedPublicationMetadata(
        ${JSON.stringify(indexKeyFor(request))},
        '2026-09-18T04:00:00.000Z',
      );
    `);
    assert.equal(child.exitCode, 73, child.stderr);
    assert.equal(child.signal, null);

    const reopened = await openLocalPublicationStore(
      configuration, contractControl,
    );
    t.after(async () => { await reopened.close(); });
    assert.equal(await reopened.confirmCommittedIndex(
      indexKeyFor(request),
    ), undefined);
    await assert.rejects(reopened.readPublicationContract(
      entry.public_index_entry_cid, 'public_index_entry',
    ), code('PublicationContractMissing'));
    assert.equal(reopened.status().storedBytes, 0);
    assert.equal(reopened.status().objectCount, 0);
  });

test('metadata retirement preserves allocations shared by another Run',
  async t => {
    const {store} = await fixture(t);
    const invocationValue = invocation();
    const firstRequest = publicationRequest(
      resultDefinition(), invocationValue.invocation_cid,
    );
    const secondRequest = publicationRequest(
      resultDefinition(), digest('second Run'),
    );
    const firstAttempt = publicationAttempt(firstRequest, 'first-attempt');
    const secondAttempt = publicationAttempt(secondRequest, 'second-attempt');
    const first = await prepareCommit(
      store, firstRequest, firstAttempt, invocationValue,
    );
    const second = await prepareCommit(
      store, secondRequest, secondAttempt, invocationValue,
    );
    const firstEntry = indexEntry(
      firstRequest, firstAttempt, invocationValue,
      {durable_result_binding_cids: [first.binding.identity]},
    );
    const secondEntry = indexEntry(
      secondRequest, secondAttempt, invocationValue,
      {durable_result_binding_cids: [second.binding.identity]},
    );
    await store.commitIndex(
      wire(firstEntry), first.required, first.evidence,
    );
    await store.commitIndex(
      wire(secondEntry), second.required, second.evidence,
    );
    const retired = await store.retireCommittedPublicationMetadata(
      indexKeyFor(firstRequest), '2026-09-18T04:00:00.000Z',
    );
    assert.equal(retired.cleanup.status().pending, false);
    assert.equal((await store.readPublicationContract(
      invocationValue.invocation_cid, 'run_invocation',
    )).identity, invocationValue.invocation_cid);
    const chunks = [];
    await store.consumeCommittedResult(
      indexKeyFor(secondRequest),
      secondRequest.inventory[0].result_definition_cid,
      () => true,
      chunk => chunks.push(Buffer.from(chunk)),
    );
    assert.equal(
      Buffer.concat(chunks).toString('utf8'),
      'fixture durable Result payload',
    );
  });

test('Result retention extensions are append-only CAS records across restart',
  async t => {
    const {store, configuration} = await fixture(t);
    const base = seal('result_retention_policy', {
      version: 'actql-result-retention-policy/0.1',
      retention_contract_cid: digest('retention-contract'),
      effective_data_policy_cid: digest('data-policy'),
      available_until: '2026-09-18T01:00:00.000Z',
      delete_by: '2026-09-18T03:00:00.000Z',
      extension_ceiling_at: '2026-09-18T02:30:00.000Z',
      metadata_retention_policy_cid: digest('metadata-retention'),
      metadata_delete_by: '2026-09-18T04:00:00.000Z',
      clock_contract_cid: digest('clock-contract'),
    });
    const first = seal('result_retention_policy', {
      ...base,
      available_until: '2026-09-18T02:00:00.000Z',
      effective_retention_policy_cid: undefined,
    });
    const second = seal('result_retention_policy', {
      ...base,
      available_until: '2026-09-18T02:15:00.000Z',
      effective_retention_policy_cid: undefined,
    });
    await store.putPublicationContract(
      'result_retention_policy', wire(base),
    );
    const invocationValue = invocation();
    const request = publicationRequest(
      resultDefinition(), invocationValue.invocation_cid,
    );
    const attempt = publicationAttempt(request);
    const prepared = await prepareCommit(
      store,
      request,
      attempt,
      invocationValue,
      base.effective_retention_policy_cid,
    );
    const entry = indexEntry(request, attempt, invocationValue, {
      durable_result_binding_cids: [prepared.binding.identity],
    });
    await store.commitIndex(
      wire(entry), prepared.required, prepared.evidence,
    );
    const resultCid = request.inventory[0].result_definition_cid;
    assert.equal(await store.readCommittedResultRetentionExtension(
      indexKeyFor(request), resultCid,
    ), undefined);
    const installed = await store.putCommittedResultRetentionExtension(
      indexKeyFor(request),
      resultCid,
      undefined,
      contractControl.admit('result_retention_policy', wire(first), limits),
      '2026-09-18T00:30:00.000Z',
    );
    assert.equal(installed.idempotent, false);
    assert.equal(installed.record.sequence, 0);
    const idempotent = await store.putCommittedResultRetentionExtension(
      indexKeyFor(request),
      resultCid,
      first.effective_retention_policy_cid,
      contractControl.admit('result_retention_policy', wire(first), limits),
      '2026-09-18T00:30:00.000Z',
    );
    assert.equal(idempotent.idempotent, true);
    await assert.rejects(store.putCommittedResultRetentionExtension(
      indexKeyFor(request),
      resultCid,
      undefined,
      contractControl.admit('result_retention_policy', wire(second), limits),
      '2026-09-18T00:45:00.000Z',
    ), code('PublicationRetentionExtensionConflict'));
    const advanced = await store.putCommittedResultRetentionExtension(
      indexKeyFor(request),
      resultCid,
      first.effective_retention_policy_cid,
      contractControl.admit('result_retention_policy', wire(second), limits),
      '2026-09-18T00:45:00.000Z',
    );
    assert.equal(advanced.record.sequence, 1);
    assert.equal(advanced.record.prior_extension_policy_cid,
      first.effective_retention_policy_cid);
    await store.close();
    const reopened = await openLocalPublicationStore(
      configuration, contractControl,
    );
    t.after(async () => { await reopened.close(); });
    const recovered = await reopened.readCommittedResultRetentionExtension(
      indexKeyFor(request), resultCid,
    );
    assert.equal(recovered.record.sequence, 1);
    assert.equal(recovered.extension.identity,
      second.effective_retention_policy_cid);
  });

test('Result retirement retains capacity until object durability retry',
  async t => {
    const directory = await mkdtemp(join(
      tmpdir(), 'actql-publication-retirement-',
    ));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const configuration = {
      directory,
      storeAuthorityCid: cids.authority,
      capacityBytes: 1024 * 1024,
      maxObjectBytes: 64 * 1024,
      maxObjects: 100,
      maxContractNodes: limits.maxNodes,
      maxContractDepth: limits.maxDepth,
    };
    let objectSyncFailures = 0;
    const durability = Object.freeze({
      async syncDirectory(path) {
        if (path === join(directory, 'objects') && objectSyncFailures > 0) {
          objectSyncFailures--;
          const error = new Error('injected object sync failure');
          error.code = 'EIO';
          throw error;
        }
        const handle = await open(path, 'r');
        try { await handle.sync(); }
        finally { await handle.close(); }
      },
    });
    const store = await openLocalPublicationStore(
      configuration, contractControl, durability,
    );
    t.after(async () => { await store.close(); });
    const invocationValue = invocation();
    const request = publicationRequest(
      resultDefinition(), invocationValue.invocation_cid,
    );
    const attempt = publicationAttempt(request);
    const prepared = await prepareCommit(
      store, request, attempt, invocationValue,
    );
    const entry = indexEntry(request, attempt, invocationValue, {
      durable_result_binding_cids: [prepared.binding.identity],
    });
    await store.commitIndex(
      wire(entry), prepared.required, prepared.evidence,
    );
    const before = store.status().storedBytes;
    objectSyncFailures = 1;
    const retired = await store.retireCommittedResult(
      indexKeyFor(request), request.inventory[0].result_definition_cid,
    );
    assert.equal(retired.cleanup.status().pending, true);
    assert.equal(store.status().storedBytes, before);
    const replacementPayload = Buffer.from(
      'fixture durable Result payload', 'utf8',
    );
    const replacement = store.createPreparedObjectWriter(
      replacementPayload.byteLength,
    );
    await replacement.append(replacementPayload);
    await assert.rejects(
      replacement.seal(digest(replacementPayload)),
      code('PublicationObjectReclamationPending'),
    );
    assert.equal(store.status().reservedBytes, 0);
    const recovered = await retired.cleanup.retry();
    assert.equal(recovered.pending, false);
    assert.equal(recovered.errors.length, 1);
    assert.equal(
      store.status().storedBytes,
      before - Buffer.byteLength('fixture durable Result payload', 'utf8'),
    );
  });

test('restart reconciles a retired Result after unlink response is lost',
  async t => {
    const directory = await mkdtemp(join(
      tmpdir(), 'actql-publication-retirement-restart-',
    ));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const configuration = {
      directory,
      storeAuthorityCid: cids.authority,
      capacityBytes: 1024 * 1024,
      maxObjectBytes: 64 * 1024,
      maxObjects: 100,
      maxContractNodes: limits.maxNodes,
      maxContractDepth: limits.maxDepth,
    };
    let objectSyncFailures = 0;
    const durability = Object.freeze({
      async syncDirectory(path) {
        if (path === join(directory, 'objects') && objectSyncFailures > 0) {
          objectSyncFailures--;
          const error = new Error('lost object directory sync response');
          error.code = 'EIO';
          throw error;
        }
        const handle = await open(path, 'r');
        try { await handle.sync(); }
        finally { await handle.close(); }
      },
    });
    const store = await openLocalPublicationStore(
      configuration, contractControl, durability,
    );
    const invocationValue = invocation();
    const request = publicationRequest(
      resultDefinition(), invocationValue.invocation_cid,
    );
    const attempt = publicationAttempt(request);
    const prepared = await prepareCommit(
      store, request, attempt, invocationValue,
    );
    const entry = indexEntry(request, attempt, invocationValue, {
      durable_result_binding_cids: [prepared.binding.identity],
    });
    await store.commitIndex(
      wire(entry), prepared.required, prepared.evidence,
    );
    objectSyncFailures = 1;
    const retired = await store.retireCommittedResult(
      indexKeyFor(request), request.inventory[0].result_definition_cid,
    );
    assert.equal(retired.cleanup.status().pending, true);
    // Model abrupt process loss: no product close or cleanup callback runs.
    // Only the dead owner's fencing record is removed before reopen.
    await rm(join(directory, 'owner'), {recursive: true, force: false});
    const reopened = await openLocalPublicationStore(
      configuration, contractControl,
    );
    t.after(async () => { await reopened.close(); });
    const recovered = await reopened.recoverRetiredResults();
    assert.equal(recovered.length, 1);
    assert.equal(recovered[0].cleanup.status().pending, false);
    await assert.rejects(reopened.consumeCommittedResult(
      indexKeyFor(request),
      request.inventory[0].result_definition_cid,
      () => true,
      () => assert.fail('retired Result reappeared after restart'),
    ), code('PublicationObjectMissing'));
  });

test('Result retirement preserves a physical allocation held by another Run',
  async t => {
    const {store} = await fixture(t);
    const invocationValue = invocation();
    const firstRequest = publicationRequest(
      resultDefinition(), invocationValue.invocation_cid,
    );
    const secondRequest = publicationRequest(
      resultDefinition('other'), digest('second Run Definition'),
    );
    const commits = [];
    for (const [request, attemptId] of [
      [firstRequest, 'shared-attempt-a'],
      [secondRequest, 'shared-attempt-b'],
    ]) {
      const attempt = publicationAttempt(request, attemptId);
      const prepared = await prepareCommit(
        store, request, attempt, invocationValue,
      );
      const entry = indexEntry(request, attempt, invocationValue, {
        durable_result_binding_cids: [prepared.binding.identity],
      });
      await store.commitIndex(
        wire(entry), prepared.required, prepared.evidence,
      );
      commits.push({request, prepared});
    }
    assert.equal(
      commits[0].prepared.binding.wire === commits[1].prepared.binding.wire,
      false,
    );
    const physicalCid = JSON.parse(
      commits[0].prepared.binding.wire,
    ).material_generation_cid;
    assert.equal(
      JSON.parse(commits[1].prepared.binding.wire).material_generation_cid,
      physicalCid,
    );
    const firstRetired = await store.retireCommittedResult(
      indexKeyFor(firstRequest),
      firstRequest.inventory[0].result_definition_cid,
    );
    assert.equal(firstRetired.cleanup.status().pending, false);
    assert.equal((await store.verifyObject(physicalCid)).cid, physicalCid);
    const remaining = [];
    await store.consumeCommittedResult(
      indexKeyFor(secondRequest),
      secondRequest.inventory[0].result_definition_cid,
      () => true,
      chunk => remaining.push(Buffer.from(chunk)),
    );
    assert.equal(Buffer.concat(remaining).toString('utf8'),
      'fixture durable Result payload');
    const secondRetired = await store.retireCommittedResult(
      indexKeyFor(secondRequest),
      secondRequest.inventory[0].result_definition_cid,
    );
    assert.equal(secondRetired.cleanup.status().pending, false);
    await assert.rejects(
      store.verifyObject(physicalCid), code('PublicationObjectMissing'),
    );
  });

test('visible index is not committed until directory durability is confirmed',
  async t => {
    const directory = await mkdtemp(join(
      tmpdir(), 'actql-publication-durability-',
    ));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const configuration = {
      directory,
      storeAuthorityCid: cids.authority,
      capacityBytes: 1024 * 1024,
      maxObjectBytes: 64 * 1024,
      maxObjects: 100,
      maxContractNodes: limits.maxNodes,
      maxContractDepth: limits.maxDepth,
    };
    let indexSyncFailures = 2;
    const durability = Object.freeze({
      async syncDirectory(path) {
        if (path === join(directory, 'indexes') && indexSyncFailures > 0) {
          indexSyncFailures--;
          const error = new Error('injected index directory sync failure');
          error.code = 'EIO';
          throw error;
        }
        const handle = await open(path, 'r');
        try { await handle.sync(); }
        finally { await handle.close(); }
      },
    });
    const store = await openLocalPublicationStore(
      configuration, contractControl, durability,
    );
    t.after(async () => { await store.close(); });
    const invocationValue = invocation();
    const request = publicationRequest(
      resultDefinition(), invocationValue.invocation_cid,
    );
    const attempt = publicationAttempt(request);
    const prepared = await prepareCommit(
      store, request, attempt, invocationValue,
    );
    const entry = indexEntry(request, attempt, invocationValue, {
      durable_result_binding_cids: [prepared.binding.identity],
    });
    let unknown;
    await assert.rejects(
      store.commitIndex(wire(entry), prepared.required, prepared.evidence),
      error => {
        unknown = error;
        return error?.code === 'EIO' && error.cleanupPending === true &&
          error.cleanupHandle?.status().pending === true;
      },
    );
    assert.deepEqual(
      await store.inspectCommittedIndex(indexKeyFor(request)), entry,
    );
    assert.equal(prepared.prepared.status().pending, true);
    assert.equal(store.status().storedBytes > 0, true);
    assert.equal((await unknown.cleanupHandle.retry()).pending, false);
    assert.equal(unknown.cleanupHandle.status().outcome, 'committed');
    assert.deepEqual(
      await store.confirmCommittedIndex(indexKeyFor(request)), entry,
    );
    const idempotent = await store.commitIndex(
      wire(entry), prepared.required, prepared.evidence,
    );
    assert.equal(idempotent.committed, false);
    assert.equal(idempotent.idempotent, true);
    assert.deepEqual(idempotent.entry, entry);
    assert.equal(prepared.prepared.status().pending, false);
  });

test('committed payload custody remains retryable after cleanup failure',
  async t => {
    const directory = await mkdtemp(join(
      tmpdir(), 'actql-publication-custody-retry-',
    ));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const configuration = {
      directory,
      storeAuthorityCid: cids.authority,
      capacityBytes: 1024 * 1024,
      maxObjectBytes: 64 * 1024,
      maxObjects: 100,
      maxContractNodes: limits.maxNodes,
      maxContractDepth: limits.maxDepth,
    };
    let custodySyncFailures = 0;
    let custodySyncSkips = 0;
    const durability = Object.freeze({
      async syncDirectory(path) {
        if (path === join(directory, 'prepared-custody') &&
            custodySyncFailures > 0) {
          if (custodySyncSkips > 0) {
            custodySyncSkips--;
          } else {
            custodySyncFailures--;
            const error = new Error('injected custody sync failure');
            error.code = 'EIO';
            throw error;
          }
        }
        const handle = await open(path, 'r');
        try { await handle.sync(); }
        finally { await handle.close(); }
      },
    });
    const store = await openLocalPublicationStore(
      configuration, contractControl, durability,
    );
    t.after(async () => { await store.close(); });
    const invocationValue = invocation();
    const request = publicationRequest(
      resultDefinition(), invocationValue.invocation_cid,
    );
    const attempt = publicationAttempt(request);
    const prepared = await prepareCommit(
      store, request, attempt, invocationValue,
    );
    const entry = indexEntry(request, attempt, invocationValue, {
      durable_result_binding_cids: [prepared.binding.identity],
    });
    custodySyncSkips = 2;
    custodySyncFailures = 2;
    let unknown;
    await assert.rejects(store.commitIndex(
      wire(entry), prepared.required, prepared.evidence,
    ), error => {
      unknown = error;
      return error?.cleanupPending === true &&
        error.cleanupHandle?.status().pending === true;
    });
    assert.deepEqual(
      await store.inspectCommittedIndex(indexKeyFor(request)), entry,
    );
    assert.equal(prepared.prepared.status().pending, true);
    const recovered = await unknown.cleanupHandle.retry();
    assert.equal(recovered.pending, false);
    assert.equal(recovered.outcome, 'committed');
    assert.equal(prepared.prepared.status().pending, false);
    assert.deepEqual(await readdir(join(directory, 'prepared-custody')), []);
  });

test('confirmed non-commit releases custody before prepared reclamation',
  async t => {
    const directory = await mkdtemp(join(
      tmpdir(), 'actql-publication-noncommit-',
    ));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const configuration = {
      directory,
      storeAuthorityCid: cids.authority,
      capacityBytes: 1024 * 1024,
      maxObjectBytes: 64 * 1024,
      maxObjects: 100,
      maxContractNodes: limits.maxNodes,
      maxContractDepth: limits.maxDepth,
    };
    let indexSyncFailures = 2;
    const durability = Object.freeze({
      async syncDirectory(path) {
        if (path === join(directory, 'indexes') && indexSyncFailures > 0) {
          indexSyncFailures--;
          const error = new Error('injected index directory sync failure');
          error.code = 'EIO';
          throw error;
        }
        const handle = await open(path, 'r');
        try { await handle.sync(); }
        finally { await handle.close(); }
      },
    });
    const store = await openLocalPublicationStore(
      configuration, contractControl, durability,
    );
    const invocationValue = invocation();
    const request = publicationRequest(
      resultDefinition(), invocationValue.invocation_cid,
    );
    const attempt = publicationAttempt(request);
    const prepared = await prepareCommit(
      store, request, attempt, invocationValue,
    );
    const entry = indexEntry(request, attempt, invocationValue, {
      durable_result_binding_cids: [prepared.binding.identity],
    });
    let unknown;
    await assert.rejects(store.commitIndex(
      wire(entry), prepared.required, prepared.evidence,
    ), error => {
      unknown = error;
      return error?.cleanupHandle?.status().pending === true;
    });
    const installed = await readdir(join(directory, 'indexes'));
    assert.equal(installed.length, 1);
    await unlink(join(directory, 'indexes', installed[0]));
    const reconciled = await unknown.cleanupHandle.retry();
    assert.equal(reconciled.pending, false);
    assert.equal(reconciled.outcome, 'uncommitted');
    const holdingCid = digest('uncommitted-effect-source-holding');
    const heldBytes = Buffer.from('held effect source', 'utf8');
    const heldWriter = store.createPreparedObjectWriter(heldBytes.length);
    await heldWriter.append(heldBytes);
    const held = await heldWriter.seal(digest(heldBytes));
    await store.commitPhysicalHolding({
      version: 'actql-local-physical-holding/0.1',
      namespace: 'effect-source',
      holding_cid: holdingCid,
      manifest_cid: cids.manifest,
      objects: [{cid: held.cid, byte_count: held.bytes}],
    }, [held.prepared]);
    // Model an Effectful commit's exact durable inventory at the fault edge.
    const inventoryPath = join(directory, 'metadata-inventories',
      `${entry.public_index_entry_cid.slice(7)}.json`);
    const inventory = JSON.parse(await readFile(inventoryPath, 'utf8'));
    inventory.physical_holding_cids = [holdingCid];
    await writeFile(inventoryPath, JSON.stringify(inventory));
    const inventoryHandle = await open(inventoryPath, 'r');
    try { await inventoryHandle.sync(); }
    finally { await inventoryHandle.close(); }
    const candidateCleanup = await store.retireUncommittedPublication(
      entry.public_index_entry_cid,
    );
    assert.equal(candidateCleanup.deleted, false);
    assert.equal(candidateCleanup.cleanup.status().pending, true);
    assert.equal(
      candidateCleanup.cleanup.status().errors.at(-1)?.code,
      'PublicationUncommittedMetadataLive',
    );
    assert.equal((await readdir(
      join(directory, 'metadata-inventories'),
    )).length, 1);
    await assert.rejects(store.close(),
      code('PublicationStoreCleanupPending'));
    assert.equal(store.status().closed, false);
    const cancelled = publicationRecord(
      attempt, 2, 'cancelled', prepared.committing,
    );
    await store.appendRecord(wire(cancelled), {uncommittedConfirmed: true});
    await assert.rejects(candidateCleanup.cleanup.retry(),
      code('PublicationPhysicalHoldingCleanupRequired'));
    assert.notEqual(await store.inspectPhysicalHolding(holdingCid), undefined);
    assert.equal((await readdir(
      join(directory, 'metadata-inventories'),
    )).length, 1);
    assert.equal((await store.retirePhysicalHolding(holdingCid)).deleted,
      true);
    assert.equal((await candidateCleanup.cleanup.retry()).pending, false);
    assert.deepEqual(await readdir(
      join(directory, 'metadata-inventories'),
    ), []);
    await assert.rejects(
      store.readPublicationContract(
        entry.public_index_entry_cid, 'public_index_entry',
      ),
      code('PublicationContractMissing'),
    );
    assert.equal(prepared.prepared.status().pending, true);
    assert.equal(await prepared.prepared.release(), true);
    assert.equal(prepared.prepared.status().pending, false);
    assert.equal(await store.close(), true);
  });

test('restart reclaims terminal uncommitted publication metadata', async t => {
  const directory = await mkdtemp(join(
    tmpdir(), 'actql-publication-uncommitted-metadata-',
  ));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const configuration = {
    directory,
    storeAuthorityCid: cids.authority,
    capacityBytes: 1024 * 1024,
    maxObjectBytes: 64 * 1024,
    maxObjects: 100,
    maxContractNodes: limits.maxNodes,
    maxContractDepth: limits.maxDepth,
  };
  let indexSyncFailures = 2;
  const durability = Object.freeze({
    async syncDirectory(path) {
      if (path === join(directory, 'indexes') && indexSyncFailures > 0) {
        indexSyncFailures--;
        const error = new Error('injected index directory sync failure');
        error.code = 'EIO';
        throw error;
      }
      const handle = await open(path, 'r');
      try { await handle.sync(); }
      finally { await handle.close(); }
    },
  });
  const store = await openLocalPublicationStore(
    configuration, contractControl, durability,
  );
  const invocationValue = invocation();
  const request = publicationRequest(
    resultDefinition(), invocationValue.invocation_cid,
  );
  const attempt = publicationAttempt(request);
  const prepared = await prepareCommit(
    store, request, attempt, invocationValue,
  );
  const entry = indexEntry(request, attempt, invocationValue, {
    durable_result_binding_cids: [prepared.binding.identity],
  });
  let unknown;
  await assert.rejects(store.commitIndex(
    wire(entry), prepared.required, prepared.evidence,
  ), error => {
    unknown = error;
    return error?.cleanupHandle?.status().pending === true;
  });
  const [installed] = await readdir(join(directory, 'indexes'));
  await unlink(join(directory, 'indexes', installed));
  assert.equal((await unknown.cleanupHandle.retry()).outcome, 'uncommitted');
  const cancelled = publicationRecord(
    attempt, 2, 'cancelled', prepared.committing,
  );
  await store.appendRecord(wire(cancelled), {uncommittedConfirmed: true});
  assert.equal(await prepared.prepared.release(), true);
  assert.equal((await readdir(
    join(directory, 'metadata-inventories'),
  )).length, 1);
  assert.equal(await store.close(), true);

  const reopened = await openLocalPublicationStore(
    configuration, contractControl,
  );
  t.after(async () => { await reopened.close(); });
  assert.deepEqual(await readdir(
    join(directory, 'metadata-inventories'),
  ), []);
  await assert.rejects(
    reopened.readPublicationContract(
      entry.public_index_entry_cid, 'public_index_entry',
    ),
    code('PublicationContractMissing'),
  );
});

test('commit verifies durable binding against the stored physical generation',
  async t => {
    const {store} = await fixture(t);
    const invocationValue = invocation();
    const request = publicationRequest(
      resultDefinition(), invocationValue.invocation_cid,
    );
    const attempt = publicationAttempt(request);
    const prepared = await prepareCommit(
      store, request, attempt, invocationValue,
    );
    const mismatchedValue = JSON.parse(prepared.binding.wire);
    delete mismatchedValue.durable_result_binding_cid;
    mismatchedValue.byte_count++;
    const mismatched = seal('durable_result_binding', mismatchedValue);
    const mismatchedContract = contractControl.admit(
      'durable_result_binding', wire(mismatched), limits,
    );
    await store.putPublicationContract(
      'durable_result_binding', wire(mismatched),
    );
    const evidence = Object.freeze({
      ...prepared.evidence,
      durableBindings: Object.freeze([mismatchedContract]),
    });
    const required = prepared.required
      .filter(cid => cid !== prepared.binding.identity)
      .concat(mismatchedContract.identity);
    const entry = indexEntry(request, attempt, invocationValue, {
      durable_result_binding_cids: [mismatchedContract.identity],
    });
    await assert.rejects(
      store.commitIndex(wire(entry), required, evidence),
      code('PublicationDurableBindingMismatch'),
    );
    assert.equal(await store.inspectCommittedIndex(indexKeyFor(request)),
      undefined);
    assert.equal(await prepared.prepared.release(), true);
  });

test('same intent is idempotent while conflicting commit is rejected',
  async t => {
    const {store} = await fixture(t);
    const invocationValue = invocation();
    const request = publicationRequest(
      resultDefinition(), invocationValue.invocation_cid,
    );
    const attempt = publicationAttempt(request);
    const prepared = await prepareCommit(
      store, request, attempt, invocationValue,
    );
    const entry = indexEntry(request, attempt, invocationValue, {
      durable_result_binding_cids: [prepared.binding.identity],
    });
    await store.commitIndex(
      wire(entry), prepared.required, prepared.evidence,
    );

    const retryAttempt = publicationAttempt(request, 'attempt-2');
    const retry = await prepareCommit(
      store, request, retryAttempt, invocationValue,
    );
    const retryEntry = indexEntry(request, retryAttempt, invocationValue, {
      durable_result_binding_cids: [retry.binding.identity],
      committed_at: '2026-09-18T00:01:00.000Z',
    });
    const idempotent = await store.commitIndex(
      wire(retryEntry), retry.required, retry.evidence,
    );
    assert.equal(idempotent.committed, false);
    assert.equal(idempotent.idempotent, true);
    assert.deepEqual(idempotent.entry, entry);
    assert.equal(retry.prepared.status().pending, false);

    const otherReceiptCid = digest('different final receipt');
    await store.putSemantic('different final receipt', otherReceiptCid);
    const changedReceipt = indexEntry(request, retryAttempt,
      invocationValue, {
        durable_result_binding_cids: [retry.binding.identity],
        run_receipt_cid: otherReceiptCid,
      });
    await assert.rejects(store.commitIndex(
      wire(changedReceipt), [...retry.required, otherReceiptCid],
      retry.evidence,
    ), code('PublicationCommitConflict'));
    assert.deepEqual(await store.confirmCommittedIndex(indexKeyFor(request)),
      entry);

    const conflictingRequest = publicationRequest(
      resultDefinition('other'), invocationValue.invocation_cid,
    );
    const conflictAttempt = publicationAttempt(
      conflictingRequest, 'attempt-3',
    );
    const conflict = await prepareCommit(
      store, conflictingRequest, conflictAttempt, invocationValue,
    );
    const conflictingEntry = indexEntry(
      conflictingRequest, conflictAttempt, invocationValue, {
        durable_result_binding_cids: [conflict.binding.identity],
      },
    );
    await assert.rejects(store.commitIndex(
      wire(conflictingEntry), conflict.required, conflict.evidence,
    ), code('PublicationCommitConflict'));
    assert.equal(await conflict.prepared.release(), true);
  });

test('concurrent public commits serialize one installation and one replay',
  async t => {
    const {store} = await fixture(t);
    const invocationValue = invocation();
    const request = publicationRequest(
      resultDefinition(), invocationValue.invocation_cid,
    );
    const attempt = publicationAttempt(request);
    const prepared = await prepareCommit(
      store, request, attempt, invocationValue,
    );
    const entry = indexEntry(request, attempt, invocationValue, {
      durable_result_binding_cids: [prepared.binding.identity],
    });
    const results = await Promise.all([
      store.commitIndex(wire(entry), prepared.required, prepared.evidence),
      store.commitIndex(wire(entry), prepared.required, prepared.evidence),
    ]);
    assert.deepEqual(results.map(result => [
      result.committed, result.idempotent,
    ]), [[true, false], [false, true]]);
    assert.deepEqual(await store.confirmCommittedIndex(indexKeyFor(request)),
      entry);
    assert.equal(prepared.prepared.status().pending, false);
  });

test('lookup hides absence and verifies current authorization', async t => {
  const {store} = await fixture(t);
  await assert.rejects(store.lookupCommittedIndex(indexKey, () => false),
    code('PublicationLookupDenied'));
  await assert.rejects(store.lookupCommittedIndex(indexKey, () => true),
    code('PublicationLookupDenied'));
  let calls = 0;
  await assert.rejects(store.lookupCommittedIndex(indexKey, value => {
    calls++;
    return !Object.hasOwn(value, 'entry');
  }), code('PublicationLookupDenied'));
  assert.equal(calls, 1);
  await assert.rejects(store.consumeCommittedResult(
    indexKey,
    resultDefinition().result_definition_cid,
    () => false,
    () => assert.fail('an unauthorized payload was exposed'),
  ), code('PublicationLookupDenied'));
});

test('physical mutation is rejected after restart', async t => {
  const {store, directory} = await fixture(t);
  const stored = await store.putBytes(Buffer.from('original'));
  await writeFile(join(
    directory, 'objects', stored.cid.slice('sha256:'.length),
  ), 'mutated!');
  await assert.rejects(store.verifyObject(stored.cid),
    code('PublicationObjectCorrupt'));
});

test('publication capacity preflight observes limits without reserving',
  async t => {
    const {store} = await fixture(t, {
      capacityBytes: 1024,
      maxObjectBytes: 128,
      maxObjects: 4,
    });
    const before = store.status();
    assert.equal(store.publicationCapacitySupports({
      requiredBytes: 1024,
      objectCount: 4,
      maxObjectBytes: 128,
    }), true);
    assert.equal(store.publicationCapacitySupports({
      requiredBytes: 1025,
      objectCount: 4,
      maxObjectBytes: 128,
    }), false);
    assert.equal(store.publicationCapacitySupports({
      requiredBytes: 1024,
      objectCount: 5,
      maxObjectBytes: 128,
    }), false);
    assert.equal(store.publicationCapacitySupports({
      requiredBytes: 1024,
      objectCount: 4,
      maxObjectBytes: 129,
    }), false);
    assert.deepEqual(store.status(), before);
  });

function physicalHolding(holdingCid, manifestCid, objects,
  namespace = 'remote-transfer') {
  return Object.freeze({
    version: 'actql-local-physical-holding/0.1',
    namespace,
    holding_cid: holdingCid,
    manifest_cid: manifestCid,
    objects: Object.freeze(objects.map(object => Object.freeze({...object}))),
  });
}

for (const damage of ['missing', 'corrupt']) {
test(`one ${damage} Effect payload does not disable unrelated holdings`,
  async t => {
    const setup = await fixture(t);
    const holdings = [];
    for (const value of ['healthy input', 'damaged input']) {
      const payload = await preparePhysical(setup.store, value);
      const holding = physicalHolding(digest(`holding ${value}`),
        digest(`artifact ${value}`),
        [{cid: payload.cid, byte_count: payload.bytes}], 'effect-source');
      await setup.store.commitPhysicalHolding(holding, [payload.prepared]);
      holdings.push(holding);
    }
    await setup.store.close();
    const damagedPath = join(setup.directory, 'objects',
      holdings[1].objects[0].cid.slice('sha256:'.length));
    if (damage === 'missing') await unlink(damagedPath);
    else await writeFile(damagedPath, 'Damaged input');
    const reopened = await openLocalPublicationStore(setup.configuration,
      contractControl);
    t.after(() => reopened.close());
    const chunks = [];
    await reopened.consumePhysicalHolding(holdings[0].holding_cid, 0,
      chunk => chunks.push(Buffer.from(chunk)));
    assert.equal(Buffer.concat(chunks).toString(), 'healthy input');
    const expected = damage === 'missing'
      ? 'PublicationObjectMissing' : 'PublicationObjectCorrupt';
    await assert.rejects(reopened.inspectPhysicalHolding(
      holdings[1].holding_cid), code(expected));
    await assert.rejects(reopened.consumePhysicalHolding(
      holdings[1].holding_cid, 0, () => assert.fail('corrupt bytes exposed')),
    code(expected));
    // Unavailable input is not a reason to discard its recovery evidence.
    assert.deepEqual(JSON.parse(await readFile(join(setup.directory,
      'physical-holdings', `${holdings[1].holding_cid.slice(7)}.json`))),
    holdings[1]);
  });
}

test('Effect source and other physical holdings release independently',
  async t => {
    const setup = await fixture(t);
    const source = await preparePhysical(setup.store, 'source rows');
    const sourceHolding = physicalHolding(
      digest('effect source holding'), digest('effect source artifact'),
      [{cid: source.cid, byte_count: source.bytes}], 'effect-source');
    await setup.store.commitPhysicalHolding(sourceHolding,
      [source.prepared]);
    const otherHolding = physicalHolding(
      digest('other holding'), sourceHolding.manifest_cid,
      sourceHolding.objects);
    await setup.store.sharePhysicalHolding(sourceHolding.holding_cid,
      otherHolding);
    assert.equal(setup.store.status().storedBytes, source.bytes);
    await setup.store.close();
    const reopened = await openLocalPublicationStore(setup.configuration,
      contractControl);
    t.after(async () => { await reopened.close(); });
    assert.deepEqual(await reopened.inspectPhysicalHolding(
      sourceHolding.holding_cid), sourceHolding);
    assert.deepEqual(await reopened.inspectPhysicalHolding(
      otherHolding.holding_cid), otherHolding);
    assert.equal((await reopened.retirePhysicalHolding(
      sourceHolding.holding_cid)).deleted, true);
    assert.equal(reopened.status().storedBytes, source.bytes);
    const chunks = [];
    await reopened.consumePhysicalHolding(otherHolding.holding_cid,
      0, chunk => chunks.push(Buffer.from(chunk)));
    assert.equal(Buffer.concat(chunks).toString('utf8'), 'source rows');
    assert.equal((await reopened.retirePhysicalHolding(
      otherHolding.holding_cid)).deleted, true);
    assert.equal(reopened.status().storedBytes, 0);
  });

test('capture holding borrows an exact allocation across manifest scopes',
  async t => {
    const setup = await fixture(t);
    const shared = await preparePhysical(setup.store, 'shared rows');
    const unique = await preparePhysical(setup.store, 'private output');
    const source = physicalHolding(
      digest('source custody'), digest('source manifest'),
      [{cid: shared.cid, byte_count: shared.bytes}], 'effect-source');
    await setup.store.commitPhysicalHolding(source, [shared.prepared]);
    const capture = physicalHolding(
      digest('capture custody'), digest('captured Run'), [
        {cid: shared.cid, byte_count: shared.bytes},
        {cid: unique.cid, byte_count: unique.bytes},
      ], 'effect-capture');
    await assert.rejects(setup.store.commitPhysicalHolding(
      capture, [shared.prepared, unique.prepared],
    ), code('InvalidPublicationPhysicalHoldingOwner'));
    await setup.store.commitPhysicalHolding(
      capture, [shared.prepared, unique.prepared], [source.holding_cid]);
    assert.equal(unique.prepared.status().pending, false);
    assert.equal((await setup.store.retirePhysicalHolding(
      source.holding_cid)).deleted, true);
    assert.equal(setup.store.status().storedBytes,
      shared.bytes + unique.bytes);
    const foreign = physicalHolding(
      digest('foreign capture custody'), digest('foreign captured Run'),
      [{cid: shared.cid, byte_count: shared.bytes}], 'effect-capture');
    await assert.rejects(setup.store.commitPhysicalHolding(
      foreign, [], [source.holding_cid],
    ), code('PublicationPhysicalHoldingUnavailable'));
    assert.equal(await setup.store.inspectPhysicalHolding(
      foreign.holding_cid), undefined);
    await setup.store.close();

    const reopened = await openLocalPublicationStore(
      setup.configuration, contractControl);
    t.after(async () => { await reopened.close(); });
    assert.deepEqual(await reopened.inspectPhysicalHolding(
      capture.holding_cid), capture);
    for (const [index, expected] of ['shared rows', 'private output']
      .entries()) {
      const chunks = [];
      await reopened.consumePhysicalHolding(capture.holding_cid, index,
        chunk => chunks.push(Buffer.from(chunk)));
      assert.equal(Buffer.concat(chunks).toString('utf8'), expected);
    }
    assert.equal((await reopened.retirePhysicalHolding(
      capture.holding_cid)).deleted, true);
    assert.equal(reopened.status().storedBytes, 0);
    assert.equal(reopened.status().objectCount, 0);
  });

async function preparePhysical(store, value) {
  const bytes = Buffer.from(value, 'utf8');
  const writer = store.createPreparedObjectWriter(bytes.byteLength);
  await writer.append(bytes);
  return await writer.seal(digest(bytes));
}

test('physical Transfer holding survives reopen and reclaims exact objects',
  async t => {
    const setup = await fixture(t);
    const values = ['alpha', '日本語'];
    const prepared = [];
    for (const value of values) {
      prepared.push(await preparePhysical(setup.store, value));
    }
    const holdingCid = digest('transfer holding a');
    const record = physicalHolding(
      holdingCid,
      digest('physical manifest a'),
      prepared.map(object => ({cid: object.cid, byte_count: object.bytes})),
    );
    const committed = await setup.store.commitPhysicalHolding(
      record,
      prepared.map(object => object.prepared),
    );
    assert.equal(committed.created, true);
    assert.equal(setup.store.status().storedBytes, 14);
    assert.equal(setup.store.status().objectCount, 2);
    assert.equal(prepared.every(object =>
      object.prepared.status().pending === false), true);

    await setup.store.close();
    const reopened = await openLocalPublicationStore(
      setup.configuration,
      contractControl,
    );
    t.after(async () => { await reopened.close(); });
    assert.deepEqual(await reopened.inspectPhysicalHolding(holdingCid), record);
    const received = [];
    for (let index = 0; index < values.length; index++) {
      const chunks = [];
      await reopened.consumePhysicalHolding(
        holdingCid,
        index,
        chunk => chunks.push(Buffer.from(chunk)),
      );
      received.push(Buffer.concat(chunks).toString('utf8'));
    }
    assert.deepEqual(received, values);
    const retired = await reopened.retirePhysicalHolding(holdingCid);
    assert.equal(retired.deleted, true);
    assert.equal(retired.cleanup.status().pending, false);
    assert.equal(reopened.status().storedBytes, 0);
    assert.equal(reopened.status().objectCount, 0);
  });

test('visible physical holdings retry directory durability before success',
  async t => {
    const directory = await mkdtemp(join(
      tmpdir(), 'actql-holding-commit-durability-',
    ));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const configuration = {
      directory,
      storeAuthorityCid: cids.authority,
      capacityBytes: 1024,
      maxObjectBytes: 512,
      maxObjects: 8,
      maxContractNodes: limits.maxNodes,
      maxContractDepth: limits.maxDepth,
    };
    let failHoldingSync = false;
    let holdingSyncs = 0;
    const durability = Object.freeze({
      async syncDirectory(path) {
        if (path === join(directory, 'physical-holdings')) {
          holdingSyncs++;
          if (failHoldingSync) {
            failHoldingSync = false;
            const error = new Error('injected holding sync failure');
            error.code = 'EIO';
            throw error;
          }
        }
        const handle = await open(path, 'r');
        try { await handle.sync(); }
        finally { await handle.close(); }
      },
    });
    const store = await openLocalPublicationStore(
      configuration, contractControl, durability,
    );
    t.after(async () => { await store.close(); });
    const prepared = await preparePhysical(store, 'durable');
    const source = physicalHolding(
      digest('holding retry source'), digest('holding retry manifest'),
      [{cid: prepared.cid, byte_count: prepared.bytes}],
    );
    const initialSyncs = holdingSyncs;
    failHoldingSync = true;
    await assert.rejects(store.commitPhysicalHolding(
      source, [prepared.prepared],
    ), code('EIO'));
    assert.equal(prepared.prepared.status().pending, true);
    assert.equal(holdingSyncs, initialSyncs + 1);
    assert.equal((await store.commitPhysicalHolding(
      source, [prepared.prepared],
    )).created, false);
    assert.equal(holdingSyncs, initialSyncs + 2);
    assert.equal(prepared.prepared.status().pending, false);

    const shared = physicalHolding(
      digest('holding retry shared'), source.manifest_cid, source.objects,
    );
    failHoldingSync = true;
    await assert.rejects(store.sharePhysicalHolding(
      source.holding_cid, shared,
    ), code('EIO'));
    assert.equal(holdingSyncs, initialSyncs + 3);
    assert.equal((await store.sharePhysicalHolding(
      source.holding_cid, shared,
    )).created, false);
    assert.equal(holdingSyncs, initialSyncs + 4);
    assert.equal((await store.retirePhysicalHolding(
      source.holding_cid,
    )).deleted, true);
    assert.equal((await store.retirePhysicalHolding(
      shared.holding_cid,
    )).deleted, true);
    assert.equal(store.status().storedBytes, 0);
  });

test('independent Transfer holdings share bytes but release independently',
  async t => {
    const {store} = await fixture(t);
    const first = await preparePhysical(store, 'shared');
    const firstRecord = physicalHolding(
      digest('transfer holding first'),
      digest('physical manifest shared'),
      [{cid: first.cid, byte_count: first.bytes}],
    );
    await store.commitPhysicalHolding(firstRecord, [first.prepared]);

    const second = await preparePhysical(store, 'shared');
    const secondRecord = physicalHolding(
      digest('transfer holding second'),
      digest('physical manifest shared'),
      [{cid: second.cid, byte_count: second.bytes}],
    );
    await store.commitPhysicalHolding(secondRecord, [second.prepared]);
    assert.equal(store.status().storedBytes, 6);
    assert.equal(store.status().objectCount, 1);

    assert.equal((await store.retirePhysicalHolding(
      firstRecord.holding_cid,
    )).deleted, true);
    assert.equal(store.status().storedBytes, 6);
    const chunks = [];
    await store.consumePhysicalHolding(
      secondRecord.holding_cid,
      0,
      chunk => chunks.push(Buffer.from(chunk)),
    );
    assert.equal(Buffer.concat(chunks).toString('utf8'), 'shared');
    assert.equal((await store.retirePhysicalHolding(
      secondRecord.holding_cid,
    )).deleted, true);
    assert.equal(store.status().storedBytes, 0);
    assert.equal(store.status().objectCount, 0);
  });

test('sealed Transfer holding is reused without uploading source again',
  async t => {
    const {store} = await fixture(t);
    const prepared = await preparePhysical(store, 'sealed');
    const source = physicalHolding(
      digest('sealed source holding'),
      digest('sealed manifest'),
      [{cid: prepared.cid, byte_count: prepared.bytes}],
    );
    await store.commitPhysicalHolding(source, [prepared.prepared]);
    const destination = physicalHolding(
      digest('sealed destination holding'),
      source.manifest_cid,
      source.objects,
    );
    assert.deepEqual(await store.sharePhysicalHolding(
      source.holding_cid,
      destination,
    ), {record: destination, created: true});
    assert.equal(store.status().storedBytes, 6);
    assert.equal(store.status().objectCount, 1);

    assert.equal((await store.retirePhysicalHolding(
      source.holding_cid,
    )).deleted, true);
    const chunks = [];
    await store.consumePhysicalHolding(
      destination.holding_cid,
      0,
      chunk => chunks.push(Buffer.from(chunk)),
    );
    assert.equal(Buffer.concat(chunks).toString('utf8'), 'sealed');
    assert.equal((await store.retirePhysicalHolding(
      destination.holding_cid,
    )).deleted, true);
    assert.equal(store.status().storedBytes, 0);
  });

test('sealed Transfer reuse rejects a different manifest or object order',
  async t => {
    const {store} = await fixture(t);
    const first = await preparePhysical(store, 'first');
    const second = await preparePhysical(store, 'second');
    const source = physicalHolding(
      digest('ordered source holding'),
      digest('ordered source manifest'),
      [
        {cid: first.cid, byte_count: first.bytes},
        {cid: second.cid, byte_count: second.bytes},
      ],
    );
    await store.commitPhysicalHolding(
      source,
      [first.prepared, second.prepared],
    );
    const differentManifest = physicalHolding(
      digest('different manifest holding'),
      digest('different manifest'),
      source.objects,
    );
    await assert.rejects(
      store.sharePhysicalHolding(source.holding_cid, differentManifest),
      {code: 'PublicationPhysicalHoldingConflict'},
    );
    const reordered = physicalHolding(
      digest('reordered holding'),
      source.manifest_cid,
      [...source.objects].reverse(),
    );
    await assert.rejects(
      store.sharePhysicalHolding(source.holding_cid, reordered),
      {code: 'PublicationPhysicalHoldingConflict'},
    );
    assert.equal(await store.inspectPhysicalHolding(
      differentManifest.holding_cid,
    ), undefined);
    assert.equal(await store.inspectPhysicalHolding(reordered.holding_cid),
      undefined);
  });

test('physical holding retirement waits for the exact active reader',
  async t => {
    const {store} = await fixture(t);
    const prepared = await preparePhysical(store, 'reader');
    const record = physicalHolding(
      digest('transfer holding reader'),
      digest('physical manifest reader'),
      [{cid: prepared.cid, byte_count: prepared.bytes}],
    );
    await store.commitPhysicalHolding(record, [prepared.prepared]);
    let continueRead;
    const blocked = new Promise(resolve => { continueRead = resolve; });
    let reading;
    const started = new Promise(resolve => { reading = resolve; });
    const consume = store.consumePhysicalHolding(
      record.holding_cid,
      0,
      async () => {
        reading();
        await blocked;
      },
    );
    await started;
    const retiring = await store.retirePhysicalHolding(record.holding_cid);
    assert.equal(retiring.deleted, false);
    assert.equal(retiring.cleanup.status().pending, true);
    assert.equal(await store.inspectPhysicalHolding(record.holding_cid),
      undefined);
    continueRead();
    await consume;
    assert.equal((await retiring.cleanup.retry()).pending, false);
    assert.equal(store.status().storedBytes, 0);
  });

test('physical holding retains capacity until unlink durability retry',
  async t => {
    const directory = await mkdtemp(join(
      tmpdir(), 'actql-transfer-holding-durability-',
    ));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const configuration = {
      directory,
      storeAuthorityCid: cids.authority,
      capacityBytes: 1024,
      maxObjectBytes: 512,
      maxObjects: 8,
      maxContractNodes: limits.maxNodes,
      maxContractDepth: limits.maxDepth,
    };
    let objectSyncFailures = 0;
    const durability = Object.freeze({
      async syncDirectory(path) {
        if (path === join(directory, 'objects') && objectSyncFailures > 0) {
          objectSyncFailures--;
          const error = new Error('injected object sync failure');
          error.code = 'EIO';
          throw error;
        }
        const handle = await open(path, 'r');
        try { await handle.sync(); }
        finally { await handle.close(); }
      },
    });
    const store = await openLocalPublicationStore(
      configuration,
      contractControl,
      durability,
    );
    t.after(async () => { await store.close(); });
    const prepared = await preparePhysical(store, 'durable');
    const record = physicalHolding(
      digest('transfer holding durability'),
      digest('physical manifest durability'),
      [{cid: prepared.cid, byte_count: prepared.bytes}],
    );
    await store.commitPhysicalHolding(record, [prepared.prepared]);
    objectSyncFailures = 1;
    const retired = await store.retirePhysicalHolding(record.holding_cid);
    assert.equal(retired.deleted, false);
    assert.equal(retired.cleanup.status().pending, true);
    assert.equal(store.status().storedBytes, 7);
    assert.equal(await store.inspectPhysicalHolding(record.holding_cid),
      undefined);
    const recovered = await retired.cleanup.retry();
    assert.equal(recovered.pending, false);
    assert.equal(recovered.errors.length, 1);
    assert.equal(store.status().storedBytes, 0);
    assert.equal(store.status().objectCount, 0);
  });
