import {generateKeyPairSync, createPrivateKey, createPublicKey, randomUUID, randomBytes} from 'node:crypto';
import {mkdir, open, lstat} from 'node:fs/promises';
import {join} from 'node:path';
import {canonicalJson, contentCid, bytesCid} from './local-account-config.mjs';
import {readBoundedConfigurationUtf8} from './source-profile-json.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {isAccountConstruction, readAccountOriginal} from './account-construction.mjs';
import {runtimeField, runtimeTupleFromFields} from '../host-common/compiler-binding.generated.mjs';

const fail = (code, cause) => {throw Object.assign(new Error(code, {cause}), {code});};
const flights = new Map();
const maximum = 1024 * 1024;

// The trusted installed caller supplies its SAME retained catalog originals.
// Full declaration/configuration wires are hash inputs, not subject members.
// Quote the actual returned forest separately from one synchronous hash's
// Buffer scratch; the existing Account Read keeps all failed-prefix debt.
export function prepareOrdinaryMockAccountSubjects(frame, bundle, originalTasks,
  projectDirectory, configurationWire, requestRealization) {
  let units = BigInt(projectDirectory.length + requestRealization.length + 256 + 71);
  let nodes = 64n + 2n * BigInt(originalTasks.length);
  for (const entry of bundle.sources) {
    units += BigInt(71 + entry.catalogue.connection.length + entry.catalogue.registration.length);
    nodes += 8n;
    for (const view of entry.catalogue.views) {
      units += BigInt(entry.catalogue.connection.length + view.resource.length);nodes += 4n;
    }
  }
  for (const entry of originalTasks) units += BigInt(entry.taskCid.length);
  for (const target of bundle.writables) {
    units += BigInt(128 + target.source.catalogue.connection.length + target.write.resource.length);
    nodes += 24n + 2n * BigInt(target.physical.itemsPath.length + target.physical.keyPath.length);
    if (bundle.writables.length > 1) {
      units += BigInt(71 + target.physical.primaryIdentity.length);
      for (const part of target.physical.itemsPath) units += BigInt(part.length);
      for (const part of target.physical.keyPath) units += BigInt(part.length);
    }
  }
  // This includes the subject, source/update tuples and original path/task
  // references. It does not charge a second retained copy of borrowed wires.
  frame.record(units, nodes, 8n);
  const hashOriginal = value => {
    // Buffer.from and digest are synchronous. Each Buffer dies before the
    // next call; the SAME frame keeps the maximum execution peak, while its
    // record debit retains every returned CID. This is no GC/physical ACK.
    frame.prepare(0n, 128n + BigInt(Buffer.byteLength(value, 'utf8')));
    return bytesCid(Buffer.from(value));
  };
  const tasks = originalTasks.map(entry => entry.taskCid);
  const sources = bundle.sources.flatMap(entry => entry.catalogue.views.map(view =>
    [entry.catalogue.connection, view.resource]));
  const updates = bundle.writables.map(target =>
    [target.source.catalogue.connection, target.write.resource]);
  const subject = {projectDirectory, configurationCid: hashOriginal(configurationWire),
    sources: bundle.sources.map(entry => ({connection: entry.catalogue.connection,
      registration: entry.catalogue.registration, declarationCid: hashOriginal(entry.wire)})),
    modelTasks: tasks, requestRealization};
  if (updates.length > 1) subject.targets = bundle.writables.map(target => {
    const mapping = target.source.effectPrepared.mappings.find(value => value.resource === target.write.resource);
    if (typeof mapping?.mappingCid !== 'string') fail('InstalledMockMappingUnavailable');
    return {connection: target.source.catalogue.connection, resource: target.write.resource,
      mappingCid: mapping.mappingCid, itemsPath: target.physical.itemsPath,
      keyPath: target.physical.keyPath, primaryIdentity: target.physical.primaryIdentity};
  });
  // Preserve the original one-target preimage and complete plural inventory.
  return {subject, sources, modelTasks: tasks,
    requestTarget: ['local-mock', requestRealization], updateTargets: updates};
}

// This is the existing Local Host's installation work, under its actual Store
// exclusion. Common owns the limited policy; these files do not create grants
// from a profile name, discovered Project, equal CID or missing saved state.
export function initializeOrdinaryMockAccount(options) {
  const key = options.root;
  if (flights.has(key)) fail('LocalMockInitializationAlreadyPending');
  const flight = Promise.resolve().then(() => initializeConstructed(options));
  flights.set(key, flight);
  const settled = () => {if (flights.get(key) === flight) flights.delete(key);};
  flight.then(settled, settled);
  return flight;
}

async function initializeConstructed({accountConstruction, prepareSubjects, ...options}) {
  if (accountConstruction === undefined) {
    if (prepareSubjects !== undefined || options.updateTargets !== undefined) fail('LocalMockAccountInventoryUnavailable');
    return initialize(options);
  }
  if (!isAccountConstruction(accountConstruction)) fail('ForeignAccountConstruction');
  const frame = accountConstruction.begin();
  try {
    const subjects = prepareSubjects === undefined ? {} : prepareSubjects(frame);
    const result = await initialize({...options, ...subjects}, frame);
    if (result !== undefined) frame.hold();
    frame.finish(result !== undefined);
    return result;
  } catch (cause) {frame.failure(cause); frame.finish(false); throw cause;}
}

async function initialize({moon, root, principal, subject, sources, modelTasks, requestTarget,
  updateTarget, updateTargets, explicitSelection, assertExclusiveCurrent, operatorAuthorization}, frame) {
  let constructing = true;
  assertExclusiveCurrent();
  // The existing diagnostic callback is not an Account, policy or signer
  // selection. Capture only that one own DATA function before any setup await;
  // every other explicit authorization object retains the original opt-out.
  const diagnosticObserver = operatorAuthorization !== null && typeof operatorAuthorization === 'object' &&
    [Object.prototype, null].includes(Object.getPrototypeOf(operatorAuthorization)) &&
    Reflect.ownKeys(operatorAuthorization).length === 1
    ? Object.getOwnPropertyDescriptor(operatorAuthorization, 'observe')?.value : undefined;
  if (operatorAuthorization !== undefined && typeof diagnosticObserver !== 'function') return undefined;
  const diagnostic = diagnosticObserver === undefined ? {} : {observe: diagnosticObserver};
  const targets = updateTargets ?? (updateTarget === undefined ? [] : [updateTarget]);
  // The trusted initializer supplied the COMPLETE catalog before any subject
  // CID or key is created. Its tuple copies are separate live constructors.
  if (frame !== undefined) frame.record(0n, 16n + 4n * BigInt(sources.length + targets.length), 2n);
  const sourceTuples = sources.map(runtimeTupleFromFields);
  const targetTuples = targets.map(runtimeTupleFromFields);
  const requestTuple = requestTarget === undefined ? undefined : runtimeTupleFromFields(requestTarget);
  if (frame !== undefined) {
    const validate = moon.clientProgramLocalMockAccountInventoryPrepared;
    if (typeof validate !== 'function' || typeof moon.clientProgramLocalMockAccountConfigurationPrepared !== 'function' ||
        typeof moon.clientProgramLocalMockAccountBeforeSigningPrepared !== 'function') {
      fail('LocalMockAccountInventoryUnavailable');
    }
    const checkedInventory = Reflect.apply(validate, moon,
      ['local-mock', sourceTuples, modelTasks, requestTuple, targetTuples, frame.core]);
    frame.assert();
    if (checkedInventory === undefined) fail('LocalMockAccountInventoryUnavailable');
    checked(checkedInventory);
  }
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
      if (info.size > maximum) fail('LocalMockInitializationLimit');
      const wire = constructing && frame !== undefined ? await readAccountOriginal(path, frame)
        : await readBoundedConfigurationUtf8(path, {maxBytes: maximum});
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
    if (constructing && frame !== undefined) frame.prepare(0n, 128n + 3n * BigInt(Buffer.byteLength(wire, 'utf8')));
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
    if (constructing) frame?.nativeJson(wire);
    try {return JSON.parse(wire);} catch (cause) {fail('LocalMockInitializationInvalid', cause);}
  }
  let intentWire = await readOptional(intentPath);
  let adoptedWire = await readOptional(receiptPath), adoptionFlight;
  if (intentWire === undefined) {
    if (adoptedWire !== undefined) fail('LocalMockAdoptedStateMissing');
    if (!explicitSelection) fail('LocalMockInitializationConsentRequired');
    try {await lstat(directory); fail('LocalMockInitializationConflict');}
    catch (cause) {if (cause?.code !== 'ENOENT') throw cause;}
    const accountId = 'local-mock-' + randomUUID();
    if (frame !== undefined) {
      // bytesCid over the actual Ed25519 public PEM has the existing exact
      // ASCII SHA256 name length. This is a constructor bound, not a key value.
      const prepared = moon.clientProgramLocalMockAccountBeforeSigningPrepared(accountId, principal,
        'local-mock', sourceTuples, modelTasks, requestTuple, targetTuples, 71, frame.core);
      frame.assert();
      if (prepared !== true) fail('LocalMockAccountConstructionUnavailable');
    }
    // Fixed Ed25519 key/PEM/intent constructors use the same original Read.
    frame?.record(8192n, 128n, 4n);
    await mkdir(directory, {mode: 0o700});
    assertExclusiveCurrent();
    const reviewer = generateKeyPairSync('ed25519'), host = generateKeyPairSync('ed25519');
    const reviewerPem = reviewer.privateKey.export({type: 'pkcs8', format: 'pem'});
    const hostPem = host.privateKey.export({type: 'pkcs8', format: 'pem'});
    const reviewerPublic = reviewer.publicKey.export({type: 'spki', format: 'pem'});
    const reviewerResource = bytesCid(Buffer.from(reviewerPublic));
    const generated = frame === undefined
      ? moon.clientProgramLocalMockAccountConfiguration(accountId, principal,
        'local-mock', sourceTuples, modelTasks, requestTuple,
        updateTarget === undefined ? undefined : targetTuples[0], reviewerResource)
      : moon.clientProgramLocalMockAccountConfigurationPrepared(accountId, principal,
        'local-mock', sourceTuples, modelTasks, requestTuple, targetTuples, reviewerResource, frame.core);
    frame?.assert();
    if (generated === undefined) fail('LocalMockAccountConstructionUnavailable');
    const configuration = checked(generated);
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
    frame?.record(BigInt(configuration.length + reviewerPem.length + hostPem.length + reviewerPublic.length) + 1024n,
      64n, 6n);
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
  const binding = Object.freeze({profile: identity, subjectCid, configurationPath: configPath,
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
    authorization: Object.freeze(publicKey === undefined ? {...diagnostic, accountConfig: configPath, siteKey: 'local-mock'} : {...diagnostic, accountConfig: configPath, siteKey: 'local-mock',
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
  constructing = false;
  return binding;
}
