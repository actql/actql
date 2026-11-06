// Actual Store/crypto/holding retirement. The existing portable contract
// control is explicit; this does not qualify Request resource admission.
import assert from 'node:assert/strict';
import test from 'node:test';
import crypto, {createHash} from 'node:crypto';
import {syncBuiltinESMExports} from 'node:module';
import {mkdtemp} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {openLocalPublicationStore} from './publication-store.mjs';
import {createPublicationContractControlFixture} from
  '../host-common/publication-contract-control.fixture.mjs';
import {recoverCompletedEffectfulComputation} from
  '../host-common/completed-run-publication.mjs';
import {prepareEffectCaptureResources} from '../host-node/effect-capture-resources.mjs';

const cid = text => `sha256:${createHash('sha256').update(text).digest('hex')}`;
async function fixture(t, originalWire) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-c-private-consumer-'));
  const store = await openLocalPublicationStore({directory,
    storeAuthorityCid: cid('consumer authority'), privateEvidenceKey: Buffer.alloc(32, 7),
    capacityBytes: 1048576, maxObjectBytes: 16384, maxObjects: 32,
    maxContractNodes: 4096, maxContractDepth: 64}, createPublicationContractControlFixture());
  t.after(async () => {
    assert.equal(await store.close(), true);
    t.diagnostic(`Original fixture retained: ${directory}`);
  });
  const name = 'effect_capture', semantic = cid('original capture'), holding = cid('original holding');
  const wire = originalWire ?? '{"value":"e\u0301\\r\\n","items":[1,null]}';
  const object = await store.preparePrivateEvidence(name, wire, semantic);
  await store.commitPhysicalHolding({version: 'actql-local-physical-holding/0.1',
    namespace: 'publication-private', holding_cid: holding, manifest_cid: semantic,
    objects: [{cid: object.physicalCid, byte_count: object.bytes}]}, [object.prepared]);
  return {store, name, semantic, holding, wire};
}

test('same private holding stays retained through the actual asynchronous decode consumer', async t => {
  const f = await fixture(t);
  let enter, resume, plaintext;
  const entered = new Promise(resolve => {enter = resolve;});
  const gate = new Promise(resolve => {resume = resolve;});
  const operation = f.store.readPrivateEvidence(f.name, f.semantic, f.holding, async bytes => {
    plaintext = bytes;
    assert.equal(bytes.toString('utf8'), f.wire);
    enter();
    await gate;
    return JSON.parse(bytes.toString('utf8'));
  });
  // Old read returns bytes and never invokes the actual consumer.
  const observed = await Promise.race([entered.then(() => 'entered'), operation.then(() => 'returned')]);
  assert.equal(observed, 'entered');
  try {
    const retiring = await f.store.retirePhysicalHolding(f.holding);
    assert.equal(retiring.cleanup.status().pending, true);
    assert.equal(plaintext.toString('utf8'), f.wire);
    resume();
    assert.deepEqual(await operation, {value: 'e\u0301\r\n', items: [1, null]});
    assert.deepEqual(plaintext, Buffer.alloc(plaintext.length));
    assert.equal((await retiring.cleanup.retry()).pending, false);
  } finally {resume(); await operation.catch(() => {});}
});

test('failed private decode preserves the original cause and retires only its temporary plaintext', async t => {
  const f = await fixture(t), cause = new Error('original typed admission');
  let plaintext, calls = 0;
  await assert.rejects(f.store.readPrivateEvidence(f.name, f.semantic, f.holding, async bytes => {
    calls++; plaintext = bytes;
    await Promise.resolve();
    throw cause;
  }), error => error === cause);
  assert.equal(calls, 1);
  assert.deepEqual(plaintext, Buffer.alloc(plaintext.length));
  assert.notEqual(await f.store.inspectPhysicalHolding(f.holding), undefined);
  assert.equal((await f.store.retirePhysicalHolding(f.holding)).cleanup.status().pending, false);
});

function captureOptions(f, cause) {
  const run = {name: 'run_definition', wire: 'original run', identity: cid('original run')};
  let plaintext, consumers = 0;
  const store = {...f.store,
    readPrivateEvidence(name, semantic, holding, consume, beforeRead) {
      if (consume === undefined) return f.store.readPrivateEvidence(name, semantic, holding);
      return f.store.readPrivateEvidence(name, semantic, holding, (bytes, read) => {
        plaintext = bytes; consumers++;
        return consume(bytes, read);
      }, beforeRead);
    }};
  const control = {
    admit(name, wire) {
      if (name === run.name && wire === run.wire) return run;
      throw cause;
    },
    effectComputationCaptureHoldingCid: () => cid('capture holding'),
    effectComputationRecordHoldingCid: () => f.holding,
  };
  // Explicit original Core ports; the selected failure stops before these
  // semantic issuers. No fake successful chain or Resource grant is supplied.
  for (const name of ['admitRunEvidence', 'admitEffectComputationPreview',
    'admitCapturedEffectSourceFromCapture', 'capturedEffectSourceHoldingCid',
    'capturedEffectSourceArtifactCid', 'effectfulComputationEvidenceChainValid',
    'capturedEffectSourceInventoryFromCaptureValid', 'capturedEffectDependencySchemas']) {
    control[name] = () => {throw new Error(`unexpected ${name}`);};
  }
  return {options: {store, control, runDefinition: run,
    contractLimits: {maxWireBytes: 16384, maxNodes: 4096, maxDepth: 64}},
  assertReleased() {
    assert.equal(consumers, 1, 'actual recovery must use the same scoped Store consumer');
    assert.deepEqual(plaintext, Buffer.alloc(plaintext.length));
  }};
}

test('actual recovery reservation refusal precedes ciphertext allocation and preserves original cause', async t => {
  const f = await fixture(t), c = captureOptions(f, new Error('unexpected typed admission'));
  const original = new Error('same Request capacity refusal');
  const events = []; let decrypts = 0;
  const createDecipheriv = crypto.createDecipheriv;
  crypto.createDecipheriv = (...args) => {decrypts++; return Reflect.apply(createDecipheriv, crypto, args);};
  syncBuiltinESMExports();
  try {
    await assert.rejects(recoverCompletedEffectfulComputation(c.options, {
      begin() {events.push('begin');},
      reserve(bytes) {assert.ok(Number.isSafeInteger(bytes) && bytes > 0); events.push('reserve'); throw original;},
      finish(failed, cause) {
        assert.equal(failed, true); assert.equal(cause.cause, original); events.push('finish');
      },
      retainCleanup() {assert.fail('No typed/schema owner before reservation');},
    }), error => error.code === 'InvalidCompletedEffectfulCaptureRecord' && error.cause === original);
    assert.deepEqual(events, ['begin','reserve','finish']); assert.equal(decrypts, 0);
    assert.notEqual(await f.store.inspectPhysicalHolding(f.holding), undefined);
  } finally {
    crypto.createDecipheriv = createDecipheriv; syncBuiltinESMExports();
  }
});

test('actual decoded capture retains SAME schema cleanup and reservation through failed release', async t => {
  const capturedCid = cid('original capture'), captureCid = cid('zero payload capture');
  const run = {name:'run_definition', identity:cid('original run'), wire:'original run'};
  const body = {version:'actql-completed-effectful-capture/0.1',
    store_authority_cid:cid('consumer authority'), run_definition:run.wire,
    invocation:'invocation', definitions:[], artifacts:[], derivations:[], orderings:[], retentions:[],
    durable_bindings:[], result_schemas:[], manifest:'manifest', computation_receipt:'receipt',
    captured_run:'captured', preview:'preview', authoring_context:'authoring',
    effect_source_artifacts:[], connector_recovery:[], effect_dependency_payloads:[]};
  const f = await fixture(t, JSON.stringify(body));
  await f.store.commitPhysicalHolding({version:'actql-local-physical-holding/0.1',
    namespace:'effect-capture', holding_cid:captureCid, manifest_cid:capturedCid, objects:[]}, []);
  let pending = true, releases = 0, retries = 0, retired = 0, resource, reserves = 0, completed = 0;
  const original = new Error('original schema release');
  const schema = {prepared:{status:() => ({pending}),
    async release() {releases++; throw original;},
    async retry() {retries++; pending = false; return {pending};}}};
  const store = {...f.store,
    async putPreparedResultSchema(wire, identity, definition) {
      assert.equal(wire, 'original schema'); assert.equal(identity, cid('schema'));
      assert.equal(definition, run.identity); return schema;
    }};
  const control = {
    admit(name, wire) {return name === 'run_definition' ? run
      : {name, wire, identity:name === 'captured_run' ? capturedCid : cid(name)};},
    admitRunEvidence:() => ({}), admitEffectComputationPreview:() => ({}),
    effectComputationCaptureHoldingCid:() => captureCid,
    effectComputationRecordHoldingCid:() => f.holding,
    effectfulComputationEvidenceChainValid:() => true,
    capturedEffectSourceInventoryFromCaptureValid:() => true,
    admitCapturedEffectSourceFromCapture:assert.fail, capturedEffectSourceHoldingCid:assert.fail,
    capturedEffectSourceArtifactCid:assert.fail,
    capturedEffectDependencyPayloadBindings:() => [],
    capturedEffectDependencySchemas:() => [{wire:'original schema', cid:cid('schema')}],
    publicationPreparedReleaseAction(index, _count, inspected, isPending, attempted) {
      return index < 0 ? 'finished' : !inspected ? 'inspect' : isPending && !attempted ? 'release' : 'advance';
    },
    publicationCleanupOwnerAction(index, count, inspected, isPending, available, attempted) {
      return index >= count ? 'finished' : !inspected ? 'inspect'
        : isPending && available && !attempted ? 'retry' : 'advance';
    },
    reserveEffectCaptureRecovery:assert.fail,
  };
  const originalDefinition = {}, recovery = {}, moon = {clientProgramPrepareInstalledEffectCaptureRecovery(
    _run, _prepared, _request, definition) {
    assert.equal(definition, originalDefinition); return {$tag:1, _0:recovery};
  }, clientProgramReserveInstalledEffectCaptureRecovery(_value, bytes) {
    assert.equal(_value,recovery);assert.ok(bytes > 0); reserves++; return {$tag:1, _0:undefined};
  }, clientProgramCompleteInstalledEffectCaptureRecovery(value) {
    assert.equal(value,recovery);assert.equal(reserves,1);assert.equal(retired,0);
    completed++;return {$tag:1, _0:undefined};
  }, clientProgramRetireInstalledEffectCaptureRecovery(value) {
    assert.equal(value,recovery);
    assert.equal(pending, false); retired++; return {$tag:1, _0:undefined};
  }};
  const limits = {maxWireBytes:16384, maxNodes:4096, maxDepth:64};
  const resources = prepareEffectCaptureResources({moon, control, request:{}, runDefinition:run,
    contractLimits:limits, managed:{value:{},prepared:{},request:{}, definitionOriginal:{definition:originalDefinition}}, assertCurrent() {},
    retain(originalView) {resource = originalView;}});
  assert.equal(resources, resource);
  const recovered = await recoverCompletedEffectfulComputation({store, control, runDefinition:run,
    contractLimits:limits}, resources);
  assert.equal(recovered.storedResults.results.length, 0); assert.equal(reserves, 1); assert.equal(retired, 0);
  assert.equal(completed,1);
  await assert.rejects(resources.close(), error => error.cleanupPending === true && error.cleanupHandle.status().pending);
  assert.equal(releases, 1); assert.equal(retired, 0);
  assert.equal(await resources.close(), true); assert.equal(retries, 1); assert.equal(retired, 1);
  assert.equal(await resources.close(), true); assert.equal(releases, 1); assert.equal(retries, 1);
  assert.equal(completed,1);
  assert.notEqual(await f.store.inspectPhysicalHolding(f.holding), undefined);
  assert.notEqual(await f.store.inspectPhysicalHolding(captureCid), undefined);
});

test('later same private confirmation retires its original temporary plaintext after directory ACK', async t => {
  const f = await fixture(t); let plaintext;
  const createDecipheriv = crypto.createDecipheriv;
  crypto.createDecipheriv = (...args) => {
    const decipher = Reflect.apply(createDecipheriv, crypto, args), update = decipher.update;
    decipher.update = function(...input) {
      plaintext = Reflect.apply(update, this, input); return plaintext;
    };
    return decipher;
  };
  syncBuiltinESMExports();
  try {
    const record = await f.store.confirmPrivateEvidence({name:f.name,
      semanticCid:f.semantic, holdingCid:f.holding, wire:f.wire});
    assert.equal(record.holding_cid, f.holding); assert.ok(plaintext.length > 0);
    assert.deepEqual(plaintext, Buffer.alloc(plaintext.length));
  } finally {
    crypto.createDecipheriv = createDecipheriv; syncBuiltinESMExports();
  }
});

test('capture recovery keeps the typed-admission failure on its original consumer', async t => {
  const runWire = 'original run';
  const f = await fixture(t, JSON.stringify({
    version: 'actql-completed-effectful-capture/0.1',
    store_authority_cid: cid('consumer authority'), run_definition: runWire,
    invocation: 'invocation', definitions: ['definition'], artifacts: [],
    derivations: [], orderings: [], retentions: [], durable_bindings: [], result_schemas: [],
    manifest: 'manifest', computation_receipt: 'receipt', captured_run: 'captured',
    preview: 'preview', authoring_context: 'authoring', effect_source_artifacts: [],
    connector_recovery: [], effect_dependency_payloads: [],
  }));
  const cause = new Error('original typed definition failure'), c = captureOptions(f, cause);
  await assert.rejects(recoverCompletedEffectfulComputation(c.options), error => error === cause);
  c.assertReleased();
  assert.notEqual(await f.store.inspectPhysicalHolding(f.holding), undefined);
});

test('capture recovery keeps malformed JSON refusal inside the same temporary plaintext lifetime', async t => {
  const f = await fixture(t, '{'), c = captureOptions(f, new Error('unexpected admission'));
  await assert.rejects(recoverCompletedEffectfulComputation(c.options), error =>
    error.code === 'InvalidCompletedEffectfulCaptureRecord' && error.cause instanceof SyntaxError);
  c.assertReleased();
  assert.equal((await f.store.retirePhysicalHolding(f.holding)).cleanup.status().pending, false);
});


test('authentication failure clears the same unauthenticated plaintext before rejection', async t => {
  const f = await fixture(t), original = crypto.createDecipheriv;
  let plaintext;
  const cause = new Error('original authentication failure');
  crypto.createDecipheriv = (...args) => {
    const decipher = Reflect.apply(original, crypto, args), update = decipher.update;
    decipher.update = function(...input) {
      plaintext = Reflect.apply(update, this, input);
      return plaintext;
    };
    decipher.final = () => {throw cause;};
    return decipher;
  };
  syncBuiltinESMExports();
  try {
    let consumed = false;
    await assert.rejects(f.store.readPrivateEvidence(f.name, f.semantic, f.holding, () => {
      consumed = true;
    }), error => error.code === 'PublicationPrivateEvidenceCorrupt' && error.cause === cause);
    assert.equal(consumed, false);
    assert.notEqual(plaintext, undefined);
    assert.deepEqual(plaintext, Buffer.alloc(plaintext.length));
    assert.notEqual(await f.store.inspectPhysicalHolding(f.holding), undefined);
  } finally {crypto.createDecipheriv = original; syncBuiltinESMExports();}
});


test('capture recovery captures original service and Core ports before the private read awaits', async t => {
  const f = await fixture(t, JSON.stringify({
    version: 'actql-completed-effectful-capture/0.1',
    store_authority_cid: cid('consumer authority'), run_definition: 'original run',
    invocation: 'invocation', definitions: ['definition'], artifacts: [], derivations: [],
    orderings: [], retentions: [], durable_bindings: [], result_schemas: [],
    manifest: 'manifest', computation_receipt: 'receipt', captured_run: 'captured',
    preview: 'preview', authoring_context: 'authoring', effect_source_artifacts: [],
    connector_recovery: [], effect_dependency_payloads: [],
  }));
  const cause = new Error('same original typed cause'), c = captureOptions(f, cause);
  const read = c.options.store.readPrivateEvidence;
  c.options.store.readPrivateEvidence = (...args) => {
    c.options.store = {};
    c.options.control = {admit() {throw new Error('foreign replacement');}};
    c.options.contractLimits = {};
    return read(...args);
  };
  await assert.rejects(recoverCompletedEffectfulComputation(c.options), error => error === cause);
  c.assertReleased();
});

test('capture recovery refuses an old reader that ignores the original decode consumer', async t => {
  const f = await fixture(t, '{}'), c = captureOptions(f, new Error('must not admit'));
  c.options.store.readPrivateEvidence = (name, semantic, holding) =>
    f.store.readPrivateEvidence(name, semantic, holding);
  await assert.rejects(recoverCompletedEffectfulComputation(c.options),
    {code: 'InvalidCompletedEffectfulCaptureRecord'});
  assert.notEqual(await f.store.inspectPhysicalHolding(f.holding), undefined);
});


test('same authenticated private read confirms without a second decrypt or wire construction', async t => {
  const f = await fixture(t), original = crypto.createDecipheriv;
  let decrypts = 0, escaped, plaintext;
  crypto.createDecipheriv = (...args) => {decrypts++; return Reflect.apply(original, crypto, args);};
  syncBuiltinESMExports();
  try {
    const result = await f.store.readPrivateEvidence(f.name, f.semantic, f.holding, async (bytes, read) => {
      plaintext = bytes; escaped = read;
      const wire = read.releaseBytes();
      assert.equal(wire, f.wire);
      assert.equal(read.releaseBytes(), wire, 'the same String is reused');
      assert.deepEqual(plaintext, Buffer.alloc(plaintext.length));
      const binding = {name: f.name, semanticCid: f.semantic, holdingCid: f.holding, wire};
      assert.equal((await read.confirm(binding)).holding_cid, f.holding);
      await assert.rejects(async () => read.confirm({...binding, wire: wire + ' '}),
        {code: 'PublicationPrivateEvidenceConflict'});
      return JSON.parse(wire);
    });
    assert.deepEqual(result, {value: 'e\u0301\r\n', items: [1, null]});
    assert.equal(decrypts, 1);
    assert.throws(() => escaped.releaseBytes(), {code: 'PublicationPrivateEvidenceUnavailable'});
    assert.throws(() => escaped.confirm({}), {code: 'PublicationPrivateEvidenceUnavailable'});
  } finally {crypto.createDecipheriv = original; syncBuiltinESMExports();}
});

test('original private-read admission refuses before ciphertext allocation and decrypt', async t => {
  const f = await fixture(t), original = crypto.createDecipheriv;
  let decrypts = 0, consumers = 0, admissions = 0;
  const cause = new Error('same original reservation refusal');
  crypto.createDecipheriv = (...args) => {decrypts++; return Reflect.apply(original, crypto, args);};
  syncBuiltinESMExports();
  try {
    await assert.rejects(f.store.readPrivateEvidence(f.name, f.semantic, f.holding,
      () => {consumers++;}, bytes => {
        admissions++;
        assert(Number.isSafeInteger(bytes) && bytes > 0);
        throw cause;
      }), error => error === cause);
    assert.equal(admissions, 1);
    assert.equal(decrypts, 0);
    assert.equal(consumers, 0);
    assert.notEqual(await f.store.inspectPhysicalHolding(f.holding), undefined);
  } finally {crypto.createDecipheriv = original; syncBuiltinESMExports();}
});
