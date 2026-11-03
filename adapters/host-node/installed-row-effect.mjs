// The standard Host's provider-neutral installed Effect for connectors whose
// writes change one provider object per row through a checked execution
// Mapping or a checked Command contract (see installed-row-source.mjs for the
// common Mapping generator and the credential Site). Capture, the Effect Set Preview, the Effect Ledger
// claims, apply, the Receipt, publication and recovery are the common
// owners'. The path of a member is selected by its Mapping's checked
// `effect_kind`: a `create` has no target; an `update` or `upsert` selects
// an original key whose observed presence determines the guarded branch.
// UPDATE and present-side UPSERT retain their observed version; an explicitly
// absent UPSERT remains conditional creation through the same provider Owner.
// A `command` binds its exact ResourceRef and input payload; its row states
// are not applicable, not an approximation of an update.
//
// Standard CREATE installations supply `write`: a fixed HTTP declaration,
// provider request mapping and response classifier, plus any provider-specific
// subject check. The Host derives the routine hooks inside this same owner.
// Conditional writes and other advanced installations supply an internal driver.
// A driver retains the following existing contract. Every kind:
// - `kinds`: the effect kinds it writes.
// - `prepareRequest({member, value, selector, current})`: the exact request
//   of one row from its mapped target value (and, for an update, its
//   selector), and `requestCid`, the identity of its exact request. Pure.
// - `requestFacts(request)`: `{value, target}`, the row value the request
//   writes and its target identity (absent for a create). The common owner
//   compares both with the Program's mapped value and selector, and with
//   the approved Preview, before anything derived from them is trusted.
// - `writeOperation(member)`: the grant operation of a row's send.
// - `send({member, request, current, authorization, credential,
//   callResource, signal})`: one physical send, called only inside a fresh
//   durable claim.
// - `project({member, memberIndex, rowIndex, preview, request, current,
//   observation, headers})`: the provider's classification `{kind,
//   outcome?}`. Only a typed success or failure carries an `effect_outcome`
//   and settles the row; anything else leaves it unknown, never resent.
// - `footprint({member, entries})`: an opaque footprint's
//   `{providerNamespace, resourceKind, boundaryCid}`, or the provider's
//   complete write footprint (`kind` and its fields).
// Optionally:
// - `prepareRequestChild({member, value, selector, current, content, signal,
//   rowIndex, authorizationForRow, assertCurrent})`: synchronously returns the same original
//   `{prepare, release, retry, status}` child. Capture retains it before await;
//   missing physical funding/read authority must refuse before acquisition.
//   CREATE uses the existing unindexed context without a target-read grant.
//   Guarded rows receive their exact rowIndex and a zero-argument read grant
//   supplier closed over that row and the original target-read decision. The
//   child may read before deriving conditional request bytes; observeTargets
//   must project that same original before observation at capture, not acquire
//   another target or append a condition to an already identified request.
// - `describe({member, runInvocationCid, dispatchRequestCid, label,
//   signal})`: the provider's current description of the member's Resource
//   (`current`), taken for the Preview and again for each apply.
// - `recheckRequests({member, entries, current})`: refuse requests the
//   current description no longer admits.
// - `issueCapability({member, entries, current, runInvocationCid,
//   dispatchRequestCid})`: the provider's formal capability issuance,
//   `{identity, route, binding}`; the common owner admits it (see
//   `admitCapability`). Without it, the common sealed capability is used.
// - `check` `{resource, operation}` and `checkRequest(...)` (create): a
//   provider read that must pass for every row before the Preview and again
//   before the Set is applied.
// - `targetRead` `{operation}` and `observeTargets({member, entries,
//   current, authorizationForRow, signal})` (update): the observed target of
//   each row, `{identity, versionCid, before}`. Only UPSERT also admits explicit
//   `{identity, state: 'absent'}` without a before value/version. The installed
//   provider must obtain it under the same original authorized complete lookup
//   and enforce its unique key atomically at creation, never overwrite a race.
//   No missing value, HTTP status or empty object is an absence observation.
//   When the Host decides target
//   reads through a resumed Checkpoint (`targetReads`), the driver's
//   `admitTargetReadApproval({member, decision})` admits the approval for
//   exactly the member's physical binding; the admitted approval grants the
//   reads and the describe.
// - `recoveryEntry({member, current, entries})`: data retained with the captured
//   computation to rebuild requests on recovery, and `recoverRequests({durable,
//   recorded, previewWire, body})`, with `requestCid(request)`, a rebuilt
//   request's identity. The three come together. Retained data is checked,
//   never authority: every rebuilt request must be exactly the one its claim
//   and approved Preview row name. `recoverMemberRequests` explicitly supports
//   composed recovery: the same full Preview and claims are passed with the
//   original global `memberIndexes`; result arrays follow that index order.
// - `prepareRecoveredContentChild(...)` optionally restores original Content
//   bindings for those already validated requests. Its factory performs no I/O;
//   the existing recovery owner retains the child before awaiting prepare.
// Commands require recheckRequests and all three recovery hooks. Target
// validation must use current reference authority; a parsed envelope alone
// is not an authority decision. An asynchronous recheck is awaited before send.
//
// The identities this factory issues (dispatch, recovery, unit, source,
// target check and continuation) use the versions of the installation's
// registered identity profile (`host-bundle.json`, generated into the
// installed connector table), or the common default. No provider name or
// type appears here.
import {runtimeField, runtimeTupleFromFields} from '../host-common/compiler-binding.generated.mjs';
import {captureInstalledEffectPlanRecipe, prepareInstalledStandardCreatePlanRecipe, prepareInstalledEffectManagedPlan, prepareInstalledEffectRequestChild, prepareInstalledEffectOwnedRequestChild, prepareInstalledEffectCredentialChild} from './installed-effect-plan.mjs';
import {installedRowCredentialOperationSite} from './installed-row-source.mjs';
import {createHash} from 'node:crypto';
import {types as nodeTypes} from 'node:util';
import {ownHttpRequest, ownRequestHeaders, ownResponseHeaderNames} from '../host-common/http-exchange.mjs';
import {invokeScopedCredentialOperation} from '../host-common/owned-invocation-context.mjs';
import {checkedTableWriteBinding} from './table-write-binding.mjs';
import {mkdir} from 'node:fs/promises';
import {checked} from '../host-common/runtime-result.mjs';
import {refusedEffectPreparation} from
  '../host-common/effect-preparation-result.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {issueCompletedEffectfulComputationEvidence,
  releaseCompletedRunPreparedPayloads, storeCompletedRunResultSet} from
  '../host-common/completed-run-publication.mjs';
import {installedConnectors} from
  '../connectors-builtin/installations.generated.mjs';
import {isInstalledConnectorTableEntry} from './installed-connectors.mjs';
import {canonicalJson} from './local-account-config.mjs';
import {canonicalJson as canonicalValueJson} from
  '../../packages/sdk/host-port.mjs';
import {preparePinnedEffectSourceHoldings, preparePinnedEffectSourceSet,
  retainPinnedEffectDependencyPayloads} from './effect-input-export.mjs';
import {verifyPinnedEffectPlan} from './effect-plan-verify.mjs';
import {retireEffectCommandKeyWorkspace} from './effect-command-key.mjs';
import {openEffectLedger} from './effect-ledger.mjs';
import {effectLedgerImplementationBounds} from './effect-ledger-implementation-bounds.mjs';
import {captureClaimedEffectResponse, snapshotEffectDispatchClaim} from
  './effect-physical-dispatch.mjs';
import {recoverProjectedEffectResponse} from './effect-response-recovery.mjs';
import {localContractLimits} from './local-values-plan.mjs';
import {prepareInstalledRowCaptureChild, retainInstalledRowCaptureChild, releaseInstalledRowCapture} from './installed-row-capture-cleanup.mjs';
import {issueUpdateTargetInstallation, assertUpdateTargetSelectionCurrent,
  assertUpdateTargetSelectionMembersCurrent} from './update-target-original-shape.mjs';
import {assertInstalledSourceConstruction, retainInstalledSourceConstruction,
  closeInstalledSourceConstruction} from './installed-host-services.mjs';

// Private provenance: copies of an adapter cannot introduce an installation.
const rowInstallations = new WeakMap();
const memberInstallations = new WeakMap();
const ROUTING_VERSION = 'actql-installed-row-effect-routing/0.1';

const CAPABILITY_VERSION = 'actql-installed-row-effect-capability/0.1';
// The common identity profile of an installation that registers none.
const defaultProfile = Object.freeze({
  continuation: 'actql-installed-row-effect-continuation/0.1',
  continuationBinding: 'binding_cid',
  dispatch: 'actql-installed-row-effect-dispatch/0.1',
  recovery: 'actql-installed-row-effect-recovery/0.1',
  source: 'actql-installed-row-effect-source/0.1',
  targetCheck: 'actql-installed-row-effect-check/0.1',
  unit: 'actql-installed-row-effect-unit/0.1',
});
const kinds = Object.freeze(['create', 'update', 'upsert', 'delete', 'command']);
// A guarded write selects an existing target and is guarded by its observed
// version.
const guarded = kind => kind === 'update' || kind === 'upsert' || kind === 'delete';
// Commands select a ResourceRef, but do not invent a row version guard or
// before/after state. The checked payload and current target authority are
// independent obligations.
const targeted = kind => guarded(kind) || kind === 'command';
const contractCidOf = member => member.kind === 'command'
  ? member.command.commandCid : member.mapping.mappingCid;
// Command has no contract minimum. Only legacy Mapping DATA uses this reader.
const approvalOf = member => member.mapping.approval;
const approvedValue = (kind, row) => kind === 'delete' ? undefined : kind === 'command'
  ? row.intended_changes?.value : row.after?.value;
// A deletion has no proposed value. It must not acquire an empty object,
// null, an UPDATE body or a Command input to satisfy the shared comparison.
const sameEffectValue = (kind, left, right) => kind === 'delete'
  ? left === undefined && right === undefined : sameValue(left, right);
const footprintKinds = Object.freeze(['exact_targets', 'collection',
  'opaque']);

const defaultLimits = Object.freeze({
  maxMembers: 16, maxRows: 200, maxWork: 10_000, maxFrontierWork: 1000,
  maxPinnedResults: 64, maxFields: 100, planWork: 10_000,
  preview: Object.freeze({maxWireBytes: 1_000_000, maxNodes: 100_000,
    maxDepth: 64}),
  key: Object.freeze({maxBytes: 4096, maxNodes: 64, maxDepth: 8}),
  locator: Object.freeze({maxBytes: 4096, maxNodes: 64, maxDepth: 8}),
  body: Object.freeze({maxBytes: 100_000, maxNodes: 10_000, maxDepth: 16}),
});

const fail = (code, cause) => {
  throw Object.assign(new Error(code, {cause}), {code});
};
const text = value => typeof value === 'string' && value.length > 0;
const cidPattern = /^sha256:[0-9a-f]{64}$/u;
const cid = value => `sha256:${createHash('sha256')
  .update(canonicalJson(value)).digest('hex')}`;
const pendingCid = `sha256:${'0'.repeat(64)}`;
// Data values (row values, targets, outcomes) keep their exact strings and
// JSON keys through the shared value encoder's explicit data mode. The
// configuration encoder serves only structural identity preimages here.
const sameValue = (left, right) =>
  canonicalValueJson(left, {dataKeys: true}) ===
    canonicalValueJson(right, {dataKeys: true});

// Private wiring over this capture's original Common materials. Escaped
// callbacks keep only this retireable projection, not the captured Run graph.
function commandContentBorrower(configuration) {
  let original = configuration;
  const views = [];
  const observe = operation => {
    const current = original;
    if (current === undefined) fail('OriginalEffectContentUnavailable');
    current.assertCurrent?.();
    if (original !== current) fail('OriginalEffectContentUnavailable');
    const result = operation();
    current.assertCurrent?.();
    if (original !== current) fail('OriginalEffectContentUnavailable');
    return result;
  };
  return Object.freeze({
    borrow(row, inputName) {
      const current = original;
      if (current === undefined || typeof inputName !== 'string' ||
          inputName.length > current.limits.maxWork) {
        fail('OriginalEffectContentUnavailable');
      }
      current.assertCurrent?.();
      if (original !== current) fail('OriginalEffectContentUnavailable');
      const prior = views.find(value => value.row === row && value.inputName === inputName);
      if (prior !== undefined) {
        if (!prior.borrow.current()) fail('OriginalEffectContentUnavailable');
        current.assertCurrent?.();
        if (original !== current) fail('OriginalEffectContentUnavailable');
        return prior.borrow;
      }
      const {maxRows, maxFields, maxWork} = current.limits;
      if (maxFields === 0 || Math.ceil((views.length + 1) / maxFields) > maxRows) {
        fail('InstalledRowEffectContentBorrowLimit');
      }
      const common = current.control.borrowEffectCommandContent(current.prepared,
        current.inputs, current.memberIndex, current.artifact, row, inputName,
        {maxFields, maxWork});
      if (original !== current) {
        common.release();
        fail('OriginalEffectContentUnavailable');
      }
      const borrow = Object.freeze({
        binding: common.binding,
        current: () => original !== undefined && observe(() => common.current()),
        matchesIssued: issued => original !== undefined &&
          observe(() => common.matchesIssued(issued)),
        wire: () => observe(() => common.wire()),
        release: () => common.release(),
      });
      // Retain before another caller callback can throw or retire this input.
      views.push({row, inputName, borrow});
      current.assertCurrent?.();
      if (original !== current) fail('OriginalEffectContentUnavailable');
      return borrow;
    },
    release() {
      original = undefined;
      for (const {borrow} of views) borrow.release();
      views.length = 0;
    },
  });
}

function commandContentRow(port, row) {
  return inputName => port.borrow(row, inputName);
}

// This is the existing installation projection used by composed recovery.
// Its canonical bytes identify an owner without admitting structural copies
// of an adapter or introducing another installation registry.
const installationFacts = owner => ({
  connector_registration: owner.connectorRegistration,
  connector_revision: owner.connectorRevision,
  runtime_bundle_cid: owner.runtimeBundleCid, binding_cid: owner.bindingCid,
  connection: owner.connection, profile: owner.profile,
  continuation_binding: owner.continuationBinding,
});
const ownerBinding = owner => issueUpdateTargetInstallation(owner.moon, installationFacts(owner));
export function installedRowEffectOwnerBinding(adapter) {
  const owner = rowInstallations.get(adapter);
  return owner === undefined || Array.isArray(owner) ? undefined : ownerBinding(owner);
}

const selectionChanged = cause => {
  throw refusedEffectPreparation(Object.assign(
    new Error('InstalledRowEffectInstallationChanged', {cause}),
    {code: 'InstalledRowEffectInstallationChanged'}));
};
const updateObservations = owners => owners.map(owner => ({installation: ownerBinding(owner),
  update: owner.owned.kinds.includes('update'),
  ...(owner.owned.kinds.includes('delete') ? {delete: true} : {}),
  ...(owner.storeMappings.length === 0 ? {} : {store: true}),
  mappings: owner.installed.map(mapping => ({
    target: mapping.target, mappingRef: mapping.mappingRef, mappingCid: mapping.mappingCid,
    update: mapping.rules.some(rule => rule.effect_kind === 'update'),
    ...(mapping.rules.some(rule => rule.effect_kind === 'delete') ? {delete: true} : {}),
    ...(owner.storeMappings.includes(mapping) ? {store: true} : {})}))}));
const validateOwnerSelections = (owners, selections, prepared) => {
  if (selections === undefined) return undefined;
  try { assertUpdateTargetSelectionCurrent(selections, updateObservations(owners), prepared); }
  catch (cause) { selectionChanged(cause); }
  return selections;
};

// Current physical installation facts; semantic matching stays in Common.
export function installedRowEffectUpdateObservations(adapter) {
  const owner = rowInstallations.get(adapter);
  return updateObservations(owner === undefined ? [] : Array.isArray(owner) ? owner : [owner]);
}

// The Host has already checked the original Core selection owners. This
// boundary additionally binds those tuples to the actual installed driver.
export function validateInstalledUpdateOwnerSelections(adapter, selections, prepared) {
  const owner = rowInstallations.get(adapter);
  return validateOwnerSelections(owner === undefined ? [] :
    Array.isArray(owner) ? owner : [owner], selections, prepared);
}

const exportLimits = output => [output.maxResultFields,
  output.maxResultMappingWork, output.maxResultOrderWork,
  output.maxResultWorkspaceEntries, output.maxRows, output.maxValueNodes,
  output.maxValueTextBytes, output.maxValueDepth, output.maxValueWork,
  output.maxWireBytes, output.maxWireNodes, output.maxWireDepth,
  output.maxColumns, output.maxOrderWork, output.maxLogicalWireBytes,
  output.maxLogicalWireNodes, output.maxLogicalWireDepth,
  output.maxSchemaFields, output.maxSchemaBytes, output.maxSchemaNodes,
  output.maxSchemaDepth, output.maxBatchBytes];

const parseExactJson = wire => {
  let value;
  try { value = JSON.parse(wire); }
  catch (error) { fail('InvalidInstalledRowEffectPreview', error); }
  if (JSON.stringify(value) !== wire) fail('LossyInstalledRowEffectPreview');
  return value;
};

const optionalFunction = value => value === undefined ||
  typeof value === 'function';

// The actual Host supplies this private service. Capturing its methods does
// not issue a Run or turn limits into capacity; the retained owner validates
// the original preparation/Run before each physical use.
// Closed operation-name DATA from the same installed provider. This keeps the
// original descriptor; it neither counts physical calls nor supplies capacity.
function captureManagedPlanDefinition(definition, driver) {
  if (definition === undefined) return undefined;
  const fields = (value, names) => {
    if (value === null || typeof value !== 'object' || nodeTypes.isProxy(value) ||
        !Object.isFrozen(value)) fail('InvalidInstalledEffectPlanDefinition');
    const descriptors = Object.getOwnPropertyDescriptors(value);
    if (Reflect.ownKeys(descriptors).length !== names.length ||
        names.some(name => !Object.hasOwn(descriptors[name] ?? {}, 'value'))) {
      fail('InvalidInstalledEffectPlanDefinition');
    }
    return descriptors;
  };
  const selected = fields(definition, ['kind', 'memberOperations', 'rowOperations']);
  const kind = selected.kind.value;
  if (!['update', 'command'].includes(kind) || !driver.kinds.includes(kind)) {
    fail('InvalidInstalledEffectPlanDefinition');
  }
  const roles = kind === 'update' ? ['target-read', 'write'] : ['write'];
  for (const [name, expected] of [['memberOperations', []], ['rowOperations', roles]]) {
    const original = selected[name].value;
    if (!Array.isArray(original) || nodeTypes.isProxy(original) ||
        !Object.isFrozen(original) || original.length !== expected.length) {
      fail('InvalidInstalledEffectPlanDefinition');
    }
    const array = fields(original, ['length', ...expected.map((_, index) => String(index))]);
    for (let index = 0; index < expected.length; index++) {
      const operation = fields(array[String(index)].value, ['role', 'operation']);
      if (operation.role.value !== expected[index] || !text(operation.operation.value) ||
          !operation.operation.value.isWellFormed() ||
          expected[index] === 'target-read' && operation.operation.value !== driver.targetRead?.operation) {
        fail('InvalidInstalledEffectPlanDefinition');
      }
    }
  }
  return definition;
}

// A retained-request Command supplies the SAME constructor metadata and
// native profile held by its actual driver. The existing standard composer
// then owns capture/request/HTTP/recovery quantities; this introduces no
// alternative calculator, row count, reservation, permission or cleanup owner.
function captureManagedDriverConstruction(construction, definition, driver, provider) {
  if (construction === undefined) return undefined;
  const own = (value, names) => {
    if (!value || typeof value !== 'object' || nodeTypes.isProxy(value) || !Object.isFrozen(value)) {
      fail('InvalidInstalledEffectDriverConstruction');
    }
    const fields = Object.getOwnPropertyDescriptors(value);
    if (Reflect.ownKeys(fields).length !== names.length || names.some(name =>
      !Object.hasOwn(fields[name] ?? {}, 'value'))) fail('InvalidInstalledEffectDriverConstruction');
    return fields;
  };
  if (definition?.kind !== 'command' || driver.kinds.length !== 1 || driver.kinds[0] !== 'command' ||
      Object.getOwnPropertyDescriptor(driver,'managedPlanDefinition')?.value !== definition ||
      Object.getOwnPropertyDescriptor(driver,'managedPlanConstruction')?.value !== construction ||
      Object.getOwnPropertyDescriptor(driver,'managedPlanProvider')?.value !== provider) {
    fail('InvalidInstalledEffectDriverConstruction');
  }
  const fields = own(construction,['write','check','metadataTextUnits']);
  const write = own(fields.write.value,['operation','maxRequestBytes','maxResponseBytes']);
  if (fields.check.value !== undefined || write.operation.value !== definition.rowOperations[0].operation ||
      ![write.maxRequestBytes.value,write.maxResponseBytes.value].every(value =>
        Number.isSafeInteger(value) && value > 0 && value <= 2147483647) ||
      !Number.isSafeInteger(fields.metadataTextUnits.value) || fields.metadataTextUnits.value < 0) {
    fail('InvalidInstalledEffectDriverConstruction');
  }
  return construction;
}

function captureEffectResources(receiver) {
  if (receiver === undefined) return undefined;
  const methods = {};
  for (const name of ['bindRunOriginal', 'assertCurrent', 'limits']) {
    const field = receiver === null || typeof receiver !== 'object'
      ? undefined : Object.getOwnPropertyDescriptor(receiver, name);
    if (field === undefined || !Object.hasOwn(field, 'value') ||
        typeof field.value !== 'function') fail('InstalledEffectResourcesUnavailable');
    const method = field.value;
    methods[name] = (...args) => Reflect.apply(method, receiver, args);
  }
  return Object.freeze(methods);
}

function requireSynchronousEffectResource(value) {
  if (typeof value?.then === 'function') {
    void Promise.resolve(value).catch(() => {});
    fail('InstalledEffectResourcesUnavailable');
  }
  return value;
}

// Standard CREATE plumbing for the SAME Row Effect, not another lifecycle.
function deriveInstalledRowWrite(write, connectorRegistration) {
  const fail = () => { throw Object.assign(new TypeError('InvalidInstalledRowWrite'),
    {code: 'InvalidInstalledRowWrite'}); };
  const cid = value => typeof value === 'string' && /^sha256:[0-9a-f]{64}$/u.test(value);
  const text = value => typeof value === 'string' && value.length > 0;
  function data(value, key, optional = false) {
    if (value === null || typeof value !== 'object' || nodeTypes.isProxy(value)) fail();
    const field = Object.getOwnPropertyDescriptor(value, key);
    if (field === undefined && optional) return undefined;
    if (!field || !Object.hasOwn(field, 'value')) fail();
    return field.value;
  }

  // Decoded proposal values already belong to the enclosing Row Effect. Freeze
  // them in place before mapping so the association retains the exact input,
  // including nested cells, without another JSON roundtrip or value checker.
  function freezeInput(value) {
    if (value !== null && typeof value === 'object') {
      for (const child of Object.values(value)) freezeInput(child);
      Object.freeze(value);
    }
    return value;
  }

  if (data(write, 'kind') !== 'create' || !text(connectorRegistration)) fail();
  const operation = data(write, 'operation'), resourceKind = data(write, 'resourceKind');
  const boundaryCid = data(write, 'boundaryCid'), http = data(write, 'http');
  const origin = data(http, 'origin'), method = data(http, 'method'), path = data(http, 'path');
  const maxRequestBytes = data(http, 'maxRequestBytes'), maxResponseBytes = data(http, 'maxResponseBytes');
  const map = data(write, 'request'), classify = data(write, 'classify');
  if (!text(operation) || !text(resourceKind) || !cid(boundaryCid) ||
      typeof origin !== 'string' || !URL.canParse(origin) || new URL(origin).origin !== origin ||
      !origin.startsWith('https://') || !text(path) || !['POST', 'PUT', 'PATCH'].includes(method) ||
      ![maxRequestBytes, maxResponseBytes].every(value => Number.isSafeInteger(value) && value > 0) ||
      typeof map !== 'function' || typeof classify !== 'function' ||
      nodeTypes.isAsyncFunction(map) || nodeTypes.isAsyncFunction(classify)) fail();
  const headers = ownRequestHeaders(data(http, 'headers', true));
  const responseHeaders = ownResponseHeaderNames(data(http, 'responseHeaders', true));
  const requestDomain = 'actql-installed-row-write-request/0.1';
  const recoveryKind = 'standard_row_write';
  // This is one immutable metadata input, not a byte tariff or a Run bound.
  // The same selected recipe later counts its actual serialization roles.
  let metadataTextUnits = connectorRegistration.length + resourceKind.length + boundaryCid.length +
    operation.length + origin.length + method.length + path.length + requestDomain.length + recoveryKind.length;
  for (const [name, value] of headers) metadataTextUnits += name.length + value.length;
  for (const name of responseHeaders) metadataTextUnits += name.length;
  const check = data(write, 'check', true);
  let checkOptions, constructionCheck = check === undefined ? undefined : null;
  if (check !== undefined) {
    const resource = data(check, 'resource'), operation = data(check, 'operation');
    const beforeSend = data(check, 'beforeSend', true);
    const checkHttp = data(check, 'http', true);
    const request = data(check, 'request', checkHttp !== undefined);
    if (!text(resource) || !text(operation) ||
        (beforeSend !== undefined && typeof beforeSend !== 'boolean')) fail();
    const description = Object.freeze({resource, operation, ...(beforeSend === true ? {beforeSend} : {})});
    if (checkHttp === undefined) {
      if (typeof request !== 'function') fail();
      checkOptions = {check: description, checkRequest: context => Reflect.apply(request, check, [context])};
    } else {
      const body = data(check, 'body'), project = data(check, 'project');
      const checkOrigin = data(checkHttp, 'origin'), checkMethod = data(checkHttp, 'method'), checkPath = data(checkHttp, 'path');
      const requestBytes = data(checkHttp, 'maxRequestBytes'), responseBytes = data(checkHttp, 'maxResponseBytes');
      if (request !== undefined || checkOrigin !== origin || !['GET','POST','HEAD'].includes(checkMethod) || !text(checkPath) ||
          ![requestBytes,responseBytes].every(value => Number.isSafeInteger(value) && value > 0) ||
          typeof body !== 'function' || typeof project !== 'function' ||
          nodeTypes.isAsyncFunction(body) || nodeTypes.isAsyncFunction(project)) fail();
      const readHeaders = ownRequestHeaders(data(checkHttp, 'headers', true));
      const readResponseHeaders = ownResponseHeaderNames(data(checkHttp, 'responseHeaders', true));
      const template = ownHttpRequest({method: checkMethod, path: checkPath,
        query: data(checkHttp, 'query', true), headers: readHeaders});
      constructionCheck = Object.freeze({resource, operation, beforeSend: beforeSend === true,
        maxRequestBytes: requestBytes, maxResponseBytes: responseBytes});
      metadataTextUnits += resource.length + operation.length + checkOrigin.length + checkMethod.length + template.target.length;
      for (const [name, value] of readHeaders) metadataTextUnits += name.length + value.length;
      for (const name of readResponseHeaders) metadataTextUnits += name.length;
      checkOptions = {check: description,
        async checkRequest({request, authorization, credential, callResource, signal, controlConstruction}) {
          const {value: mappedValue} = original(request);
          if (authorization?.scope?.resourceOrigin !== checkOrigin) fail();
          signal?.throwIfAborted();
          const context = Object.freeze({resource, value: mappedValue, request});
          const value = Reflect.apply(body, check, [context]);
          // Existing metadata GET operations carry no entity body. Keep
          // that original wire distinction; an empty String adds HTTP framing.
          const absentBody = value === undefined && checkMethod === 'GET';
          if (!absentBody && typeof value !== 'string') {
            // Invalid async provider work stays in this SAME original child
            // until settlement. Rejection preserves its original cause.
            await value;
            fail();
          }
          if (!absentBody && (value.length > requestBytes || Buffer.byteLength(value) > requestBytes)) fail();
          const observed = await invokeScopedCredentialOperation({authorization, credential, callResource,
            operation, method: checkMethod, path: template.target, headers: template.headers,
            ...(absentBody ? {} : {body: value}),
            responseHeaders: readResponseHeaders, maxRequestBytes: requestBytes, maxResponseBytes: responseBytes, signal});
          signal?.throwIfAborted();
          const projection = Object.freeze({resource, value: mappedValue, request,
            accepted: observed.accepted,
            observation: Object.freeze({useCid: observed.useCid, statusCode: observed.statusCode, body: observed.body}),
            ...(Object.hasOwn(observed, 'headers') ? {headers: observed.headers} : {})});
          // The HTTP child keeps its physical holdings. The synchronous native
          // projector uses the same Run's separately retained control frame;
          // an invalid async result stays joined by that original owner.
          const projected = controlConstruction === undefined ? Reflect.apply(project, check, [projection])
            : controlConstruction(check, project, [projection]);
          if (projected !== undefined) {await projected; fail();}
        }};
    }
  }
  const originals = new WeakMap();
  const original = request => {
    const selected = originals.get(request);
    if (selected === undefined) fail();
    return selected;
  };
  // This standard path accepts plain JSON request DATA, not native opaque
  // provider originals. Existing contract bounds cap the saved capture bytes;
  // they do not issue capacity, permission or a physical retention receipt.
  function freezeRequestData(value, depth = 0, state = {nodes: 0, active: new Set()}) {
    if (++state.nodes > localContractLimits.maxNodes || depth > localContractLimits.maxDepth) fail();
    if (value === null || typeof value === 'boolean') return value;
    if (typeof value === 'string') {
      if (value.length > localContractLimits.maxWireBytes || Buffer.byteLength(value) > localContractLimits.maxWireBytes) fail();
      return value;
    }
    if (typeof value === 'number') {
      if (!Number.isFinite(value) || Object.is(value, -0)) fail();
      return value;
    }
    if (typeof value !== 'object' || nodeTypes.isProxy(value) || state.active.has(value) ||
        Object.getPrototypeOf(value) !== (Array.isArray(value) ? Array.prototype : Object.prototype)) fail();
    state.active.add(value);
    const keys = Reflect.ownKeys(value);
    if (Array.isArray(value) && (keys.length !== value.length + 1 ||
        keys.some((key, index) => key !== (index === value.length ? 'length' : String(index))))) fail();
    for (const key of keys) {
      if (Array.isArray(value) && key === 'length') continue;
      if (typeof key !== 'string' || key.length > localContractLimits.maxWireBytes) fail();
      const field = Object.getOwnPropertyDescriptor(value, key);
      if (!field || !Object.hasOwn(field, 'value') || !field.enumerable) fail();
      freezeRequestData(field.value, depth + 1, state);
    }
    state.active.delete(value);
    return Object.freeze(value);
  }
  function bindRequest(request, resource, value, expectedCid) {
    if (request === null || typeof request !== 'object' || nodeTypes.isProxy(request) ||
        data(request, 'then', true) !== undefined || originals.has(request)) fail();
    const requestOrigin = data(request, 'origin', true), requestMethod = data(request, 'method', true);
    if ((requestOrigin !== undefined && requestOrigin !== origin) ||
        (requestMethod !== undefined && requestMethod !== method) ||
        data(request, 'headers', true) !== undefined || data(request, 'path') !== path) fail();
    const body = data(request, 'body');
    if (typeof body !== 'string') fail();
    const exact = ownHttpRequest({method, path,
      query: data(request, 'query', true), body, headers});
    if (Buffer.byteLength(exact.body) > maxRequestBytes) fail();
    const providerCid = data(request, 'requestCid', true);
    if (providerCid !== undefined && !cid(providerCid)) fail();
    // Existing typed providers keep their original request identity. Plain
    // standard HTTP mappings need no separate identity callback.
    const requestCid = providerCid ?? `sha256:${createHash('sha256').update(JSON.stringify([
      requestDomain, connectorRegistration,
      resourceKind, boundaryCid, operation, origin, method, exact.target,
      exact.headers, exact.body])).digest('hex')}`;
    if (expectedCid !== undefined && expectedCid !== requestCid) fail();
    freezeRequestData(request);
    originals.set(request, Object.freeze({resource, value, exact, requestCid}));
    return Object.freeze({request, requestCid});
  }
  const recoveryBinding = resource => [connectorRegistration, resourceKind,
    boundaryCid, operation, origin, method, path, headers, responseHeaders,
    maxRequestBytes, maxResponseBytes, resource];
  const wireCid = wire => `sha256:${createHash('sha256').update(wire).digest('hex')}`;
  function restoreMembers({durable, members}, indexes) {
    if (!Array.isArray(durable?.connectorRecovery)) fail();
    return {requests: indexes.map(index => {
      const member = members[index];
      if (member?.kind !== 'create' || !text(member.resource)) fail();
      const saved = durable.connectorRecovery.filter(item => item.memberIndex === index);
      if (saved.length !== 1 || saved[0].kind !== recoveryKind ||
          typeof saved[0].wire !== 'string' || Buffer.byteLength(saved[0].wire) > localContractLimits.maxWireBytes ||
          wireCid(saved[0].wire) !== saved[0].observationCid) fail();
      const envelope = JSON.parse(saved[0].wire);
      freezeRequestData(envelope);
      if (!Array.isArray(envelope) || envelope.length !== 2 ||
          JSON.stringify(envelope) !== saved[0].wire ||
          JSON.stringify(envelope[0]) !== JSON.stringify(recoveryBinding(member.resource)) ||
          !Array.isArray(envelope[1])) fail();
      return envelope[1].map(row => {
        if (!Array.isArray(row) || row.length !== 3 || !cid(row[0]) ||
            row[1] === null || typeof row[1] !== 'object') fail();
        return bindRequest(row[2], member.resource, row[1], row[0]).request;
      });
    })};
  }
  const driver = Object.freeze({
    kinds: Object.freeze(['create']),
    writeOperation: () => operation,
    footprint: () => ({providerNamespace: connectorRegistration, resourceKind, boundaryCid}),
    ...checkOptions,
    prepareRequest(context) {
      if (context?.member?.kind !== 'create' || !text(context.member.resource)) fail();
      const resource = context.member.resource;
      const value = freezeInput(context.value);
      const proposalWire = data(context, 'proposalWire', true);
      if (proposalWire !== undefined && (typeof proposalWire !== 'string' ||
          proposalWire.length > localContractLimits.maxWireBytes ||
          Buffer.byteLength(proposalWire) > localContractLimits.maxWireBytes)) fail();
      const request = Reflect.apply(map, write, [Object.freeze({resource, value,
        ...(proposalWire === undefined ? {} : {proposalWire})})]);
      return bindRequest(request, resource, value);
    },
    requestCid: request => original(request).requestCid,
    recoveryEntry({member, entries}) {
      if (member?.kind !== 'create' || !text(member.resource) || !Array.isArray(entries)) fail();
      const bindingValue = recoveryBinding(member.resource);
      const selectedRows = entries.map(entry => {
        const selected = original(entry.request);
        if (selected.resource !== member.resource || entry.requestCid !== selected.requestCid ||
            entry.value !== selected.value) fail();
        return [selected.requestCid, selected.value, entry.request];
      });
      freezeRequestData([bindingValue, selectedRows]);
      const binding = JSON.stringify(bindingValue);
      let bytes = Buffer.byteLength(binding) + 5;
      const rows = selectedRows.map(row => {
        const wire = JSON.stringify(row);
        bytes += Buffer.byteLength(wire) + 1;
        if (bytes > localContractLimits.maxWireBytes) fail();
        return wire;
      });
      const wire = `[${binding},[${rows.join(',')}]]`;
      return Object.freeze({kind: recoveryKind, observationCid: wireCid(wire), wire});
    },
    recoverRequests(context) {
      return restoreMembers(context, context.members.map((_, index) => index));
    },
    recoverMemberRequests(context) {
      return restoreMembers(context, context.memberIndexes);
    },
    requestFacts(request) { return {value: original(request).value}; },
    async send({request, authorization, credential, callResource, signal}) {
      const {exact} = original(request);
      if (authorization?.scope?.resourceOrigin !== origin) fail();
      signal?.throwIfAborted();
      const response = await invokeScopedCredentialOperation({authorization, credential,
        callResource, operation, method, path: exact.target, headers: exact.headers,
        body: exact.body, responseHeaders, maxRequestBytes, maxResponseBytes, signal});
      return Object.freeze({observation: Object.freeze({useCid: response.useCid,
        statusCode: response.statusCode, body: response.body}), headers: response.headers});
    },
    project(context) {
      const {resource, value} = original(context.request);
      return Reflect.apply(classify, write, [Object.freeze({resource, value,
        request: context.request, observation: context.observation,
        ...(Object.hasOwn(context, 'headers') ? {headers: context.headers} : {})})]);
    },
  });
  return Object.freeze({driver, construction: Object.freeze({
    write: Object.freeze({operation, maxRequestBytes, maxResponseBytes}),
    check: constructionCheck, metadataTextUnits})});
}

// One member's original CREATE values and canonical row identities. The
// Common inventory owns ordering; the Host never derives identities itself.
function prepareInstalledCreateRows(moon, proposals, limits) {
  // Capture each immutable original String once. Common already checks the
  // member's total wire/node/depth limits as part of this SAME canonical
  // inventory; do that before materializing the Host value tree. A mutable
  // proposal wrapper cannot substitute a different wire after that call.
  const wires = proposals.map(proposal => proposal.changesWire);
  const {maxWireBytes, maxNodes, maxDepth} = limits;
  const inventory = checked(moon.clientProgramEffectCreateRowInventory(
    wires, wires.length, maxWireBytes, maxNodes, maxDepth));
  if (inventory.length !== wires.length ||
      new Set(inventory.map(item => runtimeField(item, 0))).size !== wires.length) {
    fail('InvalidInstalledRowEffectInventory');
  }
  const createRows = inventory.map(item => {
    const wire = wires[runtimeField(item, 0)];
    const changes = JSON.parse(wire);
    return {entry: {value: changes.value, proposalWire: wire, selector: undefined},
      identity: Object.freeze(parseExactJson(runtimeField(item, 1)))};
  });
  return {rows: createRows.map(item => item.entry), createRows};
}

function checkDriver(driver) {
  if (driver === null || typeof driver !== 'object' ||
      !Array.isArray(driver.kinds) || driver.kinds.length === 0 ||
      driver.kinds.some(kind => !kinds.includes(kind)) ||
      typeof driver.prepareRequest !== 'function' ||
      typeof driver.requestFacts !== 'function' ||
      typeof driver.writeOperation !== 'function' ||
      typeof driver.send !== 'function' ||
      typeof driver.project !== 'function' ||
      typeof driver.footprint !== 'function' ||
      ![driver.describe, driver.recheckRequests, driver.issueCapability,
        driver.observeTargets, driver.recoveryEntry, driver.recoverRequests,
        driver.recoverMemberRequests,
        driver.requestCid, driver.checkRequest,
        driver.admitTargetReadApproval, driver.prepareRequestChild,
        driver.prepareRecoveredContentChild].every(optionalFunction) ||
      (driver.check !== undefined && (!text(driver.check?.resource) ||
        !text(driver.check.operation) ||
        typeof driver.checkRequest !== 'function')) ||
      (driver.kinds.some(guarded) && (!text(driver.targetRead?.operation) ||
        typeof driver.observeTargets !== 'function' ||
        typeof driver.recoverRequests !== 'function' ||
        typeof driver.requestCid !== 'function')) ||
      (driver.kinds.includes('command') &&
        (typeof driver.recheckRequests !== 'function' ||
          typeof driver.recoveryEntry !== 'function' ||
          typeof driver.recoverRequests !== 'function' ||
          typeof driver.requestCid !== 'function')) ||
      ((driver.recoveryEntry === undefined) !==
        (driver.recoverRequests === undefined)) ||
      (driver.recoverMemberRequests !== undefined &&
        driver.recoverRequests === undefined) ||
      // Recovery identifies each rebuilt request by `requestCid`.
      (driver.recoverRequests !== undefined &&
        typeof driver.requestCid !== 'function')) {
    fail('InvalidInstalledRowEffectDriver');
  }
  return driver;
}

// Optional fixed CREATE check repeated immediately before its mutation. This
// captures the original pure descriptor/callback, not a read decision/grant.
// The corresponding DISTINCT physical occurrence must already be declared.
function captureBeforeSendCheck(driver, recipe) {
  const selected = recipe?.credentialOperations?.find(entry => entry.phase === 'write-check');
  const checkField = Object.getOwnPropertyDescriptor(driver, 'check');
  const check = checkField !== undefined && Object.hasOwn(checkField, 'value') ? checkField.value : undefined;
  if (check === undefined) {
    if (selected !== undefined) fail('InstalledEffectWriteCheckUnavailable');
    return undefined;
  }
  if (nodeTypes.isProxy(check)) fail('InvalidInstalledEffectWriteCheck');
  const flag = Object.getOwnPropertyDescriptor(check, 'beforeSend');
  if (flag === undefined || (Object.hasOwn(flag, 'value') && flag.value === false)) {
    if (selected !== undefined) fail('InstalledEffectWriteCheckUnavailable');
    return undefined;
  }
  if (!Object.hasOwn(flag, 'value') || flag.value !== true || !Object.isFrozen(check) ||
      !Object.hasOwn(checkField, 'value') || selected === undefined ||
      driver.kinds.length !== 1 || driver.kinds[0] !== 'create') fail('InvalidInstalledEffectWriteCheck');
  const fields = Object.getOwnPropertyDescriptors(check);
  const request = Object.getOwnPropertyDescriptor(driver, 'checkRequest');
  if (Reflect.ownKeys(fields).length !== 3 ||
      ['resource','operation','beforeSend'].some(name => !Object.hasOwn(fields[name] ?? {}, 'value')) ||
      !text(fields.resource.value) || !text(fields.operation.value) ||
      !request || !Object.hasOwn(request, 'value') || typeof request.value !== 'function' ||
      recipe.rowOperations[selected.operationIndex].operation !== fields.operation.value) {
    fail('InvalidInstalledEffectWriteCheck');
  }
  return Object.freeze({resource: fields.resource.value, operation: fields.operation.value,
    request: request.value, receiver: driver});
}

// The identity profile of an installation: the one its connector registered
// in the installed connector table, or the common default. Only an entry of
// the generated table or a snapshot admitted by the table owner is accepted.
function profileOf(installation) {
  if (installation === undefined) return defaultProfile;
  if ((!installedConnectors.includes(installation) &&
      !isInstalledConnectorTableEntry(installation)) ||
      installation.effect === undefined) {
    fail('InvalidInstalledRowEffectInstallation');
  }
  return installation.effect.identityProfile ?? defaultProfile;
}

// The one Effect Unit of a compiled Program: its Program id, the stage id and
// index, and its Effect ids in declaration order. A Program with Effects in
// more than one stage is not this scope.
export function installedRowEffectUnit(moon, compilation) {
  let program;
  try {
    program = JSON.parse(moon.clientProgramEffectCompilationPlanWire(
      compilation)).execution_material?.program;
  } catch (error) { fail('InstalledRowEffectUnitUnsupported', error); }
  const stages = Array.isArray(program?.stages) ? program.stages : [];
  const units = stages.flatMap((stage, stageIndex) =>
    stage?.effects === undefined ? [] : [{stage, stageIndex}]);
  if (!text(program?.id) || units.length !== 1 || !text(units[0].stage.id)) {
    fail('InstalledRowEffectUnitUnsupported');
  }
  const {stage, stageIndex} = units[0];
  return Object.freeze({programId: program.id, stageId: stage.id, stageIndex,
    effectIds: Object.freeze(Object.keys(stage.effects))});
}

// Host installation selection consumes the already checked member descriptor.
// It does not prepare provider requests or widen the existing plan-work bound.
export function installedRowEffectDescriptors(moon, prepared, compilation) {
  const unit = installedRowEffectUnit(moon, compilation);
  return Object.freeze(unit.effectIds.map(effectId => {
    const descriptor = checked(moon.clientProgramEffectMemberDescriptor(
      prepared, unit.stageIndex, effectId, defaultLimits.planWork));
    const tableBinding = checkedTableWriteBinding(moon, prepared,
      unit.stageIndex, effectId, defaultLimits.planWork);
    if (runtimeField(descriptor, 2) === 'command') {
      return Object.freeze({effectId: runtimeField(descriptor, 1), kind: 'command',
        target: runtimeField(descriptor, 3), commandRef: runtimeField(descriptor, 4), commandCid: runtimeField(descriptor, 5)});
    }
    return Object.freeze({effectId: runtimeField(descriptor, 1), kind: runtimeField(descriptor, 2),
      target: runtimeField(descriptor, 3), mappingRef: runtimeField(descriptor, 4), mappingCid: runtimeField(descriptor, 5),
      ...(tableBinding === undefined ? {} : {capabilityCid: runtimeField(tableBinding, 4)})});
  }));
}

// The installed Effect over `mappings` (each `{resource, mappingRef,
// mappingCid, body}`, checked by the Check Environment it is installed in)
// on the credential `site` and installation gate `authorization`.
// `installation` is the connector's installed table entry, whose registered
// identity profile names the identities issued here; `continuationBinding`
// is the value the continuation binds the installation by.
export async function createInstalledRowEffect({moon, providerMoon, mappings = [], commands = [],
  environmentWire, sourceInitialization, declaration, declared, environment,
  connectorId, connectorRegistration, connectorRevision,
  connection, site, authorization, runtimeBundleCid, bindingCid, driver, write,
  ledgerRoot, installation, continuationBinding = bindingCid,
  limits: suppliedLimits, effectResources, issueOriginalCollectionReference, managedPlanDefinition, managedPlanRecipe, managedPlanConstruction}) {
  if (sourceInitialization !== undefined) {
    assertInstalledSourceConstruction(sourceInitialization, declaration, declared, environment, undefined, mappings, commands);
    if (environment?.wire !== environmentWire) fail('ForeignInstalledSourceConstruction');
  }
  const resources = captureEffectResources(effectResources);
  const limits = Object.freeze({...defaultLimits, ...suppliedLimits});
  if (write !== undefined && driver !== undefined) fail('InvalidInstalledRowEffectDriver');
  const standard = write === undefined ? undefined : deriveInstalledRowWrite(write, connectorRegistration);
  const owned = checkDriver(standard === undefined ? driver : standard.driver);
  const planDefinition = captureManagedPlanDefinition(managedPlanDefinition, owned);
  const suppliedRecipe = captureInstalledEffectPlanRecipe(managedPlanRecipe, localContractLimits.maxNodes);
  if (managedPlanConstruction !== undefined && (standard !== undefined || suppliedRecipe !== undefined)) {
    fail('InvalidInstalledEffectDriverConstruction');
  }
  const construction = standard?.construction ?? captureManagedDriverConstruction(
    managedPlanConstruction, planDefinition, owned, providerMoon);
  const automatic = suppliedRecipe === undefined && construction !== undefined && providerMoon !== undefined &&
    construction.check !== null;
  // Preserve the existing explicit/legacy refusal order. The new automatic
  // path waits only for its same validated installation resource names.
  const suppliedBeforeSendCheck = automatic ? undefined : captureBeforeSendCheck(owned, suppliedRecipe);
  const profile = profileOf(installation);
  if (!moon || !Array.isArray(mappings) || !Array.isArray(commands) ||
      mappings.length + commands.length === 0 ||
      !text(environmentWire) || !text(connectorId) ||
      !text(connectorRegistration) || !text(connectorRevision) ||
      (installation !== undefined &&
        (installation.registration !== connectorRegistration ||
          installation.revision !== connectorRevision)) ||
      !text(connection) || typeof site?.issueEffectGrant !== 'function' ||
      typeof site.issueReadGrant !== 'function' ||
      typeof authorization?.authorize !== 'function' ||
      !optionalFunction(issueOriginalCollectionReference) ||
      !cidPattern.test(runtimeBundleCid ?? '') ||
      !text(bindingCid) || !text(continuationBinding) || !text(ledgerRoot)) {
    fail('InvalidInstalledRowEffect');
  }
  const installed = Object.freeze(mappings.map(mapping => {
    const body = JSON.parse(mapping.body);
    if (!text(mapping.resource) || !text(mapping.mappingRef) ||
        !text(mapping.mappingCid) || body.mapping_contract_cid !==
          mapping.mappingCid ||
        !['required', 'none'].includes(body.minimum_approval)) {
      fail('InvalidInstalledRowEffect');
    }
    return Object.freeze({...mapping, target: body.target_ref,
      primaryIdentity: body.primary_identity,
      rules: Object.freeze(body.permission_rules ?? []),
      ...(body.store_command === undefined ? {} : {
        storeCommand: Object.freeze({...body.store_command})}),
      approval: body.minimum_approval});
  }));
  const installedCommands = Object.freeze(commands.map(command => {
    const body = JSON.parse(command.body);
    const {contract_cid: selfCid, ...preimage} = body;
    if (!text(command.resource) || !text(command.commandRef) ||
        !cidPattern.test(command.commandCid ?? '') ||
        body.command_id !== command.commandRef || selfCid !== command.commandCid ||
        cid(preimage) !== selfCid || body.connector_id !== connectorId ||
        !text(body.target?.resource_kind) ||
        !Array.isArray(body.permissions) ||
        Object.hasOwn(body, 'minimum_approval')) {
      fail('InvalidInstalledRowEffectCommand');
    }
    return Object.freeze({...command, target: body.target.resource_kind,
      permissions: Object.freeze([...body.permissions])});
  }));
  if (new Set(installedCommands.map(item => item.commandRef)).size !==
      installedCommands.length) fail('InvalidInstalledRowEffectCommand');
  // STORE's checked Mapping resolves to a Command, but it remains a distinct
  // original selection purpose. Retain the exact published pair beside its
  // actual Command driver; a generic command or UPDATE flag is not STORE.
  const storeMappings = Object.freeze(!owned.kinds.includes('command') ? [] :
    installed.filter(mapping => mapping.storeCommand !== undefined).map(mapping => {
      const pair = mapping.storeCommand;
      const catalogs = JSON.parse(environmentWire).connector_catalogs;
      const commands = installedCommands.filter(command => command.commandRef === pair.command_ref &&
        command.commandCid === pair.command_contract_cid && command.resource === mapping.resource);
      const {mapping_contract_cid: self, ...body} = JSON.parse(mapping.body);
      if (Object.keys(pair).sort().join('\0') !==
          ['catalog_cid', 'command_contract_cid', 'command_ref'].join('\0') ||
          self !== mapping.mappingCid || cid(body) !== self || commands.length !== 1 ||
          !Array.isArray(catalogs) || catalogs.filter(catalog => catalog.catalog_cid === pair.catalog_cid &&
            catalog.commands.some(command => command.command_id === pair.command_ref &&
              command.contract_cid === pair.command_contract_cid)).length !== 1) {
        fail('InvalidInstalledRowEffectStoreMapping');
      }
      return mapping;
    }));
  let resourceTextUnits = 0;
  if (automatic) {
    for (const selected of installed) resourceTextUnits += selected.resource.length;
    for (const selected of installedCommands) resourceTextUnits += selected.resource.length;
  }
  const planRecipe = automatic ? prepareInstalledStandardCreatePlanRecipe({moon, providerMoon,
    construction, credentialSite: installedRowCredentialOperationSite(site.credential),
    limits: limits.preview, resourceTextUnits,
    requestInput:Object.freeze({maxWireBytes:limits.body.maxBytes,
      maxNodes:limits.body.maxNodes,maxDepth:limits.body.maxDepth})}) : suppliedRecipe;
  const beforeSendCheck = automatic ? captureBeforeSendCheck(owned, planRecipe) : suppliedBeforeSendCheck;
  await mkdir(ledgerRoot, {recursive: true, mode: 0o700});
  if (sourceInitialization !== undefined) {
    // The await may retire the installer. This local association check does
    // not invoke current or repeat Mapping/Environment admission.
    assertInstalledSourceConstruction(sourceInitialization, declaration, declared, environment, undefined, mappings, commands);
  }
  const adapter = createRowEffectStage([Object.freeze({moon, limits, owned, profile,
    installed, installedCommands, storeMappings, environmentWire, connectorId,
    connectorRegistration, connectorRevision, connection, site, authorization,
    runtimeBundleCid, bindingCid, ledgerRoot, continuationBinding, resources,
    managedPlanDefinition: planDefinition, managedPlanRecipe: planRecipe, beforeSendCheck,
    issueOriginalCollectionReference, sourceInitialization})], environmentWire);
  if (sourceInitialization !== undefined) {
    retainInstalledSourceConstruction(sourceInitialization, adapter, declaration, declared, environment);
  }
  return adapter;
}

// Each physical occurrence retains its own admitted installation. Shared Run,
// Preview, claims and publication remain the existing stage's responsibility.
// This profile admits source-free create members. A retained-request driver
// must explicitly support recovery of its original members in the whole Set.
export function composeInstalledRowEffectOwners(effects, descriptors, environmentWire) {
  if (!Array.isArray(effects) || !Array.isArray(descriptors) ||
      effects.length !== descriptors.length || effects.length < 2 ||
      descriptors.some(value => value.kind !== 'create') ||
      new Set(descriptors.map(value => value.effectId)).size !== descriptors.length) {
    fail('InstalledEffectSetOwnerMismatch');
  }
  const owners = effects.map(effect => rowInstallations.get(effect));
  if (owners.some(owner => owner === undefined || Array.isArray(owner) ||
      (owner.owned.recoverRequests !== undefined &&
        owner.owned.recoverMemberRequests === undefined))) fail('InstalledEffectSetOwnerMismatch');
  const first = owners[0];
  if (descriptors.length > first.limits.maxMembers || owners.some(owner => owner.moon !== first.moon ||
      owner.ledgerRoot !== first.ledgerRoot ||
      canonicalJson(owner.limits) !== canonicalJson(first.limits))) {
    fail('InstalledEffectSetOwnerMismatch');
  }
  const routes = Object.freeze(descriptors.map((descriptor, index) =>
    Object.freeze({descriptor: Object.freeze({...descriptor}), owner: owners[index]})));
  const freeze = value => {
    if (value !== null && typeof value === 'object') {
      Object.values(value).forEach(freeze);
      Object.freeze(value);
    }
    return value;
  };
  // Equal limits are data, not shared mutable bootstrap objects. Retain the
  // same numeric ceilings for this stage even if a later table is configured.
  const limits = freeze(JSON.parse(canonicalJson(first.limits)));
  return createRowEffectStage(Object.freeze([...new Set(owners)]), environmentWire, routes, limits);
}

// The installed loader retains the original private port while exposing its
// normal adapter projection. No descriptor or structural marker admits a port.
// Initialization may expose only an already-retained private projection.
// Canonicalize to the exact registered raw adapter, never structural copies
// or equal owner DATA. The original common close remains mandatory here.
export function resolveInstalledRowEffectConstruction(original, projection) {
  if (original === projection) return original;
  const owner = rowInstallations.get(original);
  if (owner === undefined || rowInstallations.get(projection) !== owner ||
      !projection || nodeTypes.isProxy(projection)) return undefined;
  const fields = Object.getOwnPropertyDescriptors(projection);
  for (const key of ['prepareManagedPlan','prepareCaptured','prepareRecovered',
    'environmentWire','effectSelectors','close']) {
    if (!Object.hasOwn(fields[key] ?? {}, 'value') || fields[key].value !== original[key]) return undefined;
  }
  return original;
}

export function retainInstalledRowEffectAdapter(original, projection) {
  const owner = rowInstallations.get(original);
  if (owner === undefined) return projection;
  if (projection.prepareManagedPlan !== original.prepareManagedPlan ||
      projection.prepareCaptured !== original.prepareCaptured ||
      projection.prepareRecovered !== original.prepareRecovered ||
      projection.environmentWire !== original.environmentWire ||
      projection.effectSelectors !== original.effectSelectors) {
    fail('ForeignInstalledEffectOccurrence');
  }
  rowInstallations.set(projection, owner);
  return projection;
}

function createRowEffectStage(owners, environmentWire, routes, retainedLimits) {
  // Common runtime, Ledger location and limits were independently compared for
  // every retained owner before a composed stage can be constructed.
  const {moon, ledgerRoot} = owners[0];
  const limits = retainedLimits ?? owners[0].limits;
  const singular = routes === undefined ? owners[0] : undefined;
  const assertPrepared = ({moon: runMoon, compilation}) => {
    if (singular !== undefined) return;
    if (runMoon !== moon || compilation === undefined) fail('InstalledEffectSetOwnerMismatch');
    const program = JSON.parse(moon.clientProgramEffectCompilationPlanWire(compilation))
      .execution_material?.program;
    const stage = program?.stages?.[0];
    // An explicit implementation profile, not a language restriction. Imported
    // sources, Model calls and guarded/command operations keep their refusal.
    if (program?.stages?.length !== 1 || stage === undefined ||
        Object.keys(stage.inputs ?? {}).length !== 0 ||
        !Array.isArray(stage.steps) || stage.steps.length === 0 ||
        stage.steps.some(step => !Object.hasOwn(step, 'values'))) {
      fail('InstalledEffectSetOwnerMismatch');
    }
  };
  const ownerOf = member => {
    const owner = memberInstallations.get(member);
    if (owner === undefined || !owners.includes(owner)) fail('ForeignInstalledEffectOccurrence');
    return owner;
  };
  const retainMember = (owner, member) => {
    const retained = Object.freeze(member);
    memberInstallations.set(retained, owner);
    return retained;
  };
  const runResources = new WeakMap();
  const bindRunResources = (facts, members) => {
    const originals = new Map();
    for (const member of members) {
      const owner = ownerOf(member);
      if (owner.resources === undefined) continue;
      if (!originals.has(owner)) {
        const original = requireSynchronousEffectResource(owner.resources.bindRunOriginal(facts));
        if (original === null || typeof original !== 'object') {
          fail('InstalledEffectResourcesUnavailable');
        }
        originals.set(owner, original);
      }
      runResources.set(member, originals.get(owner));
    }
  };
  const resourceFields = member => {
    if (ownerOf(member).resources === undefined) return {};
    const runOriginal = runResources.get(member);
    if (runOriginal === undefined) fail('InstalledEffectResourcesUnavailable');
    return {runOriginal};
  };
  const selectionFence = (facts, members, stageIndex, updateTargetSelections) => {
    const selections = validateOwnerSelections(owners, updateTargetSelections, facts.prepared);
    const resourceOwners = [...new Map(members.flatMap(member => {
      const owner = ownerOf(member);
      return owner.resources === undefined ? [] : [[owner, resourceFields(member).runOriginal]];
    })).entries()];
    const liveAssertion = selections === undefined
      ? facts.assertContinuationCurrent : facts.assertUpdateSelectionCurrent;
    if (selections === undefined && resourceOwners.length === 0 && liveAssertion === undefined) return undefined;
    if (selections !== undefined && typeof liveAssertion !== 'function') selectionChanged();
    const selectedMembers = members.flatMap(member => {
      const stage = member.stageIndex ?? stageIndex;
      if (member.kind === 'update' || member.kind === 'delete') {
        return [{stage_index: stage, effect_id: member.effectId,
          target_ref: member.mapping.target, mapping_ref: member.mapping.mappingRef,
          mapping_cid: member.mapping.mappingCid}];
      }
      const selected = selections?.filter(value => value.stage_index === stage &&
        value.effect_id === member.effectId) ?? [];
      if (selected.length === 0) return [];
      // STORE remains a checked Command occurrence with its original Mapping
      // selection. Bind both to this same installed owner; a generic Command
      // or a matching selection tuple alone cannot supply STORE purpose.
      if (selected.length !== 1 || member.kind !== 'command') selectionChanged();
      const mappings = ownerOf(member).storeMappings.filter(mapping =>
        mapping.target === selected[0].target_ref &&
        mapping.mappingRef === selected[0].mapping_ref &&
        mapping.mappingCid === selected[0].mapping_cid &&
        mapping.storeCommand.command_ref === member.command.commandRef &&
        mapping.storeCommand.command_contract_cid === member.command.commandCid);
      if (mappings.length !== 1) selectionChanged();
      return [{stage_index: stage, effect_id: member.effectId,
        target_ref: mappings[0].target, mapping_ref: mappings[0].mappingRef,
        mapping_cid: mappings[0].mappingCid}];
    });
    const assertCurrent = () => {
      for (const [owner, original] of resourceOwners) {
        if (requireSynchronousEffectResource(owner.resources.assertCurrent(original)) !== undefined) {
          fail('InstalledEffectResourcesUnavailable');
        }
      }
      if (selections !== undefined) {
        validateOwnerSelections(owners, selections, facts.prepared);
        try {
          assertUpdateTargetSelectionMembersCurrent(selections, selectedMembers, facts.prepared);
        } catch (cause) { selectionChanged(cause); }
      }
      if (liveAssertion === undefined) return;
      const result = Reflect.apply(liveAssertion, facts, []);
      // A live-owner assertion must finish before the physical operation.
      if (typeof result?.then === 'function') {
        void Promise.resolve(result).catch(() => {});
        selectionChanged();
      }
    };
    assertCurrent();
    return assertCurrent;
  };
  const selectOwner = descriptor => {
    if (singular !== undefined) return singular;
    const route = routes.find(value => value.descriptor.effectId === runtimeField(descriptor, 1));
    const expected = route?.descriptor;
    if (expected === undefined || expected.kind !== runtimeField(descriptor, 2) ||
        expected.target !== runtimeField(descriptor, 3) || expected.mappingRef !== runtimeField(descriptor, 4) ||
        expected.mappingCid !== runtimeField(descriptor, 5)) fail('InstalledEffectProgramMismatch');
    return route.owner;
  };
  const effect = runtimeCore(moon).effectApplicationControl;
  const openLedger = (identity, controlConstruction) => {
    const options = {moon, root: ledgerRoot,
      authorityScopeCid: moon.clientRequestAuthorityScopeCid(identity),
      callerRequestId: moon.clientRequestCallerId(identity),
      maxEntryBytes: effectLedgerImplementationBounds.maxEntryBytes,
      ...(controlConstruction === undefined ? {} : {controlConstruction})};
    return controlConstruction === undefined ? openEffectLedger(options)
      : controlConstruction(undefined, openEffectLedger, [options]);
  };
  const scopes = members => Object.freeze(members.map(member =>
    Object.freeze({connection: ownerOf(member).connection, resource: member.resource})));
  const permissionsOf = member => {
    if (member.kind === 'command') return [...member.command.permissions];
    const rule = member.mapping.rules.find(item =>
      item.effect_kind === member.kind);
    if (!Array.isArray(rule?.permissions)) {
      fail('InstalledRowEffectMappingNotInstalled');
    }
    return [...rule.permissions];
  };

  // One member of the Effect Unit: its Program descriptor, the installed
  // Mapping the Program resolved and the kind that Mapping was checked for.
  // Refused before any I/O when the Mapping is not installed or its kind is
  // not one this driver writes.
  const resolveMember = (prepared, {stageIndex, effectId}) => {
    const descriptor = checked(moon.clientProgramEffectMemberDescriptor(
      prepared, stageIndex, effectId, limits.planWork));
    const owner = selectOwner(descriptor);
    const {installed, installedCommands, owned} = owner;
    if (runtimeField(descriptor, 2) === 'command') {
      const command = installedCommands.find(candidate =>
        candidate.commandCid === runtimeField(descriptor, 5) &&
        candidate.commandRef === runtimeField(descriptor, 4) && candidate.target === runtimeField(descriptor, 3));
      if (command === undefined || !owned.kinds.includes('command') ||
          runtimeField(descriptor, 6) === undefined) fail('InstalledRowEffectCommandNotInstalled');
      return retainMember(owner, {stageIndex, effectId: runtimeField(descriptor, 1),
        memberIndex: runtimeField(descriptor, 0), kind: 'command', command,
        resource: command.resource});
    }
    const mapping = installed.find(candidate =>
      candidate.mappingCid === runtimeField(descriptor, 5) &&
      candidate.mappingRef === runtimeField(descriptor, 4));
    if (mapping === undefined || !owned.kinds.includes(runtimeField(descriptor, 2)) ||
        runtimeField(descriptor, 6) === undefined) {
      fail('InstalledRowEffectMappingNotInstalled');
    }
    const member = retainMember(owner, {stageIndex, effectId: runtimeField(descriptor, 1),
      memberIndex: runtimeField(descriptor, 0), kind: runtimeField(descriptor, 2), mapping,
      resource: mapping.resource});
    permissionsOf(member);
    return member;
  };
  const membersOf = (prepared, unit) => {
    const effectIds = unit.effectIds;
    if (effectIds.length > limits.maxMembers ||
        new Set(effectIds).size !== effectIds.length) {
      fail('InstalledRowEffectUnitUnsupported');
    }
    const members = effectIds.map(effectId => resolveMember(prepared,
      {stageIndex: unit.stageIndex, effectId}));
    members.sort((a, b) => a.memberIndex - b.memberIndex);
    if (members.some((member, index) => member.memberIndex !== index)) {
      fail('InstalledRowEffectUnitUnsupported');
    }
    return Object.freeze(members);
  };
  const prepareManagedPlan = (facts, inputs) => {
    assertPrepared({moon, prepared: facts?.prepared, compilation: facts?.compilation});
    const unit = installedRowEffectUnit(moon, facts.compilation);
    const members = membersOf(facts.prepared, unit);
    return prepareInstalledEffectManagedPlan({moon, facts, inputs, unit, members,
      recipeFor: member => ownerOf(member).managedPlanRecipe});
  };

  const memberDispatch = (runInvocationCid, member) => cid({
    version: ownerOf(member).profile.dispatch, run_invocation_cid: runInvocationCid,
    effect_id: member.effectId});
  const recoveryCid = (member, dispatch) => cid({version: ownerOf(member).profile.recovery,
    dispatch_request_cid: dispatch});

  // One row's request with the facts the common owner holds it to: the
  // value it writes and, for an update, the target it selects.
  const entryOf = (member, request, requestCid) => {
    const {owned} = ownerOf(member);
    const facts = owned.requestFacts(request);
    if (!request || !cidPattern.test(requestCid ?? '') ||
        facts === null || typeof facts !== 'object' ||
        (member.kind === 'delete' ? facts.value !== undefined :
          facts.value === null || typeof facts.value !== 'object') ||
        targeted(member.kind) === (facts.target === undefined)) {
      fail('InvalidInstalledRowEffectRequest');
    }
    return Object.freeze({request, requestCid, value: facts.value,
      target: facts.target});
  };

  // The exact request of every row of a member, from its mapped values and
  // selectors. A request that writes another value, or selects another
  // target, than the Program's row is refused.
  const requestEntry = (member, row, prepared) => {
    const entry = entryOf(member, prepared?.request, prepared?.requestCid);
    if (!sameEffectValue(member.kind, entry.value, row.value) ||
        (targeted(member.kind) && !sameValue(entry.target, row.selector))) {
      fail('ForeignInstalledRowEffectRequest');
    }
    return entry;
  };
  const requestsOf = (member, rows, current, contentOf, createRows) => Object.freeze(rows.map((row, index) => {
    const {owned} = ownerOf(member);
    return requestEntry(member, row, owned.prepareRequest({member, value: row.value,
      selector: row.selector, current, ...resourceFields(member),
      ...(member.kind === 'create' ? {createRowIdentity: createRows[index].identity,
        ...(row.proposalWire === undefined ? {} : {proposalWire: row.proposalWire})} : {}),
      ...(contentOf === undefined ? {} : {content: commandContentRow(contentOf, index)})}));
  }));

  // The common sealed capability of an installation whose driver issues
  // none: its runtime, connection and Mapping, and the exact requests.
  const commonCapability = (member, entries) => {
    const {connectorRegistration, connectorRevision, runtimeBundleCid, bindingCid, connection, owned} = ownerOf(member);
    return Object.freeze({
    identity: cid({
      version: CAPABILITY_VERSION,
      connector_registration: connectorRegistration,
      connector_revision: connectorRevision,
      runtime_bundle_cid: runtimeBundleCid, binding_cid: bindingCid,
      connection, resource: member.resource,
      ...(member.kind === 'command'
        ? {command_cid: contractCidOf(member)} : {mapping_cid: contractCidOf(member)}),
      operation: owned.writeOperation(member),
      route: 'single_serial', idempotency: 'unavailable',
      request_cids: entries.map(entry => entry.requestCid)}),
    route: 'single_serial'});
  };

  // Admit a member's capability. A provider-issued capability (its formal
  // issuer having checked its own evidence) is admitted only when its
  // binding names this installation's registration, revision and the
  // runtime the Host itself runs, and its route is the one this factory
  // drives: one serial row per request, no provider idempotency, an
  // uncertain send reconciled. The admission does not establish the
  // provider evidence's authenticity, and nothing it binds is claimed to be
  // inside the provider's identity.
  const admitCapability = (member, entries, current, runInvocationCid,
    dispatchRequestCid) => {
    const {owned, connectorRegistration, connectorRevision, runtimeBundleCid} = ownerOf(member);
    if (owned.issueCapability === undefined) {
      return commonCapability(member, entries);
    }
    const issued = owned.issueCapability({member, entries, current,
      runInvocationCid, dispatchRequestCid});
    const binding = issued?.binding;
    if (!cidPattern.test(issued?.identity ?? '') ||
        issued.route !== 'single_serial' ||
        binding === null || typeof binding !== 'object' ||
        binding.connector_registration !== connectorRegistration ||
        binding.connector_revision !== connectorRevision ||
        binding.runtime_bundle_cid !== runtimeBundleCid) {
      fail('InstalledRowEffectCapabilityNotAdmitted');
    }
    return Object.freeze({identity: issued.identity, route: issued.route});
  };
  const routeOf = capability => checked(
    moon.clientProgramEffectApplyCapabilityFromCodes(capability.identity, 0,
      0, 0, true, true, 2, 1));

  // A current read decision of `resource` for `subjectCid`; a held or denied
  // read reads nothing.
  const readDecision = async (member, resource, subjectCid, signal, assertCurrent) => {
    const {authorization, connection} = ownerOf(member);
    assertCurrent?.();
    const decision = await authorization.authorize('acquisition', {
      connection, resource, operation: 'read'}, {subjectCid, signal});
    assertCurrent?.();
    if (decision?.action !== 'dispatch') {
      throw Object.assign(new Error('InstalledRowEffectCheckNotAuthorized'),
        {code: 'InstalledRowEffectCheckNotAuthorized',
          action: decision?.action});
    }
    return decision;
  };
  const checkSubject = (runInvocationCid, member) => cid({
    version: ownerOf(member).profile.targetCheck, run_invocation_cid: runInvocationCid,
    effect_id: member.effectId});

  // This is the same capture retainer and original Run/Plan, including its
  // failed child prefix. The implementation recipe selects a DISTINCT native
  // occurrence for each phase; equal operation names do not share a slot.
  const prepareCredentialOperation = async ({member, rowIndex, phase, operation,
    site, originalAuthorization, useId, resource, purpose, invoke,
    managedEffect, requestChildren, retireRequestAliases, runInvocationCid,
    dispatchRequestCid, assertCurrent, signal}) => {
    const recipe = ownerOf(member).managedPlanRecipe;
    const selected = recipe?.credentialOperations?.find(entry => entry.phase === phase);
    if (selected === undefined || recipe.rowOperations[selected.operationIndex].operation !== operation ||
        managedEffect?.runtime !== moon || !Array.isArray(requestChildren) ||
        typeof retireRequestAliases !== 'function' || typeof assertCurrent !== 'function') {
      fail('InstalledEffectPhysicalPlanUnavailable');
    }
    const readChildren = moon.clientProgramInstalledEffectManagedPlanCaptureChildren;
    if (typeof readChildren !== 'function') fail('InstalledEffectOperationRuntimeUnavailable');
    const maxChildren = Reflect.apply(readChildren, moon, [managedEffect.operationPlan]);
    if (!Number.isSafeInteger(maxChildren) || maxChildren < 1 || requestChildren.length >= maxChildren) {
      fail('InstalledEffectPhysicalChildLimit');
    }
    // Lookup recognizes only the original credential returned by this Site.
    // Its issuer receives the untouched authorization, never the useId copy.
    const originalSite = installedRowCredentialOperationSite(site.credential);
    return prepareInstalledRowCaptureChild({children: requestChildren,
      create: () => prepareInstalledEffectCredentialChild({run: managedEffect,
        memberIndex: member.memberIndex, rowIndex,
        operationIndex: selected.operationIndex, operation, originalSite,
        originalAuthorization, useId, resource, purpose, runInvocationCid, dispatchRequestCid,
        maxRequestBytes: selected.maxRequestBytes, maxResponseBytes: selected.maxResponseBytes,
        assertCurrent, observeCurrent: async () => {assertCurrent();},
        requestsRetired: retireRequestAliases, invoke}), assertCurrent, signal});
  };

  // Every create row's provider check, under a current read decision.
  const checkRows = async ({members, entries, runInvocationCid, dispatches,
    subjectOf, signal, assertCurrent, physicalOperations, controlConstruction, operationPhase = 'capture'}) => {
    assertCurrent?.();
    for (const [index, member] of members.entries()) {
      const {owned, site, managedPlanRecipe} = ownerOf(member);
      if (member.kind !== 'create' || owned.check === undefined) continue;
      if (managedPlanRecipe?.credentialOperations !== undefined && typeof physicalOperations !== 'function') {
        fail('InstalledEffectPhysicalPlanUnavailable');
      }
      const subjectCid = subjectOf(member);
      const decision = await readDecision(member, owned.check.resource, subjectCid,
        signal, assertCurrent);
      for (const [rowIndex, entry] of entries[index].entries()) {
        signal?.throwIfAborted();
        assertCurrent?.();
        const grantFacts = {operation: owned.check.operation,
          decision, resource: owned.check.resource, runInvocationCid,
          dispatchRequestCid: dispatches[index], maxUses: 1};
        const grant = controlConstruction === undefined ? site.issueReadGrant(grantFacts)
          : controlConstruction(site, site.issueReadGrant, [grantFacts]);
        const useId = `${dispatches[index]}-check-${subjectCid}-${rowIndex}`;
        if (managedPlanRecipe?.credentialOperations !== undefined) {
          await physicalOperations({member, rowIndex, phase: `${operationPhase}-check`,
            operation: owned.check.operation, site, originalAuthorization: grant, useId,
            resource: owned.check.resource, purpose: 'read',
            runInvocationCid, dispatchRequestCid: dispatches[index], assertCurrent, signal,
            invoke: ({authorization, credential, callResource}) =>
              owned.checkRequest({member, request: entry.request, authorization, credential, callResource, signal, controlConstruction})});
        } else {
          await owned.checkRequest({member, request: entry.request,
            authorization: {...grant, useId},
            credential: site.credential, callResource: site.callResource, signal, controlConstruction});
        }
        assertCurrent?.();
      }
    }
  };

  // A current read decision of an update member's targets for `subjectCid`:
  // on the installation's gate, or through the Host's resumed target-read
  // Checkpoint (`targetReads`), whose approval the driver admits for exactly
  // this member. A held or denied read reads nothing.
  const decideTargetRead = async ({member, runInvocationCid,
    dispatchRequestCid, subjectCid, signal, targetReads, assertCurrent, controlConstruction}) => {
    const {connection, authorization, owned, site} = ownerOf(member);
    const tuple = {connection, resource: member.resource, operation: 'read'};
    assertCurrent?.();
    const decision = targetReads === undefined
      ? await authorization.authorize('acquisition', tuple, {subjectCid, signal})
      : await targetReads.authorize(tuple, {subjectCid, signal});
    assertCurrent?.();
    if (decision?.action !== 'dispatch') {
      throw Object.assign(new Error('InstalledRowEffectCheckNotAuthorized'),
        {code: 'InstalledRowEffectCheckNotAuthorized',
          action: decision?.action});
    }
    let approval;
    if (targetReads !== undefined) {
      if (typeof owned.admitTargetReadApproval !== 'function') {
        fail('InstalledRowEffectTargetReadApprovalNotAdmitted');
      }
      approval = owned.admitTargetReadApproval({member, decision});
    }
    let use = 0;
    return Object.freeze({approval,
      authorizationForRow: async rowIndex => {
        assertCurrent?.();
        const grantFacts = {operation: owned.targetRead.operation, decision: approval ?? decision,
          resource: member.resource, runInvocationCid, dispatchRequestCid, maxUses: 1};
        const grant = controlConstruction === undefined ? site.issueReadGrant(grantFacts)
          : controlConstruction(site, site.issueReadGrant, [grantFacts]);
        return {...grant, useId: `${dispatchRequestCid}-check-${subjectCid}-${rowIndex}-${use++}`};
      }});
  };

  // The observed target of every update row under its read decision. Each
  // observation must be of exactly the target the row's request selects.
  const observeRows = async ({member, entries, current, read, signal, assertCurrent}) => {
    const {owned} = ownerOf(member);
    assertCurrent?.();
    const observed = await owned.observeTargets({member, entries, current,
      authorizationForRow: read.authorizationForRow, signal, ...resourceFields(member)});
    assertCurrent?.();
    if (!Array.isArray(observed) || observed.length !== entries.length) {
      fail('ForeignInstalledRowEffectObservation');
    }
    return Object.freeze(observed.map((row, index) => {
      const {identity, state, versionCid, before} = row ?? {};
      if (!sameValue(identity, entries[index].target)) fail('ForeignInstalledRowEffectObservation');
      if (state === 'absent') {
        if (member.kind !== 'upsert' || versionCid !== undefined || before !== undefined) {
          fail('ForeignInstalledRowEffectObservation');
        }
        return Object.freeze({identity, state: 'absent'});
      }
      if ((state !== undefined && state !== 'present') || !cidPattern.test(versionCid ?? '') ||
          before === null || typeof before !== 'object') fail('ForeignInstalledRowEffectObservation');
      return Object.freeze({identity, state: 'present', versionCid, before});
    }));
  };

  const scopeKey = member => JSON.stringify([ownerOf(member).connection, member.resource]);
  // A resource name alone cannot identify a decision across installations.
  const commitDecisions = (decisions, subjectCid, members) => {
    const byScope = new Map();
    const required = new Set(members.map(scopeKey));
    for (const decision of decisions ?? []) {
      const tuple = decision?.tuple;
      const key = JSON.stringify([tuple?.connection ?? null, tuple?.resource ?? null]);
      if (decision?.action !== 'dispatch' || decision.boundary !== 'effect_commit' ||
          decision.subjectCid !== subjectCid || tuple?.operation !== 'effect' ||
          !required.has(key) || byScope.has(key)) fail('InstalledRowEffectCommitNotAuthorized');
      byScope.set(key, decision);
    }
    for (const key of required) if (!byScope.has(key)) fail('InstalledRowEffectCommitNotAuthorized');
    return byScope;
  };

  // Settle one row from a typed provider outcome. Anything else leaves the
  // row's possible dispatch unknown; it is never resent.
  const settle = ({ledger, claim, applyPreview, memberIndex, rowIndex,
    projected}) => {
    if (projected?.kind !== 'typed-success-response' &&
        projected?.kind !== 'typed-failure-response') return undefined;
    const outcome = projected.outcome;
    if (!['applied', 'failed'].includes(outcome?.state)) {
      fail('InvalidInstalledRowEffectOutcome');
    }
    const recorded = ledger.recordAdmittedRowOutcome({claim,
      preview: applyPreview, memberIndex, previewRowIndex: rowIndex,
      outcomeWire: canonicalValueJson(outcome, {dataKeys: true})});
    const terminal = ledger.commitAdmittedRowOutcome({claim,
      preview: applyPreview, memberIndex, previewRowIndex: rowIndex});
    return Object.freeze({outcomeReceipt: recorded.receipt,
      terminal: terminal.transition});
  };

  // A Mapping that requires approval is written only under a commit the Host
  // resumed from a resolved Checkpoint of this sealed Set; an account allow
  // alone is not an approval. Decided from the commit decision before the
  // row's claim, so the Set's prepared intents show nothing was sent.
  const requireApproval = (member, decision) => {
    if (member.kind !== 'command' && approvalOf(member) === 'required' &&
        (decision?.basis !== 'resumed' || !text(decision.checkpointCid) ||
          !text(decision.resolutionCid))) {
      throw refusedEffectPreparation(Object.assign(
        new Error('InstalledRowEffectApprovalRequired'),
        {code: 'InstalledRowEffectApprovalRequired'}));
    }
  };

  // Bind a row's request to its admitted Preview row: the request must write
  // exactly the approved value to exactly the approved target, under its
  // claim.
  const admitRow = ({applyPreview, memberIndex, rowIndex, claim, member,
    entry, previewRow}) => {
    if (claim.canonicalRequestCid !== entry.requestCid ||
        !sameEffectValue(member.kind, entry.value, approvedValue(member.kind, previewRow)) ||
        (targeted(member.kind) &&
          !sameValue(entry.target, previewRow.target_row_identity))) {
      fail('ForeignInstalledRowEffectRequest');
    }
    const rowPreviewCid = moon.strategyEffectPreviewOrderedRowCid(
      applyPreview, memberIndex, rowIndex);
    if (typeof rowPreviewCid !== 'string') {
      fail('InvalidInstalledRowEffectDispatch');
    }
    const ownedClaim = snapshotEffectDispatchClaim(claim);
    effect.admitMemberRow(applyPreview, memberIndex, rowIndex, member.kind,
      ownedClaim.scope, rowPreviewCid, ownedClaim.locator, ownedClaim.key);
    return ownedClaim;
  };

  // Current use and physical dispatch over one set of members. `entries`
  // and `previewRows` are each member's rows in the approved Preview's order.
  const physicalRoute = ({members, entries, previewRows, runInvocationCid,
    dispatches, subjectCid, applyPreview, ledger, targetReads, assertCurrent,
    dispatchIndexes, physicalOperations, controlConstruction, operationPhase = 'apply'}) => {
    // A saved route cannot borrow the fresh capture's parent merely from its
    // recipe or CID. The recovery owner must supply its actual retainer first.
    if (typeof physicalOperations !== 'function' && members.some(member =>
      ownerOf(member).managedPlanRecipe?.credentialOperations !== undefined)) {
      fail('InstalledEffectPhysicalPlanUnavailable');
    }
    // Once the durable claim exists, selection drift does not establish an
    // unsent outcome. Preserve the claim and any retained response for recovery.
    const assertClaimedCurrent = () => {
      try { assertCurrent?.(); }
      catch (error) { fail('InstalledRowEffectSelectionChangedAfterClaim', error); }
    };
    // Every apply carries its exact returned refresh into dispatch. A later
    // refresh may finish before this one is sent; equal capability DATA does
    // not substitute that later Catalog for this original current observation.
    let currentsByPreflight = new WeakMap();
    let hasRefreshed = false, closing = false, active = 0;
    const requireOpen = () => { if (closing) fail('InstalledRowEffectRouteRetired'); };
    const retire = () => {
      closing = true;
      if (active !== 0) return false;
      // SAME route/closure inventory. A fulfilled prepare did not sever these
      // aliases, and an active refresh/send still owns its original locals.
      currentsByPreflight = new WeakMap();
      entries = undefined;
      previewRows = undefined;
      return true;
    };
    const current = async ({signal, preflight}) => {
      requireOpen();
      active++;
      try {
        assertCurrent?.();
        if (preflight === null || typeof preflight !== 'object') {
          fail('InvalidInstalledRowEffectRoute');
        }
        for (const member of members) {
          const {installed, installedCommands} = ownerOf(member);
          const available = member.kind === 'command'
            ? installedCommands.includes(member.command) : installed.includes(member.mapping);
          if (!available) {
            fail('InstalledRowEffectMappingNotInstalled');
          }
        }
        // Every read is decided before this refresh's provider I/O.
        const reads = [];
        for (const [index, member] of members.entries()) {
          reads.push(!guarded(member.kind) ? undefined :
            await decideTargetRead({member, runInvocationCid,
              dispatchRequestCid: dispatches[index], subjectCid, signal,
              targetReads, assertCurrent, controlConstruction}));
          assertCurrent?.();
        }
        const fresh = [];
        for (const [index, member] of members.entries()) {
          const {owned} = ownerOf(member);
          assertCurrent?.();
          const description = owned.describe === undefined ? undefined :
            await owned.describe({member, runInvocationCid,
              dispatchRequestCid: dispatches[index], label: `apply-${index}`,
              approval: reads[index]?.approval, signal, ...resourceFields(member)});
          assertCurrent?.();
          await owned.recheckRequests?.({member, entries: entries[index],
            current: description, ...resourceFields(member)});
          assertCurrent?.();
          fresh.push(description);
        }
        await checkRows({members, entries, runInvocationCid, dispatches,
          subjectOf: () => subjectCid, signal, assertCurrent, physicalOperations, controlConstruction, operationPhase});
        assertCurrent?.();
        const currentVersions = new Map();
        for (const [index, member] of members.entries()) {
          if (!guarded(member.kind)) continue;
          const observed = await observeRows({member, entries: entries[index],
            current: fresh[index], read: reads[index], signal, assertCurrent});
          assertCurrent?.();
          for (const [rowIndex, row] of observed.entries()) {
            const original = previewRows[index][rowIndex];
            if ((row.state === 'absent') !== (original.before.state === 'absent')) {
              // A fresh read cannot switch a sealed creation into an update, or
              // a sealed update into creation. Nothing has been claimed/sent.
              fail('InstalledRowEffectTargetPresenceChanged');
            }
            if (row.state !== 'absent') currentVersions.set(original.row_preview_cid, row.versionCid);
          }
        }
        const capabilities = members.map((member, index) => admitCapability(
          member, entries[index], fresh[index], runInvocationCid,
          dispatches[index]));
        signal?.throwIfAborted();
        assertCurrent?.();
        if (currentVersions.size !== preflight.observedRows.length) fail('ForeignInstalledRowEffectObservation');
        const refreshed = Object.freeze({...preflight,
          guardVersions: Object.freeze(preflight.observedRows.map(row => {
            if (!currentVersions.has(row)) fail('ForeignInstalledRowEffectObservation');
            return currentVersions.get(row);
          })),
          capabilities: Object.freeze(capabilities.map(value => value.identity)),
          routes: Object.freeze(capabilities.map(routeOf))});
        currentsByPreflight.set(refreshed, Object.freeze(fresh));
        hasRefreshed = true;
        return refreshed;
      } finally { active--; }
    };
    const bindDispatch = ({members: claims, subjectCid: activeSubject, signal,
      decisions}) => {
      requireOpen();
      assertCurrent?.();
      if (activeSubject !== subjectCid || !hasRefreshed) {
        fail('InvalidInstalledRowEffectRoute');
      }
      const commits = commitDecisions(decisions, subjectCid, members);
      return async ({memberIndex, rowIndex, claim, currentPreflight}) => {
        requireOpen();
        active++;
        try {
          assertCurrent?.();
          const now = currentsByPreflight.get(currentPreflight);
          if (now === undefined) fail('InvalidInstalledRowEffectRoute');
          const member = members[memberIndex];
          const sourceIndex = dispatchIndexes[memberIndex]?.[rowIndex];
          const entry = entries[memberIndex]?.[sourceIndex];
          const expected = claims[memberIndex]?.claims[rowIndex];
          if (member === undefined || entry === undefined || !claim ||
              !expected || ['scope', 'locator', 'key', 'basis',
                'intentFingerprintCid', 'canonicalRequestCid'].some(field =>
                expected[field] === undefined ||
                expected[field] !== claim[field])) {
            fail('InvalidInstalledRowEffectDispatch');
          }
          const {owned, site, managedPlanRecipe, beforeSendCheck} = ownerOf(member);
          signal?.throwIfAborted();
          requireApproval(member, commits.get(scopeKey(member)));
          const ownedClaim = admitRow({applyPreview, memberIndex, rowIndex,
            claim, member, entry,
            previewRow: previewRows[memberIndex][sourceIndex]});
          await owned.recheckRequests?.({member, entries: [entry],
            current: now[memberIndex], ...resourceFields(member)});
          assertCurrent?.();
          const grantFacts = {operation: owned.writeOperation(member),
            decision: commits.get(scopeKey(member)), resource: member.resource,
            runInvocationCid, dispatchRequestCid: dispatches[memberIndex], subjectCid};
          const grant = controlConstruction === undefined ? site.issueEffectGrant(grantFacts)
            : controlConstruction(site, site.issueEffectGrant, [grantFacts]);
          const captured = await captureClaimedEffectResponse({ledger,
            claim: ownedClaim, requestCid: entry.requestCid,
            execute: () => {
              assertClaimedCurrent();
              const useId = `${dispatches[memberIndex]}-write-${subjectCid}-${rowIndex}`;
              if (managedPlanRecipe?.credentialOperations !== undefined) {
                if (typeof physicalOperations !== 'function') fail('InstalledEffectPhysicalPlanUnavailable');
                const send = () => physicalOperations({member, rowIndex: sourceIndex, phase: 'write',
                  operation: owned.writeOperation(member), site, originalAuthorization: grant, useId,
                  resource: member.resource, purpose: 'effect', runInvocationCid,
                  dispatchRequestCid: dispatches[memberIndex], assertCurrent: assertClaimedCurrent, signal,
                  invoke: ({authorization, credential, callResource}) =>
                    owned.send({member, request: entry.request, current: now[memberIndex],
                      authorization, credential, callResource, signal, ...resourceFields(member)})});
                if (beforeSendCheck === undefined) return send();
                return (async () => {
                  // The SAME durable dispatch already owns this possible send.
                  // A fresh acquisition decision is still required for Form
                  // access; effect commit cannot stand in for a read grant.
                  const decision = await readDecision(member, beforeSendCheck.resource,
                    subjectCid, signal, assertClaimedCurrent);
                  assertClaimedCurrent();
                  const checkGrantFacts = {operation: beforeSendCheck.operation,
                    decision, resource: beforeSendCheck.resource, runInvocationCid,
                    dispatchRequestCid: dispatches[memberIndex], maxUses: 1};
                  const originalAuthorization = controlConstruction === undefined ? site.issueReadGrant(checkGrantFacts)
                    : controlConstruction(site, site.issueReadGrant, [checkGrantFacts]);
                  await physicalOperations({member, rowIndex: sourceIndex, phase: 'write-check',
                    operation: beforeSendCheck.operation, site, originalAuthorization,
                    useId: `${dispatches[memberIndex]}-write-check-${subjectCid}-${rowIndex}`,
                    resource: beforeSendCheck.resource, purpose: 'read', runInvocationCid,
                    dispatchRequestCid: dispatches[memberIndex], assertCurrent: assertClaimedCurrent, signal,
                    invoke: context => Reflect.apply(beforeSendCheck.request, beforeSendCheck.receiver,
                      [{member, request: entry.request, ...context, signal, controlConstruction}])});
                  assertClaimedCurrent();
                  return send();
                })();
              }
              return owned.send({member, request: entry.request, current: now[memberIndex],
                authorization: {...grant, useId}, credential: site.credential,
                callResource: site.callResource, signal, ...resourceFields(member)});
            }});
          assertClaimedCurrent();
          if (!captured.claimed) {
            return Object.freeze({claimed: false,
              ownership: Object.freeze({action: captured.ownership.action})});
          }
          const projectionFacts = {member, memberIndex, rowIndex,
            preview: applyPreview, request: entry.request, current: now[memberIndex],
            observation: captured.physical.observation, headers: captured.physical.headers};
          const projected = controlConstruction === undefined ? owned.project(projectionFacts)
            : controlConstruction(owned, owned.project, [projectionFacts]);
          const settled = settle({ledger, claim: ownedClaim, applyPreview,
            memberIndex, rowIndex, projected});
          return Object.freeze({claimed: true, physical: projected,
            ...(settled ?? {})});
        } finally { active--; }
      };
    };
    return {current, bindDispatch, assertClaimedCurrent, retire};
  };

  const basePreflight = ({effects, members, requestScope, keys}) => ({
    sources: effects.map(member => member.source_binding_cid),
    contracts: members.map(contractCidOf),
    capabilities: effects.map(member => member.capability_evidence_cid),
    authorities: effects.map(() => moon.clientProgramEffectRequestAuthority(
      requestScope)),
    observedRows: effects.flatMap(member => {
      if (!guarded(member.effect_kind)) return [];
      const versioned = new Set(member.changes.filter(row => row.target_guard.state === 'version')
        .map(row => row.row_preview_cid));
      return member.row_order.filter(row => versioned.has(row));
    }),
    guardVersions: [], routes: [],
    risk: undefined, reviewProjectionCid: '', authorityScopeCid: '',
    policyCid: '', validityCid: '', issuerCid: '', authenticationCid: '',
    issuerKind: '', decision: '',
    requestScope, ...(keys === undefined ? {} : {keys}),
    maxMembers: members.length, maxRows: limits.maxRows,
    maxFootprintWork: limits.maxRows, maxWork: limits.maxWork,
  });

  const continuationOf = (plan, unit, members, dispatches, selected) => canonicalJson({
    ...(singular === undefined ? {version: ROUTING_VERSION} : {
      version: singular.profile.continuation,
      [singular.profile.continuationBinding]: singular.continuationBinding}),
    program_id: unit.programId, stage_id: unit.stageId,
    ...(selected ? {stage_index: unit.stageIndex} : {}),
    request: plan.request, attempt: plan.attempt,
    members: members.map((member, index) => ({
      effect_id: member.effectId,
      ...(member.kind === 'command'
        ? {command_cid: contractCidOf(member)} : {mapping_cid: contractCidOf(member)}),
      dispatch_request_cid: dispatches[index],
      ...(singular === undefined || selected
        ? {installation: installationFacts(ownerOf(member))} : {}),
    }))});

  // A member's write footprint: the provider's complete footprint, or the
  // opaque footprint of its boundary.
  const footprintOf = (member, entries) => {
    const {owned, connectorRegistration} = ownerOf(member);
    const footprint = owned.footprint({member, entries});
    if (footprint?.kind !== undefined) {
      if (!footprintKinds.includes(footprint.kind) ||
          !cidPattern.test(footprint.provider_boundary_cid ?? '') ||
          !text(footprint.provider_namespace) ||
          !text(footprint.resource_kind) ||
          !cidPattern.test(footprint.resource_identity_scheme_cid ?? '') ||
          !Array.isArray(footprint.provider_object_identity_cids)) {
        fail('InvalidInstalledRowEffectDriver');
      }
      return {...footprint};
    }
    if (!text(footprint?.providerNamespace) ||
        !text(footprint.resourceKind) ||
        !cidPattern.test(footprint.boundaryCid ?? '')) {
      fail('InvalidInstalledRowEffectDriver');
    }
    return {kind: 'opaque', provider_boundary_cid: footprint.boundaryCid,
      provider_namespace: footprint.providerNamespace,
      resource_kind: footprint.resourceKind,
      resource_identity_scheme_cid: cid({
        version: 'actql-installed-row-effect-identity-scheme/0.1',
        connector_registration: connectorRegistration,
        resource: member.resource,
        ...(member.kind === 'command'
          ? {command_cid: contractCidOf(member)}
          : {primary_identity: member.mapping.primaryIdentity})}),
      provider_object_identity_cids: []};
  };

  // The Preview of the Effect Unit: the common draft with each member's rows
  // (create rows already in canonical order) stated as their exact values,
  // and each update row's observed target, version and before value.
  function authorPreview({control, prepared, inputs, context, requestScope,
    members, rowsOf, capabilities, footprints, payloads}) {
    const {maxWireBytes, maxNodes, maxDepth} = limits.preview;
    const requestAuthority = moon.clientProgramEffectRequestAuthority(
      requestScope);
    const definitionCid = moon.clientProgramEffectDefinitionCid(prepared);
    const authoring = checked(moon.strategyRunEvidenceSeal(
      'authoring_context', JSON.stringify({
        version: 'actql-authoring-context/0.1',
        program_definition_cid: definitionCid, annotations: []}),
      maxWireBytes, maxNodes, maxDepth));
    const identities = [];
    let rowCount = 0;
    const effects = members.map((member, index) => {
      const descriptor = checked(moon.clientProgramEffectMemberDescriptor(
        prepared, member.stageIndex, member.effectId, limits.planWork));
      const source = control.effectSourceArtifactPreviewBinding(
        payloads[index].summary.artifact,
        moon.strategyPublicationContractIdentity(context.runInvocation),
        runtimeField(descriptor, 6), context.storeAuthorityCid);
      const identity = control.issueSourceFreeLocalEffectIdentity(
        prepared, inputs, runtimeField(descriptor, 0), payloads[index].localResultArtifact,
        {maxWork: limits.planWork, maxWireBytes, maxNodes, maxDepth});
      identities.push(identity);
      const rows = rowsOf[index];
      rowCount += rows.length;
      if (rowCount > limits.maxRows) fail('InstalledRowEffectRowLimit');
      const planCid = checked(moon.clientProgramEffectPlanCid(prepared,
        runtimeField(descriptor, 0), limits.maxFields, limits.planWork, maxWireBytes,
        maxNodes, maxDepth));
      return {
        effect_id: runtimeField(descriptor, 1), effect_kind: runtimeField(descriptor, 2),
        target: runtimeField(descriptor, 3),
        ...(member.kind === 'command'
          ? {contract: runtimeField(descriptor, 4), resolved_command_contract_cid: runtimeField(descriptor, 5)}
          : {mapping: runtimeField(descriptor, 4), resolved_mapping_contract_cid: runtimeField(descriptor, 5)}),
        effect_identity_cid: identity.identity,
        source_result: runtimeField(descriptor, 6),
        ...(planCid === undefined ? {} : {effect_plan_logical_cid: planCid}),
        // The identity names the checked semantic Result. Its physical
        // export is bound separately by the existing captured-source owner.
        result_artifact_cid: payloads[index].localResultArtifact.identity,
        preview_strength: 'full_diff',
        source_binding_cid: runtimeField(source, 1),
        capability_evidence_cid: capabilities[index].identity,
        authority_scope_cid: requestAuthority,
        write_footprint: footprints[index],
        count: rows.length, max_items: rows.length,
        required_permissions: permissionsOf(member),
        ...(member.kind === 'command' ? {} : {approval: approvalOf(member)}),
        on_item_failure: runtimeField(descriptor, 7),
        changes: rows.map(row => member.kind === 'create' ? {
          target_row_identity: row.identity,
          target_guard: {state: 'not_applicable'},
          before: {state: 'absent'},
          after: {state: 'present', value: row.entry.value},
          intended_changes: {state: 'present', value: row.entry.value},
          row_preview_cid: pendingCid, row_idempotency_key: pendingCid,
        } : member.kind === 'command' ? {
          target_row_identity: row.entry.target,
          target_guard: {state: 'not_applicable'},
          before: {state: 'not_applicable'}, after: {state: 'not_applicable'},
          intended_changes: {state: 'present', value: row.entry.value},
          row_preview_cid: pendingCid, row_idempotency_key: pendingCid,
        } : member.kind === 'delete' ? {
          target_row_identity: row.entry.target,
          target_guard: {state: 'version', version_cid: row.versionCid},
          before: {state: 'present', value: row.before},
          after: {state: 'absent'},
          intended_changes: {state: 'not_applicable'},
          row_preview_cid: pendingCid, row_idempotency_key: pendingCid,
        } : {
          target_row_identity: row.entry.target,
          target_guard: row.state === 'absent' ? {state: 'not_applicable'}
            : {state: 'version', version_cid: row.versionCid},
          before: row.state === 'absent' ? {state: 'absent'} : {state: 'present', value: row.before},
          after: {state: 'present', value: row.entry.value},
          intended_changes: {state: 'present', value: row.entry.value},
          row_preview_cid: pendingCid, row_idempotency_key: pendingCid,
        }),
        row_order: [], effect_member_preview_cid: pendingCid,
        executed: false,
      };
    });
    const draft = {
      version: 'actql-effect-preview/0.1', sensitivity: 'private',
      retention_class: 'authority-evidence', encryption_required: true,
      program_semantics_cid: moon.clientProgramEffectSemanticsCid(prepared),
      program_definition_cid: definitionCid,
      invocation_cid: moon.strategyPublicationContractIdentity(
        context.runInvocation),
      run_identity_cid: moon.strategyPublicationContractIdentity(
        context.runDefinition),
      compiled_plan_cid: moon.strategyPublicationContractIdentity(
        context.compiledPlan),
      check_environment_cid: moon.clientProgramEffectEnvironmentCid(prepared),
      authoring_context: JSON.parse(moon.strategyRunEvidenceJson(authoring)),
      barrier_provenance_cids: [], model_derived: false,
      model_task_contract_cids: [], model_invocation_evidence_cids: [],
      model_response_artifact_cids: [], effects, executed: false,
      effect_preview_cid: pendingCid,
    };
    const draftWire = JSON.stringify(draft);
    if (Buffer.byteLength(draftWire, 'utf8') > maxWireBytes) {
      fail('InstalledRowEffectPreviewByteLimit');
    }
    const canonical = checked(moon.clientProgramCanonicalEffectPreviewDraft(
      draftWire, maxWireBytes, maxNodes, maxDepth));
    const authoringCid = draft.authoring_context.authoring_context_cid;
    const authored = checked(moon.clientProgramAuthorEffectPreview(
      canonical, draft.run_identity_cid, authoringCid, requestScope,
      maxWireBytes, maxNodes, maxDepth, members.length, rowCount,
      limits.key.maxBytes, limits.key.maxNodes, limits.key.maxDepth));
    control.checkSourceFreeLocalEffectPreviewIdentities(prepared, inputs,
      runtimeField(authored, 0), draft.run_identity_cid, authoringCid, identities,
      {maxWireBytes, maxNodes, maxDepth});
    return Object.freeze({wire: runtimeField(authored, 0), authoringCid,
      keys: runtimeField(authored, 1)});
  }

  // Project original change positions from the Common-sealed dispatch order.
  // The Plan still verifies changes against the original source cursor; neither
  // source positions nor request/observation objects are rewritten to sort it.
  const orderedSourceIndexes = member => {
    const positions = new Map(member.changes.map((row, index) => [row.row_preview_cid, index]));
    if (positions.size !== member.changes.length || member.row_order.length !== positions.size ||
        new Set(member.row_order).size !== positions.size) fail('InstalledRowEffectPreviewOrderMismatch');
    return Object.freeze(member.row_order.map(row => {
      if (!positions.has(row)) fail('InstalledRowEffectPreviewOrderMismatch');
      return positions.get(row);
    }));
  };

  // The Ledger claims of every row in the admitted dispatch order.
  const claimsOf = ({body, keys, entries, requestScope, unit, dispatches,
    unitCids, members, retentionId}) => body.effects.map((member, memberIndex) => ({
    claims: orderedSourceIndexes(member).map(rowIndex => {
      const change = member.changes[rowIndex];
      const key = keys[memberIndex][rowIndex];
      const locator = effect.logicalItemLocator(requestScope,
        unit.programId, unit.stageId, member.effect_id,
        canonicalValueJson(change.target_row_identity), limits.locator.maxBytes,
        limits.key.maxBytes, limits.key.maxNodes, limits.key.maxDepth);
      const canonicalRequestCid = entries[memberIndex][rowIndex].requestCid;
      const basis = effect.ledgerBasis(requestScope, locator, key, unitCids[memberIndex],
        member.effect_member_preview_cid, change.row_preview_cid,
        canonicalRequestCid, recoveryCid(members[memberIndex], dispatches[memberIndex]),
        // A write without a provider idempotency key.
        'unavailable', member.capability_evidence_cid, retentionId);
      return {scope: requestScope, locator, key, basis,
        intentFingerprintCid: change.row_preview_cid, canonicalRequestCid};
    })}));

  async function captureStage({control, store, execution, checkedHost,
    prepared, identity, plan, previewContext, unit, members,
    runInvocationCid, dispatches, requestScope, storedResults, signal,
    targetReads, contentOwner, managedEffect, updateTargetSelections, own, ownInputs, ownChildren, assertCurrent}) {
    assertCurrent?.();
    const inputs = checked(moon.clientProgramPinEffectSources(checkedHost,
      limits.maxPinnedResults));
    const commandWorkspaces = [];
    const commandKeys = [];
    const contentBorrowers = [];
    const contentArtifacts = [];
    const requestChildren = [];
    const memberCaptures = new Array(members.length);
    const proposals = [], currents = [], rowsOf = [], observations = [];
    let sourceSet;
    const controlConstruction = managedEffect?.controlConstruction;
    if (managedEffect !== undefined && typeof controlConstruction !== 'function') fail('InstalledEffectControlRuntimeUnavailable');
    let entries, route, captureOpen = true;
    const retireRequestAliases = () => {
      if (captureOpen || (route !== undefined && !route.retire())) return false;
      entries = undefined;
      currents.length = 0;
      rowsOf.length = 0;
      observations.length = 0;
      proposals.length = 0;
      memberCaptures.length = 0;
      return true;
    };
    const physicalOperations = facts => {
      if (managedEffect?.runtime !== moon || managedEffect.prepared !== prepared ||
          managedEffect.request !== identity) fail('ForeignInstalledEffectManagedRun');
      return prepareCredentialOperation({...facts, managedEffect, requestChildren, retireRequestAliases});
    };
    ownChildren(requestChildren);
    const childrenPending = () => requestChildren.some(value =>
      typeof value?.prepared?.status !== 'function' ||
      value.prepared.status()?.pending !== false);
    const releaseInputPins = async () => {
      if (!retireRequestAliases()) fail('InstalledRowEffectRequestCleanupPending');
      for (const borrower of contentBorrowers) borrower.release();
      contentBorrowers.length = 0;
      let retired = true;
      for (const artifact of contentArtifacts) {
        // Scrub every original inventory, but do not return the parent pin
        // merely because one bounded cleanup quantum was exhausted.
        if (!control.releaseEffectCommandContentArtifact(artifact, limits.maxWork)) retired = false;
      }
      if (!retired) fail('InstalledRowEffectContentCleanupPending');
      contentArtifacts.length = 0;
      // The original parent retains phase/key aliases until request children,
      // content borrowers and artifacts have actually retired. Export finally
      // closes only the temporary import, never this byte borrower.
      for (const workspace of commandWorkspaces) {
        if (workspace === undefined) continue;
        await retireEffectCommandKeyWorkspace(() => checked(
          moon.clientProgramCloseEffectCommandKeyWorkspace(workspace)));
      }
      commandWorkspaces.length = 0;
      commandKeys.length = 0;
      moon.clientProgramReleaseEffectInputs(inputs);
    };
    const releaseInputs = async () => {
      if (!retireRequestAliases()) fail('InstalledRowEffectRequestCleanupPending');
      // Direct successful-route disposal still drains its original children
      // and Sources. Failure cleanup already owns that same inventory below;
      // its input-pin callback must not create a second nested cleanup pass.
      if (requestChildren.length) {
        const marker = Object.freeze(new Error('InstalledRowEffectRequestCleanup'));
        try { await releaseInstalledRowCapture({children: requestChildren,
          payloads: sourceSet?.payloads ?? [], control}, marker); }
        catch (error) { if (error !== marker) throw error; }
      }
      await releaseInputPins();
    };
    ownInputs(releaseInputPins, () => { captureOpen = false; });
    // Reserve each original member's capture body before export can append
    // proposal rows, parse their values or issue canonical CREATE inventory.
    // These SAME arrays and children survive through ordinary route retirement.
    for (const member of members) {
      const recipe = ownerOf(member).managedPlanRecipe;
      if (recipe === undefined) { proposals.push([]); continue; }
      if (managedEffect?.runtime !== moon || managedEffect.prepared !== prepared ||
          managedEffect.request !== identity) fail('ForeignInstalledEffectManagedRun');
      const selected = recipe.captureConstruction;
      if (selected === undefined) fail('InstalledEffectCaptureConstructionUnavailable');
      const operation = recipe.memberOperations[selected.operationIndex]?.operation;
      const {owned} = ownerOf(member);
      const recoveryEntry = owned.recoveryEntry;
      let original;
      const retained = retainInstalledRowCaptureChild({children: requestChildren,
        create: () => {
          original = prepareInstalledEffectRequestChild({run: managedEffect,
            memberIndex: member.memberIndex, perRow: false, rowIndex: 0,
            operationIndex: selected.operationIndex, operation,
            construct: () => recoveryEntry === undefined ? undefined :
              Reflect.apply(recoveryEntry, owned, [{member, current: currents[member.memberIndex],
                entries: entries[member.memberIndex]}]), requestsRetired: retireRequestAliases});
          return original;
        }, assertCurrent, signal});
      // Retain before this cheap original-record fence can fail. The actual
      // constructor is deferred; its original reservation already owns input.
      original.checkOriginal();
      proposals.push([]);
      memberCaptures[member.memberIndex] = retained;
    }
    let proposalCount = 0;
    const sourceLimits = moon.clientProgramEffectInputExportLimits(
      ...exportLimits(plan.outputLimits));
    if (typeof moon.clientProgramPlanEffectCommandKeyWorkspace === 'function') {
      for (let index = 0; index < members.length; index++) {
        // This is the original Local Effect Host, not the prepared computation
        // (`checkedOwner`) or a Host re-created from the same CID.
        commandWorkspaces.push(checked(moon.clientProgramPlanEffectCommandKeyWorkspace(
          checkedHost, inputs, index, sourceLimits, limits.maxWork)));
      }
    }
    let publishedTargets;
    if (typeof moon.clientProgramEffectPublishedStoreBinding === 'function') {
      let selected = false;
      const targets = members.map(member => {
        const pair = checked(moon.clientProgramEffectPublishedStoreBinding(
          inputs, member.memberIndex, limits.maxWork));
        if (pair === undefined) return undefined;
        const owner = ownerOf(member);
        if (member.kind !== 'command' ||
            typeof owner.issueOriginalCollectionReference !== 'function' ||
            typeof moon.clientProgramBindEffectCommandTarget !== 'function') {
          fail('InstalledEffectPublishedTargetUnavailable');
        }
        assertCurrent?.();
        const reference = owner.issueOriginalCollectionReference(pair, limits.maxWork);
        assertCurrent?.();
        const target = checked(moon.clientProgramBindEffectCommandTarget(
          inputs, member.memberIndex, pair, reference, limits.maxWork));
        selected = true;
        return target;
      });
      if (selected) publishedTargets = Object.freeze(targets);
    } else if (members.some(member =>
      typeof ownerOf(member).issueOriginalCollectionReference === 'function')) {
      fail('InstalledEffectPublishedTargetUnavailable');
    }
    sourceSet = await preparePinnedEffectSourceSet({moon,
      ...(commandWorkspaces.length ? {commandWorkspaces: Object.freeze([...commandWorkspaces])} : {}),
      ...(publishedTargets === undefined ? {} : {publishedTargets}),
      onCommandKey(memberIndex, key) { commandKeys[memberIndex] = key; },
      checkedOwner: prepared, execution, inputs,
      maxMembers: members.length,
      // Membership, distinct keyed/target groups and dependency imports share
      // the existing finite Host structural-work ceiling. Result/member counts
      // bound inventory size, not the work of its cross-product comparisons.
      maxGroupingWork: limits.maxWork,
      limits: sourceLimits,
      store, maxBytes: plan.outputLimits.maxWireBytes, control,
      invocation: plan.invocation, retention: plan.effectInputRetention,
      ...(singular === undefined ? {memberSourceBindings: Object.freeze(members.map((member, memberIndex) =>
        Object.freeze({memberIndex, sourceBindingCid: cid({version: ownerOf(member).profile.source,
          run_invocation_cid: runInvocationCid, store_authority_cid: store.storeAuthorityCid})})))} : {
        sourceBindingCid: cid({version: singular.profile.source,
          run_invocation_cid: runInvocationCid, store_authority_cid: store.storeAuthorityCid})}),
      contractLimits: plan.contractLimits,
      localEvidenceContext: plan.localEvidenceContext,
      proposalLimits: {maxFields: limits.maxFields, maxWork: limits.maxWork,
        maxBytes: limits.body.maxBytes, maxNodes: limits.body.maxNodes,
        maxDepth: limits.body.maxDepth,
        maxUtf16Units: limits.body.maxBytes},
      onOriginalArtifact(artifact, memberIndex) {
        if (members[memberIndex]?.kind !== 'command') return;
        if (!contentArtifacts.includes(artifact)) contentArtifacts.push(artifact);
        // Retain before a Common/source callback can fail after the move.
        control.prepareEffectCommandContentArtifact(prepared, inputs,
          memberIndex, artifact, limits);
      },
      onProposalRow(memberIndex, rowIndex, proposal) {
        if (rowIndex !== proposals[memberIndex]?.length ||
            rowIndex >= limits.maxRows || proposalCount >= limits.maxRows) {
          fail('InstalledRowEffectRowLimit');
        }
        proposalCount++;
        proposals[memberIndex].push(proposal);
      },
      signal});
    own(sourceSet);
    assertCurrent?.();
    // Reads of each update member's targets are decided before any provider
    // I/O: a held or denied read authors no Preview.
    const reads = [];
    for (const [index, member] of members.entries()) {
      reads.push(!guarded(member.kind) ? undefined :
        await decideTargetRead({member, runInvocationCid,
          dispatchRequestCid: dispatches[index],
          subjectCid: checkSubject(runInvocationCid, member), signal,
          targetReads, assertCurrent, controlConstruction}));
      assertCurrent?.();
    }
    for (const [index, member] of members.entries()) {
      const {owned} = ownerOf(member);
      assertCurrent?.();
      if (proposals[index].length === 0) fail('InstalledRowEffectEmptyMember');
      const description = owned.describe === undefined ? undefined :
        await owned.describe({member, runInvocationCid,
          dispatchRequestCid: dispatches[index], label: `preview-${index}`,
          approval: reads[index]?.approval, signal, ...resourceFields(member)});
      assertCurrent?.();
      currents.push(description);
      const contentOf = member.kind !== 'command' ? undefined : commandContentBorrower({
        control, prepared, inputs, memberIndex: member.memberIndex,
        artifact: sourceSet.members[index].payload.localResultArtifact,
        limits, assertCurrent});
      if (contentOf !== undefined) contentBorrowers.push(contentOf);
      const selectedCreate = member.kind === 'create'
        ? prepareInstalledCreateRows(moon, proposals[index], limits.preview) : undefined;
      const rows = selectedCreate?.rows ?? proposals[index].map(proposal => {
        const changes = JSON.parse(proposal.changesWire);
        return {value: changes.value, selector: targeted(member.kind)
          ? JSON.parse(proposal.selectorWire) : undefined};
      });
      const createRows = selectedCreate?.createRows;
      let entries;
      const recipe = ownerOf(member).managedPlanRecipe;
      const constructor = recipe?.requestConstruction;
      if (constructor !== undefined && (managedEffect?.runtime !== moon ||
          managedEffect.prepared !== prepared || managedEffect.request !== identity)) {
        fail('ForeignInstalledEffectManagedRun');
      }
      if (owned.prepareRequestChild !== undefined || constructor !== undefined) {
        const preparedEntries = [];
        for (const [rowIndex, row] of rows.entries()) {
          // Export already bounds the total proposal rows. Member/control
          // children share the same retainer but do not consume a row slot.
          if (rowIndex >= limits.maxRows) fail('InstalledRowEffectRowLimit');
          const context = {member, value: row.value, selector: row.selector,
            ...(member.kind === 'create' ? {createRowIdentity: createRows[rowIndex].identity,
              proposalWire: row.proposalWire} : {}),
            current: description, content: commandContentRow(contentOf, rowIndex), signal,
            ...(contentOwner === undefined ? {} : {contentOwner}),
            ...resourceFields(member),
            ...(guarded(member.kind) ? {rowIndex, assertCurrent,
              authorizationForRow: () => reads[index].authorizationForRow(rowIndex)} :
              {authorizationForRow: reads[index]?.authorizationForRow})};
          const preparedRequest = await prepareInstalledRowCaptureChild({children: requestChildren,
            create: () => constructor === undefined ? owned.prepareRequestChild(context) :
              (owned.prepareRequestChild === undefined ? prepareInstalledEffectRequestChild :
                prepareInstalledEffectOwnedRequestChild)({run: managedEffect, memberIndex: member.memberIndex,
                rowIndex, operationIndex: constructor.operationIndex,
                operation: recipe.rowOperations[constructor.operationIndex].operation,
                ...(owned.prepareRequestChild === undefined
                  ? {construct: () => owned.prepareRequest(context)}
                  : {constructChild: () => owned.prepareRequestChild(context)}),
                requestsRetired: retireRequestAliases}),
            assertCurrent, signal});
          preparedEntries.push(requestEntry(member, row, preparedRequest));
        }
        entries = Object.freeze(preparedEntries);
      } else entries = requestsOf(member, rows, description, contentOf, createRows);
      if (member.kind === 'create') {
        // Reuse the SAME Common inventory for Preview and requests.
        for (const [row, entry] of entries.entries()) {
          createRows[row].entry = entry;
          Object.freeze(createRows[row]);
        }
        rowsOf.push(Object.freeze(createRows));
        observations.push(undefined);
        continue;
      }
      if (member.kind === 'command') {
        await owned.recheckRequests({member, entries, current: description, ...resourceFields(member)});
        assertCurrent?.();
        rowsOf.push(Object.freeze(entries.map(entry => Object.freeze({entry}))));
        observations.push(undefined);
        continue;
      }
      const observed = await observeRows({member, entries,
        current: description, read: reads[index], signal, assertCurrent});
      assertCurrent?.();
      observations.push(observed);
      rowsOf.push(Object.freeze(entries.map((entry, row) => Object.freeze({
        entry, state: observed[row].state, versionCid: observed[row].versionCid,
        before: observed[row].before}))));
    }
    entries = Object.freeze(rowsOf.map(rows =>
      Object.freeze(rows.map(row => row.entry))));
    // Every create row passes the provider check before a Preview.
    await checkRows({members, entries, runInvocationCid, dispatches,
      subjectOf: member => checkSubject(runInvocationCid, member), signal, assertCurrent,
      physicalOperations, controlConstruction, operationPhase: 'capture'});
    assertCurrent?.();
    const capabilities = members.map((member, index) => admitCapability(
      member, entries[index], currents[index], runInvocationCid,
      dispatches[index]));
    const footprints = members.map((member, index) =>
      footprintOf(member, entries[index]));
    if (sourceSet.dependencies !== undefined) {
      retainPinnedEffectDependencyPayloads({sources: sourceSet, execution,
        store, storedResults, control, runDefinition: plan.runDefinition});
    }
    const payloads = sourceSet.members.map(member => member.payload);
    const preview = authorPreview({control, prepared, inputs,
      context: {runDefinition: previewContext.runDefinition,
        runInvocation: previewContext.runInvocation,
        compiledPlan: previewContext.compiledPlan,
        storeAuthorityCid: store.storeAuthorityCid},
      requestScope, members, rowsOf, capabilities, footprints, payloads});
    const body = JSON.parse(preview.wire);
    // The admitted Preview must state exactly the rows its requests write.
    body.effects.forEach((member, index) => {
      if (member.changes.length !== entries[index].length ||
          member.changes.some((change, row) =>
            !sameEffectValue(members[index].kind, approvedValue(members[index].kind, change), entries[index][row].value) ||
            (targeted(members[index].kind) && !sameValue(
              change.target_row_identity, entries[index][row].target)))) {
        fail('InstalledRowEffectPreviewOrderMismatch');
      }
    });
    const authoringContext = control.admitRunEvidence('authoring_context',
      canonicalJson(body.authoring_context), plan.contractLimits);
    const admittedPreview = control.admitEffectComputationPreview(
      preview.wire, plan.runDefinition, authoringContext,
      plan.contractLimits);
    const holdings = await preparePinnedEffectSourceHoldings({
      sources: sourceSet, store, control, preview: admittedPreview,
      invocation: plan.invocation,
      resultArtifacts: payloads.map(payload => payload.localResultArtifact)}).commit();
    assertCurrent?.();
    const previewInputs = checked(moon.clientProgramBindEffectPreviewInputs(
      checkedHost, inputs, previewContext.runInvocation,
      moon.clientProgramEffectInputStage(
        moon.clientProgramEffectInputAt(inputs, 0)), preview.wire,
      preview.authoringCid, moon.clientProgramEffectPreviewInputLimits(
        limits.preview.maxWireBytes, limits.preview.maxNodes,
        limits.preview.maxDepth, limits.maxWork, limits.maxFields,
        limits.preview.maxWireBytes, limits.preview.maxNodes,
        limits.preview.maxDepth, members.length, limits.maxRows,
        limits.maxWork, limits.maxWork)));
    // Every non-create member is verified against its pinned input. Command
    // proofs bind exact target/input but are not Mapping Plan documents.
    const plans = [];
    for (const member of members) {
      if (member.kind === 'create') continue;
      const chunks = [];
      const verified = await verifyPinnedEffectPlan({moon, execution,
        previewInputs, previewIndex: member.memberIndex,
        inputKey: commandKeys[member.memberIndex],
        publishedTarget: publishedTargets?.[member.memberIndex],
        limits: moon.clientProgramEffectInputExportLimits(
          ...exportLimits(plan.outputLimits)),
        planLimits: {maxFields: limits.maxFields, maxWork: limits.planWork,
          maxBytes: limits.preview.maxWireBytes,
          maxNodes: limits.preview.maxNodes,
          maxDepth: limits.preview.maxDepth,
          maxUtf16Units: limits.preview.maxWireBytes},
        onChunk: chunk => { chunks.push(chunk); }, signal});
      assertCurrent?.();
      plans.push({name: member.effectId,
        ...(member.kind === 'command' ? {} : {wire: chunks.join('')}),
        proof: verified.proof});
    }
    const connectorRecovery = [];
    for (const [index, member] of members.entries()) {
      const {owned} = ownerOf(member);
      const retained = memberCaptures[index];
      const entry = retained === undefined
        ? owned.recoveryEntry?.({member, current: currents[index], entries: entries[index]})
        : await retained.prepare();
      if (owned.recoveryEntry !== undefined) connectorRecovery.push({memberIndex: index,
        kind: entry?.kind, observationCid: entry?.observationCid, wire: entry?.wire});
    }
    const computation = await issueCompletedEffectfulComputationEvidence({
      execution, store, storedResults, control, admission: plan.admission,
      runDefinition: plan.runDefinition, invocation: plan.invocation,
      observation: plan.observation,
      normalizationJournal: plan.normalizationJournal, authoringContext,
      receiptEvidence: plan.receiptEvidence,
      captureEvidence: plan.captureEvidence, preview: admittedPreview,
      plans: plans.filter(item => item.wire !== undefined)
        .map(({name, wire}) => ({name, wire})),
      effectSourceHoldings: holdings, connectorRecovery,
      contractLimits: plan.contractLimits, signal});
    assertCurrent?.();
    for (const payload of sourceSet.payloads) {
      if (!childrenPending() && payload.prepared.status().pending) await payload.prepared.release();
      assertCurrent?.();
    }
    const ledger = openLedger(identity, controlConstruction);
    try {
      const applyPreview = effect.admitPreviewIdentity(preview.wire,
        body.run_identity_cid, preview.authoringCid, requestScope,
        preview.keys, limits.preview.maxWireBytes, limits.preview.maxNodes,
        limits.preview.maxDepth);
      const claims = claimsOf({body, keys: preview.keys, entries,
        requestScope, unit, dispatches,
        members, unitCids: members.map(member => cid({version: ownerOf(member).profile.unit,
          run_definition_cid: plan.runDefinition.identity, stage_index: member.stageIndex})),
        retentionId: plan.effectInputRetention.identity});
      route = physicalRoute({members, entries,
        previewRows: body.effects.map(member => member.changes),
        dispatchIndexes: body.effects.map(orderedSourceIndexes),
        runInvocationCid, dispatches,
        subjectCid: moon.clientProgramEffectApplySubjectCid(previewInputs),
        applyPreview, ledger, targetReads, assertCurrent, physicalOperations, controlConstruction});
      const preflight = {proofs: plans.map(item => item.proof),
        ...basePreflight({effects: body.effects, members, requestScope,
          keys: preview.keys})};
      return Object.freeze({preview: admittedPreview, computation,
        storedResults,
        apply: {moon, capturedInputs: previewInputs, preflight, ledger,
          members: claims, maxFrontierWork: limits.maxFrontierWork,
          refreshPreflight: route.current, bindDispatch: route.bindDispatch,
          authorization: {gate: singular?.authorization, scopes: scopes(members)}},
        receipt: {ledger, preview: applyPreview, commonMoon: moon,
          publicationPreview: admittedPreview,
          authorizeEvidenceRead: async () => true,
          members: claims.map(member => ({rowOwners: member.claims.map(
            claim => ({claim})), replayed: false})),
          limits: plan.contractLimits},
        publication: {execution, store, storedResults, control, computation,
          preview: admittedPreview, ledger, request: plan.request,
          attempt: plan.attempt, contractLimits: plan.contractLimits,
          now: plan.now},
        scopes: scopes(members),
        continuationWire: continuationOf(plan, unit, members, dispatches,
          updateTargetSelections !== undefined),
        releaseInputs,
        dispose: async () => { await releaseInputs(); ledger.close(); }});
    } catch (error) {
      ledger.close();
      throw error;
    }
  }

  // Capture a completed computation as one Effect Unit and return the stage
  // the common owner applies after the whole-set commit decision.
  // `facts` are the Host's Effect Site facts, or an installation's own
  // capture inputs that already carry the Preview context and Effect Unit.
  async function prepareCaptured(facts) {
    assertPrepared(facts ?? {});
    const {moon: runMoon, control, store, execution, checkedHost, prepared,
      identity, definition, compilation, signal, targetReads, contentOwner} = facts ?? {};
    const plan = facts?.publicationPlan ?? facts?.plan;
    if (runMoon !== moon || !plan || !execution || !checkedHost ||
        !prepared || !identity || ((definition === undefined ||
          compilation === undefined) && (facts.previewContext === undefined ||
          facts.unit === undefined))) {
      fail('InvalidInstalledEffectCapture');
    }
    signal?.throwIfAborted();
    const previewContext = facts.previewContext ?? {runDefinition: definition,
      runInvocation: plan.invocationOwner,
      compiledPlan: checked(moon.strategyPublicationAdmit('compiled_plan',
        moon.clientProgramEffectCompilationCompiledPlanWire(compilation),
        plan.contractLimits.maxWireBytes, plan.contractLimits.maxNodes,
        plan.contractLimits.maxDepth))};
    const unit = facts.unit ?? installedRowEffectUnit(moon, compilation);
    const members = membersOf(prepared, unit);
    bindRunResources(facts, members);
    const updateTargetSelections = facts.updateTargetSelections;
    const assertCurrent = selectionFence(facts, members, unit.stageIndex, updateTargetSelections);
    const runInvocationCid = plan.invocation.identity;
    const dispatches = members.map(member =>
      memberDispatch(runInvocationCid, member));
    const requestScope = moon.clientProgramEffectRequestScope(prepared,
      identity);
    const storedResults = await storeCompletedRunResultSet({execution,
      store, control, runDefinition: plan.runDefinition,
      invocation: plan.invocation, results: plan.results,
      outputLimits: plan.outputLimits, contractLimits: plan.contractLimits});
    let sourceSet;
    let releaseInputs;
    let requestChildren, finishCapture;
    try {
      try {
        return await captureStage({control, store, execution, checkedHost,
          prepared, identity, plan, previewContext, unit, members,
          runInvocationCid, dispatches, requestScope, storedResults, signal,
          targetReads, contentOwner, managedEffect: facts.managedEffect, updateTargetSelections, assertCurrent, own: value => { sourceSet = value; },
          ownChildren: value => { requestChildren = value; },
          ownInputs: (release, finish) => { releaseInputs = release; finishCapture = finish; }});
      } finally { finishCapture?.(); }
    } catch (error) {
      await releaseInstalledRowCapture({payloads: sourceSet?.payloads,
        children: requestChildren,
        // This owner's false means already released, not pending cleanup.
        releaseResults: async () => { await releaseCompletedRunPreparedPayloads(storedResults, control); },
        releaseInputs, control}, error);
    }
  }

  // The members of a recovered capture, from its exact saved Preview and
  // continuation. The installation must still hold each Mapping.
  const recoveredMembers = (body, provider, selected) => {
    if (body.effects.length !== provider.members.length) {
      fail('InstalledEffectContinuationMismatch');
    }
    return Object.freeze(body.effects.map((member, index) => {
      const saved = provider.members[index];
      const owner = selectOwner(runtimeTupleFromFields({1: member.effect_id, 2: member.effect_kind, 3: member.target, 4: member.mapping, 5: member.resolved_mapping_contract_cid}));
      const {installed, installedCommands, owned} = owner;
      // Initial composed-profile restriction: recovery requires every retained
      // installation identity, not merely equivalent Mappings/capabilities. A
      // republished revision or binding therefore refuses here even when the
      // historical singular row profile could admit that replacement.
      if ((singular === undefined || selected) &&
          !sameValue(saved?.installation, installationFacts(owner))) {
        if (selected) selectionChanged();
        fail('InstalledRowEffectInstallationChanged');
      }
      if (member.effect_kind === 'command') {
        const command = installedCommands.find(candidate =>
          candidate.commandCid === member.resolved_command_contract_cid &&
          candidate.commandRef === member.contract && candidate.target === member.target);
        if (saved?.effect_id !== member.effect_id ||
            saved.command_cid !== member.resolved_command_contract_cid ||
            Object.hasOwn(saved, 'mapping_cid')) fail('InstalledEffectContinuationMismatch');
        if (command === undefined || !owned.kinds.includes('command')) {
          fail('InstalledRowEffectCommandNotInstalled');
        }
        return retainMember(owner, {effectId: member.effect_id, memberIndex: index,
          kind: 'command', command, resource: command.resource});
      }
      const mapping = installed.find(candidate =>
        candidate.mappingCid === member.resolved_mapping_contract_cid &&
        (!selected || (candidate.mappingRef === member.mapping &&
          candidate.target === member.target)));
      if (saved?.effect_id !== member.effect_id ||
          saved.mapping_cid !== member.resolved_mapping_contract_cid) {
        fail('InstalledEffectContinuationMismatch');
      }
      if (mapping === undefined || !owned.kinds.includes(member.effect_kind)) {
        if (selected) selectionChanged();
        fail('InstalledRowEffectMappingNotInstalled');
      }
      return retainMember(owner, {effectId: member.effect_id, memberIndex: index,
        kind: member.effect_kind, mapping, resource: mapping.resource});
    }));
  };

  // Each recovered row's request, rebuilt from its approved Preview row (a
  // create) or from the provider's retained data (an update), and held to
  // exactly the request its durable claim names, the value the Preview
  // approved and, for an update, the Preview's target.
  const recoveredEntries = ({members, body, durable, recorded,
    previewWire, runInvocationCid, dispatches}) => {
    const rebuilt = singular?.owned.recoverRequests === undefined ? undefined :
      singular.owned.recoverRequests({durable, recorded, previewWire, body,
        members, runInvocationCid, dispatches,
        ...resourceFields(members[0])});
    const requests = members.map((_, index) => rebuilt?.requests?.[index]);
    const usesRecovery = members.map(() => rebuilt !== undefined);
    const currents = members.map((_, index) => rebuilt?.currents?.[index]);
    if (singular === undefined) {
      for (const owner of owners) {
        if (owner.owned.recoverMemberRequests === undefined) continue;
        const memberIndexes = Object.freeze(members.flatMap((member, index) =>
          ownerOf(member) === owner ? [index] : []));
        if (memberIndexes.length === 0) continue;
        const recovered = owner.owned.recoverMemberRequests({durable, recorded,
          previewWire, body, memberIndexes, members, runInvocationCid, dispatches,
          ...resourceFields(members[memberIndexes[0]])});
        if (!Array.isArray(recovered?.requests) ||
            recovered.requests.length !== memberIndexes.length ||
            (recovered.currents !== undefined &&
              (!Array.isArray(recovered.currents) ||
                recovered.currents.length !== memberIndexes.length))) {
          fail('InstalledEffectContinuationMismatch');
        }
        memberIndexes.forEach((index, selectedIndex) => {
          if (!Array.isArray(recovered.requests[selectedIndex])) {
            fail('InstalledEffectContinuationMismatch');
          }
          usesRecovery[index] = true;
          requests[index] = recovered.requests[selectedIndex];
          currents[index] = recovered.currents?.[selectedIndex];
        });
      }
    }
    const entries = members.map((member, index) => {
      const {owned} = ownerOf(member);
      const claims = recorded.members[index]?.claims ?? [];
      const effectMember = body.effects[index];
      const changes = effectMember.changes;
      const sourceIndexes = orderedSourceIndexes(effectMember);
      const claimBySource = new Map(sourceIndexes.map((sourceIndex, dispatchIndex) =>
        [sourceIndex, claims[dispatchIndex]]));
      if (claims.length !== changes.length) {
        fail('InstalledEffectContinuationMismatch');
      }
      const rows = !usesRecovery[index]
        ? changes.map(change => {
          const prepared = owned.prepareRequest({member,
            ...(member.kind === 'create' ? {createRowIdentity: Object.freeze(change.target_row_identity)} : {}),
            value: change.after?.value, selector: undefined,
            current: currents[index], ...resourceFields(member)});
          return entryOf(member, prepared?.request, prepared?.requestCid);
        })
        : (requests[index] ?? []).map(request =>
          entryOf(member, request, owned.requestCid(request)));
      if (rows.length !== changes.length) {
        fail('InstalledEffectContinuationMismatch');
      }
      rows.forEach((entry, row) => {
        if (entry.requestCid !== claimBySource.get(row)?.canonicalRequestCid ||
            !sameEffectValue(member.kind, entry.value, approvedValue(member.kind, changes[row])) ||
            (targeted(member.kind) && !sameValue(entry.target,
              changes[row].target_row_identity))) {
          fail('ForeignInstalledRowEffectRequest');
        }
      });
      return Object.freeze(rows);
    });
    return {entries: Object.freeze(entries),
      currents: Object.freeze(currents)};
  };

  // Continue a recovered capture: the exact saved Preview, requests rebuilt
  // and held to their claims and approved rows, and the Ledger's durable
  // claims. The installation must still be the one the Preview was authored
  // against: a changed Mapping, binding, runtime or capability is refused
  // before any provider I/O.
  function prepareRecovered(facts) {
    const {moon: runMoon, control, store, recovered, continuation, signal,
      retainRecoveryOwner, targetReads, managedEffect} = facts ?? {};
    if (runMoon !== moon || !recovered?.computation || !continuation) {
      fail('InvalidInstalledEffectRecovery');
    }
    signal?.throwIfAborted();
    const contractLimits = localContractLimits;
    const provider = continuation.provider ?? continuation;
    // The legacy singular continuation records, but does not compare, its binding:
    // a republished installation resumes only if every Mapping remains and
    // it issues/adopts the Preview's capability (both checked below). The
    // initial composed profile additionally checks exact installation facts
    // in recoveredMembers. Selected updates require the exact retained owner
    // and stage even for a singular installation.
    if (provider?.version !== (singular?.profile.continuation ?? ROUTING_VERSION) ||
        (singular !== undefined && !text(provider[singular.profile.continuationBinding])) ||
        !Array.isArray(provider.members) || !text(provider.program_id) ||
        !text(provider.stage_id)) {
      fail('InstalledEffectContinuationMismatch');
    }
    const updateTargetSelections = facts.updateTargetSelections;
    const selected = updateTargetSelections !== undefined;
    if (!selected && Object.hasOwn(provider, 'stage_index')) selectionChanged();
    if (selected && (!Number.isSafeInteger(provider.stage_index) ||
        provider.stage_index < 0 || (singular !== undefined &&
        provider[singular.profile.continuationBinding] !== singular.continuationBinding))) {
      selectionChanged();
    }
    const {requestIdentity, requestScope, computation: durable} = recovered;
    const {computation, preview, storedResults} = durable;
    const previewWire = control.effectComputationPreviewWire(preview);
    const body = JSON.parse(previewWire);
    const members = recoveredMembers(body, provider, selected);
    bindRunResources(facts, members);
    const assertCurrent = selectionFence(facts, members, provider.stage_index, updateTargetSelections);
    const runInvocationCid = body.invocation_cid;
    const dispatches = members.map(member =>
      memberDispatch(runInvocationCid, member));
    if (dispatches.some((dispatch, index) =>
      dispatch !== provider.members[index].dispatch_request_cid)) {
      fail('InstalledEffectContinuationMismatch');
    }
    const admitted = control.effectComputationPreviewLedgerIdentity(preview);
    const keys = effect.recoveredPreviewKeys(admitted, requestScope,
      members.length, limits.maxRows, limits.maxWork, limits.key.maxBytes,
      limits.key.maxNodes, limits.key.maxDepth);
    const applyPreview = effect.admitPreviewIdentity(previewWire,
      body.run_identity_cid, body.authoring_context.authoring_context_cid,
      requestScope, keys, limits.preview.maxWireBytes,
      limits.preview.maxNodes, limits.preview.maxDepth);
    const submitted = recovered.originalSubmittedIntent;
    submitted?.assertCurrent();
    const requestedStop = submitted === undefined ||
      !moon.clientSubmittedIntentRequestsCommitStop(submitted.intent)
      ? undefined : control.restoreRequestedEffectStop(
      submitted, requestIdentity, recovered.materials, durable.invocation, preview,
      moon.clientProgramEffectPreviewInputLimits(
        limits.preview.maxWireBytes, limits.preview.maxNodes,
        limits.preview.maxDepth, limits.maxWork, limits.maxFields,
        limits.preview.maxWireBytes, limits.preview.maxNodes,
        limits.preview.maxDepth, members.length, limits.maxRows,
        limits.maxWork, limits.maxWork));
    const assertRequestedStopCurrent = () => {
      submitted?.assertCurrent();
      assertCurrent?.();
    };
    const controlConstruction = managedEffect?.controlConstruction;
    if (managedEffect !== undefined && typeof controlConstruction !== 'function') fail('InstalledEffectControlRuntimeUnavailable');
    const managedPrepared = managedEffect?.prepared, managedRequest = managedEffect?.request;
    if (managedEffect !== undefined) {
      if (typeof retainRecoveryOwner !== 'function') fail('InstalledEffectRecoveryCustodyRequired');
      if (managedEffect.runtime !== moon || managedEffect.closed || managedPrepared === undefined ||
          typeof moon.clientRequestRelation !== 'function' ||
          moon.clientRequestRelation(managedRequest, requestIdentity) !== 1 ||
          managedEffect.definitionOriginal?.definition === undefined || recovered.runDefinition === undefined ||
          typeof moon.strategyPublicationContractIdentity !== 'function' ||
          moon.strategyPublicationContractIdentity(managedEffect.definitionOriginal.definition) !== recovered.runDefinition.identity) {
        fail('ForeignInstalledEffectManagedRun');
      }
      if (Object.hasOwn(managedEffect, 'failure')) throw managedEffect.failure;
    }
    const ledger = openLedger(requestIdentity, controlConstruction);
    // The handle is released exactly once: it is marked released only after
    // its close succeeds, so a failed close stays this owner's pending
    // cleanup and a retry by the same owner closes it.
    let closed = false, closing = false, opening = true, reconciling = 0, cleanupFlight;
    let entries, currents, route;
    const recoveryChildren = [], requestChildren = [];
    const recoveryPending = () => recoveryChildren.some(child => child.status().pending !== false);
    const requestsPending = () => requestChildren.some(child => child.prepared.status().pending !== false);
    const retireRequestAliases = () => {
      if (opening || reconciling !== 0 || route !== undefined && !route.retire()) return false;
      entries = currents = undefined;
      return true;
    };
    const physicalOperations = managedEffect === undefined ? undefined : operation => {
      if (closing || closed) fail('InstalledRowEffectRouteRetired');
      if (managedEffect.runtime !== moon || managedEffect.prepared !== managedPrepared ||
          managedEffect.request !== managedRequest || managedEffect.closed) fail('ForeignInstalledEffectManagedRun');
      if (Object.hasOwn(managedEffect, 'failure')) throw managedEffect.failure;
      const observeCurrent = operation.assertCurrent;
      return prepareCredentialOperation({...operation, managedEffect, requestChildren, retireRequestAliases,
        assertCurrent() {
          if (closing || closed) fail('InstalledRowEffectRouteRetired');
          observeCurrent();
          if (closing || closed) fail('InstalledRowEffectRouteRetired');
        }});
    };
    const releaseLedger = () => {
      if (closed) return;
      ledger.close();
      closed = true;
    };
    const closeRecovery = () => {
      closing = true;
      if (closed) return Promise.resolve(true);
      if (opening) return Promise.resolve(false);
      // A child may await this Owner reentrantly. Report pending rather than
      // making that child await the flight which is itself awaiting the child.
      if (cleanupFlight !== undefined) return Promise.resolve(false);
      // Keep this same Owner/flight before any child method can reenter it.
      const flight = Promise.resolve().then(async () => {
        if (!retireRequestAliases()) return false;
        for (const child of requestChildren) {
          const retry = child.recoveryReleaseAttempted === true;
          child.recoveryReleaseAttempted = true;
          await (retry ? child.prepared.retry() : child.prepared.release());
        }
        if (requestsPending()) return false;
        for (const child of recoveryChildren) await child.release();
        if (recoveryPending()) return false;
        releaseLedger();
        return true;
      }).finally(() => {if (cleanupFlight === flight) cleanupFlight = undefined;});
      cleanupFlight = flight;
      return flight;
    };
    const ledgerOwner = Object.freeze({close: closeRecovery, cleanup: closeRecovery,
      cleanupPending: () => !closed || recoveryPending() || requestsPending()});
    if (retainRecoveryOwner !== undefined) {
      try { retainRecoveryOwner(ledgerOwner); }
      catch (error) { releaseLedger(); throw error; }
    }
    try {
      const recorded = ledger.recoverClaimFacts({preview: admitted,
        scope: requestScope, programId: provider.program_id,
        nodeId: provider.stage_id, maxRows: limits.maxRows,
        maxWork: limits.maxWork});
      assertCurrent?.();
      ({entries, currents} = recoveredEntries({members, body, durable,
        recorded, previewWire, runInvocationCid, dispatches}));
      assertCurrent?.();
      const finish = () => {
        if (closing) fail('InstalledRowEffectRouteRetired');
        // The installation as loaded now must issue and admit the same
        // capability the Preview carries, for the same requests, before any
        // provider I/O.
        members.forEach((member, index) => {
          let capability;
          try {
            capability = admitCapability(member, entries[index],
              currents[index], runInvocationCid, dispatches[index]);
          } catch (error) {
            fail('InstalledRowEffectInstallationChanged', error);
          }
          if (capability.identity !==
              body.effects[index].capability_evidence_cid) {
            fail('InstalledRowEffectInstallationChanged');
          }
        });
        const previewRows = body.effects.map(member => member.changes);
        const dispatchIndexes = body.effects.map(orderedSourceIndexes);
        if (closing) fail('InstalledRowEffectRouteRetired');
        route = physicalRoute({members, entries, previewRows, dispatchIndexes,
          runInvocationCid, dispatches,
          subjectCid: control.effectComputationPreviewSemanticCid(preview),
          applyPreview, ledger, targetReads, assertCurrent, physicalOperations, controlConstruction, operationPhase: 'resume'});
        const reconcileStoredResponses = async ({members: claims,
          preview: ledgerPreview}) => {
          if (closing || closed) fail('InstalledRowEffectRouteRetired');
          reconciling++;
          const assertRecoveredCurrent = () => {
            if (closing || closed) fail('InstalledRowEffectRouteRetired');
            route.assertClaimedCurrent();
            if (closing || closed) fail('InstalledRowEffectRouteRetired');
          };
          try {
            assertRecoveredCurrent();
            for (const [memberIndex, member] of claims.entries()) {
              for (const [rowIndex, claim] of member.claims.entries()) {
                assertRecoveredCurrent();
                if (ledger.readClaimedResponse(claim) === undefined) continue;
                const sourceIndex = dispatchIndexes[memberIndex][rowIndex];
                const entry = entries[memberIndex][sourceIndex];
                const ownedClaim = admitRow({applyPreview: ledgerPreview,
                  memberIndex, rowIndex, claim, member: members[memberIndex],
                  entry, previewRow: previewRows[memberIndex][sourceIndex]});
                const recovery = await recoverProjectedEffectResponse({ledger,
                  claims: ownedClaim, commonMoon: moon,
                  expectedRequestCid: entry.requestCid,
                  authorizeEvidenceRead: async () => true,
                  projectStored: stored => {
                    assertRecoveredCurrent();
                    const owned = ownerOf(members[memberIndex]).owned;
                    const projectionFacts = {member: members[memberIndex], memberIndex, rowIndex,
                      preview: ledgerPreview, request: entry.request, current: currents[memberIndex],
                      observation: Object.freeze({useCid: stored.credentialUseCid,
                        statusCode: stored.statusCode, body: stored.responseBytes}), headers: undefined};
                    return controlConstruction === undefined ? owned.project(projectionFacts)
                      : controlConstruction(owned, owned.project, [projectionFacts]);
                  }});
                assertRecoveredCurrent();
                settle({ledger, claim: ownedClaim, applyPreview: ledgerPreview,
                  memberIndex, rowIndex, projected: recovery.recovered});
              }
            }
          } finally {reconciling--;}
        };
        return Object.freeze({preview, computation, storedResults,
          ...(requestedStop === undefined ? {} : {requestedStop, assertRequestedStopCurrent}),
          apply: {moon, store, publicationControl: control, computation,
            preview, ledger, requestScope, programId: provider.program_id,
            nodeId: provider.stage_id, maxRows: limits.maxRows,
            maxFrontierWork: limits.maxFrontierWork,
            maxRecoveryWork: limits.maxWork,
            keyLimits: {...limits.key, maxWork: limits.maxWork},
            reconcileStoredResponses,
            refreshPreflight: ({signal: refreshSignal} = {}) => route.current({
              signal: refreshSignal, preflight: basePreflight({
                effects: body.effects, members, requestScope})}),
            bindDispatch: route.bindDispatch,
            authorization: {gate: singular?.authorization, scopes: scopes(members)}},
          receipt: {ledger, preview: applyPreview, commonMoon: moon,
            publicationPreview: preview,
            authorizeEvidenceRead: async () => true,
            members: recorded.members.map(member => ({rowOwners:
              member.claims.map(claim => ({claim})), replayed: true})),
            limits: contractLimits},
          publication: {execution: null, store, storedResults, control,
            computation, preview, ledger, request: provider.request,
            attempt: {...provider.attempt, externalIdempotencyKey:
              provider.attempt?.externalIdempotencyKey}, contractLimits,
            now: () => new Date().toISOString()},
          scopes: scopes(members),
          continuationWire: canonicalJson(provider),
          cleanupOwner: ledgerOwner,
          dispose: closeRecovery});
      };
      for (const owner of owners) {
        if (owner.owned.prepareRecoveredContentChild === undefined) continue;
        if (typeof retainRecoveryOwner !== 'function') {
          fail('InstalledEffectRecoveryCustodyRequired');
        }
        const memberIndexes = Object.freeze(members.flatMap((member, index) =>
          ownerOf(member) === owner ? [index] : []));
        if (memberIndexes.length === 0) continue;
        const child = owner.owned.prepareRecoveredContentChild({
          recovered, members, entries, memberIndexes, control, store, signal,
          contentRun: facts.contentRun, principalId: facts.principalId,
          assertCurrent, limits, ...resourceFields(members[memberIndexes[0]])});
        if (typeof child?.prepare !== 'function' || typeof child.release !== 'function' ||
            typeof child.status !== 'function') {
          fail('InvalidInstalledEffectRecoveryChild');
        }
        // The same already-retained ledger owner keeps every child before
        // current callbacks or the first awaited physical Store confirmation.
        recoveryChildren.push(child);
        assertCurrent?.();
      }
      if (recoveryChildren.length === 0) {
        const stage = finish();
        opening = false;
        return stage;
      }
      return (async () => {
        try {
          for (const child of recoveryChildren) {
            await child.prepare();
            signal?.throwIfAborted();
            assertCurrent?.();
          }
          return finish();
        } finally {opening = false;}
      })();
    } catch (error) {
      opening = false;
      if (retainRecoveryOwner === undefined) releaseLedger();
      throw error;
    }
  }

  if (singular === undefined) {
    const adapter = Object.freeze({environmentWire, assertPrepared, prepareManagedPlan,
      prepareCaptured, prepareRecovered});
    rowInstallations.set(adapter, Object.freeze([...owners]));
    return adapter;
  }
  const {installed, installedCommands, owned, connectorId, bindingCid,
    connectorRegistration, connectorRevision, connection, site, sourceInitialization} = singular;
  let constructionClosed = false;
  const adapter = Object.freeze({
    environmentWire,
    connectorBindings: Object.freeze([Object.freeze({connectorId,
      bindingCid})]),
    connectorRegistration, connectorRevision, connection,
    mappings: Object.freeze(installed.map(mapping => Object.freeze({
      resource: mapping.resource, target: mapping.target,
      mappingRef: mapping.mappingRef, mappingCid: mapping.mappingCid}))),
    commands: Object.freeze(installedCommands.map(command => Object.freeze({
      resource: command.resource, target: command.target,
      commandRef: command.commandRef, commandCid: command.commandCid}))),
    effectSelectors: Object.freeze([...installed.flatMap(mapping =>
      [...new Set(owned.kinds)].filter(kind =>
        mapping.rules.some(rule => rule.effect_kind === kind)).map(kind =>
        Object.freeze({kind, target: mapping.target,
          mappingRef: mapping.mappingRef, mappingCid: mapping.mappingCid}))),
    ...(!owned.kinds.includes('command') ? [] : installedCommands.map(command =>
      Object.freeze({kind: 'command', target: command.target,
        commandRef: command.commandRef, commandCid: command.commandCid})))]),
    prepareManagedPlan, prepareCaptured, prepareRecovered,
    close() {
      const observed = site.close();
      if (sourceInitialization === undefined) return observed;
      return Promise.resolve(observed).then(value => {
        if (value === false) fail('InstalledEffectSiteCleanupPending');
        if (!constructionClosed) {
          closeInstalledSourceConstruction(sourceInitialization, adapter);
          constructionClosed = true;
        }
        return value;
      });
    },
  });
  rowInstallations.set(adapter, singular);
  return adapter;
}
