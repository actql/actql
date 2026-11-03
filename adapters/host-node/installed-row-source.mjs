// The standard Host's provider-neutral installed row source. A connector
// whose Site driver returns pages of JSON rows (keyed by its declared field
// names) is installed through this adapter: declaration restore, Check
// Environment, read decisions, credential grants, acquisition, capture and
// Source Evidence are the common runtime's and this module's; the connector
// supplies only its view specification, its physical target and its page
// driver. No provider name or type appears here.
import {invocationBindingsMatch} from '../host-common/owned-invocation-context.mjs';
import {runtimeField, runtimeIsOk, runtimeIsBoxedSome} from '../host-common/compiler-binding.generated.mjs';
import {createHash, createPrivateKey, createPublicKey, randomUUID} from
  'node:crypto';
import {readFile} from 'node:fs/promises';
import {types as nodeTypes} from 'node:util';
import {performance} from 'node:perf_hooks';
import {setImmediate as yieldEventLoop} from 'node:timers/promises';
import {canonicalJson as canonicalValueJson} from '../../packages/sdk/host-port.mjs';
import {validInstallationBinding} from './ordinary-source-binding.mjs';
import {isAbsolute} from 'node:path';
import {fileURLToPath} from 'node:url';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {prepareOriginalSourceQuery} from './original-query-preparation.mjs';
import {acquisitionFailure, acquisitionOutcome, AcquisitionOpenError} from
  '../host-common/acquisition-outcome.mjs';
import {startInstalledRowRun} from './installed-row-run.mjs';
import {rowListingCallbacks} from './installed-row-listing.mjs';
import {authorizationDispatchFacts, authorizationRuntimeCode} from
  '../host-common/authorization-gate.mjs';
import {checkpointApprovalFacts} from '../host-common/checkpoint-approval.mjs';
import {canonicalJson, contentCid, createLocalAuthorizationGate} from
  './local-account-config.mjs';
import {openSqliteCredentialJournal} from
  '../site-node/sqlite-credential-journal.mjs';
import {signRemoteCredentialGrant} from
  '../site-node/remote-credential-signature.mjs';
import {callHttpsCredentialResource} from
  '../site-node/https-credential-resource.mjs';
import {openHttpsCredentialBinding, closeHttpsCredentialBinding, retainHttpsCredentialBindingReadChild} from
  '../site-node/https-credential-resource.mjs';
import {readBoundedConfigurationText} from './source-profile-json.mjs';
import {retainInstalledHostInitializationFailure} from './installed-host-cleanup.mjs';
import {bindClientSourceOperationRowRun} from './client-source-operation.mjs';
import {assertInstalledSourceConstruction, retainInstalledSourceConstruction,
  closeInstalledSourceConstruction, prepareInstalledSourceAcquisitionContracts, readInstalledSourceAcquisitionContract} from './installed-host-services.mjs';

const fail = (code, cause) => {
  throw Object.assign(new Error(code, {cause}), {code});
};
const text = value => typeof value === 'string' && value.length > 0;
const cidPattern = /^sha256:[0-9a-f]{64}$/u;
const cid = value => `sha256:${createHash('sha256')
  .update(canonicalJson(value)).digest('hex')}`;
// A keyed request includes data values (not configuration identifiers).
// Keep exact version/target text; NFC must not broaden read approval identity.
const valueCid = value => `sha256:${createHash('sha256')
  .update(canonicalValueJson(value, {dataKeys: true})).digest('hex')}`;

// Private standard installation DATA, not a callback-currentness promise.
// Callback targets keep their original full revalidation below, even when a
// callback happens to return a frozen object. No public or restored wire can
// replace an original prepared target through this constructor input.
function prepareImmutablePhysicalTargets(value) {
  if (typeof value === 'function') return undefined;
  const mismatch = () => fail('InstalledSourcePreparationMismatch');
  const arrayValues = input => {
    if (!Array.isArray(input) || nodeTypes.isProxy(input) || !Object.isFrozen(input) ||
        Object.getPrototypeOf(input) !== Array.prototype) mismatch();
    const length = Object.getOwnPropertyDescriptor(input, 'length').value;
    if (Reflect.ownKeys(input).length !== length + 1) mismatch();
    for (let index = 0; index < length; index++) {
      const property = Object.getOwnPropertyDescriptor(input, index);
      if (!property || !Object.hasOwn(property, 'value')) mismatch();
    }
    return input;
  };
  const resources = new Set();
  const inventory = arrayValues(value);
  for (const input of inventory) {
    if (input === null || typeof input !== 'object' || nodeTypes.isProxy(input) ||
        !Object.isFrozen(input) || Object.getPrototypeOf(input) !== Object.prototype) mismatch();
    for (const key of Reflect.ownKeys(input)) {
      const property = Object.getOwnPropertyDescriptor(input, key);
      if (typeof key !== 'string' || !Object.hasOwn(property, 'value') ||
          !property.enumerable || key !== 'fields' && typeof property.value !== 'string') mismatch();
    }
    if (!text(input.resource) || resources.has(input.resource) || !Object.hasOwn(input, 'fields')) mismatch();
    const fields = arrayValues(input.fields);
    if (fields.some(field => !text(field)) || new Set(fields).size !== fields.length) mismatch();
    resources.add(input.resource);
  }
  if (inventory.length === 0) mismatch();
  resources.clear();
  // The existing Source constructor already retains these exact immutable
  // outputs. Do not allocate another inventory, target Map or field arrays.
  return Object.freeze({inventory, prepare(resource, fields) {
    const target = inventory.find(target => target.resource === resource);
    if (target === undefined || !Array.isArray(fields) || new Set(fields).size !== fields.length ||
        fields.some(field => !target.fields.includes(field))) mismatch();
    return Object.freeze({...target, fields: Object.freeze([...fields])});
  }});
}
const contractRoot = new URL('../../spec/contracts/', import.meta.url);

const byCid = values => values.map(value => JSON.parse(value))
  .sort((a, b) => {
    const left = valueCid(a);
    const right = valueCid(b);
    return left < right ? -1 : left > right ? 1 : 0;
  });

// The Check Environment of a restored row declaration: the Host's base
// environment with the declaration's Catalog, source views, contracts,
// manifest entry and evidence members, plus the create Mappings the common
// runtime generated from the connector's declared writes. Built only from
// regenerated declarations; nothing is read from the provider. Complete
// declared Command bodies keep their original Catalog/role correspondence for
// Common admission; this assembly does not confer permission or issue targets.
// Without Mappings or Commands the read-only environment remains unchanged.
// Checked contracts contain exact data text, including enum values and field
// names. Preserve those originals rather than applying configuration NFC.
export function rowSourceCheckEnvironment(baseWire, declared, mappings = []) {
  const base = JSON.parse(baseWire);
  const {evidence_bundle_cid: _, ...body} = base;
  const commands = Object.hasOwn(declared, 'command_bodies')
    ? declared.command_bodies : [];
  if (body.version !== 'actql-check-environment/0.1' ||
      body.connector_catalogs.length !== 0 ||
      body.schema_snapshots.length !== 0 ||
      body.connector_capabilities.length !== 0 ||
      body.connector_manifest !== undefined ||
      declared.evidence_schemas.length !== declared.view_bodies.length ||
      declared.evidence_capabilities.length !== declared.view_bodies.length ||
      !Array.isArray(mappings) || !Array.isArray(commands) ||
      (mappings.length !== 0 && body.mapping_contracts?.length !== 0) ||
      (commands.length !== 0 && body.command_contracts?.length !== 0)) {
    fail('InvalidRowSourceCheckEnvironmentBase');
  }
  const environment = {...body,
    schema_snapshots: byCid(declared.evidence_schemas),
    connector_capabilities: byCid(declared.evidence_capabilities),
    source_views: byCid(declared.view_bodies),
    contract_registry: byCid(declared.contracts),
    connector_catalogs: [JSON.parse(declared.catalog)],
    connector_manifest: {version: 'actql-connectors/0.1',
      connectors: [JSON.parse(declared.manifest_entry)]},
    ...(mappings.length === 0 ? {} : {mapping_contracts: byCid(mappings)}),
    ...(commands.length === 0 ? {} : {command_contracts: byCid(commands)})};
  const evidenceCid = valueCid(environment);
  return Object.freeze({
    wire: canonicalValueJson({...environment, evidence_bundle_cid: evidenceCid},
      {dataKeys: true}),
    evidenceCid});
}

// The create Mapping of `resource`, generated by the common runtime from the
// connector's declared writes. `sources` maps each written target field to a
// field of the Effect's source result: [{target, field, null_behavior}].
export function rowSourceMapping(moon, declaration, writesJson, resource,
  sources) {
  const prepared = JSON.parse(moon.clientProgramRowSourcePrepareMapping(
    declaration, writesJson, resource, JSON.stringify(sources)));
  if (prepared.issue !== undefined) fail(`RowSourceMapping${prepared.issue}`);
  return Object.freeze({mappingRef: prepared.mapping_ref,
    mappingCid: prepared.mapping_cid, body: prepared.body,
    target: JSON.parse(prepared.body).target_ref,
    writeFields: Object.freeze(prepared.write_fields),
    omittable: Object.freeze(prepared.omittable)});
}

// The Host account gate of one installed row source, under its own context.
// A trusted existing installer may retain its original immutable context
// preimage. This is installation DATA, not a decision, grant or current ACK;
// the same Account Owner still admits the configuration and every decision.
export async function installRowSourceAuthorization({accountConfiguration,
  principalId, root, connectorRegistration, originalContext, gateOptions = {}}) {
  if (!text(accountConfiguration) || !text(principalId) || !text(root) ||
      !text(connectorRegistration) ||
      (originalContext !== undefined &&
        (originalContext === null || typeof originalContext !== 'object' ||
          !Object.isFrozen(originalContext) ||
          Object.getPrototypeOf(originalContext) !== Object.prototype ||
          Object.keys(originalContext).length !== 2 ||
          !Object.hasOwn(originalContext, 'principal') ||
          !Object.hasOwn(originalContext, 'contextCid') ||
          originalContext.principal !== principalId ||
          !cidPattern.test(originalContext.contextCid ?? '')))) {
    fail('InvalidRowSourceAuthorizationInstallation');
  }
  const context = originalContext ?? Object.freeze({principal: principalId,
    contextCid: cid({version: 'actql-installed-row-source-context/0.1',
      root, principalId, connectorRegistration})});
  const gate = await createLocalAuthorizationGate({...gateOptions,
    accountConfiguration, principal: principalId, context});
  const issued = new WeakSet();
  const own = decision => {
    if (decision !== null && typeof decision === 'object') issued.add(decision);
    return decision;
  };
  return Object.freeze({...gate, context, accountConfiguration,
    issued: decision => issued.has(decision),
    authorize: async (...args) => own(await gate.authorize(...args)),
    resume: async (...args) => own(await gate.resume(...args))});
}

// Load the selected installed issuer into the same credential custody. A
// compatibility installer keeps its own profile and refusal names; neither
// the key nor a second journal/signing implementation leaves this Owner.
export async function loadRowSourceCredentialCustody({
  openCredentialJournal = openSqliteCredentialJournal, ...options}, {
  caPath, prepareResolver, invalidCode = 'InvalidRowSourceCredentialSite'} = {}) {
  let privateKey;
  let ca = options.ca;
  try {
    const reader = options.configurationReader;
    let read;
    if (reader !== undefined) {
      if (nodeTypes.isProxy(reader)) fail(invalidCode);
      const field = Object.getOwnPropertyDescriptor(reader, 'readOriginalText');
      if (!field || !Object.hasOwn(field, 'value') || typeof field.value !== 'function') fail(invalidCode);
      read = field.value;
    }
    privateKey = createPrivateKey(await (reader === undefined
      ? readFile(options.profile.credentialPrivateKeyPath, 'utf8')
      : Reflect.apply(read, reader, [options.profile.credentialPrivateKeyPath])));
    if (caPath !== undefined) {
      if (reader === undefined) ca = await readFile(caPath);
      else {
        const bytes = Object.getOwnPropertyDescriptor(reader, 'readOriginalBytes');
        if (!bytes || !Object.hasOwn(bytes, 'value') || typeof bytes.value !== 'function') fail(invalidCode);
        ca = await Reflect.apply(bytes.value, reader, [caPath]);
      }
    }
  } catch (cause) {
    const failure = Object.assign(new Error(invalidCode, {cause}), {code: invalidCode});
    // Preserve the existing same-FD cleanup Owner through the old Site error
    // wrapper. A failed key read must not become an unowned Source abort.
    const cleanup = Object.getOwnPropertyDescriptor(Object(cause), 'cleanupHandle');
    if (cleanup && Object.hasOwn(cleanup, 'value')) {
      Object.defineProperty(failure, 'cleanupHandle', {value: cleanup.value});
    }
    throw failure;
  }
  if (privateKey.asymmetricKeyType !== 'ed25519') fail(invalidCode);
  // The existing installer can construct its default resolver only after the
  // original key/CA admission. It receives no private key or provider secret.
  const resolveSecret = prepareResolver === undefined
    ? options.resolveSecret : prepareResolver();
  if (typeof resolveSecret !== 'function') {
    if (typeof resolveSecret?.then === 'function') {
      void Promise.resolve(resolveSecret).catch(() => {});
    }
    fail(invalidCode);
  }
  return openRowSourceCredentialCustody({...options,
    privateKey, ca, resolveSecret, openCredentialJournal});
}

// One physical credential-journal/signing implementation for installed Row
// Sites. The existing Site validates its selected profile/key and authorizes
// each operation before calling sign; this private Host port is not a grant.
// Preserve the original scope members/task attempt and same journal custody.
function ownCredentialAcquisitionLimits(input) {
  if (input === undefined) return undefined;
  if (input === null || typeof input !== 'object' || nodeTypes.isProxy(input)) {
    fail('InvalidRowSourceCredentialAcquisitionLimits');
  }
  const descriptors = Object.getOwnPropertyDescriptors(input);
  if (Reflect.ownKeys(descriptors).length !== 2 ||
      ['maxBindings', 'maxSecretBytes'].some(name => {
        const field = descriptors[name];
        return !field || !Object.hasOwn(field, 'value') ||
          !Number.isSafeInteger(field.value) || field.value <= 0 || field.value > 2147483647;
      })) fail('InvalidRowSourceCredentialAcquisitionLimits');
  return Object.freeze({maxBindings: descriptors.maxBindings.value,
    maxSecretBytes: descriptors.maxSecretBytes.value});
}

// Trusted installing code selects only an existing physical presentation.
// This is not profile DATA, a header name, an auth provider or a grant. The
// physical binding still validates its original registration/auth dependency.
function ownCredentialSecretPresentation(options) {
  if (options === null || typeof options !== 'object' || nodeTypes.isProxy(options)) {
    fail('InvalidRowSourceSecretPresentation');
  }
  const field = Object.getOwnPropertyDescriptor(options, 'secretPresentation');
  if (field === undefined) return undefined;
  if (!Object.hasOwn(field, 'value') ||
      !['bearer', 'kintone-api-token'].includes(field.value)) {
    fail('InvalidRowSourceSecretPresentation');
  }
  return field.value;
}

// Internal operation assembly recognizes the exact credential returned by
// this existing Site. An equal envelope cannot recover its issuer/binding.
const operationSites = new WeakMap();
export function installedRowCredentialOperationSite(credential) {
  const original = operationSites.get(credential);
  if (original === undefined) fail('ForeignInstalledCredentialOperationSite');
  if (!original.referenceCurrent()) fail('RowSourceSiteClosed');
  return original;
}

function retainCredentialOperationSite(site, custody, identity, enabled) {
  if (enabled) {
    const bind = custody.bindRunAcquisition;
    const purpose = custody.authorizationPurpose;
    const child = custody.readChildCredential;
    const bindResourceChild = custody.bindReadResourceChild;
    const resourceChild = custody.readResourceChildCredential;
    operationSites.set(site.credential, Object.freeze({
      ...identity, site, credential: site.credential, callResource: site.callResource,
      construction: custody.construction,
      referenceCurrent: custody.referenceCurrent,
      bindRunAcquisition: (authorization, current) =>
        Reflect.apply(bind, custody, [authorization, current]),
      authorizationPurpose: authorization => Reflect.apply(purpose, custody, [authorization]),
      readChildCredential: (acquisition, authorization) => Reflect.apply(child, custody, [acquisition, authorization]),
      bindReadResourceChild: bindResourceChild,
      readResourceChildCredential: resourceChild,
    }));
  }
  return site;
}


export function openRowSourceCredentialCustody({profile, principalId,
  connectorRegistration, connectorRevision, runtimeBundleCid, commonMoon,
  privateKey, resolveSecret, ca, now, grantLifetimeMs,
  openCredentialJournal, credentialFacts, runAcquisitionLimits,
  closedCode = 'RowSourceSiteClosed',
  grantCode = 'InvalidRowSourceGrantRequest'}) {
  const secretPresentation = ownCredentialSecretPresentation(arguments[0]);
  const acquisitionLimits = ownCredentialAcquisitionLimits(runAcquisitionLimits);
  if (acquisitionLimits !== undefined) {
    if (profile === null || typeof profile !== 'object' || nodeTypes.isProxy(profile) ||
        !Object.isFrozen(profile) || Object.values(Object.getOwnPropertyDescriptors(profile))
          .some(field => !Object.hasOwn(field, 'value'))) fail('InvalidRowSourceCredentialAcquisitionProfile');
  }
  const control = runtimeCore(commonMoon).remoteCredentialControl;
  const journalRoot = profile.journalRoot;
  const credentialAuthorities = new Map([[profile.credentialAuthorityId,
    new Map([[profile.credentialKeyId, createPublicKey(privateKey)]])]]);
  const [authority, originalKeys] = credentialAuthorities.entries().next().value;
  const metadataIssuer = Object.freeze({authority, keyId: originalKeys.keys().next().value});
  // Define the immutable managed scope once in the SAME issuer that consumes
  // it. These original strings/limits are constructor DATA, not a grant,
  // current observation, copied credential or another policy selection.
  const originalScopeFields = () => ({
    issuerAuthority: profile.credentialAuthorityId, principal: principalId,
    namespaceId: profile.namespaceId, environment: profile.environment,
    siteKey: profile.siteKey, siteGeneration: profile.siteGeneration,
    runtimeBundleCid, connectorRegistration, connectorRevision,
    resourceOrigin: profile.resourceOrigin,
  });
  const scopeDefinition = acquisitionLimits === undefined ? undefined
    : Object.freeze(originalScopeFields());
  const construction = scopeDefinition === undefined ? undefined
    : Object.freeze({scope: scopeDefinition, limits: acquisitionLimits, issuer: metadataIssuer});
  const journal = openCredentialJournal(journalRoot, {credentialAuthorities});
  let closing = false;
  let released = false;
  const runBindings = acquisitionLimits === undefined ? undefined : new Set();
  let runBindingAttempts = 0;
  const runAcquisitions = new WeakMap();
  const issuedRunAuthorizations = acquisitionLimits === undefined ? undefined : new WeakMap();
  let runJournalClose, runJournalFailure, runJournalCloseObservation;
  if (runBindings !== undefined) {
    // Capture before returning a borrow. A substituted method cannot retire
    // this original Journal, and capture failure remains with this custody.
    try {
      if (nodeTypes.isProxy(journal) || !Object.isFrozen(journal) ||
          ['acceptGrant', 'claim', 'authorize', 'finish', 'checkGrant', 'inspect', 'recover', 'close']
            .some(name => {
              const method = Object.getOwnPropertyDescriptor(journal, name);
              return !method || !Object.hasOwn(method, 'value') || typeof method.value !== 'function';
            })) fail('InvalidRowSourceCredentialAcquisitionJournal');
      runJournalClose = Object.getOwnPropertyDescriptor(journal, 'close').value;
    } catch (cause) { runJournalFailure = cause; }
  }
  // The metadata alternative uses this same original issuer/key/Journal.
  // Legacy Run signing below deliberately retains its existing profile rules.
  const credential = Object.freeze({...credentialFacts,
    control, journal, resolveSecret, ca, now});
  const ensureOpen = () => {
    if (closing) fail(closedCode);
  };
  function checkGrantRequest(runInvocationCid, dispatchRequestCid, maxUses,
    taskAttempt = 1) {
    if (!cidPattern.test(runInvocationCid ?? '') ||
        !cidPattern.test(dispatchRequestCid ?? '') ||
        !Number.isSafeInteger(taskAttempt) || taskAttempt < 1 ||
        !Number.isSafeInteger(maxUses) || maxUses < 1 || maxUses > 10_000) {
      fail(grantCode);
    }
  }
  function sign({operation, runInvocationCid, taskAttempt = 1,
    dispatchRequestCid, maxUses, issuerPurpose}) {
    ensureOpen();
    checkGrantRequest(runInvocationCid, dispatchRequestCid, maxUses, taskAttempt);
    // The legacy branch fills its original one scope record directly; it
    // does not allocate a temporary field record only to spread it again.
    const scope = scopeDefinition === undefined ? originalScopeFields() : {...scopeDefinition};
    scope.operation = operation;
    scope.runInvocationCid = runInvocationCid;
    scope.taskAttempt = taskAttempt;
    scope.dispatchRequestCid = dispatchRequestCid;
    scope.expiresUnixMilliseconds = BigInt(now() + grantLifetimeMs);
    scope.maxUses = maxUses;
    Object.freeze(scope);
    // Re-admitting this signed scope never refills its durable use inventory.
    const grant = control.prepare(scope);
    journal.acceptGrant(signRemoteCredentialGrant(grant, control, {
      keyId: construction === undefined ? profile.credentialKeyId : construction.issuer.keyId, privateKey}), control);
    const authorization = Object.freeze({grant, scope});
    issuedRunAuthorizations?.set(authorization, {state: 'unused', issuerPurpose});
    return authorization;
  }
  function authorizationPurpose(authorization) {
    ensureOpen();
    const original = issuedRunAuthorizations?.get(authorization)?.issuerPurpose;
    if (original === undefined) fail('RowSourceAuthorizationPurposeUnavailable');
    // This is the original issuance branch, not a new Allow or a substitute
    // for current Account/Checkpoint, Journal use, claim or Run admission.
    return original;
  }
  function closeRunBindings() {
    let pending = false;
    for (const original of runBindings ?? []) {
      if (!original.closed && original.binding === undefined) {
        pending = true;
        continue;
      }
      if (!original.closed) {
        original.closing = true;
        original.closed = closeHttpsCredentialBinding(original.binding) === 'closed';
      }
      if (!original.closed) pending = true;
      else {original.binding = undefined; runBindings.delete(original);}
    }
    if (pending) fail('RowSourceCredentialAcquisitionCleanupPending');
  }
  function close() {
    closing = true;
    if (runBindings === undefined) journal.close();
    else {
      if (released) return;
      closeRunBindings();
      if (runJournalFailure !== undefined) throw runJournalFailure;
      const acknowledged = Reflect.apply(runJournalClose, journal, []);
      if (typeof acknowledged !== 'boolean') {
        runJournalCloseObservation = acknowledged;
        runJournalFailure = Object.assign(new Error('RowSourceCredentialJournalCleanupUnconfirmed'),
          {code: 'RowSourceCredentialJournalCleanupUnconfirmed'});
        const failure = runJournalFailure;
        try {
          if (typeof runJournalCloseObservation?.then === 'function') {
            void Promise.resolve(runJournalCloseObservation).catch(cause => { failure.cause = cause; });
          }
        } catch (cause) { failure.cause = cause; }
        throw failure;
      }
    }
    released = true;
  }
  function openRunAcquisition(request, callbacks) {
    ensureOpen();
    if (acquisitionLimits === undefined) fail('RowSourceCredentialAcquisitionUnavailable');
    if (runJournalFailure !== undefined) throw runJournalFailure;
    if (runBindingAttempts >= acquisitionLimits.maxBindings) fail('RowSourceCredentialAcquisitionLimit');
    if (callbacks === null || typeof callbacks !== 'object' || nodeTypes.isProxy(callbacks)) {
      fail('InvalidRowSourceCredentialAcquisitionCurrent');
    }
    if (request === null || typeof request !== 'object' || nodeTypes.isProxy(request)) {
      fail('InvalidRowSourceCredentialAcquisitionRequest');
    }
    const fields = Object.getOwnPropertyDescriptors(request);
    const names = ['operation', 'runInvocationCid', 'taskAttempt', 'dispatchRequestCid', 'maxUses'];
    if (Reflect.ownKeys(fields).some(name => !names.includes(name)) ||
        names.some(name => name !== 'taskAttempt' && !fields[name]) ||
        Object.values(fields).some(field => !Object.hasOwn(field, 'value'))) {
      fail('InvalidRowSourceCredentialAcquisitionRequest');
    }
    const originalRequest = Object.freeze(Object.fromEntries(names.map(name =>
      [name, name === 'taskAttempt' && !Object.hasOwn(fields, name) ? 1 : fields[name].value])));
    const {assertCurrent, observeCurrent} = captureRunCurrent(callbacks);
    assertCurrent();
    // Preserve the existing issue-and-bind caller. A Site that has already
    // authorized and issued its grant uses bindRunAcquisition instead.
    const authorization = sign(originalRequest);
    return retainRunBinding(authorization, {assertCurrent, observeCurrent});
  }
  function captureRunCurrent(callbacks) {
    if (callbacks === null || typeof callbacks !== 'object' || nodeTypes.isProxy(callbacks)) {
      fail('InvalidRowSourceCredentialAcquisitionCurrent');
    }
    const methods = Object.getOwnPropertyDescriptors(callbacks);
    if (Reflect.ownKeys(methods).length !== 2 || ['assertCurrent', 'observeCurrent'].some(name =>
      !methods[name] || !Object.hasOwn(methods[name], 'value') || typeof methods[name].value !== 'function')) {
      fail('InvalidRowSourceCredentialAcquisitionCurrent');
    }
    const originalAssert = methods.assertCurrent.value;
    const originalObserve = methods.observeCurrent.value;
    const assertCurrent = () => {
      ensureOpen();
      const result = Reflect.apply(originalAssert, undefined, []);
      if (result !== undefined) {
        if (typeof result?.then === 'function') void Promise.resolve(result).catch(() => {});
        fail('InvalidRemoteCredentialCurrentFence');
      }
      ensureOpen();
    };
    const observeCurrent = async () => {
      assertCurrent();
      await Reflect.apply(originalObserve, undefined, []);
      assertCurrent();
    };
    return {assertCurrent, observeCurrent};
  }
  function retainRunBinding(authorization, current, resourceParent) {
    const {assertCurrent, observeCurrent} = current;
    ensureOpen();
    if (acquisitionLimits === undefined) fail('RowSourceCredentialAcquisitionUnavailable');
    if (runJournalFailure !== undefined) throw runJournalFailure;
    const issued = issuedRunAuthorizations.get(authorization);
    if (issued === undefined) fail('ForeignRowSourceCredentialAcquisitionAuthorization');
    if (issued.state !== 'unused') fail('RowSourceCredentialAcquisitionAuthorizationConsumed');
    if (runBindingAttempts >= acquisitionLimits.maxBindings) fail('RowSourceCredentialAcquisitionLimit');
    // Retain the opening child before invoking a current callback. Reentrant
    // close cannot ACK the Journal while this original binding is opening.
    const original = {binding: undefined, closed: false, closing: false, borrow: undefined, current};
    if (resourceParent !== undefined) original.resourceParent = resourceParent;
    issued.state = 'opening';
    runBindingAttempts++;
    runBindings.add(original);
    try {
      assertCurrent();
      original.binding = openHttpsCredentialBinding({scope: authorization.scope,
        control, journal, resolveSecret, maxSecretBytes: acquisitionLimits.maxSecretBytes,
        assertCurrent, ...(secretPresentation === undefined ? {} : {secretPresentation})});
      issued.state = 'bound';issued.acquisition = original;
    } catch (cause) {
      // No physical binding was returned. Keep the original grant with its
      // Journal and refuse another binding attempt under this authorization.
      original.closed = true;
      runBindings.delete(original);
      issued.state = 'failed';
      throw cause;
    }
    const boundCredential = Object.freeze({...credential, binding: original.binding,
      currentBeforeSend: observeCurrent});
    const acquisition = Object.freeze({authorization, credential: boundCredential,
      close() {
        original.closing = true;
        if (!original.closed) original.closed = closeHttpsCredentialBinding(original.binding) === 'closed';
        if (original.closed) {original.binding = undefined; runBindings.delete(original);}
        return original.closed ? 'closed' : 'pending';
      }});
    runAcquisitions.set(acquisition, original);
    const originalSite = operationSites.get(credential);
    if (originalSite !== undefined && issued.issuerPurpose?.kind === 'read') {
      // Recognize only this SAME already-open Run credential. No copied
      // envelope, scope/CID or fresh binding can construct this parent view.
      operationSites.set(boundCredential, Object.freeze({...originalSite, credential: boundCredential,
        referenceCurrent() {
          return !original.closing && !original.closed && original.binding !== undefined &&
            originalSite.referenceCurrent() && (original.borrow === undefined || original.borrow.available());
        },
        bindRunAcquisition(childAuthorization, callbacks) {
          const childCurrent = captureRunCurrent(callbacks);
          childCurrent.assertCurrent();assertCurrent();
          // Existing issuer/purpose/resource/invocation checks retain their
          // original grant. Sharing the binding does not authorize a use.
          readChildCredential(acquisition, childAuthorization);
          const physical = retainHttpsCredentialBindingReadChild(original.binding);
          original.borrow = physical;
          const childCredential = Object.freeze({...boundCredential, bindingBorrow: physical});
          let retired = false;
          const childAcquisition = Object.freeze({authorization: childAuthorization, credential: childCredential,
            close() {
              if (this !== childAcquisition) fail('ForeignRowSourceCredentialReadChild');
              return physical.close();
            },
            retire() {
              if (this !== childAcquisition) fail('ForeignRowSourceCredentialReadChild');
              if (retired) return true;
              if (!physical.retire()) return false;
              retired = true;if (original.borrow === physical) original.borrow = undefined;
              return true;
            }});
          runAcquisitions.set(childAcquisition, {parent: original, borrow: physical, current: childCurrent});
          return childAcquisition;
        },
        callResource(input) {
          const beforeSend = input.currentBeforeSend;
          if (typeof beforeSend !== 'function') fail('InvalidRemoteCredentialCurrentFence');
          return Reflect.apply(originalSite.callResource, originalSite.site, [{...input,
            currentBeforeSend: async () => {
              // Both original parent and child current duties stay with the
              // Host. Neither is reconstructed from a credential envelope.
              await observeCurrent();await Reflect.apply(beforeSend, undefined, []);
            }}]);
        },
      }));
    }
    return acquisition;
  }
  function readChildCredential(acquisition, authorization) {
    ensureOpen();
    const retained = runAcquisitions.get(acquisition);
    const parent = retained?.parent ?? retained;
    const issued = issuedRunAuthorizations?.get(authorization);
    if (retained?.borrow !== undefined && !retained.borrow.available()) fail('ForeignRowSourceCredentialReadChild');
    if (parent === undefined || parent.closing || parent.closed || parent.binding === undefined || issued === undefined ||
        issued.state !== 'unused' && (issued.state !== 'bound' || issued.acquisition !== parent)) {
      fail('ForeignRowSourceCredentialReadChild');
    }
    const purpose = issued.issuerPurpose;
    const originalPurpose = issuedRunAuthorizations.get(acquisition.authorization)?.issuerPurpose;
    if (purpose?.kind !== 'read' || originalPurpose?.kind !== 'read' ||
        purpose.resource !== originalPurpose.resource || purpose.decision === undefined || originalPurpose.decision === undefined ||
        !invocationBindingsMatch(authorization.scope, acquisition.authorization.scope)) {
      fail('ForeignRowSourceCredentialReadChild');
    }
    // This exact Site issuer has already authorized the child's own original
    // read decision. A current observation can yield a fresh decision object;
    // it need not reuse the parent's earlier decision to share this binding.
    // Associate it with
    // the parent's existing binding; do not sign, open, or own another one.
    issued.state = 'bound';issued.acquisition = parent;
    return acquisition.credential;
  }
  // A separately authorized Resource gets its own real binding, never an
  // exemption from readChildCredential's strict same-Resource sharing rule.
  function readResourceParent(acquisition) {
    ensureOpen();
    const retained = runAcquisitions.get(acquisition);
    if (retained === undefined) fail('ForeignRowSourceCredentialResourceChild');
    const original = retained.parent ?? retained;
    const issued = issuedRunAuthorizations?.get(acquisition.authorization);
    if (original === undefined || original.resourceParent !== undefined || original.closing || original.closed || original.binding === undefined ||
        retained.borrow !== undefined && !retained.borrow.available() ||
        issued?.state !== 'bound' || issued.acquisition !== original ||
        issued.issuerPurpose?.kind !== 'read' || issued.issuerPurpose.decision === undefined ||
        !text(issued.issuerPurpose.resource)) fail('ForeignRowSourceCredentialResourceChild');
    return {retained, original, purpose: issued.issuerPurpose};
  }
  function bindReadResourceChild(parent, authorization, callbacks) {
    const owner = readResourceParent(parent);
    const issued = issuedRunAuthorizations?.get(authorization);
    if (issued === undefined || issued.state !== 'unused' || issued.issuerPurpose?.kind !== 'read' ||
        issued.issuerPurpose.decision === undefined || !text(issued.issuerPurpose.resource) ||
        issued.issuerPurpose.resource === owner.purpose.resource ||
        !invocationBindingsMatch(authorization.scope, parent.authorization.scope)) {
      fail('ForeignRowSourceCredentialResourceChild');
    }
    const childCurrent = captureRunCurrent(callbacks);
    const parentCurrent = owner.original.current;
    const borrowedCurrent = owner.retained === owner.original ? undefined : owner.retained.current;
    const assertParent = () => {
      const selected = readResourceParent(parent);
      if (selected.retained !== owner.retained || selected.original !== owner.original) {
        fail('ForeignRowSourceCredentialResourceChild');
      }
    };
    const assertCurrent = () => {
      assertParent();parentCurrent.assertCurrent();assertParent();
      if (borrowedCurrent !== undefined) {borrowedCurrent.assertCurrent();assertParent();}
      childCurrent.assertCurrent();assertParent();
    };
    const observeCurrent = async () => {
      assertCurrent();await parentCurrent.observeCurrent();assertCurrent();
      if (borrowedCurrent !== undefined) {await borrowedCurrent.observeCurrent();assertCurrent();}
      await childCurrent.observeCurrent();assertCurrent();
    };
    // retainRunBinding spends this original authorization and retains the
    // opening duty before invoking either parent's or child's current fence.
    // Its failure path remains consumed; no replacement child is returned.
    return retainRunBinding(authorization, {assertCurrent, observeCurrent}, parent);
  }
  function readResourceChildCredential(parent, acquisition, authorization) {
    const owner = readResourceParent(parent);
    const child = runAcquisitions.get(acquisition);
    const issued = issuedRunAuthorizations?.get(authorization);
    if (child === undefined || child.resourceParent !== parent || child.closing || child.closed ||
        child.binding === undefined || acquisition.authorization !== authorization ||
        issued?.state !== 'bound' || issued.acquisition !== child ||
        issued.issuerPurpose?.kind !== 'read' || issued.issuerPurpose.decision === undefined ||
        issued.issuerPurpose.resource === owner.purpose.resource ||
        !invocationBindingsMatch(authorization.scope, parent.authorization.scope)) {
      fail('ForeignRowSourceCredentialResourceChild');
    }
    child.current.assertCurrent();
    readResourceParent(parent);
    if (child.closing || child.closed || child.binding === undefined) fail('ForeignRowSourceCredentialResourceChild');
    return acquisition.credential;
  }
  function bindRunAcquisition(authorization, callbacks) {
    ensureOpen();
    if (acquisitionLimits === undefined) fail('RowSourceCredentialAcquisitionUnavailable');
    // Membership is the exact authorization returned by this existing issuer,
    // not a re-admitted grant, equal CID, reconstructed scope or caller copy.
    if (!issuedRunAuthorizations.has(authorization)) {
      fail('ForeignRowSourceCredentialAcquisitionAuthorization');
    }
    return retainRunBinding(authorization, captureRunCurrent(callbacks));
  }
  function signInstallationMetadata({control: metadataControl, scope,
    expiresUnixMilliseconds, maxUses}) {
    ensureOpen();
    if (metadataControl?.kind !== 'installation-metadata') fail(grantCode);
    metadataControl.scopeFields(scope);
    const prepared = metadataControl.prepare({issuerAuthority: metadataIssuer.authority,
      scope, expiresUnixMilliseconds, maxUses});
    const grant = journal.acceptGrant(signRemoteCredentialGrant(prepared,
      metadataControl, {keyId: metadataIssuer.keyId, privateKey}), metadataControl);
    return Object.freeze({grant, scope});
  }
  function installationMetadataJournal() {
    // New-purpose admission captures the original close/receiver before any
    // method substitution. A missing/accessor method keeps this same custody
    // pending; it must not escape before the Site can return its cleanup duty.
    let originalClose, failure;
    try {
      if (nodeTypes.isProxy(journal)) fail('InvalidInstallationMetadataJournal');
      const descriptor = Object.getOwnPropertyDescriptor(journal, 'close');
      if (!descriptor || !Object.hasOwn(descriptor, 'value') ||
          typeof descriptor.value !== 'function') fail('InstallationMetadataJournalCleanupUnavailable');
      originalClose = descriptor.value;
      if (!Object.isFrozen(journal) || ['acceptGrant', 'claim', 'authorize',
        'finish', 'checkGrant', 'inspect', 'recover'].some(name => {
        const method = Object.getOwnPropertyDescriptor(journal, name);
        return !method || !Object.hasOwn(method, 'value') || typeof method.value !== 'function';
      })) fail('InvalidInstallationMetadataJournal');
    } catch (cause) { failure = cause; }
    return Object.freeze({journal, failure, close() {
      closing = true;
      if (released) return;
      closeRunBindings();
      if (originalClose === undefined) throw failure;
      const acknowledged = Reflect.apply(originalClose, journal, []);
      if (typeof acknowledged !== 'boolean') fail('InstallationMetadataJournalCleanupUnconfirmed');
      released = true;
    }});
  }
  const custody = Object.freeze({credential, sign, signInstallationMetadata,
    ...(construction === undefined ? {} : {construction}),
    ...(construction === undefined ? {} : {retainOperationSite(site) {
      ensureOpen();
      if (this !== custody || site === null || typeof site !== 'object' ||
          nodeTypes.isProxy(site) || !Object.isFrozen(site)) fail('ForeignInstalledCredentialOperationSite');
      const fields = Object.getOwnPropertyDescriptors(site);
      if (!Object.hasOwn(fields.credential ?? {}, 'value') || fields.credential.value !== credential ||
          !Object.hasOwn(fields.callResource ?? {}, 'value') || typeof fields.callResource.value !== 'function' ||
          !Object.hasOwn(fields.connection ?? {}, 'value') || !text(fields.connection.value)) {
        fail('ForeignInstalledCredentialOperationSite');
      }
      const retained = operationSites.get(credential);
      if (retained !== undefined) {
        if (retained.site !== site) fail('ForeignInstalledCredentialOperationSite');
        return site;
      }
      // This same private issuer binds its own original Site. No caller may
      // replace the custody, credential, principal or immutable runtime facts.
      return retainCredentialOperationSite(site, custody,
        {connection: fields.connection.value, principalId, connectorRegistration,
          connectorRevision, runtimeBundleCid}, true);
    }}),
    installationMetadataJournal, openRunAcquisition, bindRunAcquisition, authorizationPurpose, readChildCredential,
    bindReadResourceChild, readResourceChildCredential,
    checkGrantRequest, ensureOpen,
    referenceCurrent: () => !closing,
    // The existing generic entry calls its original journal close on every
    // close call. The Salesforce entry already skips an acknowledged close.
    // Both paths share this same physical close and never infer an ACK.
    close,
    closeOnce() { if (!released) close(); },
    cleanupPending: () => closing && !released,
  });
  return custody;
}

// An operational alternative of this same installed Credential Site. Common
// owns Subject/Scope DATA; the original Host, Account, Site and issuer remain
// necessary at every action. Resource/egress admission is a separate caller
// duty, never supplied by a bounded key read or a signed metadata grant.
async function prepareInstallationMetadataSite(options) {
  const {installationMetadata: input, profile, principalId, authorization,
    connection, connectorRegistration, connectorRevision, runtimeBundleCid,
    commonMoon, resolveSecret, ca, now, grantLifetimeMs} = options;
  const invalid = () => fail('InvalidRowSourceInstallationMetadata');
  const positive = value => Number.isSafeInteger(value) && value > 0 && value <= 2147483647;
  const data = (value, keys) => {
    if (value === null || typeof value !== 'object' || nodeTypes.isProxy(value) ||
        Object.getPrototypeOf(value) !== Object.prototype) invalid();
    const descriptors = Object.getOwnPropertyDescriptors(value);
    const names = Reflect.ownKeys(descriptors);
    if (names.length !== keys.length || names.some(key => !keys.includes(key))) invalid();
    return Object.fromEntries(keys.map(key => {
      const descriptor = descriptors[key];
      if (!descriptor?.enumerable || !Object.hasOwn(descriptor, 'value')) invalid();
      return [key, descriptor.value];
    }));
  };
  const original = data(input, ['publicationRequest', 'originals', 'declaration',
    'declarationSourceCid', 'operations', 'maxOperations', 'maxSecretBytes',
    'maxIssuerKeyBytes', 'maxCaBytes', 'targetAuthority', 'siteCurrent']);
  if (original.declaration === null || typeof original.declaration !== 'object' ||
      !cidPattern.test(original.declarationSourceCid ?? '') ||
      !positive(original.maxOperations) || !positive(original.maxSecretBytes) ||
      !positive(original.maxIssuerKeyBytes) || !positive(original.maxCaBytes) ||
      !Array.isArray(original.operations) || nodeTypes.isProxy(original.operations) ||
      original.operations.length === 0 || original.operations.length > original.maxOperations ||
      original.operations.some(operation => !text(operation)) ||
      typeof authorization?.assertAccountCurrent !== 'function' ||
      typeof authorization?.assertConfigurationCurrent !== 'function' ||
      !cidPattern.test(authorization.configurationCid ?? '') ||
      !text(authorization.accountId) || authorization.principal !== principalId ||
      !positive(grantLifetimeMs) || !text(connection)) invalid();
  const operations = new Set(original.operations);
  if (operations.size !== original.operations.length) invalid();
  const targetAuthority = data(original.targetAuthority, ['project']);
  const siteCurrent = data(original.siteCurrent, ['observe', 'assertCurrent']);
  if ([targetAuthority.project, siteCurrent.observe, siteCurrent.assertCurrent]
    .some(method => typeof method !== 'function')) invalid();
  const account = Object.freeze(Object.fromEntries(['accountId', 'configurationCid',
    'principal', 'contextCid'].map(name => {
    const descriptor = Object.getOwnPropertyDescriptor(authorization, name);
    if (!descriptor || !Object.hasOwn(descriptor, 'value')) invalid();
    return [name, descriptor.value];
  })));
  const accountMethods = Object.fromEntries(['authorize', 'assertAccountCurrent',
    'assertConfigurationCurrent'].map(name => {
    const descriptor = Object.getOwnPropertyDescriptor(authorization, name);
    if (!descriptor || !Object.hasOwn(descriptor, 'value') ||
        typeof descriptor.value !== 'function') invalid();
    return [name, descriptor.value];
  }));
  const callAccount = (name, ...args) => Reflect.apply(accountMethods[name], authorization, args);
  // Capture the actual entry pair once; accessors cannot substitute another
  // runtime, provider, resolver or checked profile across an await.
  const pairNames = ['root', 'principalId', 'moon', 'installation', 'profile',
    'resolveSecret', 'runtimeBundleCid', 'providerMoon'];
  if (original.originals === null || typeof original.originals !== 'object' ||
      nodeTypes.isProxy(original.originals)) invalid();
  const descriptors = Object.getOwnPropertyDescriptors(original.originals ?? {});
  const pair = Object.freeze(Object.fromEntries(pairNames.map(name => {
    const descriptor = descriptors[name];
    if (descriptor === undefined && name === 'providerMoon') return [name, undefined];
    if (!descriptor || !Object.hasOwn(descriptor, 'value')) invalid();
    return [name, descriptor.value];
  })));
  if (pair.principalId !== principalId || pair.moon !== commonMoon ||
      pair.resolveSecret !== resolveSecret || pair.runtimeBundleCid !== runtimeBundleCid ||
      pair.installation?.registration !== connectorRegistration ||
      pair.installation?.revision !== connectorRevision) invalid();
  const host = await import('./installed-source.mjs');
  host.assertInstalledSourcePublicationRequest(original.publicationRequest, pair);
  const view = runtimeCore(commonMoon).installationPreparationMetadata();
  const subject = view.prepareSubject({
    accountConfigurationCid: account.configurationCid,
    accountId: account.accountId, connection, connectorRegistration,
    connectorRevision, declarationSourceCid: original.declarationSourceCid,
    installationRequestId: host.installedSourcePublicationRequestId(original.publicationRequest),
    principal: principalId, runtimeBundleCid, siteGeneration: profile.siteGeneration,
    siteKey: profile.siteKey,
  });
  const control = view.forSubject(subject);
  const subjectCid = view.subjectCid(subject);
  const profileKeys = ['credentialPrivateKeyPath', 'credentialAuthorityId',
    'credentialKeyId', 'journalRoot', 'resourceOrigin', 'namespaceId',
    'environment', 'siteKey', 'siteGeneration'];
  const selectedProfile = Object.freeze(Object.fromEntries(profileKeys.map(key => {
    const descriptor = Object.getOwnPropertyDescriptor(profile, key);
    if (!descriptor || !Object.hasOwn(descriptor, 'value')) invalid();
    return [key, descriptor.value];
  })));
  // The selected PEM authority is immutable in the exposed credential facts.
  // This purpose does not accept an arbitrary mutable TLS option object.
  let authority;
  if (ca !== undefined) {
    if (!(typeof ca === 'string' || Buffer.isBuffer(ca)) ||
        ca.length > original.maxCaBytes) invalid();
    authority = typeof ca === 'string' ? ca : ca.toString('latin1');
    if (authority.length > original.maxCaBytes || /[^\x00-\x7f]/u.test(authority)) invalid();
  }
  const synchronous = result => {
    if (result !== undefined) {
      if (typeof result?.then === 'function') void Promise.resolve(result).catch(() => {});
      fail('InvalidInstallationMetadataCurrentFence');
    }
  };
  let closing = false, closed = false, binding, bindingClosed = false;
  let journalClosed = false, retired = false, custody, credential, originalFailure;
  const entries = new Map(), authorizations = new WeakMap(), children = new Set();
  const acquisitions = new WeakMap();
  const profileCurrent = () => profileKeys.every(key => {
    const descriptor = Object.getOwnPropertyDescriptor(profile, key);
    return descriptor !== undefined && Object.hasOwn(descriptor, 'value') &&
      descriptor.value === selectedProfile[key];
  });
  const ensureCurrent = operation => { try {
    if (closing) fail('RowSourceSiteClosed');
    if (originalFailure !== undefined) throw originalFailure;
    host.assertInstalledSourcePublicationRequest(original.publicationRequest, pair);
    if (!profileCurrent()) {
      fail('RowSourceInstallationMetadataSiteChanged');
    }
    synchronous(Reflect.apply(siteCurrent.assertCurrent, original.siteCurrent, []));
    if (closing) fail('RowSourceSiteClosed');
    synchronous(callAccount('assertConfigurationCurrent'));
    for (const entry of entries.values()) {
      if ((operation === undefined || entry.facts.operation === operation) && entry.decision !== undefined) {
        synchronous(callAccount('assertAccountCurrent', entry.decision));
      }
    }
    if (closing) fail('RowSourceSiteClosed');
    host.assertInstalledSourcePublicationRequest(original.publicationRequest, pair);
    if (!profileCurrent()) {
      fail('RowSourceInstallationMetadataSiteChanged');
    }
  } catch (cause) { if (!closing) originalFailure ??= cause; throw cause; } };
  const factsFor = target => {
    const facts = data(Reflect.apply(targetAuthority.project, original.targetAuthority,
      [target, original.declaration]), ['resource', 'operation', 'origin', 'method', 'path', 'bodyBytes']);
    if (!text(facts.resource) || !operations.has(facts.operation) ||
        facts.origin !== selectedProfile.resourceOrigin || facts.method !== 'GET' ||
        !text(facts.path) || facts.bodyBytes !== 0) invalid();
    return Object.freeze(facts);
  };
  const current = async operation => {
    try {
      if (!operations.has(operation)) fail('RowSourceMetadataOperationNotRegistered');
      ensureCurrent(operation);
      await host.observeInstalledSourcePublicationCurrent(original.publicationRequest, pair);
      ensureCurrent(operation);
      synchronous(await Reflect.apply(siteCurrent.observe, original.siteCurrent, []));
      ensureCurrent(operation);
    } catch (cause) { originalFailure ??= cause; throw cause; }
  };
  return Object.freeze({maxIssuerKeyBytes: original.maxIssuerKeyBytes,
    privateKeyPath: selectedProfile.credentialPrivateKeyPath,
    assertInitializingCurrent: () => ensureCurrent(),
    close() {
      // Before Journal acquisition, the existing initialization Owner may
      // retain this view behind an original bounded-key FD cleanup duty.
      if (custody !== undefined) fail('RowSourceMetadataSiteAlreadyAttached');
      closing = true;
      if (!retired) {view.retireMetadataView(); retired = true;}
    },
    attach(originalCustody) {
      custody = originalCustody;
      const retainedJournal = custody.installationMetadataJournal();
      const site = {
        connection,
        current,
        async issueMetadataGrant({target, metadataOccurrenceId, useId,
          expiresUnixMilliseconds, maxUses}) {
          ensureCurrent();
          if (!text(metadataOccurrenceId) || !text(useId) ||
              typeof expiresUnixMilliseconds !== 'bigint' ||
              !Number.isSafeInteger(maxUses) || maxUses <= 0 || maxUses > 10_000) invalid();
          if (entries.has(metadataOccurrenceId)) fail('RowSourceMetadataOccurrenceAlreadyPrepared');
          if (entries.size >= original.maxOperations) fail('RowSourceMetadataOperationLimit');
          const facts = factsFor(target);
          const scope = view.prepareScope(subject, {metadataOccurrenceId,
            operation: facts.operation, resourceOrigin: facts.origin,
            requestMethod: 'GET', requestPath: facts.path,
            requestBodyCid: 'sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'});
          // Retain the original target and fallible outcome before the first
          // await. A failed/Unknown occurrence cannot be prepared again here.
          const entry = {target, facts, scope, decision: undefined, failure: undefined};
          entries.set(metadataOccurrenceId, entry);
          try {
            await current(facts.operation);
            const decision = await callAccount('authorize', 'acquisition', {
              connection, resource: facts.resource, operation: 'read'}, {subjectCid});
            ensureCurrent(facts.operation);
            if (decision.action !== 'dispatch' ||
                decision.boundary !== 'acquisition' || decision.subjectCid !== subjectCid ||
                decision.contextCid !== account.contextCid ||
                decision.tuple?.principal !== principalId ||
                decision.tuple?.connection !== connection ||
                decision.tuple?.resource !== facts.resource || decision.tuple?.operation !== 'read') {
              fail('RowSourceMetadataGrantNotAuthorized');
            }
            // The Account Owner checks this exact scope's nominal dispatch;
            // an equal/copied decision cannot supply current authority.
            synchronous(callAccount('assertAccountCurrent', decision));
            entry.decision = decision;
            ensureCurrent(facts.operation);
            const observed = factsFor(target);
            if (Object.keys(facts).some(key => facts[key] !== observed[key])) {
              fail('RowSourceMetadataTargetChanged');
            }
            const trustedNow = now();
            if (!Number.isSafeInteger(trustedNow) || trustedNow < 0 ||
                expiresUnixMilliseconds <= BigInt(trustedNow) ||
                expiresUnixMilliseconds > BigInt(trustedNow) + BigInt(grantLifetimeMs)) invalid();
            const signed = custody.signInstallationMetadata({control, scope,
              expiresUnixMilliseconds, maxUses});
            entry.signed = signed;
            ensureCurrent(facts.operation);
            if (binding === undefined) {
              binding = openHttpsCredentialBinding({scope, control,
                journal: custody.credential.journal, resolveSecret,
                maxSecretBytes: original.maxSecretBytes, assertCurrent: () => ensureCurrent()});
              credential = Object.freeze({binding, control,
                journal: custody.credential.journal, resolveSecret, ca: authority, now});
              // The metadata Site retains its original Subject, binding and
              // Journal. This private operation view can lend only that SAME
              // original to the shared reader; equal envelopes do not select it.
              operationSites.set(credential, Object.freeze({site, credential,
                referenceCurrent: site.referenceCurrent, callResource: site.callResource,
                authorizationPurpose(authorization) {
                  const entry = authorizations.get(authorization);
                  if (entry === undefined) fail('ForeignRowSourceMetadataChild');
                  ensureCurrent(entry.facts.operation);
                  return Object.freeze({kind: 'installation-metadata', control});
                },
                bindRunAcquisition(authorization, callbacks) {
                  const entry = authorizations.get(authorization);
                  if (entry === undefined || entry.child !== undefined || children.size !== 0 || bindingClosed) {
                    fail('ForeignRowSourceMetadataChild');
                  }
                  const methods = data(callbacks, ['assertCurrent', 'observeCurrent']);
                  if (typeof methods.assertCurrent !== 'function' || typeof methods.observeCurrent !== 'function') invalid();
                  synchronous(Reflect.apply(methods.assertCurrent, callbacks, []));
                  ensureCurrent(entry.facts.operation);
                  // No external callback follows insertion before this original
                  // is returned. A failed current fence cannot strand a lease.
                  const record = {retired: false};
                  const acquisition = Object.freeze({authorization, credential,
                    close() {
                      if (this !== acquisition) fail('ForeignRowSourceMetadataChild');
                      if (!bindingClosed) bindingClosed = closeHttpsCredentialBinding(binding) === 'closed';
                      return bindingClosed ? 'closed' : 'pending';
                    },
                    retire() {
                      if (this !== acquisition) fail('ForeignRowSourceMetadataChild');
                      if (record.retired) return true;
                      if (!bindingClosed) return false;
                      record.retired = true;children.delete(record);
                      return true;
                    }});
                  entry.child = record;children.add(record);acquisitions.set(acquisition, record);
                  return acquisition;
                },
                readChildCredential(acquisition, authorization) {
                  const record = acquisitions.get(acquisition), entry = authorizations.get(authorization);
                  if (record === undefined || record.retired || !children.has(record) || entry === undefined ||
                      entry.child !== undefined && entry.child !== record || bindingClosed) {
                    fail('ForeignRowSourceMetadataChild');
                  }
                  ensureCurrent(entry.facts.operation);
                  // The control checks both scopes against the SAME nominal
                  // metadata Subject, never a copied request/Run substitute.
                  if (!invocationBindingsMatch(authorization.scope, acquisition.authorization.scope, control)) {
                    fail('ForeignRowSourceMetadataChild');
                  }
                  entry.child = record;
                  return credential;
                },
              }));
            }
            const authorization = Object.freeze({...signed, useId});
            authorizations.set(authorization, entry);
            return authorization;
          } catch (cause) {
            entry.failure = cause;
            originalFailure ??= cause;
            throw cause;
          }
        },
        callResource(options) {
          ensureCurrent();
          for (const operation of options?.operations?.values?.() ?? []) {
            if ((operation.responseHeaders ?? []).length !== 0) fail('UndeclaredResponseHeader');
          }
          return callHttpsCredentialResource(options);
        },
        credential() {
          ensureCurrent();
          if (credential === undefined) fail('RowSourceMetadataGrantUnavailable');
          return credential;
        },
        referenceCurrent: () => !closing && originalFailure === undefined && custody.referenceCurrent(),
        cleanupPending: () => closing && !closed,
        close() {
          closing = true;
          if (closed) return;
          if (binding !== undefined && !bindingClosed) {
            bindingClosed = closeHttpsCredentialBinding(binding) === 'closed';
            if (!bindingClosed) fail('RowSourceMetadataCleanupPending');
          }
          // A closed socket is not retirement of the shared reader's
          // callbacks/response aliases. Keep the SAME Journal while borrowed.
          if (children.size !== 0) fail('RowSourceMetadataCleanupPending');
          if (!journalClosed) { retainedJournal.close(); journalClosed = true; }
          if (!retired) { view.retireMetadataView(); retired = true; }
          closed = true;
        },
      };
      return Object.freeze({site: Object.freeze(site), failure: retainedJournal.failure});
    },
  });
}

// The credential Site of one installed row source: the credential authority
// key, the credential journal and the secret resolver. Grants are signed
// only for a read decision the installed gate returned as dispatch for this
// connection and Resource, or for a Checkpoint approval of exactly this
// installation's physical target.
// `responseHeaders` is the installation's declared response header names
// (its `host-bundle.json`); the Site's `callResource` refuses, before any
// credential use, an operation that would observe any other header.
// Optional `admitsEffectTargetRead(binding, resource, operation)` belongs to
// the same trusted installation. It validates the driver's exact original
// physical binding and read operation; it cannot replace Checkpoint facts or
// current/entry authority. The returned Site accepts that original decision
// with `admitCheckpointEffectTargetRead(decision, binding, operation)`.
// Each such approval adds a seven-field record, the bounded canonical binding
// String and original binding/fence aliases in this Site's existing WeakMap.
// Canonical comparison and signing overlap the original bounded inventory;
// these controls do not supply a numerical reservation or physical close ACK.
export async function openRowSourceCredentialSite({profile, principalId,
  authorization, connection, connectorRegistration, connectorRevision,
  runtimeBundleCid, commonMoon, resolveSecret, ca, admitsApprovalTarget,
  admitsEffectTargetRead,
  installationMetadata,
  runAcquisitionLimits, configurationReader,
  ownAuthorization = false, secretMaterial,
  responseHeaders = [],
  now = () => Date.now(), grantLifetimeMs = 15 * 60 * 1000,
  openCredentialJournal = openSqliteCredentialJournal}) {
  const secretPresentation = ownCredentialSecretPresentation(arguments[0]);
  if (!text(profile?.credentialPrivateKeyPath) ||
      !isAbsolute(profile.credentialPrivateKeyPath) ||
      !text(profile.credentialAuthorityId) || !text(profile.credentialKeyId) ||
      !text(profile.journalRoot) || !isAbsolute(profile.journalRoot) ||
      !text(profile.resourceOrigin) || !text(profile.namespaceId) ||
      !text(profile.environment) || !text(profile.siteKey) ||
      !Number.isSafeInteger(profile.siteGeneration) ||
      typeof resolveSecret !== 'function' ||
      (installationMetadata === undefined && typeof admitsApprovalTarget !== 'function')) {
    fail('InvalidRowSourceCredentialSite');
  }
  if (typeof ownAuthorization !== 'boolean' ||
      (secretMaterial !== undefined && !ownAuthorization) ||
      (ownAuthorization && installationMetadata !== undefined) ||
      (admitsEffectTargetRead !== undefined && typeof admitsEffectTargetRead !== 'function') ||
      !Array.isArray(responseHeaders) ||
      responseHeaders.some(name => !text(name))) {
    fail('InvalidRowSourceCredentialSite');
  }
  const authorizationClose = ownAuthorization ?
    Object.getOwnPropertyDescriptor(authorization, 'close')?.value : undefined;
  if (ownAuthorization && typeof authorizationClose !== 'function') {
    fail('InvalidRowSourceAuthorizationInstallation');
  }
  const declaredHeaders = new Set(responseHeaders);
  const selectedAcquisitionLimits = ownCredentialAcquisitionLimits(runAcquisitionLimits);
  // Capture the SAME Source reader before metadata/current work can await.
  // The existing issuer-byte bound remains mandatory on this original read.
  let metadataKeyRead;
  if (installationMetadata !== undefined && configurationReader !== undefined) {
    if (configurationReader === null || typeof configurationReader !== 'object' ||
        nodeTypes.isProxy(configurationReader)) fail('InvalidRowSourceCredentialSite');
    const method = Object.getOwnPropertyDescriptor(configurationReader, 'readText');
    if (!method || !Object.hasOwn(method, 'value') || typeof method.value !== 'function') {
      fail('InvalidRowSourceCredentialSite');
    }
    metadataKeyRead = method.value;
  }
  const metadata = installationMetadata === undefined ? undefined
    : await prepareInstallationMetadataSite({installationMetadata, profile,
      principalId, authorization, connection, connectorRegistration,
      connectorRevision, runtimeBundleCid, commonMoon, resolveSecret, ca,
      now, grantLifetimeMs, ...(secretPresentation === undefined ? {} : {secretPresentation})});
  const custodyOptions = {profile, principalId,
    connectorRegistration, connectorRevision, runtimeBundleCid, commonMoon,
    resolveSecret, ca, now, grantLifetimeMs, openCredentialJournal,
    configurationReader,
    runAcquisitionLimits: selectedAcquisitionLimits,
    ...(secretPresentation === undefined ? {} : {secretPresentation})};
  let custody;
  if (metadata === undefined) custody = await loadRowSourceCredentialCustody(custodyOptions);
  else {
    // This separately typed purpose retains its bounded key read and original
    // initialization/current carrier. It does not adopt legacy Run defaults.
    let privateKey;
    try {
      privateKey = createPrivateKey(await (metadataKeyRead === undefined
        ? readBoundedConfigurationText(metadata.privateKeyPath, {maxBytes: metadata.maxIssuerKeyBytes})
        : Reflect.apply(metadataKeyRead, configurationReader,
          [metadata.privateKeyPath, {maxBytes: metadata.maxIssuerKeyBytes}])));
      if (privateKey.asymmetricKeyType !== 'ed25519') fail('InvalidRowSourceCredentialSite');
      metadata.assertInitializingCurrent();
      custody = openRowSourceCredentialCustody({...custodyOptions, privateKey});
    } catch (error) {
      // The same metadata view already exists even when no Site was returned.
      // Its existing cleanup waits for any original failed child first.
      throw await retainInstalledHostInitializationFailure(error, {sourceProfile: metadata});
    }
  }
  if (metadata !== undefined) {
    const attached = metadata.attach(custody);
    if (attached.failure !== undefined) throw await retainInstalledHostInitializationFailure(
      attached.failure, {sourceProfile: attached.site});
    return attached.site;
  }
  const {credential, ensureOpen, checkGrantRequest, sign} = custody;
  let custodyClosed = false, authorizationClosed = false;
  const custodyClose = custody.close;
  const closeOwnedAuthorization = () => {
    if (!custodyClosed) {Reflect.apply(custodyClose, custody, []); custodyClosed = true;}
    if (!authorizationClosed) {
      if (Reflect.apply(authorizationClose, authorization, []) !== true) {
        fail('RowSourceAuthorizationCleanupPending');
      }
      authorizationClosed = true;
    }
    if (secretMaterial !== undefined) secretMaterial.close();
  };
  const approvals = new WeakMap();
  const callResource = options => {
    for (const operation of options?.operations?.values?.() ?? []) {
      for (const name of operation?.responseHeaders ?? []) {
        if (!declaredHeaders.has(name)) fail('UndeclaredResponseHeader');
      }
    }
    return callHttpsCredentialResource(options);
  };
  const bindingWire = value => canonicalValueJson(value, {dataKeys: true});
  function synchronous(result) {
    // Checkpoint currency/entry are synchronous Owner operations. An async
    // callback cannot finish after a credential has already been issued.
    if (result !== undefined) {
      if (typeof result?.then === 'function') void Promise.resolve(result).catch(() => {});
      fail('RowSourceEffectTargetReadApprovalNotAdmitted');
    }
  }
  function currentEffectRead(approved) {
    ensureOpen();
    if (bindingWire(approved.binding) !== approved.wire) {
      fail('RowSourceEffectTargetReadApprovalNotAdmitted');
    }
    const admitted = admitsEffectTargetRead(approved.binding, approved.resource, approved.operation);
    if (admitted !== true) {
      if (typeof admitted?.then === 'function') void Promise.resolve(admitted).catch(() => {});
      fail('RowSourceEffectTargetReadApprovalNotAdmitted');
    }
    synchronous(approved.assertCurrent());
    ensureOpen();
    if (bindingWire(approved.binding) !== approved.wire) {
      fail('RowSourceEffectTargetReadApprovalNotAdmitted');
    }
  }
  return retainCredentialOperationSite(Object.freeze({
    credential, connection, callResource,
    // Borrowed references observe this same Site's lifecycle, not a caller's
    // permission Boolean. False means closing, not physical cleanup ACK.
    referenceCurrent: custody.referenceCurrent,
    // Admit a resumed Checkpoint approval only for this installation's own
    // physical target of the same Resource.
    admitCheckpointReadApproval(decision) {
      ensureOpen();
      const facts = checkpointApprovalFacts(decision);
      if (facts === undefined || facts.kind === 'effect_target' || decision.action !== 'dispatch' ||
          decision.basis !== 'resumed_approval' ||
          decision.boundary !== 'acquisition' ||
          decision.tuple?.connection !== connection ||
          decision.tuple?.operation !== 'read' ||
          facts.principalId !== principalId ||
          facts.readTuple?.connection !== connection ||
          facts.readTuple?.operation !== 'read' ||
          facts.readTuple?.resource !== decision.tuple.resource ||
          !admitsApprovalTarget(facts.physicalBinding, decision.tuple.resource)) {
        fail('RowSourceReadApprovalNotAdmitted');
      }
      approvals.set(decision, decision.tuple.resource);
      return decision;
    },
    // The existing Checkpoint continuation supplies this exact original
    // decision and its live entry/current fences. The installed driver checks
    // its own member/Site binding and read operation; matching DATA alone is
    // never admission. Keep the original decision, not a replacement grant.
    admitCheckpointEffectTargetRead(decision, physicalBinding, operation) {
      ensureOpen();
      const facts = checkpointApprovalFacts(decision);
      if (typeof admitsEffectTargetRead !== 'function' || !text(operation) ||
          facts?.kind !== 'effect_target' || decision.action !== 'dispatch' ||
          decision.boundary !== 'acquisition' || facts.principalId !== principalId ||
          !cidPattern.test(authorization.configurationCid ?? '') ||
          !cidPattern.test(authorization.context?.contextCid ?? '') ||
          facts.configurationCid !== authorization.configurationCid ||
          facts.contextCid !== authorization.context.contextCid ||
          decision.tuple?.connection !== connection || decision.tuple?.operation !== 'read' ||
          facts.readTuple?.connection !== connection || facts.readTuple?.operation !== 'read' ||
          facts.readTuple?.resource !== decision.tuple.resource ||
          typeof facts.assertCurrent !== 'function' || typeof facts.enter !== 'function' ||
          !Array.isArray(facts.physicalBindings)) {
        fail('RowSourceEffectTargetReadApprovalNotAdmitted');
      }
      const wire = bindingWire(physicalBinding);
      if (!facts.physicalBindings.some(binding => bindingWire(binding) === wire)) {
        fail('RowSourceEffectTargetReadApprovalNotAdmitted');
      }
      const approved = Object.freeze({kind: 'effect_target', resource: decision.tuple.resource,
        operation, binding: physicalBinding, wire,
        assertCurrent: facts.assertCurrent, enter: facts.enter});
      currentEffectRead(approved);
      approvals.set(decision, approved);
      return decision;
    },
    issueReadGrant({operation, decision, resource, runInvocationCid,
      dispatchRequestCid, maxUses}) {
      ensureOpen();
      const approved = approvals.get(decision);
      if (approved !== undefined) {
        if (typeof approved === 'string') {
          if (approved !== resource) fail('RowSourceGrantNotAuthorized');
        } else {
          if (approved.resource !== resource || approved.operation !== operation) {
            fail('RowSourceGrantNotAuthorized');
          }
          // Validate before consuming the original one-shot entry. A malformed
          // request cannot spend it; journal/signing failures after entry stay
          // with the existing acquisition/capture cleanup and never reset it.
          checkGrantRequest(runInvocationCid, dispatchRequestCid, maxUses);
          currentEffectRead(approved);
          synchronous(approved.enter());
          currentEffectRead(approved);
        }
      } else if (!authorization.issued(decision) ||
          decision.action !== 'dispatch' ||
          decision.boundary !== 'acquisition' ||
          decision.contextCid !== authorization.context.contextCid ||
          decision.tuple?.connection !== connection ||
          decision.tuple?.resource !== resource ||
          decision.tuple?.operation !== 'read') {
        fail('RowSourceGrantNotAuthorized');
      }
      return sign({operation, runInvocationCid, dispatchRequestCid, maxUses,
        issuerPurpose: Object.freeze({kind: typeof approved === 'object' ? 'target-read' : 'read',
          resource, decision,
          ...(typeof approved === 'object' ? {physicalBinding: approved.binding} : {})})});
    },
    // One write grant for an Effect commit decision on `resource`, for the
    // sealed Set `subjectCid`. A commit the Host's own Checkpoint commit gate
    // decided counts only when that gate decided it for this principal under
    // this exact account configuration; the gate owns its approval's
    // currency.
    issueEffectGrant({operation, decision, resource, runInvocationCid,
      dispatchRequestCid, subjectCid}) {
      ensureOpen();
      const facts = authorizationDispatchFacts(decision);
      const hostCommit = facts !== undefined &&
        facts.principal === principalId &&
        facts.configurationCid === authorization.configurationCid;
      if (!text(operation) || !cidPattern.test(subjectCid ?? '') ||
          !(authorization.issued(decision) || hostCommit) ||
          decision.action !== 'dispatch' ||
          decision.boundary !== 'effect_commit' ||
          (!hostCommit &&
            decision.contextCid !== authorization.context.contextCid) ||
          decision.tuple?.connection !== connection ||
          decision.tuple?.resource !== resource ||
          decision.tuple?.operation !== 'effect' ||
          decision.subjectCid !== subjectCid) {
        fail('RowSourceGrantNotAuthorized');
      }
      return sign({operation, runInvocationCid, dispatchRequestCid,
        maxUses: 1, issuerPurpose: Object.freeze({kind: 'effect', resource, decision})});
    },
    close: ownAuthorization ? closeOwnedAuthorization : custody.close,
  }), custody, {connection, principalId, connectorRegistration,
    connectorRevision, runtimeBundleCid}, selectedAcquisitionLimits !== undefined);
}

// The installed source adapter of one row declaration (see
// `installed-source.mjs`). `readPages({resource, columns, requestWire, operation,
// authorizationFor, chargePage, consumeObservation, consumePage, listing, signal})`
// is the Site driver.
// A checked listing uses listing.beginRequest(token) before each actual send
// and awaits listing.consumePage(fullEnvelope, {charge}) for all observed items.
// Provider translation charges the original response before decoding; its
// exact ticket carries physical bytes into the common listing budget.
// An accounted ordinary acquisition can consume a non-row observation's exact
// ticket without adding a data page. Its request authorization/count and typed
// observation remain the installed driver's responsibility; this is no grant.
// ordinary rows use consumePage. Completion is never the driver's return alone;
// `physicalTarget(resource, fields)` the exact target an approval covers.
// Standard installations may instead supply their frozen full target DATA
// inventory. It has no authorization/current/physical cleanup methods.
export async function createInstalledRowSource({moon, declaration, commands,
  declared, environmentWire, environment, sourceInitialization, connectorId, connectorRegistration,
  connectorRevision, site, authorization, readOperation, physicalTarget,
  readPages, bindingCid, publicationBindingCid, tableReadTargets, publication,
  publicationSurface, realizationKey = 'row-source-acquired', limits, referenceIssuer, listingPolicy, captureContent,
  listingReportCapacity, prepareAcquisition, directReadIdentity,
  prepareRead, grantBeforeBegin = false, originalSourceAccess, providerReader,
  prepareSourceRead, closeSourceRead, prepareKeyedSourceRead, closeKeyedSourceRead,
  originalKeyedTransport, readAsset, originalPageLimits}) {
  if (typeof realizationKey !== 'string' || realizationKey.length === 0) fail('InvalidInstalledSourcePublication');
  let selectedSurface;
  if (publicationSurface !== undefined) {
    if (!Array.isArray(publicationSurface) || nodeTypes.isProxy(publicationSurface) ||
        !Object.isFrozen(publicationSurface)) fail('InvalidInstalledSourcePublication');
    selectedSurface = [];
    for (let i = 0; i < publicationSurface.length; i++) {
      const field = Object.getOwnPropertyDescriptor(publicationSurface, String(i));
      if (!field || !Object.hasOwn(field, 'value') || typeof field.value !== 'string' ||
          selectedSurface.includes(field.value)) fail('InvalidInstalledSourcePublication');
      selectedSurface.push(field.value);
    }
    if (['realizationKey','supportsRetainedRelationOutput','connectorRegistration','connectorRevision',
      'environmentWire','connectorBindings','readAuthorization','sourceAccess','sourceReadAccesses',
      'admitsSource','ledgerCapacity','prepare','open','close'].some(key => !selectedSurface.includes(key))) {
      fail('InvalidInstalledSourcePublication');
    }
  }
  let publicationFields = {};
  if (publication !== undefined) {
    if (!publication || typeof publication !== 'object' || nodeTypes.isProxy(publication) ||
        !Object.isFrozen(publication) ||
        ![Object.prototype, null].includes(Object.getPrototypeOf(publication))) fail('InvalidInstalledSourcePublication');
    publicationFields = Object.getOwnPropertyDescriptors(publication);
    for (const key of Reflect.ownKeys(publicationFields)) {
      if (typeof key !== 'string' || key === 'then' ||
          !Object.hasOwn(publicationFields[key], 'value')) fail('InvalidInstalledSourcePublication');
    }
  }
  const readerDemand = sourceInitialization === undefined ? undefined
    : assertInstalledSourceConstruction(sourceInitialization, declaration, declared, environment, providerReader, undefined, commands);
  const retainedAcquisitionContracts = sourceInitialization !== undefined && prepareAcquisition === undefined;
  const prepareWithContracts = !retainedAcquisitionContracts ? undefined
    : moon.clientProgramRowSourcePrepareAcquisitionWithContracts;
  if (retainedAcquisitionContracts && typeof prepareWithContracts !== 'function') {
    fail('InstalledSourceInitializationRuntimeUnavailable');
  }
  if (sourceInitialization !== undefined && environment?.wire !== environmentWire) {
    fail('ForeignInstalledSourceConstruction');
  }
  // Trusted installation compatibility only: preserve an existing provider
  // identity and ordering while this one Owner retains preparation, current
  // authorization, RowRun, capture and failure cleanup. No wire selects this
  // port and none of these callbacks issues authority or a cleanup ACK.
  if (directReadIdentity !== undefined &&
      (directReadIdentity === null || typeof directReadIdentity !== 'object' ||
        Array.isArray(directReadIdentity) || !Object.isFrozen(directReadIdentity) ||
        Object.getPrototypeOf(directReadIdentity) !== Object.prototype ||
        Object.keys(directReadIdentity).sort().join("\0") !==
          ["attempt", "input", "subject", "useId"].join("\0") ||
        !Number.isSafeInteger(directReadIdentity.input) || directReadIdentity.input < 0 ||
        !["subject", "attempt", "useId"].every(key =>
          typeof directReadIdentity[key] === "function"))) {
    fail("InvalidInstalledSourceReadIdentity");
  }
  if ((prepareRead !== undefined && typeof prepareRead !== "function") ||
      typeof grantBeforeBegin !== "boolean") {
    fail("InvalidInstalledSourceReadPreparation");
  }
  // One trusted installation's original declaration and I/O-free preparer.
  // Public packets/configuration cannot replace either after preparation.
  // The declaration is DATA; Core still reserves on the original Run Ledger.
  let originalReader;
  // Managed and advanced page readers are distinct installation alternatives.
  // A managed reader never needs a dummy or fallback unaccounted readPages.
  if (providerReader === undefined ? typeof readPages !== 'function' : readPages !== undefined) {
    fail('InvalidInstalledSourceReader');
  }
  if ((prepareKeyedSourceRead !== undefined || closeKeyedSourceRead !== undefined) &&
      (typeof prepareKeyedSourceRead !== 'function' || typeof closeKeyedSourceRead !== 'function' ||
        providerReader !== undefined || listingReportCapacity !== undefined ||
        ['clientProgramInstalledKeyedSourceReadCheckCurrent',
          'clientProgramInstalledKeyedSourceReadAcquisition',
          'clientProgramInstalledKeyedSourceReadRetire']
          .some(name => typeof moon?.[name] !== 'function'))) fail('InstalledKeyedSourceReadUnavailable');
  if (prepareSourceRead !== undefined && (typeof prepareSourceRead !== 'function' ||
      providerReader !== undefined || listingReportCapacity !== undefined ||
      ['clientProgramInstalledSourceReadCheckCurrent', 'clientProgramInstalledSourceReadBindProgram',
        'clientProgramInstalledSourceReadBindEffectProgram', 'clientProgramInstalledSourceReadAttachAcquisition']
        .some(name => typeof moon?.[name] !== 'function'))) fail('InstalledSourceReadUnavailable');
  if (closeSourceRead !== undefined && (typeof closeSourceRead !== 'function' ||
      prepareSourceRead === undefined)) fail('InstalledSourceReadUnavailable');
  // Only the original local Source consumer can borrow these private
  // installation inputs. Neither option is a public packet or a capacity
  // issuer; the same RowRun still admits its actual original child below.
  if (readAsset !== undefined && (prepareSourceRead === undefined ||
      typeof readAsset !== 'function')) fail('InstalledSourceReadUnavailable');
  let pageLimits;
  if (originalPageLimits !== undefined) {
    if (prepareSourceRead === undefined || originalPageLimits === null ||
        typeof originalPageLimits !== 'object' || nodeTypes.isProxy(originalPageLimits) ||
        Object.getPrototypeOf(originalPageLimits) !== Object.prototype) fail('InvalidInstalledSourcePageLimits');
    const properties = Object.getOwnPropertyDescriptors(originalPageLimits);
    if (Reflect.ownKeys(properties).length !== 2 || ['maxNodes', 'maxDepth'].some(name =>
      !Object.hasOwn(properties[name] ?? {}, 'value') ||
      !Number.isSafeInteger(properties[name].value) || properties[name].value < 1 ||
      properties[name].value > 2147483647) ||
      typeof moon.clientProgramRowSourceBeginWithPageLimits !== 'function') fail('InvalidInstalledSourcePageLimits');
    pageLimits = Object.freeze({maxNodes: properties.maxNodes.value, maxDepth: properties.maxDepth.value});
  }
  if (providerReader !== undefined) {
    if (providerReader === null || typeof providerReader !== 'object' ||
        nodeTypes.isProxy(providerReader)) fail('InvalidInstalledSourceReader');
    const fields = Object.getOwnPropertyDescriptors(providerReader);
    const names = Reflect.ownKeys(fields);
    if (names.length !== (Object.hasOwn(fields, 'retire') ? 3 : 2) ||
        ['capacity', 'prepare'].some(function invalidReaderField(name) {
          return !Object.hasOwn(fields[name] ?? {}, 'value');
        }) ||
        Object.hasOwn(fields, 'retire') && (!Object.hasOwn(fields.retire, 'value') ||
          typeof fields.retire.value !== 'function')) fail('InvalidInstalledSourceReader');
    const capacity = fields.capacity.value, prepare = fields.prepare.value;
    const retire = fields.retire?.value;
    if (capacity === undefined || capacity === null || typeof prepare !== 'function' ||
        listingReportCapacity !== undefined) fail('InvalidInstalledSourceReader');
    if (['clientProgramInstalledProviderRowCaptureCapacity',
      'clientProgramInstalledProviderRowCaptureCapacityMatches',
      'clientProgramRowSourceStartProviderAccounted', 'clientProgramRowSourceBorrowResponses',
      'clientProgramRowSourceBindResponseCleanup'].some(name => typeof moon?.[name] !== 'function')) {
      fail('InstalledProviderSourceUnavailable');
    }
    originalReader = Object.freeze({capacity, prepare, retire, receiver: providerReader});
  }
  let managedPageLimits;
  if (readerDemand !== undefined) {
    // This is the SAME immutable service selection already checked against
    // this declaration/Environment/reader, not the legacy preparer option.
    if (nodeTypes.isProxy(readerDemand)) fail('InvalidInstalledSourceReaderPageDemand');
    const nodes = Object.getOwnPropertyDescriptor(readerDemand, 'maxNodes');
    const depth = Object.getOwnPropertyDescriptor(readerDemand, 'maxDepth');
    if (!nodes || !depth || !Object.hasOwn(nodes, 'value') || !Object.hasOwn(depth, 'value') ||
        !Number.isSafeInteger(nodes.value) || nodes.value < 1 || nodes.value > 2147483647 ||
        !Number.isSafeInteger(depth.value) || depth.value < 1 || depth.value > 2147483647 ||
        typeof moon.clientProgramRowSourceBeginWithPageLimits !== 'function') {
      fail('InvalidInstalledSourceReaderPageDemand');
    }
    managedPageLimits = Object.freeze({maxNodes: nodes.value, maxDepth: depth.value});
  }
  if (prepareAcquisition !== undefined &&
      (typeof prepareAcquisition !== 'function' ||
        typeof moon?.clientProgramRowSourceCheckOriginalAcquisition !== 'function')) {
    fail('InvalidInstalledSourceAcquisitionPreparer');
  }
  if (captureContent !== undefined && typeof captureContent !== 'function') {
    fail('InvalidInstalledContentCapture');
  }
  // Exact trusted installation declaration, not a packet value or a callback
  // capable of choosing another capacity after acquisition. The installation
  // must justify it for every listing selector admitted by this declaration,
  // target and limits. Absence keeps the existing non-report profile; it does
  // not manufacture the completed-report guarantees or a Model grant.
  if (listingReportCapacity !== undefined &&
      (listingReportCapacity === null || typeof listingReportCapacity !== 'object' ||
        Array.isArray(listingReportCapacity))) {
    fail('InvalidInstalledListingReportCapacity');
  }
  if (listingReportCapacity !== undefined &&
      (typeof moon?.clientProgramInstalledListingRowCaptureCapacity !== 'function' ||
        typeof moon?.clientProgramRowSourceStartListingAccounted !== 'function')) {
    fail('InstalledListingSourceUnavailable');
  }
  const [queryContract, evidenceContract] = readAsset === undefined
    ? await Promise.all(['actql-query-acquisition.json', 'actql-query-process-evidence.json']
      .map(name => sourceInitialization !== undefined
        ? readInstalledSourceAcquisitionContract(sourceInitialization, fileURLToPath(new URL(name,contractRoot)))
        : readFile(new URL(name, contractRoot), 'utf8')))
    : ['actql-query-acquisition.json', 'actql-query-process-evidence.json']
      .map(name => readAsset(`spec/contracts/${name}`));
  if (typeof queryContract !== 'string' || typeof evidenceContract !== 'string') {
    fail('InstalledSourceReadUnavailable');
  }
  // The default normal constructor retains one admitted protocol original on
  // its SAME initialization material. Existing provider-specific preparers and
  // explicit legacy constructors keep their original raw-wire entry law.
  let acquisitionContracts = retainedAcquisitionContracts
    ? prepareInstalledSourceAcquisitionContracts(sourceInitialization, queryContract, evidenceContract) : undefined;
  const sourceRefs = new Set(declared.views.map(view => view.source_ref));
  if (!['maxPages', 'maxPageBytes', 'maxPageRows', 'maxCaptureRows']
    .every(key => Number.isSafeInteger(limits?.[key]) && limits[key] > 0 &&
      limits[key] <= 2_147_483_647)) {
    fail('InvalidInstalledRowSourceLimits');
  }
  if (readerDemand !== undefined && (limits.maxPages !== readerDemand.queryPages ||
      limits.maxPageBytes !== readerDemand.maxResponseBytes || limits.maxPageRows !== readerDemand.maxRows ||
      limits.maxCaptureRows !== readerDemand.maxTotalRows)) fail('ForeignInstalledSourceReaderDemand');
  const maxTransferBytes = readerDemand?.transferBytes ??
    BigInt(limits.maxPages) * BigInt(limits.maxPageBytes);
  let keyedTransferBytes = maxTransferBytes, keyedExecutionBytes = BigInt(limits.maxPageBytes);
  if (originalKeyedTransport !== undefined) {
    // Fixed installing Source limits, not a public packet, grant or Resource
    // original. Actual same-Run admission must cover this complete transport
    // workspace, including collected native bytes beside encoding/capture.
    if (prepareKeyedSourceRead === undefined || originalKeyedTransport === null ||
        typeof originalKeyedTransport !== 'object' || nodeTypes.isProxy(originalKeyedTransport)) {
      fail('InvalidInstalledKeyedTransportLimits');
    }
    const fields = Object.getOwnPropertyDescriptors(originalKeyedTransport);
    if (Reflect.ownKeys(fields).length !== 2 || ['transferBytes', 'executionBytes'].some(name =>
      !Object.hasOwn(fields[name] ?? {}, 'value') || typeof fields[name].value !== 'bigint' ||
      fields[name].value < 0n || fields[name].value > 9223372036854775807n)) {
      fail('InvalidInstalledKeyedTransportLimits');
    }
    keyedTransferBytes = fields.transferBytes.value;
    keyedExecutionBytes = fields.executionBytes.value;
  }
  // A plural Source can expose separately registered metadata/content reads.
  // Copy its closed Resource->operation binding once; a Run's selected view
  // cannot substitute another operation or inherit a missing view's grant.
  const resources = new Set(declared.views.map(view => view.resource));
  const operationBindings = typeof readOperation === 'string'
    ? new Map([...resources].map(resource => [resource, readOperation]))
    : readOperation !== null && typeof readOperation === 'object' && !Array.isArray(readOperation)
      ? new Map(Object.entries(readOperation)) : undefined;
  if (operationBindings === undefined || operationBindings.size !== resources.size ||
      [...operationBindings].some(([resource, operation]) => !resources.has(resource) || !text(operation))) {
    fail('InvalidInstalledRowSourceOperations');
  }
  const immutableTargets = prepareImmutablePhysicalTargets(physicalTarget);
  if (immutableTargets !== undefined) physicalTarget = immutableTargets.prepare;
  let physicalTargetGeneration = immutableTargets?.inventory;
  const preparations = new WeakMap();
  // SAME prepared read, retained until the accounted RowRun takes custody.
  const preparingSourceReads = new Set();
  const keyedPreparations = new WeakMap();
  function prepareOriginalAcquisition(requirement) {
    if (retainedAcquisitionContracts && acquisitionContracts === undefined) fail('InstalledSourceInitializationClosed');
    const acquisition = prepareAcquisition === undefined
      ? !retainedAcquisitionContracts
        ? checked(moon.clientProgramRowSourcePrepareAcquisition(
          declaration, requirement, queryContract, evidenceContract, listingPolicy))
        : checked(Reflect.apply(prepareWithContracts, moon,
          [declaration, requirement, acquisitionContracts, listingPolicy]))
      : prepareAcquisition(Object.freeze({declaration, requirement,
        queryContract, evidenceContract}));
    if (prepareAcquisition !== undefined) {
      checked(moon.clientProgramRowSourceCheckOriginalAcquisition(
        acquisition, declaration, requirement));
    }
    return acquisition;
  }
  const providerSiteCurrent = originalReader === undefined ? undefined : site.referenceCurrent;
  function managedProviderCaptureCapacity(requirement) {
    if (originalReader === undefined) {
      if (typeof prepareSourceRead !== 'function') fail('InstalledSourceCapacityUnavailable');
      // A Host-backed original read uses the same checked Row acquisition,
      // without pretending to have a provider reader or a second Run budget.
      const acquisition = prepareOriginalAcquisition(requirement);
      const capacity = moon.clientProgramInstalledRowCaptureCapacity(acquisition);
      if (capacity === undefined) fail('InstalledSourceCapacityUnavailable');
      return Object.freeze({capacity, transferBytes: maxTransferBytes,
        executionBytes: BigInt(limits.maxPageBytes)});
    }
    if (typeof providerSiteCurrent !== 'function' ||
        Reflect.apply(providerSiteCurrent, site, []) !== true) fail('InstalledSourceReaderNotCurrent');
    const acquisition = prepareOriginalAcquisition(requirement);
    const capacity = moon.clientProgramInstalledProviderRowCaptureCapacity(acquisition, originalReader.capacity);
    if (capacity === undefined || moon.clientProgramInstalledProviderRowCaptureCapacityMatches(
      capacity, acquisition, originalReader.capacity) !== true) fail('InstalledSourceCapacityUnavailable');
    return Object.freeze({capacity, transferBytes: maxTransferBytes,
      executionBytes: BigInt(limits.maxPageBytes)});
  }
  function managedWholeSourceCapacity({preparedProgram, sourceSelection, installedContracts}) {
    if (originalReader === undefined || typeof providerSiteCurrent !== 'function' ||
        Reflect.apply(providerSiteCurrent, site, []) !== true) fail('InstalledSourceReaderNotCurrent');
    const selectedPageLimits = managedPageLimits ?? pageLimits;
    const capacity = checked(moon.clientProgramPrepareWholeSourceCapacity(
      preparedProgram, sourceSelection, declaration, installedContracts, originalReader.capacity,
      limits.maxCaptureRows, limits.maxPageBytes, selectedPageLimits?.maxNodes ?? 400000,
      selectedPageLimits?.maxDepth ?? 32, limits.maxPageRows));
    return Object.freeze({capacity, wholeInput: true, transferBytes: maxTransferBytes,
      executionBytes: BigInt(limits.maxPageBytes)});
  }
  const captureCapacity = owner => {
    if (originalReader !== undefined) {
      if (owner.wholeInput) {
        if (moon.clientProgramWholeSourceCapacityMatches(
          owner.providerCaptureCapacity, owner.acquisition, originalReader.capacity) !== true) {
          fail('InstalledSourcePreparationMismatch');
        }
        return owner.providerCaptureCapacity;
      }
      if (moon.clientProgramInstalledProviderRowCaptureCapacityMatches(
        owner.providerCaptureCapacity, owner.acquisition, originalReader.capacity) !== true) {
        fail('InstalledSourcePreparationMismatch');
      }
      return owner.providerCaptureCapacity;
    }
    if (owner.providerCaptureCapacity !== undefined) return owner.providerCaptureCapacity;
    return listingReportCapacity !== undefined &&
        moon.clientProgramRowSourceIsListing(owner.acquisition)
      ? moon.clientProgramInstalledListingRowCaptureCapacity(owner.acquisition, listingReportCapacity)
      : moon.clientProgramInstalledRowCaptureCapacity(owner.acquisition);
  };
  const installationBinding = Object.freeze({connectorId, connectorRegistration,
    connectorRevision, bindingCid});
  function ordinaryRecoveryBinding(prepared) {
    const owner = preparations.get(prepared);
    if (owner === undefined || !validInstallationBinding(installationBinding)) {
      fail('InstalledSourcePreparationMismatch');
    }
    if (immutableTargets === undefined
      ? valueCid(prepared.physicalBinding) !== owner.physicalBindingCid
      : physicalTargetGeneration === undefined || owner.physicalTargetGeneration !== physicalTargetGeneration ||
        prepared.physicalBinding !== owner.physicalBindingOriginal) {
      fail('InstalledSourcePreparationMismatch');
    }
    const [resource, ...fields] = owner.wholeInput
      ? moon.clientProgramWholeSourceTarget(owner.acquisition)
      : checked(moon.clientProgramRowSourceTarget(declaration, owner.requirement));
    if (resource !== owner.resource || prepared.readTuple.connection !== site.connection ||
        prepared.readTuple.resource !== resource || prepared.readTuple.operation !== 'read') {
      fail('InstalledSourcePreparationMismatch');
    }
    // The same immutable target was fully constructed and hashed at prepare.
    // Still obtain the exact Core target and compare all ordered field names;
    // this is not an Account decision or a substitute for its current checks.
    if (immutableTargets === undefined
      ? valueCid(physicalTarget(resource, fields)) !== owner.physicalBindingCid
      : fields.length !== owner.physicalBindingOriginal.fields.length ||
        fields.some((field, index) => field !== owner.physicalBindingOriginal.fields[index])) {
      fail('InstalledSourcePreparationMismatch');
    }
    return installationBinding;
  }
  // Preserve an original installation's exact immutable access metadata;
  // this is neither a wire object nor an authorization decision. Defaults
  // keep the ordinary singleton Source projection unchanged.
  if (originalSourceAccess !== undefined &&
      (originalSourceAccess === null || typeof originalSourceAccess !== 'object' ||
        Object.getPrototypeOf(originalSourceAccess) !== Object.prototype ||
        !Object.isFrozen(originalSourceAccess) ||
        Reflect.ownKeys(originalSourceAccess).sort().join('\0') !== 'authorization\0connection' ||
        Object.getOwnPropertyDescriptor(originalSourceAccess, 'authorization')?.value !== authorization ||
        Object.getOwnPropertyDescriptor(originalSourceAccess, 'connection')?.value !== site.connection)) {
    fail('InvalidInstalledSourceAccess');
  }
  const sourceAccess = originalSourceAccess ?? Object.freeze({authorization,
    connection: site.connection,
    ...(sourceRefs.size === 1 ? {sourceRef: [...sourceRefs][0]} : {})});
  // Read disclosure and held-Run authority are per declared view. The
  // acquisition access stays installation-scoped; its checked preparation
  // supplies the one exact view and read tuple before provider I/O.
  const sourceReadAccesses = Object.freeze(declared.views.map(view =>
    Object.freeze({authorization, connection: site.connection,
      sourceRef: view.source_ref, resource: view.resource})));
  const ordinarySubject = prepared => {
    const subject = directReadIdentity === undefined
      ? cid({version: 'actql-row-source-acquisition-read/0.1',
        ...(prepared.checkedSource.sourceInput === undefined
          ? {requirementCid: prepared.checkedSource.requirementCid}
          : {sourceInput: prepared.checkedSource.sourceInput}), physicalBinding: prepared.physicalBinding})
      : directReadIdentity.subject(prepared);
    if (typeof subject !== 'string' || !cidPattern.test(subject)) {
      fail('InvalidInstalledSourceReadIdentity');
    }
    return subject;
  };
  const decideRead = (prepared, access, signal) =>
    access.authorization.authorize('acquisition', prepared.readTuple, {
      subjectCid: prepared.readSubjectCid ?? (prepared.checkedSource.selectionCid === undefined
        ? ordinarySubject(prepared)
        : valueCid({version: 'actql-keyed-source-selection-read/0.1',
          selectionCid: prepared.checkedSource.selectionCid, physicalBinding: prepared.physicalBinding})), signal});
  const currentRead = async (prepared, access, signal) => {
    if (prepared.checkedSource?.selectionCid === undefined) ordinaryRecoveryBinding(prepared);
    const decision = await decideRead(prepared, access, signal);
    if (prepared.checkedSource?.selectionCid === undefined) ordinaryRecoveryBinding(prepared);
    if (decision?.action !== 'dispatch') {
      throw Object.assign(new Error('ExecutionAuthorizationDenied'),
        {code: 'ExecutionAuthorizationDenied', decision});
    }
    if (prepared.checkedSource?.selectionCid !== undefined &&
        decision.basis === 'resumed_approval') {
      const facts = checkpointApprovalFacts(decision);
      if (facts === undefined || facts.checkedSource?.selectionCid !== prepared.checkedSource.selectionCid ||
          valueCid(facts.checkedSource) !== valueCid(prepared.checkedSource) ||
          valueCid(facts.physicalBinding) !== valueCid(prepared.physicalBinding) ||
          valueCid(facts.readTuple) !== valueCid(prepared.readTuple)) {
        fail('InstalledKeyedReadApprovalMismatch');
      }
    }
    if (prepared.checkedSource?.selectionCid === undefined && decision.basis === 'resumed_approval') {
      const facts = checkpointApprovalFacts(decision);
      if (facts === undefined || valueCid(facts.checkedSource) !== valueCid(prepared.checkedSource) ||
          valueCid(facts.readTuple) !== valueCid(prepared.readTuple) ||
          valueCid(facts.physicalBinding) !== valueCid(prepared.physicalBinding) ||
          (facts.installationBinding !== undefined &&
            valueCid(facts.installationBinding) !== valueCid(installationBinding))) {
        fail('InstalledSourceReadApprovalMismatch');
      }
    }
    return decision;
  };

  // A declared keyed response port is selected before observing any left
  // rows. It is not a fabricated Direct requirement or an individual GET.
  async function prepareKeyed({preparedProgram, keyedAcquisition, requestIdentity,
    sourceAccess: access = sourceAccess}) {
    // This selected declaration covers the Direct reader only, not a keyed
    // child or listing report. Other original profiles retain their behavior.
    if (originalReader !== undefined) fail('InstalledProviderSourceUnavailable');
    if (requestIdentity === undefined ||
        moon.clientProgramMatchesRequestIdentity(preparedProgram, requestIdentity) !== true ||
        moon.clientProgramKeyedAcquisitionMatchesProgram(keyedAcquisition, preparedProgram) !== true) {
      fail('InstalledSourceProgramMismatch');
    }
    const capacity = checked(moon.clientProgramKeyedRowPrepareCapacity(keyedAcquisition,
      declaration, limits.maxPageBytes, limits.maxPageBytes, 1000000));
    const facts = checked(moon.clientProgramKeyedAcquisitionSourceEvidenceFacts(keyedAcquisition));
    if (!Array.isArray(facts) || facts.length !== 6 || !sourceRefs.has(facts[0])) {
      fail('InstalledSourceEvidenceFactsUnavailable');
    }
    const selectedCoordinates = moon.clientProgramKeyedAcquisitionInputCoordinates(keyedAcquisition);
    const coordinates = runtimeIsOk(selectedCoordinates) ? runtimeField(selectedCoordinates, 0) : undefined;
    if (coordinates === undefined || coordinates.length !== 4 ||
        !coordinates.every(value => Number.isSafeInteger(value) && value >= 0)) {
      fail('InvalidAcquisitionOccurrence');
    }
    const [stage, input, task, step] = coordinates;
    const [resource, ...fields] = checked(
      moon.clientProgramKeyedRowCapacityTarget(capacity, declaration));
    const [sourceRef, sourceContractCid, carrierSchemaContractCid,
      sourceDataPolicyCid, dataClassification, sourceViewContractCid] = facts;
    const programCid = moon.clientRequestProgramCid(requestIdentity);
    const parametersCid = moon.clientRequestParametersCid(requestIdentity);
    if (![programCid, parametersCid].every(value => cidPattern.test(value))) {
      fail('InstalledKeyedRequestIdentityUnavailable');
    }
    const selectionCid = valueCid({version: 'actql-installed-keyed-selection/0.1',
      programCid, parametersCid, coordinates, sourceFacts: facts});
    const prepared = Object.freeze({
      checkedSource: Object.freeze({selectionCid, programCid, parametersCid, step,
        sourceRef, sourceContractCid, carrierSchemaContractCid, sourceDataPolicyCid,
        dataClassification, sourceViewContractCid}),
      readTuple: Object.freeze({connection: site.connection, resource, operation: 'read'}),
      physicalBinding: physicalTarget(resource, fields),
    });
    const decision = await decideRead(prepared, access);
    if (decision?.action === 'deny') fail(authorizationRuntimeCode(decision), decision);
    keyedPreparations.set(prepared, {preparedProgram, keyedAcquisition, access,
      physicalBindingCid: valueCid(prepared.physicalBinding)});
    return Object.freeze({prepared, occurrence: Object.freeze({stage, input, task})});
  }

  // Reopening retained bytes needs the same checked keyed selection's current
  // read authority, not a new RowRun or a grant inferred from saved metadata.
  // This checks the original preparation and installed target without I/O.
  async function verifyKeyedRead({preparedProgram, keyedAcquisition, preparedKeyed,
    sourceAccess: access = sourceAccess, signal}) {
    const owner = keyedPreparations.get(preparedKeyed);
    if (owner === undefined || owner.preparedProgram !== preparedProgram ||
        owner.keyedAcquisition !== keyedAcquisition || owner.access !== access) {
      fail('InstalledSourcePreparationMismatch');
    }
    const recheck = () => {
      signal?.throwIfAborted();
      if (moon.clientProgramKeyedAcquisitionMatchesProgram(keyedAcquisition, preparedProgram) !== true) {
        fail('InstalledSourceProgramMismatch');
      }
      const capacity = checked(moon.clientProgramKeyedRowPrepareCapacity(keyedAcquisition,
        declaration, limits.maxPageBytes, limits.maxPageBytes, 1000000));
      const [resource, ...fields] = checked(moon.clientProgramKeyedRowCapacityTarget(capacity, declaration));
      if (valueCid(preparedKeyed.physicalBinding) !== owner.physicalBindingCid ||
          valueCid(physicalTarget(resource, fields)) !== owner.physicalBindingCid) {
        fail('InstalledSourcePreparationMismatch');
      }
    };
    recheck();
    const decision = await currentRead(preparedKeyed, access, signal);
    recheck();
    return decision;
  }
  function keyedRecoveryBinding(prepared) {
    const owner = keyedPreparations.get(prepared);
    if (owner === undefined || valueCid(prepared.physicalBinding) !== owner.physicalBindingCid) {
      fail('InstalledSourcePreparationMismatch');
    }
    return Object.freeze({version: 'actql-installed-keyed-read-binding/0.1',
      selectionCid: prepared.checkedSource.selectionCid,
      physicalBindingCid: owner.physicalBindingCid,
      connectorRegistration, connectorRevision, bindingCid, connection: site.connection});
  }

  async function prepare({preparedProgram, preparedEffect, registry, values,
    fragment, ordered, sourceAccess: access = sourceAccess,
    queryTimePreparation, requestIdentity, managedRun,
    occurrence = {stage: 0, input: 0, task: 0}}) {
    if (immutableTargets !== undefined && physicalTargetGeneration === undefined) {
      fail('InstalledSourceInitializationClosed');
    }
    if ((preparedProgram === undefined) === (preparedEffect === undefined)) {
      fail('InvalidInstalledSourcePreparation');
    }
    if (![occurrence.stage, occurrence.input, occurrence.task].every(Number.isSafeInteger) ||
        occurrence.stage < 0 || occurrence.stage > 1 ||
        occurrence.input < 0 || occurrence.task !== occurrence.stage ||
        (directReadIdentity !== undefined && occurrence.input !== directReadIdentity.input)) {
      fail('InvalidAcquisitionOccurrence');
    }
    occurrence = Object.freeze({...occurrence});
    const effectful = preparedEffect !== undefined;
    const checkedOwner = preparedEffect ?? preparedProgram;
    let planned;
    let wholeInput = false;
    if (effectful) {
      if (managedRun === undefined || originalReader === undefined && prepareSourceRead === undefined ||
          typeof moon.clientProgramInstalledEffectManagedSourceRead !== 'function') {
        fail('InstalledEffectPlanUnavailable');
      }
      // The admitted parent already owns this acquisition/capacity. Do not
      // prepare another equal requirement or attach a replacement acquisition.
      checked(moon.clientProgramInstalledEffectManagedRunCheck(managedRun, checkedOwner, requestIdentity));
      planned = checked(moon.clientProgramInstalledEffectManagedSourceRead(managedRun, declaration, occurrence.task));
    } else if (managedRun !== undefined && originalReader !== undefined) {
      if (typeof moon.clientProgramInstalledManagedCaptureSourceRead !== 'function') {
        fail('InstalledSourcePlanUnavailable');
      }
      // Pure provider reads consume the SAME original Plan acquisition too.
      // Missing retained-plan support cannot fall back to another equal query.
      if (typeof moon.clientProgramInstalledManagedSourceInputKind !== 'function') {
        fail('InstalledSourcePlanUnavailable');
      }
      const kind = checked(moon.clientProgramInstalledManagedSourceInputKind(managedRun, checkedOwner, requestIdentity));
      if (kind !== 'query' && kind !== 'whole-input') fail('InstalledSourcePlanUnavailable');
      wholeInput = kind === 'whole-input';
      planned = wholeInput
        ? checked(moon.clientProgramInstalledManagedWholeSourceRead(
          managedRun, checkedOwner, requestIdentity, declaration))
        : checked(moon.clientProgramInstalledManagedCaptureSourceRead(
          managedRun, checkedOwner, requestIdentity, declaration, occurrence.task));
    } else if (managedRun !== undefined && prepareSourceRead !== undefined) {
      // This original getter binds Prepared/Request/declaration and crosses
      // current itself. It retains the same base Row Plan's partial read.
      planned = checked(moon.clientProgramInstalledManagedCaptureSourceRead(
        managedRun, checkedOwner, requestIdentity, declaration, occurrence.task));
    }
    const plannedRead = planned === undefined ? undefined : runtimeField(planned, 0);
    if (plannedRead !== undefined) preparingSourceReads.add(plannedRead);
    try {
      const requirement = planned === undefined ? prepareOriginalSourceQuery({moon,
        preparedProgram, preparedEffect, stage: occurrence.stage, input: occurrence.input,
        registry, values, fragment, ordered, queryTimePreparation, requestIdentity}).requirement
        : runtimeField(planned, 1);
      const plannedAcquisition = wholeInput ? runtimeField(planned, 2) : undefined;
      const facts = wholeInput ? moon.clientProgramWholeSourceFacts(plannedAcquisition)
        : checked(moon.clientProgramQueryRequirementSourceEvidenceFacts(requirement));
      if (!Array.isArray(facts) || facts.length !== 6 ||
          !facts.every(value => typeof value === 'string')) {
        fail('InstalledSourceEvidenceFactsUnavailable');
      }
      const [sourceRef, sourceContractCid, carrierSchemaContractCid,
        sourceDataPolicyCid, dataClassification, sourceViewContractCid] = facts;
      if (!sourceRefs.has(sourceRef)) fail('InstalledSourceProgramMismatch');
      const [resource, ...fields] = wholeInput ? moon.clientProgramWholeSourceTarget(plannedAcquisition)
        : checked(moon.clientProgramRowSourceTarget(declaration, requirement));
      const sourceInputOption = wholeInput ? moon.clientProgramWholeSourceInputIdentity(checkedOwner, requirement) : undefined;
      const sourceInput = wholeInput && runtimeIsBoxedSome(sourceInputOption)
        ? runtimeField(sourceInputOption, 0) : undefined;
      if (wholeInput && (!Array.isArray(sourceInput) || sourceInput.length !== 2 ||
          sourceInput.some(value => typeof value !== 'string' || !cidPattern.test(value)))) {
        fail('InstalledSourceProgramMismatch');
      }
      const prepared = Object.freeze({
        checkedSource: Object.freeze({
          ...(wholeInput ? {sourceInput: Object.freeze([...sourceInput])}
            : {requirementCid: moon.clientProgramQueryRequirementCid(requirement)}),
          sourceRef, sourceContractCid, carrierSchemaContractCid,
          sourceDataPolicyCid, dataClassification, sourceViewContractCid,
          ...(wholeInput ? {} : {
            inputContractCid: moon.clientProgramQueryRequirementInputContractCid(requirement),
            outputContractCid: moon.clientProgramQueryRequirementOutputContractCid(requirement)}),
        }),
        readTuple: Object.freeze({connection: site.connection, resource,
          operation: 'read'}),
        physicalBinding: physicalTarget(resource, fields),
        occurrence,
      });
      const physicalBindingCid = valueCid(prepared.physicalBinding);
      const authorizePreparation = async () => {
        const decision = await decideRead(prepared, access);
        const refused = decision?.action === 'deny'
          ? authorizationRuntimeCode(decision) : undefined;
        if (refused !== undefined) {
          throw Object.assign(new Error(refused), {code: refused,
            authorization: decision});
        }
      };
      // Original provider compatibility authorizes before its pure acquisition
      // preparation. The ordinary path keeps its original opposite order.
      if (directReadIdentity !== undefined) await authorizePreparation();
      // The actual installation retains the imported child before returning
      // this same opaque read. A failure below remains with that original
      // supplier; no local scalar/fallback Ledger or cleanup ACK is created.
      const originalRead = planned !== undefined ? plannedRead
        : prepareSourceRead === undefined ? undefined :
          prepareSourceRead(Object.freeze({checkedOwner, effectful, declaration, requirement, occurrence}));
      if (planned !== undefined && prepareSourceRead !== undefined &&
          prepareSourceRead(Object.freeze({checkedOwner, effectful, declaration, requirement,
            occurrence, managedRun, originalRead, requestIdentity})) !== originalRead) fail('InstalledSourceReadUnavailable');
      if (originalRead !== undefined) {
        if (originalRead === undefined || nodeTypes.isPromise(originalRead)) fail('InstalledSourceReadUnavailable');
        // Bind includes the same current check. No external operation occurs
        // between a separate check and this original-owner binding.
        checked(effectful
          ? moon.clientProgramInstalledSourceReadBindEffectProgram(originalRead, checkedOwner)
          : moon.clientProgramInstalledSourceReadBindProgram(originalRead, checkedOwner));
      }
      // An installed provider may select its existing pure typed preparer. It
      // must return this exact requirement/declaration's original acquisition;
      // this is neither an I/O callback nor permission to replace a checked Run.
      const acquisition = planned !== undefined ? runtimeField(planned, 2)
        : prepareOriginalAcquisition(requirement);
      if (planned === undefined && originalRead !== undefined) checked(moon.clientProgramInstalledSourceReadAttachAcquisition(
        originalRead, declaration, requirement, acquisition, occurrence.stage, occurrence.input));
      const providerCaptureCapacity = planned !== undefined ? runtimeField(planned, 3)
        : originalReader === undefined ? undefined :
          moon.clientProgramInstalledProviderRowCaptureCapacity(acquisition, originalReader.capacity);
      if (originalReader !== undefined && providerCaptureCapacity === undefined) {
        fail('InstalledSourceCapacityUnavailable');
      }
      if (directReadIdentity === undefined) await authorizePreparation();
      if (plannedRead !== undefined && !preparingSourceReads.has(plannedRead)) {
        fail('InstalledSourceReadUnavailable');
      }
      preparations.set(prepared, Object.freeze({checkedOwner, effectful,
        requirement, resource, access, acquisition, wholeInput,
        occurrence, physicalBindingCid, providerCaptureCapacity, originalRead, managedRun,
        ...(immutableTargets === undefined ? {} : {physicalBindingOriginal: prepared.physicalBinding,
          physicalTargetGeneration})}));
      ordinaryRecoveryBinding(prepared);
      return prepared;
    } catch (error) {
      if (plannedRead !== undefined && preparingSourceReads.has(plannedRead)) {
        try {
          checked(moon.clientProgramInstalledSourceReadRetire(plannedRead));
          preparingSourceReads.delete(plannedRead);
        } catch { /* SAME Source close retains the original retirement retry. */ }
      }
      throw error;
    }
  }

  async function open(options) {
    const state = {started: false, closeFailed: false, recovery: undefined};
    try {
      return await acquire(state, options);
    } catch (error) {
      if (state.closeFailed && error instanceof AcquisitionOpenError &&
          error.recovery === undefined) {
        throw new AcquisitionOpenError(error, 'unknown', state.recovery);
      }
      throw acquisitionFailure(error, state.closeFailed ? 'unknown'
        : !state.started ? 'not_started' : 'stopped', state.recovery);
    }
  }

  // A keyed consumer first borrows this original capture prefix. Its enclosing
  // task is not complete until the checked JOIN's other inputs are acquired.
  // This exposes no replacement Program, raw rows or fabricated task result.
  async function openCapture(options) {
    const state = {started: false, closeFailed: false, recovery: undefined};
    try {
      return await acquire(state, options, true);
    } catch (error) {
      if (state.closeFailed && error instanceof AcquisitionOpenError &&
          error.recovery === undefined) {
        throw new AcquisitionOpenError(error, 'unknown', state.recovery);
      }
      throw acquisitionFailure(error, state.closeFailed ? 'unknown'
        : !state.started ? 'not_started' : 'stopped', state.recovery);
    }
  }

  // One checked keyed occurrence, not whole-lookup completion. The enclosing
  // Host keeps the original left capture and all right captures until its
  // checked JOIN barrier has completed; this method issues no Source evidence.
  const selectedKeyedContent = value => {
    if (value === undefined) return undefined;
    const capture = value?.capture, issuer = value?.referenceIssuer;
    if (typeof capture !== 'function' || issuer === undefined || captureContent !== undefined) {
      fail('InvalidInstalledContentCapture');
    }
    // Select once before any await. Caller mutation cannot replace the Run's
    // capture or issuer between current authorization and row admission.
    return Object.freeze({capture, referenceIssuer: issuer});
  };
  async function openKeyed({preparedProgram, preparedEffect, keyedAcquisition,
    request, ledger, signal, preparedKeyed, chargeVerification, capturedResourcePath,
    keyedContent,
    sourceAccess: access = sourceAccess}) {
    if (originalReader !== undefined) fail('InstalledProviderSourceUnavailable');
    const state = {started: false, closeFailed: false, recovery: undefined};
    let session;
    let originalKeyedRead, originalClosed = prepareKeyedSourceRead === undefined;
    const closeOriginal = async () => {
      if (originalClosed) return;
      if (originalKeyedRead === undefined) return;
      const observed = await closeKeyedSourceRead(originalKeyedRead);
      const pending = observed !== null && typeof observed === 'object'
        ? Object.getOwnPropertyDescriptor(observed, 'pending') : undefined;
      if (pending === undefined || !Object.hasOwn(pending, 'value') || pending.value !== false) {
        fail('InstalledSourceCleanupPending');
      }
      originalClosed = true;
    };
    let deadline;
    const budgetAbort = new AbortController();
    signal = signal === undefined ? budgetAbort.signal : AbortSignal.any([signal, budgetAbort.signal]);
    try {
      // Per-Run capture custody is selected by the original dispatch owner,
      // never stored on the shared installation. Its issuer admits only the
      // same held content returned by that owner for this exact lookup.
      keyedContent = selectedKeyedContent(keyedContent);
      const captureBytes = keyedContent?.capture ?? captureContent;
      // Content custody belongs to this Run, but the returned Resource still
      // belongs to the installed Source. Do not replace either authority or
      // fall back to the other domain after an issuer refuses a reference.
      const captureIssuer = keyedContent === undefined ? referenceIssuer
        : moon.clientProgramRowContentReferenceIssuer(referenceIssuer,
          keyedContent.referenceIssuer);
      signal?.throwIfAborted();
      if ((preparedProgram === undefined) === (preparedEffect === undefined) ||
          ledger === undefined || (preparedEffect === undefined
            ? moon.clientProgramKeyedAcquisitionMatchesProgram(keyedAcquisition,
              preparedProgram)
            : moon.clientProgramKeyedAcquisitionMatchesEffectProgram(keyedAcquisition,
              preparedEffect)) !== true) {
        fail('InstalledSourceProgramMismatch');
      }
      const facts = checked(
        moon.clientProgramKeyedAcquisitionSourceEvidenceFacts(keyedAcquisition));
      if (!Array.isArray(facts) || facts.length !== 6 ||
          !facts.every(text) || !sourceRefs.has(facts[0])) {
        fail('InstalledSourceEvidenceFactsUnavailable');
      }
      if (prepareKeyedSourceRead !== undefined) {
        if (preparedEffect !== undefined || preparedKeyed === undefined ||
            !keyedPreparations.has(preparedKeyed)) fail('InstalledSourcePreparationMismatch');
        // The same installing Source retains its physical-child duty before
        // returning this Core original. Preserve it before current/getter use.
        originalKeyedRead = prepareKeyedSourceRead(Object.freeze({
          checkedOwner: preparedProgram, keyedAcquisition, request, declaration}));
        checked(moon.clientProgramInstalledKeyedSourceReadCheckCurrent(originalKeyedRead));
      }
      const acquisition = checked(originalKeyedRead === undefined
        ? moon.clientProgramKeyedRowPrepareAcquisition(keyedAcquisition, request,
          declaration, limits.maxPageBytes, limits.maxPageBytes, 1000000)
        : moon.clientProgramInstalledKeyedSourceReadAcquisition(originalKeyedRead));
      const [resource, ...columns] = checked(
        moon.clientProgramKeyedRowTarget(acquisition));
      const physicalBinding = physicalTarget(resource, columns);
      const scope = preparedKeyed === undefined ? undefined : keyedPreparations.get(preparedKeyed);
      if (preparedKeyed !== undefined && (scope === undefined ||
          scope.preparedProgram !== preparedProgram || scope.keyedAcquisition !== keyedAcquisition ||
          scope.access !== access || valueCid(physicalBinding) !== valueCid(preparedKeyed.physicalBinding))) {
        fail('InstalledSourcePreparationMismatch');
      }
      const nonce = randomUUID();
      session = startInstalledRowRun({moon, acquisition, nonce, ledger,
        keyed: true, originalKeyedRead, capacity: {transferBytes: keyedTransferBytes,
          executionBytes: keyedExecutionBytes}});
      const {run} = session;
      // Encode only under the common acquisition's workspace reservation.
      const requestWire = checked(
        moon.clientProgramKeyedRequestWire(request, limits.maxPageBytes));
      const readSubject = Object.freeze({version: 'actql-keyed-row-source-read/0.1',
        sourceFacts: [...facts],
        occurrence: [...moon.clientProgramKeyedAcquisitionCoordinates(keyedAcquisition)],
        request: JSON.parse(requestWire), physicalBinding,
        connectorRegistration, connectorRevision, bindingCid});
      const prepared = Object.freeze({...preparedKeyed, readSubjectCid: valueCid(readSubject), physicalBinding,
        readTuple: Object.freeze({connection: site.connection, resource,
          operation: 'read'})});
      const verifyRead = () => currentRead(prepared, access, signal);
      const decision = await verifyRead();
      signal?.throwIfAborted();
      const granted = decision.basis === 'resumed_approval'
        ? site.admitCheckpointReadApproval(decision) : decision;
      const runInvocationCid = valueCid({version: 'actql-keyed-row-acquisition/0.1',
        readSubject, nonce});
      const dispatchRequestCid = cid({
        version: 'actql-keyed-row-acquisition-dispatch/0.1', runInvocationCid});
      checked(moon.clientProgramKeyedRowBegin(run, captureIssuer));
      const operation = operationBindings.get(resource);
      const grant = site.issueReadGrant({operation,
        decision: granted, resource, runInvocationCid, dispatchRequestCid,
        maxUses: limits.maxPages});
      const observedMs = () => BigInt(Math.floor(performance.now()));
      let sendIndex = 0;
      await readPages({resource, columns, requestWire, operation,
        signal, verifyRead,
        rowRun: Object.freeze({acquisition, run, requestId: nonce, runInvocationCid, dispatchRequestCid,
          ...(originalKeyedRead === undefined ? {} : {originalKeyedRead})}),
        capturedResourcePath: capturedResourcePath === undefined ? undefined : async () => {
          await verifyRead();
          signal?.throwIfAborted();
          if (state.started) fail('InstalledFileLocatorAfterSend');
          return await capturedResourcePath(verifyRead, signal);
        },
        chargeVerification: chargeVerification === undefined ? undefined : async bytes => {
          if (!Number.isSafeInteger(bytes) || bytes < 1 || bytes > 4096) {
            fail('InvalidKeyedVerificationObservation');
          }
          await verifyRead();
          signal?.throwIfAborted();
          if (!state.started) fail('InstalledContentCaptureBeforeSend');
          await chargeVerification(bytes);
        },
        // Host-selected capture receives original typed request/Source facts,
        // not a driver-selected request, target or permission. The callback
        // transfers actual verified bytes to the existing holding owner before
        // returning an issued envelope for this keyed row's ordinary admission.
        captureContent: captureBytes === undefined ? undefined : async bytes => {
          await verifyRead();
          signal?.throwIfAborted();
          if (!state.started) fail('InstalledContentCaptureBeforeSend');
          const content = await captureBytes({...bytes, keyedAcquisition,
            request, readSubjectCid: prepared.readSubjectCid, verifyRead, signal});
          await verifyRead();
          signal?.throwIfAborted();
          return content;
        },
        // The driver supplies the actual serialized request before each send.
        // Grants and lookup accounting share this boundary; returning from
        // readPages without an observed send cannot produce a capture.
        beginRequest: async body => {
          if (!(body instanceof Uint8Array)) fail('InvalidKeyedRequestObservation');
          await verifyRead();
          signal?.throwIfAborted();
          checked(moon.clientProgramKeyedRequestObserveAttempt(request,
            BigInt(body.byteLength), observedMs()));
          if (deadline === undefined) {
            const remaining = checked(moon.clientProgramKeyedRequestRemainingMs(request, observedMs()));
            // Schedule beyond the inclusive exact boundary and clamp only the
            // timer representation. Long policies are rechecked on every
            // observation; the timer must not overflow to immediate expiry.
            const expire = () => {
              try {
                const left = checked(moon.clientProgramKeyedRequestRemainingMs(request, observedMs()));
                deadline = setTimeout(expire, Number(left < 2147483646n ? left + 1n : 2147483647n));
                deadline.unref();
              } catch (cause) {
                budgetAbort.abort(Object.assign(new Error('KeyedLookupDurationExceeded', {cause}),
                  {code: 'KeyedLookupDurationExceeded'}));
              }
            };
            deadline = setTimeout(expire, Number(remaining < 2147483646n ? remaining + 1n : 2147483647n));
            deadline.unref();
          }
          state.started = true;
          return {...grant, useId: `${nonce}-read-${sendIndex++}`};
        },
        chargePage: body => {
          if (!(body instanceof Uint8Array)) fail('InvalidKeyedResponseObservation');
          // Preserve the physical Ledger charge even when the lookup ceiling
          // rejects this received body before decoding or private admission.
          const charge = checked(moon.clientProgramRowSourceChargePage(run, body));
          checked(moon.clientProgramKeyedResponseObserve(request,
            BigInt(body.byteLength), 0n, observedMs()));
          return charge;
        },
        // Received native file bytes use this original RowRun's pending
        // ticket before the subsequent encoded row is charged. A lookup
        // verification count is not a physical-byte observation or a grant.
        consumeObservation: charge => checked(moon.clientProgramRowSourceConsumeObservationCharge(run, charge)),
        // The Site must await admission before returning protocol completion.
        consumePage: (rows, {charge} = {}) => {
          const body = Buffer.from(JSON.stringify(rows), 'utf8');
          const ticket = charge ?? checked(moon.clientProgramRowSourceChargePage(run, body));
          checked(moon.clientProgramKeyedResponseObserve(request,
            charge === undefined ? BigInt(body.byteLength) : 0n,
            BigInt(body.byteLength), observedMs()));
          return session.consumeKeyedPage(body,
            {charge: ticket, currentRead: verifyRead, signal});
        }});
      session.confirmTransportStopped();
      const capture = await session.capture({currentRead: verifyRead, signal});
      checked(moon.clientProgramKeyedRequestFinishIO(request, observedMs()));
      return Object.freeze({capture: Object.freeze({read: () => checked(
        moon.clientProgramKeyedRowCaptureRead(capture)), identity: () => checked(
        moon.clientProgramKeyedRowCaptureIdentity(capture))}),
        verifyRead,
        // Only the actual installed successful capture can enter assembly.
        acceptLookup: lookup => checked(moon.clientProgramKeyedLookupAcceptCapture(
          lookup, keyedAcquisition, request, capture)),
        async close() {session.close(); await closeOriginal();}});
    } catch (error) {
      if (session !== undefined) {
        moon.clientProgramKeyedRequestFailIO(request);
        // Before dispatch there was no physical reader to stop. Once entered,
        // absence of an explicit transport-end observation remains pending.
        const end = acquisitionOutcome(error);
        if (!state.started || end.outcome === 'stopped' || end.outcome === 'not_started') {
          session.confirmTransportStopped();
        } else if (end.recovery !== undefined) {
          // The physical driver's same recovery owner stops its own resources;
          // it does not settle successful response evidence or the RowRun.
          try { await end.recovery.close(); } catch { /* Keep pending custody. */ }
        }
        session.closeAfterFailure(state, end.recovery);
      }
      if (originalKeyedRead !== undefined) {
        const rowRecovery = state.recovery;
        let cleaned = false;
        const cleanup = async () => {
          if (cleaned) return true;
          if (rowRecovery !== undefined &&
              (await rowRecovery.cleanup() === false || rowRecovery.cleanupPending())) return false;
          if (session === undefined) checked(moon.clientProgramInstalledKeyedSourceReadRetire(originalKeyedRead));
          await closeOriginal();
          cleaned = true;
          return true;
        };
        try {await cleanup();} catch { /* Retain the same original duty below. */ }
        if (!cleaned) {
          state.closeFailed = true;
          state.recovery = Object.freeze({close: () => rowRecovery?.close(),
            cleanup, cleanupPending: () => !cleaned});
        }
      }
      // Do not let an inner transport outcome bypass this RowRun's pending
      // retention/cleanup responsibility through acquisitionFailure's reuse.
      throw new AcquisitionOpenError(error, state.closeFailed ? 'unknown'
        : !state.started ? 'not_started' : 'stopped', state.recovery);
    } finally {
      clearTimeout(deadline);
    }
  }

  // Exact-key sharing changes physical reads, not original left multiplicity.
  // This assembles a right Relation input; it is not Source/task evidence.
  async function openKeyedLookup({preparedProgram, preparedEffect,
    keyedAcquisition, left, ledger, signal, preparedKeyed, originalCapture,
    keyedContent,
    sourceAccess: access = sourceAccess, maxWork = 1000000, quantum = 64}) {
    if (originalReader !== undefined) fail('InstalledProviderSourceUnavailable');
    keyedContent = selectedKeyedContent(keyedContent);
    if (!Number.isSafeInteger(maxWork) || maxWork < 1 || maxWork > 2147483647 ||
        !Number.isSafeInteger(quantum) || quantum < 1 || quantum > 1024) {
      fail('InstalledKeyedLookupLimits');
    }
    const rows = moon.clientProgramKeyedLeftReadRows(left);
    if (rows === undefined || ledger === undefined ||
        moon.clientProgramKeyedLeftMatchesAcquisition(left, keyedAcquisition) !== true ||
        (preparedProgram === undefined) === (preparedEffect === undefined) ||
        (preparedEffect === undefined
          ? moon.clientProgramKeyedAcquisitionMatchesProgram(keyedAcquisition, preparedProgram)
          : moon.clientProgramKeyedAcquisitionMatchesEffectProgram(keyedAcquisition, preparedEffect)) !== true) {
      fail('InstalledSourceProgramMismatch');
    }
    signal?.throwIfAborted();
    const lookup = checked(moon.clientProgramKeyedLookupStart(left, ledger,
      limits.maxPageBytes, maxWork));
    const children = [];
    const released = new Set();
    let pendingRecovery;
    let unownedUncertainty = false;
    let preparation;
    let ioStarted = false;
    let closed = false;
    const stop = () => {
      moon.clientProgramKeyedLookupStop(lookup);
      if (preparation !== undefined) {
        moon.clientProgramKeyedRequestCancel(preparation);
        preparation = undefined;
      }
    };
    const cleanup = async () => {
      if (closed) return true;
      stop();
      let pending = unownedUncertainty;
      for (const child of children) {
        if (released.has(child)) continue;
        try { await child.close(); released.add(child); }
        catch { pending = true; }
      }
      if (pendingRecovery !== undefined) {
        try {
          await pendingRecovery.close();
          if (await pendingRecovery.cleanup() === false || pendingRecovery.cleanupPending()) pending = true;
          else pendingRecovery = undefined;
        } catch { pending = true; }
      }
      // Keep assembly custody until all original physical children settle.
      // Cleanup never obtains a new Request or sends again.
      if (pending) return false;
      while (!checked(moon.clientProgramKeyedLookupCleanup(lookup, quantum))) {
        await yieldEventLoop();
      }
      children.length = 0;
      released.clear();
      closed = true;
      return true;
    };
    const close = async () => {
      if (!await cleanup()) fail('InstalledSourceCleanupPending');
    };
    const recovery = Object.freeze({close: stop, cleanup, cleanupPending: () => !closed});
    try {
      for (let row = 0; row < rows; row++) {
        signal?.throwIfAborted();
        preparation = checked(moon.clientProgramKeyedLookupRequestStart(lookup, row));
        let request;
        while (request === undefined) {
          signal?.throwIfAborted();
          for (let poll = 0; poll < quantum; poll++) {
            let compilerTuple1 = moon.clientProgramKeyedLookupRequestAdvance(lookup, preparation);
            const status = runtimeField(compilerTuple1, 0), value = runtimeField(compilerTuple1, 2), issue = runtimeField(compilerTuple1, 3);
            compilerTuple1 = undefined;
            if (status === 2) fail('InstalledKeyedRequestFailed', issue);
            if (status === 1) { request = value; break; }
          }
          if (request === undefined) await yieldEventLoop();
        }
        preparation = undefined;
        const index = checked(moon.clientProgramKeyedLookupFind(lookup, request));
        if (index >= 0) {
          await children[index].verifyRead();
          signal?.throwIfAborted();
          checked(moon.clientProgramKeyedLookupReuse(lookup, request, index));
          continue;
        }
        let acquired;
        try {
          acquired = await openKeyed({preparedProgram, preparedEffect,
            keyedContent,
            keyedAcquisition, request, ledger, signal, preparedKeyed, sourceAccess: access,
            capturedResourcePath: async (verifyRead, activeSignal) => {
              if (typeof originalCapture?.originalRead !== 'function') fail('InstalledFileLocatorUnavailable');
              const read = originalCapture.originalRead();
              if (read === undefined) fail('InstalledFileLocatorUnavailable');
              const locator = checked(moon.clientProgramKeyedFileLocatorStart(lookup, request,
                originalCapture.source(), read));
              try {
                for (;;) {
                  await verifyRead();
                  activeSignal?.throwIfAborted();
                  for (let poll = 0; poll < quantum; poll++) {
                    const path = checked(moon.clientProgramKeyedFileLocatorAdvance(locator));
                    if (path !== undefined) return path;
                  }
                  await yieldEventLoop();
                }
              } finally {
                moon.clientProgramKeyedFileLocatorCancel(locator);
              }
            },
            chargeVerification: bytes => checked(
              moon.clientProgramKeyedLookupChargeVerification(lookup, request, bytes))});
          ioStarted = true;
        } catch (error) {
          const end = acquisitionOutcome(error);
          if (end.outcome !== 'not_started') ioStarted = true;
          if (end.outcome === 'unknown') {
            pendingRecovery = end.recovery;
            unownedUncertainty = end.recovery === undefined;
          }
          throw error;
        }
        // Preserve the physical close handle before copying can fail.
        children.push(acquired);
        acquired.acceptLookup(lookup);
        while (!checked(moon.clientProgramKeyedLookupAdvance(lookup, quantum))) {
          signal?.throwIfAborted();
          await acquired.verifyRead();
          signal?.throwIfAborted();
          await yieldEventLoop();
        }
      }
      for (const child of children) {
        await child.verifyRead();
        signal?.throwIfAborted();
      }
      signal?.throwIfAborted();
      const read = checked(moon.clientProgramKeyedLookupRead(lookup));
      return Object.freeze({capture: Object.freeze({
        read: () => closed ? fail('InstalledSourceClosed')
          : checked(moon.clientProgramKeyedLookupRead(lookup)),
        identity: () => {
          const identity = moon.clientProgramKeyedLookupIdentity(lookup);
          if (identity === undefined) fail('InstalledSourceClosed');
          return identity;
        }}), close, cleanup, cleanupPending: recovery.cleanupPending,
        work: () => moon.clientProgramKeyedLookupWork(lookup), read,
        async issueObservation({authorityScopeCid, observedAt}) {
          if (closed) fail('InstalledSourceClosed');
          signal?.throwIfAborted();
          for (const child of children) {
            await child.verifyRead();
            signal?.throwIfAborted();
          }
          if (closed) fail('InstalledSourceClosed');
          const observation = checked(moon.clientProgramKeyedLookupIssueObservation(
            lookup, authorityScopeCid, observedAt));
          const wires = moon.clientProgramKeyedLookupObservationWires(observation);
          if (wires === undefined) fail('InstalledSourceClosed');
          return Object.freeze({observation,
            inputLogicalWire: runtimeField(wires, 0), sourceEvidenceWire: runtimeField(wires, 1)});
        },
        async openDag() {
          if (closed) fail('InstalledSourceClosed');
          signal?.throwIfAborted();
          for (const child of children) {
            await child.verifyRead();
            signal?.throwIfAborted();
          }
          if (preparedEffect !== undefined) {
            fail('InstalledKeyedEffectDagRequiresRunOwner');
          }
          if (closed) fail('InstalledSourceClosed');
          return checked(moon.clientProgramKeyedLookupOpenDag(preparedProgram,
            lookup, ledger));
        },
        async openHost({registry, values, fragment, ordered, retainedRelationOutput = false}) {
          if (closed) fail('InstalledSourceClosed');
          signal?.throwIfAborted();
          for (const child of children) {
            await child.verifyRead();
            signal?.throwIfAborted();
          }
          if (closed) fail('InstalledSourceClosed');
          if (preparedEffect !== undefined) fail('InstalledKeyedEffectDagRequiresRunOwner');
          const host = moon.clientProgramKeyedLookupOpenLocalHost(preparedProgram,
            lookup, ledger, registry, values, fragment, ordered, retainedRelationOutput);
          if (host === undefined) fail('InstalledKeyedHostPreparation');
          return host;
        },
        // Original Local preparation, not a replacement acquisition Program.
        // The normal dispatcher must reserve its capacity and own its child.
        async borrowSerializationInput() {
          if (closed) fail('InstalledSourceClosed');
          signal?.throwIfAborted();
          for (const child of children) {
            await child.verifyRead();
            signal?.throwIfAborted();
          }
          if (closed) fail('InstalledSourceClosed');
          // This is the original sealed lookup, not a new task completion or
          // a transfer of custody. The dependent prefix must stop first.
          checked(moon.clientProgramKeyedLookupRead(lookup));
          return lookup;
        },
        async prepareJoin({registry, values, fragment, ordered}) {
          if (closed) fail('InstalledSourceClosed');
          for (const child of children) {
            await child.verifyRead();
            signal?.throwIfAborted();
          }
          const prepared = preparedEffect === undefined
            ? moon.clientProgramKeyedLookupJoinPrepare(preparedProgram, lookup,
              registry, values, fragment, ordered)
            : moon.clientProgramEffectKeyedLookupJoinPrepare(preparedEffect, lookup,
              registry, values, fragment, ordered);
          if (prepared === undefined) fail('InstalledKeyedJoinPreparation');
          return prepared;
        }});
    } catch (error) {
      let complete = false;
      try { complete = await cleanup(); } catch { /* Same recovery retains custody. */ }
      throw new AcquisitionOpenError(error, complete
        ? ioStarted ? 'stopped' : 'not_started' : 'unknown', complete ? undefined : recovery);
    }
  }

  async function acquire(state, {preparedProgram, preparedEffect, registry,
    values, fragment, ordered, sourceAccess: access = sourceAccess, signal,
    preparedSource, retainedRelationOutput = false,
    occurrence = {stage: 0, input: 0, task: 0}, ledger,
    originalOperationScope}, captureOnly = false) {
    const prepared = preparedSource ?? await prepare({preparedProgram,
      preparedEffect, registry, values, fragment, ordered,
      sourceAccess: access, occurrence});
    const owner = preparations.get(prepared);
    if (owner === undefined ||
        owner.checkedOwner !== (preparedEffect ?? preparedProgram) ||
        owner.effectful !== (preparedEffect !== undefined) ||
        owner.access !== access ||
        owner.occurrence.stage !== occurrence.stage ||
        owner.occurrence.input !== occurrence.input ||
        owner.occurrence.task !== occurrence.task) {
      fail('InstalledSourcePreparationMismatch');
    }
    if (originalReader !== undefined) {
      if (ledger === undefined) fail('InstalledProviderSourceLedgerRequired');
      captureCapacity(owner);
    }
    const decision = await currentRead(prepared, access, signal);
    const granted = owner.originalRead === undefined && decision.basis === 'resumed_approval'
      ? site.admitCheckpointReadApproval(decision) : decision;
    const acquisition = owner.acquisition;
    const columns = owner.wholeInput ? moon.clientProgramWholeSourceTarget(acquisition).slice(1)
      : [...moon.clientProgramRowSourceColumns(acquisition)];
    const nonce = randomUUID();
    const identity = directReadIdentity === undefined ? undefined
      : directReadIdentity.attempt(prepared, nonce);
    if (directReadIdentity !== undefined &&
        (identity === null || typeof identity !== 'object' ||
          Object.getPrototypeOf(identity) !== Object.prototype ||
          !Object.isFrozen(identity) ||
          Object.keys(identity).sort().join('\0') !==
            ['dispatchRequestCid', 'runInvocationCid'].join('\0') ||
          !cidPattern.test(identity.runInvocationCid) ||
          !cidPattern.test(identity.dispatchRequestCid))) {
      fail('InvalidInstalledSourceReadIdentity');
    }
    const runInvocationCid = identity?.runInvocationCid ??
      cid({version: 'actql-row-source-acquisition/0.1',
        ...(owner.wholeInput ? {sourceInput: prepared.checkedSource.sourceInput}
          : {requirementCid: prepared.checkedSource.requirementCid}), nonce});
    const dispatchRequestCid = identity?.dispatchRequestCid ?? cid({
      version: 'actql-row-source-acquisition-dispatch/0.1', runInvocationCid});
    let preparedRead;
    if (prepareRead !== undefined && originalReader === undefined) {
      // A provider's original bounded metadata observation precedes the row
      // attempt. Mark the physical start before awaiting that same operation;
      // a lost response is never reclassified as an unstarted acquisition.
      state.started = true;
      preparedRead = await prepareRead(Object.freeze({prepared, acquisition,
        decision, granted, resource: owner.resource, nonce, runInvocationCid,
        dispatchRequestCid, signal}));
    }
    const capacity = {transferBytes: maxTransferBytes,
      executionBytes: BigInt(limits.maxPageBytes)};
    if (originalReader !== undefined) capacity.provider = originalReader.capacity;
    if (listingReportCapacity !== undefined &&
        moon.clientProgramRowSourceIsListing(acquisition)) {
      // Extra report/control backing is admitted by Core before page I/O and
      // retained through original capture/evidence/cleanup, not settled by
      // this JS caller when capture returns. Ordinary rows have no new field.
      capacity.listingReport = listingReportCapacity;
    }
    const session = startInstalledRowRun({moon, acquisition, nonce, ledger, capacity,
      originalRead: owner.originalRead, wholeInput: owner.wholeInput});
    preparingSourceReads.delete(owner.originalRead);
    const {run} = session;
    let externalClosed = closeSourceRead === undefined || owner.managedRun === undefined;
    let externalCloseAttempted = false;
    let nativeReadPending = false;
    const closeOriginal = async () => {
      if (externalClosed) return;
      externalCloseAttempted = true;
      const observed = await closeSourceRead(owner.originalRead);
      const pending = observed !== null && typeof observed === 'object'
        ? Object.getOwnPropertyDescriptor(observed, 'pending') : undefined;
      if (!pending || !Object.hasOwn(pending, 'value') || pending.value !== false) {
        fail('InstalledSourceCleanupPending');
      }
      externalClosed = true;
    };
    const complete = async () => {
      const verifyRead = () => currentRead(prepared, access, signal);
      // The completed Direct prefix owns its own logical input and Source
      // observation even when later keyed inputs are still unacquired. Reuse
      // the existing capture tuple issuer, never label it as JOIN completion.
      return await session.complete({owner, prepared, registry,
        values, fragment, ordered, retainedRelationOutput, signal,
        currentRead: verifyRead, captureOnly});
    };
    try {
      if (prepareRead !== undefined && originalReader !== undefined) {
        // A managed Reader's original facts are prepared only after its SAME
        // accounted Run starts. Its native protocol owns every physical child;
        // the original session catches and retires a failed preparation too.
        preparedRead = await prepareRead(Object.freeze({prepared, acquisition,
          decision, granted, resource: owner.resource, nonce, runInvocationCid,
          dispatchRequestCid, signal}));
      }
      // Encode only after the existing RowRun's accounted reservation. The
      // common owner includes this wire while its completion records overlap.
      // The driver decodes its declared typed Request (including existing wire
      // markers for JSON scalars), not a replacement selector.
      const requestWire = checked(owner.wholeInput ? moon.clientProgramWholeSourceRequestWire(acquisition)
        : moon.clientProgramRowSourceRequestWire(acquisition));
      const operation = operationBindings.get(owner.resource);
      const issueGrant = () => site.issueReadGrant({operation,
        decision: granted, resource: owner.resource, runInvocationCid,
        dispatchRequestCid, maxUses: (readerDemand?.sequences?.[owner.resource] ?? readerDemand?.sequence)?.maxUses ?? limits.maxPages});
      // Preserve a selected driver's original grant/attempt order. The
      // ordinary JSON/listing path keeps its existing post-begin issuance.
      // A local original read has no credential to issue. A managed provider
      // read adds Resource custody only: it still needs the same Site grant
      // and current Account decision, never permission from its Run identity.
      const credentialRead = owner.originalRead === undefined ||
        owner.managedRun !== undefined && originalReader !== undefined;
      let grant = credentialRead && grantBeforeBegin ? issueGrant() : undefined;
      const readChildGrants = new Map(), readChildUses = new Map();
      const readChildOriginals = new WeakMap();
      let readChildIndex = 0, rootReadUses = 0, propertyOccurrences = 0;
      const beginPageLimits = owner.wholeInput ? managedPageLimits ?? pageLimits : pageLimits;
      checked(beginPageLimits === undefined
        ? moon.clientProgramRowSourceBegin(run, limits.maxPageBytes,
          limits.maxPageRows, limits.maxCaptureRows, referenceIssuer)
        : moon.clientProgramRowSourceBeginWithPageLimits(run, limits.maxPageBytes,
          beginPageLimits.maxNodes, beginPageLimits.maxDepth, limits.maxPageRows,
          limits.maxCaptureRows, referenceIssuer));
      const isListing = !owner.wholeInput && moon.clientProgramRowSourceIsListing(acquisition);
      // paths=[] is already typed and complete. Do not issue a read grant or
      // enter a Site driver merely to manufacture an empty transport result.
      if (isListing && moon.clientProgramRowSourceListingComplete(run)) {
        await closeOriginal();
        return await complete();
      }
      if (credentialRead && !grantBeforeBegin) grant = issueGrant();
      state.started = true;
      const rowRun = Object.freeze({acquisition, run, requestId: nonce,
        runInvocationCid, dispatchRequestCid,
        ...(owner.originalRead === undefined ? {} : {originalRead: owner.originalRead})});
      const withOriginalJob = originalOperationScope === undefined ? undefined
        : bindClientSourceOperationRowRun(originalOperationScope, moon,
          preparedProgram, prepared, rowRun);
      const readerOptions = {resource: owner.resource, columns, requestWire, preparedRead,
        operation, signal,
        verifyRead: () => currentRead(prepared, access, signal),
        // Same-runtime opaque borrowing for trusted installed adapters only.
        // The original Host keeps finish/capture/close and physical capacity.
        rowRun,
        ...(withOriginalJob === undefined ? {} : {withOriginalJob}),
        ...(isListing ? {listing: rowListingCallbacks({moon, run, signal,
          currentRead: () => currentRead(prepared, access, signal)})} : {}),
        // The current read decision is taken again before every request.
        ...(credentialRead ? {originalAuthorization: grant, authorizationFor: async index => {
          if (index > 0) await currentRead(prepared, access, signal);
          const useId = directReadIdentity === undefined ? `${nonce}-read-${index}`
            : directReadIdentity.useId(nonce, index);
          if (!text(useId)) fail('InvalidInstalledSourceReadIdentity');
          return {...grant, useId};
        }, authorizeReadChild: async (childOperation,index,occurrence,supplied) => {
          if (readerDemand?.sequence !== undefined || readerDemand?.sequences !== undefined) {
            const sequence = readerDemand.sequences?.[owner.resource] ?? readerDemand.sequence;
            if (sequence === undefined || operation !== sequence.operation || !Number.isSafeInteger(index) || index !== readChildIndex ||
                index >= readerDemand.responses || occurrence === null || typeof occurrence !== 'object' ||
                nodeTypes.isProxy(occurrence) || readChildOriginals.has(occurrence)) fail('InvalidInstalledSourceReadChild');
            if (childOperation === sequence.operation) {
              if (rootReadUses >= sequence.maxUses) fail('InstalledSourceQueryUseLimit');
              rootReadUses++;
            } else {
              const selected = sequence.children.find(entry => entry.operation === childOperation);
              if (selected === undefined) fail('InvalidInstalledSourceReadChild');
              const used = readChildUses.get(childOperation) ?? 0;
              if (used >= selected.maxUses) fail('InstalledSourceReadChildUseLimit');
              readChildUses.set(childOperation,used+1);
            }
            readChildIndex++;
            // Spend the original occurrence before any reentrant current or
            // Site callback. Failure cannot restore a consumed request/use.
            readChildOriginals.set(occurrence,true);
            const decision = await currentRead(prepared,access,signal);
            if (supplied !== undefined) return supplied;
            const childGranted = owner.originalRead === undefined && decision.basis === 'resumed_approval'
              ? site.admitCheckpointReadApproval(decision) : decision;
            let original = childOperation === operation ? grant : readChildGrants.get(childOperation);
            if (original === undefined) {
              original = site.issueReadGrant({operation:childOperation,decision:childGranted,
                resource:owner.resource,runInvocationCid,dispatchRequestCid,maxUses:sequence.children.find(entry => entry.operation === childOperation).maxUses});
              readChildGrants.set(childOperation,original);
            }
            const useId = directReadIdentity === undefined ? `${nonce}-read-${index}`
              : directReadIdentity.useId(nonce,index);
            if (!text(useId)) fail('InvalidInstalledSourceReadIdentity');
            return Object.freeze({originalAuthorization:original,authorization:Object.freeze({...original,useId})});
          }
          if (readerDemand?.nested === true) {
            if (!text(childOperation) || !Number.isSafeInteger(index) || index !== readChildIndex ||
                index >= readerDemand.responses) fail('InvalidInstalledSourceReadChild');
            let entry;
            if (childOperation === operation) {
              if (rootReadUses >= readerDemand.queryPages) fail('InstalledSourceQueryUseLimit');
              rootReadUses++;
            } else {
              if (occurrence === null || typeof occurrence !== 'object' || nodeTypes.isProxy(occurrence)) {
                fail('InstalledSourceReadChildOriginalUnavailable');
              }
              entry = readChildOriginals.get(occurrence);
              if (entry === undefined) {
                if (propertyOccurrences >= readerDemand.propertyOccurrences) fail('InstalledSourcePropertyOccurrenceLimit');
                propertyOccurrences++;
                // A weak occurrence key never turns the completed native
                // query/property graph into a retained all-pages history.
                entry = {operation: childOperation, uses: 0, grant: undefined};
                readChildOriginals.set(occurrence, entry);
              }
              if (entry.operation !== childOperation || entry.uses >= readerDemand.propertyPages) {
                fail('InstalledSourcePropertyUseLimit');
              }
              entry.uses++;
            }
            readChildIndex++;
            const decision = await currentRead(prepared, access, signal);
            if (supplied !== undefined) return supplied;
            const childGranted = owner.originalRead === undefined && decision.basis === 'resumed_approval'
              ? site.admitCheckpointReadApproval(decision) : decision;
            if (entry !== undefined && entry.grant === undefined) {
              entry.grant = site.issueReadGrant({operation: childOperation, decision: childGranted,
                resource: owner.resource, runInvocationCid, dispatchRequestCid, maxUses: readerDemand.propertyPages});
            }
            const selected = entry === undefined ? grant : entry.grant;
            const useId = directReadIdentity === undefined ? `${nonce}-read-${index}`
              : directReadIdentity.useId(nonce,index);
            if (!text(useId)) fail('InvalidInstalledSourceReadIdentity');
            return Object.freeze({originalAuthorization: selected,
              authorization: Object.freeze({...selected,useId})});
          }
          if (!text(childOperation) || !Number.isSafeInteger(index) || index !== readChildIndex || index >= limits.maxPages) {
            fail('InvalidInstalledSourceReadChild');
          }
          // Spend this original ordinal before an external current callback.
          // A failed or reentrant call cannot reuse it to issue another child.
          readChildIndex++;
          await currentRead(prepared, access, signal);
          if (supplied !== undefined) return supplied;
          let original = childOperation === operation ? grant : readChildGrants.get(childOperation);
          if (original === undefined) {
            original = site.issueReadGrant({operation:childOperation,decision:granted,
              resource:owner.resource,runInvocationCid,dispatchRequestCid,maxUses:limits.maxPages});
            readChildGrants.set(childOperation,original);
          }
          const useId = directReadIdentity === undefined ? `${nonce}-read-${index}`
            : directReadIdentity.useId(nonce,index);
          if (!text(useId)) fail('InvalidInstalledSourceReadIdentity');
          return Object.freeze({originalAuthorization:original,
            authorization:Object.freeze({...original,useId})});
        }} : {}),
        chargePage: body => checked(moon.clientProgramRowSourceChargePage(
          run, body)),
        consumeObservation: ledger === undefined ? undefined : function consumeObservation(charge) {
          return checked(moon.clientProgramRowSourceConsumeObservationCharge(run, charge));
        },
        consumeProjectedPage: (page, {charge} = {}) => {
          // The same compiled RowRun checks opaque page provenance and the
          // original response ticket before full schema/retention admission.
          // Foreign pages never fall back to serialization or another parse.
          if (charge === undefined) fail('InvalidInstalledSourcePageCharge');
          return checked(moon.clientProgramRowSourceAcceptChargedProjectedPage(run, charge, page));
        },
        ...(originalReader === undefined ? {} : {consumeValues: (columns, rows, {charge} = {}) => {
          if (charge === undefined) fail('InvalidInstalledSourcePageCharge');
          return checked(moon.clientProgramRowSourceAcceptChargedValues(run, charge, columns, rows));
        }}),
        consumePageWire: (wire, {charge} = {}) => {
          if (typeof wire !== 'string') fail('InvalidInstalledSourcePageWire');
          const bytes = Buffer.from(wire, 'utf8');
          return checked(charge === undefined
            ? moon.clientProgramRowSourceAcceptPage(run, bytes)
            : moon.clientProgramRowSourceAcceptChargedPage(run, charge, bytes));
        },
        consumePage: (rows, {charge} = {}) => {
          const bytes = Buffer.from(JSON.stringify(rows), 'utf8');
          return checked(charge === undefined
            ? moon.clientProgramRowSourceAcceptPage(run, bytes)
            : moon.clientProgramRowSourceAcceptChargedPage(run, charge, bytes));
        }};
      if (originalReader === undefined) {
        nativeReadPending = true;
        await readPages(readerOptions);
        nativeReadPending = false;
      }
      else await session.readProvider({prepare: originalReader.prepare,
        receiver: originalReader.receiver, options: Object.freeze(readerOptions)});
      await closeOriginal();
      return await complete();
    } catch (error) {
      if (nativeReadPending && !externalClosed && closeSourceRead !== undefined && owner.managedRun !== undefined &&
          error instanceof AcquisitionOpenError && error.outcome === 'unknown') {
        // The native adapter already attempted cleanup. Preserve its original
        // recovery instead of immediately asking another helper to close it.
        // An absent owner cannot be replaced by a different close's success.
        const original = error.recovery ?? Object.freeze({
          async cleanup() {return false;}, cleanupPending: () => true,
        });
        session.closeAfterFailure(state, original);
        throw new AcquisitionOpenError(error, 'unknown', state.recovery);
      }
      if (!externalClosed && !externalCloseAttempted) {
        try {await closeOriginal();} catch { /* Same cleanup remains pending. */ }
      }
      if (!externalClosed) {
        // The original external child still owns its backing. Do not close
        // the Core RowRun or release that capacity ahead of its actual ACK.
        const recovery = Object.freeze({close() {}, async cleanup() {
          try {await closeOriginal();} catch {return false;}
          return true;
        }, cleanupPending: () => !externalClosed});
        session.closeAfterFailure(state, recovery);
        throw new AcquisitionOpenError(error, 'unknown', state.recovery);
      }
      session.closeAfterFailure(state);
      throw error;
    }
  }

  let constructionClosed = false;
  const sourceBody = {
    realizationKey,
    supportsRetainedRelationOutput: true,
    connectorRegistration, connectorRevision,
    environmentWire,
    connectorBindings: Object.freeze([Object.freeze({connectorId,
      bindingCid: publicationBindingCid ?? bindingCid})]),
    ...(tableReadTargets === undefined ? {} : {tableReadTargets, declarationCatalogCid: declared.catalog_cid}),
    readAuthorization: Object.freeze({
      accountConfiguration: authorization.accountConfiguration,
      context: authorization.context}),
    sourceAccess,
    sourceReadAccesses,
    ...(originalReader !== undefined || typeof prepareSourceRead === 'function'
      ? {managedCaptureCapacity: managedProviderCaptureCapacity} : {}),
    ...(originalReader === undefined ? {} : {managedWholeSourceCapacity}),
      managedEffectPlanSelection() {
        // This entry selects the common original acquisition constructor.
        // A compatibility preparer/policy or earlier physical callback cannot
        // be replaced by that default merely because its column counts match.
        if (prepareAcquisition !== undefined || listingPolicy !== undefined ||
            prepareRead !== undefined && originalReader === undefined) {
          fail('InstalledSourcePlanConstructorUnavailable');
        }
        if (originalReader === undefined && typeof prepareSourceRead !== 'function') {
          fail('InstalledSourcePlanConstructorUnavailable');
        }
        if (originalReader !== undefined && (typeof providerSiteCurrent !== 'function' ||
            Reflect.apply(providerSiteCurrent, site, []) !== true)) fail('InstalledSourceReaderNotCurrent');
        return Object.freeze({declaration, provider: originalReader?.capacity,
          transferBytes: maxTransferBytes, executionBytes: BigInt(limits.maxPageBytes)});
      },
    admitsSource: sourceRef => sourceRefs.has(sourceRef),
    ordinaryRecoveryBinding,
    retainedCapture(prepared) {
      const owner = preparations.get(prepared);
      if (owner === undefined) fail('InstalledSourcePreparationMismatch');
      const capacity = captureCapacity(owner);
      if (capacity === undefined) fail('InstalledSourceCapacityUnavailable');
      return Object.freeze({requirement: owner.requirement, capacity, referenceIssuer});
    },
    ledgerCapacity(prepared) {
      const owner = preparations.get(prepared);
      if (owner === undefined) fail('InstalledSourcePreparationMismatch');
      const capacity = captureCapacity(owner);
      if (capacity === undefined) fail('InstalledSourceCapacityUnavailable');
      return Object.freeze({
        capacity,
        ...(owner.wholeInput ? {wholeInput: true} : {}),
        ...(owner.managedRun === undefined ? {} : {managedRun: owner.managedRun}),
        transferBytes: maxTransferBytes,
        executionBytes: BigInt(limits.maxPageBytes),
      });
    },
    keyedLedgerCapacity(keyedAcquisition, {maxWork = 1000000} = {}) {
      if (originalReader !== undefined) fail('InstalledProviderSourceUnavailable');
      if (!Number.isSafeInteger(maxWork) || maxWork < 1 || maxWork > 2147483647) {
        fail('InstalledKeyedLookupLimits');
      }
      const facts = checked(moon.clientProgramKeyedAcquisitionSourceEvidenceFacts(keyedAcquisition));
      if (!Array.isArray(facts) || facts.length !== 6 ||
          !facts.every(text) || !sourceRefs.has(facts[0])) {
        fail('InstalledSourceEvidenceFactsUnavailable');
      }
      const capacity = checked(moon.clientProgramKeyedRowPrepareCapacity(keyedAcquisition,
        declaration, limits.maxPageBytes, limits.maxPageBytes, maxWork));
      return Object.freeze({capacity, transferBytes: keyedTransferBytes,
        executionBytes: keyedExecutionBytes, maxBytes: limits.maxPageBytes, maxWork});
    },
    prepare, prepareKeyed, verifyKeyedRead, keyedRecoveryBinding, open, openCapture, openKeyed, openKeyedLookup,
    close() {
      // Invalidate this installation's immutable target selection as soon as
      // retirement starts. Physical pending/ACK handling remains below.
      physicalTargetGeneration = undefined;
      for (const read of preparingSourceReads) {
        checked(moon.clientProgramInstalledSourceReadRetire(read));
        preparingSourceReads.delete(read);
      }
      if (originalReader?.retire !== undefined &&
          Reflect.apply(originalReader.retire, originalReader.receiver, []) !== true) {
        fail('InstalledSourceReaderCleanupPending');
      }
      const observed = site.close();
      if (sourceInitialization === undefined) return observed;
      // Only the existing Site's completed physical cleanup releases this
      // constructor's aliases; the request to stop is not its acknowledgement.
      return Promise.resolve(observed).then(value => {
        if (!constructionClosed) {
          closeInstalledSourceConstruction(sourceInitialization, installedSource);
          acquisitionContracts = undefined;
          constructionClosed = true;
        }
        return value;
      });
    },
  };
  for (const key of Object.keys(publicationFields)) {
    if (Object.hasOwn(sourceBody, key)) fail('InstalledSourcePublicationCollision');
  }
  // Provider-only publication fields enter the sole adapter before freezing
  // and exact registration. They cannot replace any common lifecycle method.
  let surface = sourceBody;
  if (selectedSurface !== undefined) {
    surface = {};
    for (const key of selectedSurface) {
      if (!Object.hasOwn(sourceBody, key)) fail('InvalidInstalledSourcePublication');
      Object.defineProperty(surface, key, Object.getOwnPropertyDescriptor(sourceBody, key));
    }
  }
  const installedSource = Object.freeze(Object.defineProperties(surface, publicationFields));
  if (sourceInitialization !== undefined) {
    retainInstalledSourceConstruction(sourceInitialization, installedSource, declaration, declared, environment);
  }
  return installedSource;
}


export async function openInstalledRowSite({root, principalId, commonMoon,
  installation, runtimeBundleCid, accountConfiguration, originalContext,
  connection, profile, resolveSecret, ca, responseHeaders = [],
  admitsApprovalTarget, admitsEffectTargetRead, runAcquisitionLimits,
  assertCurrent, receiver, configurationReader, prepareSecretMaterial, openCredentialJournal}) {
  if (typeof assertCurrent !== 'function' || nodeTypes.isAsyncFunction(assertCurrent) ||
      !installation || typeof installation !== 'object' || nodeTypes.isProxy(installation) ||
      profile === null || typeof profile !== 'object' || nodeTypes.isProxy(profile) ||
      !Object.isFrozen(profile) || Object.values(Object.getOwnPropertyDescriptors(profile))
        .some(field => !Object.hasOwn(field, 'value')) || !Array.isArray(responseHeaders)) {
    fail('InvalidInstalledRowSite');
  }
  const identity = Object.getOwnPropertyDescriptors(installation);
  const registration = identity.registration?.value, revision = identity.revision?.value;
  if (!text(registration) || !text(revision) || nodeTypes.isProxy(responseHeaders)) {
    fail('InvalidInstalledRowSite');
  }
  const secretPresentation = ownCredentialSecretPresentation(arguments[0]);
  const headerFields = Object.getOwnPropertyDescriptors(responseHeaders);
  const headers = [];
  for (let index = 0; index < responseHeaders.length; index++) {
    const field = headerFields[index];
    if (!field || !Object.hasOwn(field, 'value') || !text(field.value)) {
      fail('InvalidInstalledRowSite');
    }
    headers.push(field.value);
  }
  Object.freeze(headers);
  const acquisition = ownCredentialAcquisitionLimits(runAcquisitionLimits);
  const current = () => {
    if (Reflect.apply(assertCurrent, receiver, []) !== undefined) {
      fail('InstalledRowSiteCurrentCheckNotSynchronous');
    }
  };
  current();
  let authorization, site, materialOwner, originalMaterial, materialResolve, materialClose, materialClosed = false;
  if (prepareSecretMaterial !== undefined && (typeof prepareSecretMaterial !== 'function' ||
      nodeTypes.isProxy(prepareSecretMaterial) || nodeTypes.isAsyncFunction(prepareSecretMaterial))) {
    fail('InvalidInstalledSecretMaterialConstructor');
  }
  try {
    authorization = await installRowSourceAuthorization({root, principalId,
      connectorRegistration: registration, accountConfiguration, originalContext,
      gateOptions: {runtime: commonMoon}});
    current();
    if (prepareSecretMaterial !== undefined) {
      // Retain the returned original before inspecting methods/currentness.
      // This constructor is pure and synchronous; provider secrets remain
      // lazy and are resolved only by the existing operational credential use.
      materialOwner = Object.freeze({
        resolveSecret(...args) {
          if (materialClosed || typeof materialResolve !== 'function') fail('InstalledSecretMaterialClosed');
          return Reflect.apply(materialResolve, originalMaterial, args);
        },
        close() {
          if (materialClosed) return;
          if (typeof materialClose !== 'function') fail('InstalledSecretMaterialCleanupUnavailable');
          const result = Reflect.apply(materialClose, originalMaterial, []);
          if (result !== undefined) fail('InstalledSecretMaterialCleanupPending');
          materialClosed = true; originalMaterial = materialResolve = materialClose = undefined;
        },
      });
      originalMaterial = Reflect.apply(prepareSecretMaterial, undefined, []);
      if (!originalMaterial || typeof originalMaterial !== 'object' || nodeTypes.isProxy(originalMaterial)) {
        fail('InvalidInstalledSecretMaterial');
      }
      const fields = Object.getOwnPropertyDescriptors(originalMaterial);
      if (Object.hasOwn(fields.close ?? {}, 'value') && typeof fields.close.value === 'function' &&
          !nodeTypes.isAsyncFunction(fields.close.value)) materialClose = fields.close.value;
      if (!Object.hasOwn(fields.close ?? {}, 'value') || typeof fields.close.value !== 'function' ||
          !Object.hasOwn(fields.resolveSecret ?? {}, 'value') || typeof fields.resolveSecret.value !== 'function' ||
          nodeTypes.isAsyncFunction(fields.close.value) || Object.hasOwn(fields, 'then')) fail('InvalidInstalledSecretMaterial');
      materialClose = fields.close.value; materialResolve = fields.resolveSecret.value;
      resolveSecret = materialOwner.resolveSecret;
      current();
    }
    site = await openRowSourceCredentialSite({root, profile, principalId, authorization,
      connection, connectorRegistration: registration, connectorRevision: revision,
      runtimeBundleCid, commonMoon, resolveSecret, ca, responseHeaders: headers,
      configurationReader, openCredentialJournal, secretMaterial: materialOwner,
      admitsApprovalTarget, admitsEffectTargetRead, runAcquisitionLimits: acquisition,
      ownAuthorization: true, ...(secretPresentation === undefined ? {} : {secretPresentation})});
    current();
    return Object.freeze({authorization, site});
  } catch (cause) {
    if (authorization === undefined) throw cause;
    if (originalMaterial === undefined) materialOwner = undefined;
    throw await retainInstalledHostInitializationFailure(cause,
      site === undefined ? {authorization, secretMaterial: materialOwner} : {sourceProfile: site});
  }
}
