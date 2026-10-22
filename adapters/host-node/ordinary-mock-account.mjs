import {generateKeyPairSync, createPrivateKey, createPublicKey, randomUUID, randomBytes} from 'node:crypto';
import {mkdir, open, lstat} from 'node:fs/promises';
import {join} from 'node:path';
import {canonicalJson, contentCid, bytesCid} from './local-account-config.mjs';
import {readBoundedConfigurationUtf8} from './source-profile-json.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeField, runtimeTupleFromFields} from '../host-common/compiler-binding.generated.mjs';

const fail = (code, cause) => {throw Object.assign(new Error(code, {cause}), {code});};
const flights = new Map();
const maximum = 1024 * 1024;

// This is the existing Local Host's installation work, under its actual Store
// exclusion. Common owns the limited policy; these files do not create grants
// from a profile name, discovered Project, equal CID or missing saved state.
export function initializeOrdinaryMockAccount(options) {
  const key = options.root;
  if (flights.has(key)) fail('LocalMockInitializationAlreadyPending');
  const flight = Promise.resolve().then(() => initialize(options));
  flights.set(key, flight);
  const settled = () => {if (flights.get(key) === flight) flights.delete(key);};
  flight.then(settled, settled);
  return flight;
}

async function initialize({moon, root, principal, subject, sources, modelTasks, requestTarget,
  updateTarget, explicitSelection, assertExclusiveCurrent, operatorAuthorization}) {
  assertExclusiveCurrent();
  if (operatorAuthorization !== undefined) return undefined;
  const policyOriginal = moon.clientLocalSigningBootstrapOriginal;
  const bootstrapIssue = moon.clientLocalSigningBootstrapIssue;
  const publicKeyOriginal = moon.clientLocalSigningPublicKeyOriginal;
  const profileKnown = moon.clientProgramLocalMockAccountProfileKnown;
  if (typeof profileKnown !== 'function') fail('InvalidHostRuntimeResult');
  const directory = join(root, 'mock-account');
  const intentPath = join(directory, 'initialization.json');
  const receiptPath = join(directory, 'adopted.json');
  const configPath = join(directory, 'account.json');
  const reviewerPath = join(directory, 'reviewer.pem'), hostPath = join(directory, 'host.pem');
  const evidencePath = join(directory, 'continuation.key');
  const profile = moon.clientProgramLocalMockAccountProfile();
  let identity = Object.freeze({id: runtimeField(profile, 0), version: runtimeField(profile, 1),
    cid: runtimeField(profile, 2)});
  if (Object.values(identity).some(value => typeof value !== 'string')) fail('InvalidHostRuntimeResult');
  const subjectCid = contentCid({principal, ...subject});
  async function readOptional(path) {
    assertExclusiveCurrent();
    try {
      const info = await lstat(path);
      if (!info.isFile() || info.isSymbolicLink() || (info.mode & 0o077) !== 0) fail('LocalMockInitializationExposed');
      const wire = await readBoundedConfigurationUtf8(path, {maxBytes: maximum});
      assertExclusiveCurrent(); return wire;
    } catch (cause) {if (cause?.code === 'ENOENT') return undefined; throw cause;}
  }
  async function closeOriginal(handle, primary, failed) {
    const originalClose = handle.close;
    try {if (await Reflect.apply(originalClose, handle, []) === false) fail('LocalMockInitializationCleanupPending');}
    catch (cause) {
      let held = handle, flight;
      const status = () => Object.freeze({pending: held !== undefined});
      const cleanupHandle = Object.freeze({status, retry() {
        if (held === undefined) return Promise.resolve(status());
        if (flight !== undefined) return flight;
        const work = Promise.resolve().then(async () => {
          if (await Reflect.apply(originalClose, held, []) === false) fail('LocalMockInitializationCleanupPending');
          held = undefined; return status();
        });
        flight = work;
        work.then(() => {flight = undefined;}, () => {flight = undefined;});
        return work;
      }});
      throw Object.assign(new Error('LocalMockInitializationCleanupPending', {cause: failed ? primary : cause}),
        {code: 'LocalMockInitializationCleanupPending', cleanupPending: true, cleanupHandle});
    }
    if (failed) throw primary;
  }
  async function syncDirectory() {
    const handle = await open(directory, 'r');
    let primary, failed = false;
    try {assertExclusiveCurrent(); await handle.sync(); assertExclusiveCurrent();}
    catch (cause) {primary = cause; failed = true;}
    await closeOriginal(handle, primary, failed);
  }
  async function createOriginal(path, wire) {
    assertExclusiveCurrent();
    let handle;
    try {handle = await open(path, 'wx', 0o600);}
    catch (cause) {
      if (cause?.code !== 'EEXIST') throw cause;
      if (await readOptional(path) !== wire) fail('LocalMockInitializationConflict');
      return;
    }
    let primary, failed = false;
    try {assertExclusiveCurrent(); await handle.writeFile(wire, 'utf8'); await handle.sync(); assertExclusiveCurrent();}
    catch (cause) {primary = cause; failed = true;}
    await closeOriginal(handle, primary, failed);
    await syncDirectory();
  }
  function parse(wire) {
    try {return JSON.parse(wire);} catch (cause) {fail('LocalMockInitializationInvalid', cause);}
  }
  let intentWire = await readOptional(intentPath);
  let adoptedWire = await readOptional(receiptPath), adoptionFlight;
  if (intentWire === undefined) {
    if (adoptedWire !== undefined) fail('LocalMockAdoptedStateMissing');
    if (!explicitSelection) fail('LocalMockInitializationConsentRequired');
    try {await lstat(directory); fail('LocalMockInitializationConflict');}
    catch (cause) {if (cause?.code !== 'ENOENT') throw cause;}
    await mkdir(directory, {mode: 0o700});
    assertExclusiveCurrent();
    const reviewer = generateKeyPairSync('ed25519'), host = generateKeyPairSync('ed25519');
    const reviewerPem = reviewer.privateKey.export({type: 'pkcs8', format: 'pem'});
    const hostPem = host.privateKey.export({type: 'pkcs8', format: 'pem'});
    const reviewerPublic = reviewer.publicKey.export({type: 'spki', format: 'pem'});
    const reviewerResource = bytesCid(Buffer.from(reviewerPublic));
    const accountId = 'local-mock-' + randomUUID();
    const configuration = checked(moon.clientProgramLocalMockAccountConfiguration(accountId, principal,
      'local-mock', sources.map(runtimeTupleFromFields), modelTasks,
      requestTarget === undefined ? undefined : runtimeTupleFromFields(requestTarget),
      updateTarget === undefined ? undefined : runtimeTupleFromFields(updateTarget), reviewerResource));
    if (typeof configuration !== 'string') fail('InvalidHostRuntimeResult');
    // The private, owner-only intent is also the original durable key record.
    // Recovery copies THESE exact purpose-confined originals, never generates
    // replacement keys after an interrupted external-file creation.
    let signingPolicy, signingPublicKey;
    if (typeof policyOriginal === 'function' && typeof bootstrapIssue === 'function' &&
        typeof publicKeyOriginal === 'function') {
      const original = Reflect.apply(policyOriginal, moon, []);
      signingPolicy = {wire: runtimeField(original, 0), cid: runtimeField(original, 1)};
      const raw32 = Buffer.from(reviewer.publicKey.export({format: 'jwk'}).x, 'base64url');
      const key = checked(Reflect.apply(publicKeyOriginal, moon, [raw32]));
      signingPublicKey = {wire: runtimeField(key, 0), cid: runtimeField(key, 1)};
      if (typeof signingPolicy.wire !== 'string' || typeof signingPolicy.cid !== 'string') {
        fail('InvalidHostRuntimeResult');
      }
    }
    intentWire = canonicalJson({attempt: randomUUID(), profile: identity, subjectCid, accountId,
      configuration, configurationCid: contentCid(parse(configuration)), reviewerResource,
      reviewerPem, hostPem, evidence: randomBytes(32).toString('base64'), signingPolicy, signingPublicKey});
    await createOriginal(intentPath, intentWire);
  }
  const intent = parse(intentWire);
  if (intent.subjectCid !== subjectCid || intent.profile === null || typeof intent.profile !== 'object' ||
      Array.isArray(intent.profile) || Object.keys(intent.profile).sort().join('\0') !== 'cid\0id\0version' ||
      ![intent.profile.id, intent.profile.version, intent.profile.cid].every(value => typeof value === 'string') ||
      Reflect.apply(profileKnown, moon, [intent.profile.id, intent.profile.version, intent.profile.cid]) !== true ||
      typeof intent.attempt !== 'string' || typeof intent.configuration !== 'string' ||
      contentCid(parse(intent.configuration)) !== intent.configurationCid) fail('LocalMockInstallationChanged');
  // A known predecessor keeps its original adopted configuration and receipt.
  // This is neither migration nor permission to initialize missing saved state.
  identity = Object.freeze({...intent.profile});
  const receiptFields = {attempt: intent.attempt, subjectCid,
    profile: identity, configurationCid: intent.configurationCid,
    reviewerResource: intent.reviewerResource, intentCid: bytesCid(Buffer.from(intentWire))};
  const storeContractPath = join(root, 'publication', 'store.json');
  if (adoptedWire !== undefined) {
    const storeWire = await readOptional(storeContractPath);
    if (storeWire === undefined) fail('LocalMockAdoptedStateMissing');
    if (adoptedWire !== canonicalJson({...receiptFields, storeContractCid: bytesCid(Buffer.from(storeWire))})) {
      fail('LocalMockInstallationChanged');
    }
  }
  const expected = [[hostPath, intent.hostPem], [evidencePath, intent.evidence]];
  if (adoptedWire === undefined) {
    // An unfinished intent may finish only its own exclusive file creation.
    // Existing operator files are neither overwritten nor merged.
    await createOriginal(configPath, intent.configuration);
    for (const [path, wire] of [[reviewerPath, intent.reviewerPem], ...expected]) await createOriginal(path, wire);
  }
  for (const [path, wire] of expected) {
    if (await readOptional(path) !== wire) fail('LocalMockAdoptedStateMissing');
  }
  // An adopted Reviewer may be unavailable without invalidating independently
  // admitted Account reads. Never recover that capability from the intent's
  // key bytes: only the actual, unchanged Reviewer file can supply it.
  const reviewerPem = await readOptional(reviewerPath);
  if (reviewerPem !== undefined && reviewerPem !== intent.reviewerPem) fail('LocalMockAdoptedStateMissing');
  const currentConfiguration = await readOptional(configPath);
  if (currentConfiguration === undefined) fail('LocalMockAdoptedStateMissing');
  // Original generated bytes establish provenance. Current operator Account
  // configuration, including Deny/restriction, is admitted again by Common.
  const account = parse(currentConfiguration);
  if (account.account_id !== intent.accountId) fail('LocalMockInstallationChanged');
  moon.executionAuthorizationAdmit(currentConfiguration);
  const reviewerKey = reviewerPem === undefined ? undefined : createPrivateKey(reviewerPem);
  const hostKey = createPrivateKey(intent.hostPem);
  let publicKey = reviewerKey === undefined ? undefined : createPublicKey(reviewerKey).export({type: 'spki', format: 'pem'});
  if (reviewerKey === undefined && intent.signingPublicKey !== undefined) {
    // The adopted intent/receipt can retain verification without a private
    // Reviewer. Re-admit its exact public bytes through the existing Common
    // Owner; the saved private PEM is never used to reconstruct this view.
    const saved = intent.signingPublicKey;
    if (typeof saved?.wire !== 'string' || typeof saved?.cid !== 'string' ||
        typeof publicKeyOriginal !== 'function') fail('LocalMockInstallationChanged');
    const body = parse(saved.wire);
    if (typeof body?.public_key !== 'string') fail('LocalMockInstallationChanged');
    const raw32 = Buffer.from(body.public_key, 'base64');
    const original = checked(Reflect.apply(publicKeyOriginal, moon, [raw32]));
    if (saved.wire !== runtimeField(original, 0) || saved.cid !== runtimeField(original, 1)) {
      fail('LocalMockInstallationChanged');
    }
    publicKey = createPublicKey({key: {kty: 'OKP', crv: 'Ed25519', x: raw32.toString('base64url')},
      format: 'jwk'}).export({type: 'spki', format: 'pem'});
  }
  if (publicKey !== undefined && bytesCid(Buffer.from(publicKey)) !== intent.reviewerResource) fail('LocalMockInstallationChanged');
  const evidence = Buffer.from(intent.evidence, 'base64');
  if (evidence.length !== 32) fail('LocalMockInstallationChanged');
  assertExclusiveCurrent();
  let adoptedStore, adoptedStoreStatus;
  return Object.freeze({profile: identity, subjectCid, configurationPath: configPath,
    adoptStore(store) {
      if (adoptionFlight !== undefined) return adoptionFlight;
      const status = store.status;
      if (typeof status !== 'function' || Reflect.apply(status, store, []).closed !== false) {
        fail('LocalMockInstallationChanged');
      }
      // Adoption follows the actual Store constructor, never merely key/config
      // creation. Its missing saved format cannot be treated as fresh setup.
      adoptionFlight = Promise.resolve().then(async () => {
        assertExclusiveCurrent();
        const storeWire = await readOptional(storeContractPath);
        if (storeWire === undefined || Reflect.apply(status, store, []).closed !== false) {
          fail('LocalMockAdoptedStateMissing');
        }
        const receipt = canonicalJson({...receiptFields, storeContractCid: bytesCid(Buffer.from(storeWire))});
        if (adoptedWire !== undefined && receipt !== adoptedWire) fail('LocalMockInstallationChanged');
        await createOriginal(receiptPath, receipt);
        adoptedWire = receipt;
        adoptedStore = store;
        adoptedStoreStatus = status;
      });
      return adoptionFlight;
    },
    async assertSigningCurrent(store) {
      assertExclusiveCurrent();
      if (store !== adoptedStore || adoptedWire === undefined ||
          Reflect.apply(adoptedStoreStatus, store, []).closed !== false ||
          await readOptional(intentPath) !== intentWire ||
          await readOptional(receiptPath) !== adoptedWire) fail('LocalMockInstallationChanged');
      for (const [path, wire] of expected) {
        if (await readOptional(path) !== wire) fail('LocalMockAdoptedStateMissing');
      }
      const currentReviewerPem = await readOptional(reviewerPath);
      if (reviewerKey === undefined || currentReviewerPem === undefined) fail('CheckpointSignerUnavailable');
      if (currentReviewerPem !== reviewerPem) fail('LocalMockAdoptedStateMissing');
      const storeWire = await readOptional(storeContractPath);
      if (storeWire === undefined || adoptedWire !== canonicalJson({...receiptFields,
        storeContractCid: bytesCid(Buffer.from(storeWire))})) fail('LocalMockInstallationChanged');
      assertExclusiveCurrent();
      if (Reflect.apply(adoptedStoreStatus, store, []).closed !== false) fail('LocalMockInstallationChanged');
    },
    // This closure belongs to the actual initializer and SAME adopted Store.
    // Saved policy absence is not repaired from the packaged getter on cold
    // open. The candidate is DATA; the Checkpoint owner must still authenticate
    // its original subject/current authority and durably claim before signing.
    signingOriginal(store, sampledAt, validUntil) {
      assertExclusiveCurrent();
      if (store !== adoptedStore || adoptedWire === undefined ||
          reviewerKey === undefined ||
          intent.signingPolicy === undefined || intent.signingPublicKey === undefined ||
          typeof bootstrapIssue !== 'function' || typeof publicKeyOriginal !== 'function') {
        fail('CheckpointSignerUnavailable');
      }
      const raw32 = Buffer.from(createPublicKey(reviewerKey).export({format: 'jwk'}).x, 'base64url');
      const key = checked(Reflect.apply(publicKeyOriginal, moon, [raw32]));
      if (intent.signingPublicKey.wire !== runtimeField(key, 0) ||
          intent.signingPublicKey.cid !== runtimeField(key, 1)) fail('LocalMockInstallationChanged');
      const intentCid = bytesCid(Buffer.from(intentWire));
      const issue = checked(Reflect.apply(bootstrapIssue, moon, [
        intent.signingPolicy.wire, intent.signingPolicy.cid, intentCid, sampledAt, validUntil]));
      return Object.freeze({policyWire: intent.signingPolicy.wire, policyCid: intent.signingPolicy.cid,
        initializationIntentCid: intentCid, adoptionCid: bytesCid(Buffer.from(adoptedWire)),
        issuer: runtimeField(issue, 0), sampledAt: runtimeField(issue, 1),
        expiresAt: runtimeField(issue, 2), maxUses: runtimeField(issue, 3),
        principal, accountId: intent.accountId, keyId: 'local-mock-reviewer',
        reviewerId: 'local-mock', keyGenerationCid: bytesCid(Buffer.from(intent.reviewerPem)),
        publicKeyCid: intent.signingPublicKey.cid, signingResource: intent.reviewerResource,
        privateKey: reviewerKey});
    },
    // The original control connection is independent of signing capability.
    authorization: Object.freeze(publicKey === undefined ? {accountConfig: configPath, siteKey: 'local-mock'} : {accountConfig: configPath, siteKey: 'local-mock',
      reviewers: Object.freeze([Object.freeze({keyId: 'local-mock-reviewer', reviewerId: 'local-mock',
        principalId: principal, publicKey})]), reviewReaders: Object.freeze([principal]),
      // Existing Checkpoint construction admits PKCS8 input itself. Preserve
      // that API instead of passing a KeyObject to createPrivateKey again.
      hostKey: Object.freeze({keyId: 'local-mock-host', privateKey: intent.hostPem})}),
    // These actual private keys remain inside the Host; selection is not an
    // approval/signature, and no Client-facing arbitrary signing port exists.
    reviewer: reviewerKey === undefined ? undefined : Object.freeze({keyId: 'local-mock-reviewer', privateKey: reviewerKey,
      resource: intent.reviewerResource}),
    evidenceKey: Object.freeze({key: evidence, keyId: bytesCid(evidence)})});
}
