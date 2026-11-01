import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {mkdtemp} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createHash, randomUUID, sign, verify, createPublicKey, generateKeyPairSync} from 'node:crypto';
import test from 'node:test';
import {parse} from 'acorn';
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {createLocalSigningMetadata} from '../host-common/local-signing-metadata.mjs';
import {openSqliteCheckpointJournal} from './sqlite-checkpoint-journal.mjs';
// Focused components may supply their SAME-source canonical debug modules.
// CI/default consumers retain the original normal release module locations.
const checkpointRuntime = await import(process.env.ACTQL_CHECKPOINT_RUNTIME_URL ??
  new URL('../../_build/js/release/build/checkpoint_runtime_node/checkpoint_runtime_node.js', import.meta.url).href);
const credentialRuntime = await import(process.env.ACTQL_SOURCE_CREDENTIAL_RUNTIME_URL ??
  new URL('../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js', import.meta.url).href);

// Execute the exact new coordinator with explicit Checkpoint/initialization
// ports, real SQLite/Ed25519 and the actual selected Credential codec.
// The NEW proof/subject exports below are doubles: this is not a matching new
// Common runtime, an initialized Host/Account or ordinary installed approval.
const source = readFileSync(new URL('./local-checkpoint-answer.mjs', import.meta.url), 'utf8');
const tree = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
const code = tree.body.filter(node => node.type !== 'ImportDeclaration').map(node => {
  const original = node.type === 'ExportNamedDeclaration' ? node.declaration : node;
  return source.slice(original.start, original.end);
}).join('\n') + '\nreturn createLocalCheckpointAnswer;';
const hash = value => 'sha256:' + createHash('sha256').update(canonicalJson(value)).digest('hex');
const cid = digit => 'sha256:' + digit.repeat(64);
const T0 = Date.parse('2026-09-25T10:01:00.000Z');
const ok = value => ({$tag: 1, _0: value});

async function fixture({loseSignatureOutcome = false, deny = false, delayedKey} = {}) {
  const root = await mkdtemp(join(tmpdir(), 'actql-local-answer-counter-'));
  console.log('Fresh original signing fixture KEEP: ' + root);
  let transitions = 0, nativeCalls = 0, current = true, clock = T0;
  const pair = generateKeyPairSync('ed25519');
  const summary = {checkpointId: 'original-cp', checkpointCid: cid('1'), kind: 'effect_set',
    phase: 'commit', subject: {kind: 'run_unit', runId: 'original-run', runDefinitionCid: cid('2')},
    requiredArtifact: {type: 'effect_set_preview', cid: cid('3')}, reviewProjectionCid: cid('4'),
    requirements: ['effect_scope_approved'], createdAt: new Date(T0 - 1000).toISOString(),
    expiresAt: new Date(T0 + 3600000).toISOString(), humanSummary: 'Original'};
  const journal = openSqliteCheckpointJournal(root, {runtime: checkpointRuntime,
    expectedAuthorityScopeCid: cid('5'), authorizeResolution() {assert.fail('No business resolution');},
    attestResolution() {assert.fail('No Host attestation');}, faults: {
      beforeCommit(step) {
        if (step === 'localSigningRecord' && ++transitions === 3 && loseSignatureOutcome) {
          throw new Error('Original saved-signature write failed');
        }
      },
    }});
  const fence = () => {if (!current) throw Object.assign(new Error('Original revoked'), {code: 'OriginalRevoked'});};
  const metadata = createLocalSigningMetadata(credentialRuntime);
  const originalKey = {policyWire: 'original-policy', policyCid: cid('6'),
    initializationIntentCid: cid('7'), adoptionCid: cid('8'), issuer: 'original-initializer',
    sampledAt: BigInt(T0), expiresAt: BigInt(T0 + 300000), maxUses: 1,
    principal: 'original-owner', accountId: 'original-account', keyId: 'original-reviewer',
    reviewerId: 'local-mock', keyGenerationCid: cid('9'), publicKeyCid: cid('a'),
    signingResource: cid('b'), privateKey: pair.privateKey};
  const mockAccount = {reviewer: {resource: originalKey.signingResource},
    async assertSigningCurrent(value) {assert.strictEqual(value, store); await delayedKey?.(); fence();},
    signingOriginal(value, sample) {assert.strictEqual(value, store); assert.equal(sample, BigInt(T0)); fence(); return originalKey;}};
  const store = {};
  const moon = {clientLocalCheckpointProofPrepare(wire, unsigned) {
    assert.equal(wire, 'actual-journal-checkpoint'); return ok(JSON.parse(unsigned));
  }, clientLocalCheckpointProofPreimage: proof => hash(proof),
  clientLocalCheckpointProofActor: proof => proof.actor,
  clientLocalCheckpointProofSeal(proof, keyId, signature) {
    const body = {...proof, proof: {scheme: 'ed25519-v1', key_id: keyId, signature}};
    return ok(canonicalJson({...body, resolution_cid: hash(body)}));
  }, clientLocalCheckpointProofEffectSubject(materials, reference, wire) {
    assert.strictEqual(materials, ownedMaterials); assert.equal(reference, 'original-submission');
    assert.equal(wire, 'actual-journal-checkpoint'); return ok({_0: cid('c'), _1: cid('d')});
  }, clientRequestIntentCid(value) {assert.strictEqual(value, identity); return cid('e');},
  clientRequestScopeCid(value) {assert.strictEqual(value, identity); return cid('f');}};
  const ownedMaterials = {}, identity = {};
  const checkpoints = {journal, async localSigningContext({summary: observed, signingResource}) {
    if (deny) throw Object.assign(new Error('Original Deny'), {code: 'CheckpointAnswerDenied'});
    assert.deepEqual(observed, summary); assert.equal(signingResource, originalKey.signingResource);
    return {wire: 'actual-journal-checkpoint', view: {}, configurationCid: cid('0'), assertCurrent: fence};
  }};
  const loadRunOriginal = async (_view, _signal, consume) => consume({materials: ownedMaterials, referenceWire: 'original-submission',
    requestIdentity: identity, invocation: {identity: cid('a')}, assertCurrent: fence});
  const tracedSign = (...args) => {
    fence(); nativeCalls++;
    const record = JSON.parse(journal.localSigningRecord(hash({checkpoint_cid: summary.checkpointCid,
      purpose: 'reviewer_proof'})));
    assert(Object.values(record.signatures).some(value => value.state === 'claimed'),
      'A confirmed original claim precedes every actual native signature');
    return sign(...args);
  };
  const factory = new Function('createHash', 'randomUUID', 'sign', 'verify', 'createPublicKey',
    'canonicalJson', 'checked', 'runtimeField', code)(createHash, randomUUID, tracedSign,
      verify, createPublicKey, canonicalJson, checked, runtimeField);
  const make = () => factory({moon, checkpoints, mockAccount, store, authorityScopeCid: cid('5'),
    principalId: 'original-owner', metadata, assertCurrent: fence, loadRunOriginal, now: () => clock});
  return {summary, journal, pair, make, calls: () => nativeCalls, revoke() {current = false;},
    expire() {clock = T0 + 300000;}, close() {metadata.retireMetadataView(); journal.close();}};
}

test('same saved Reviewer answer is returned without another physical signature or a new use', async () => {
  const f = await fixture();
  try {
    const first = await f.make()(f.summary, 'approved');
    assert.equal(f.calls(), 2);
    const second = await f.make()(f.summary, 'approved');
    assert.deepEqual(second, first); assert.equal(f.calls(), 2);
    const body = JSON.parse(first.resolutionWire), unsigned = {...body};
    delete unsigned.proof; delete unsigned.resolution_cid;
    assert(verify(null, Buffer.from(hash(unsigned)), f.pair.publicKey,
      Buffer.from(body.proof.signature, 'base64')));
    await assert.rejects(f.make()(f.summary, 'rejected'), {code: 'LocalSigningOriginalConflict'});
    assert.equal(f.calls(), 2);
  } finally {f.close();}
});

test('original signature outcome loss stays claimed across a new coordinator without re-signing', async () => {
  const f = await fixture({loseSignatureOutcome: true});
  try {
    await assert.rejects(f.make()(f.summary, 'approved'), {code: 'LocalSigningUnknown'});
    assert.equal(f.calls(), 1);
    await assert.rejects(f.make()(f.summary, 'approved'), {code: 'LocalSigningUnknown'});
    assert.equal(f.calls(), 1);
  } finally {f.close();}
});

test('a saved signature cannot replace its exact claimed use with another valid metadata use', async () => {
  const f = await fixture();
  try {
    await f.make()(f.summary, 'approved'); assert.equal(f.calls(), 2);
    const operation = hash({checkpoint_cid: f.summary.checkpointCid, purpose: 'reviewer_proof'});
    const wire = f.journal.localSigningRecord(operation), changed = JSON.parse(wire);
    const use = JSON.parse(changed.signatures.resolution.useWire);
    use.use_id = 'another-valid-but-unclaimed-use';
    changed.signatures.resolution.useWire = canonicalJson(use);
    changed.signatures.resolution.useCid = hash(use);
    f.journal.transitionLocalSigningRecord(operation, wire, canonicalJson(changed));
    await assert.rejects(f.make()(f.summary, 'approved'), {code: 'LocalSigningOriginalConflict'});
    assert.equal(f.calls(), 2);
  } finally {f.close();}
});

test('current Deny and expiry do not issue a replacement signing operation', async () => {
  const denied = await fixture({deny: true});
  try {
    await assert.rejects(denied.make()(denied.summary, 'approved'), {code: 'CheckpointAnswerDenied'});
    assert.equal(denied.calls(), 0);
  } finally {denied.close();}
  const f = await fixture();
  try {
    await f.make()(f.summary, 'rejected'); assert.equal(f.calls(), 1);
    f.expire();
    await assert.rejects(f.make()(f.summary, 'rejected'), {code: 'LocalSigningExpired'});
    assert.equal(f.calls(), 1);
  } finally {f.close();}
});

test('revocation during original key observation prevents native use and concurrent answer replacement', async () => {
  let release, entered;
  const pending = new Promise(resolve => {release = resolve;});
  const observed = new Promise(resolve => {entered = resolve;});
  const f = await fixture({delayedKey: async () => {entered(); await pending;}});
  try {
    const answer = f.make(), first = answer(f.summary, 'approved');
    await observed;
    assert.throws(() => answer(f.summary, 'rejected'), {code: 'LocalSigningAlreadyPending'});
    f.revoke(); release();
    await assert.rejects(first, {code: 'OriginalRevoked'}); assert.equal(f.calls(), 0);
  } finally {f.close();}
});
