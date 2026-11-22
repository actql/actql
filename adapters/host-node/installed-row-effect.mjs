import {installedEffectDependencyOriginal} from '../host-common/installed-effect-dependency-original.mjs';
import {prepareInstalledEffectResultProgress} from './effect-result-work.mjs';
import {createInstalledRowEffectPlanCapture} from './installed-row-effect-plan-capture.mjs';
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
import {installedEffectSavedControlEntryLimit, installedEffectSavedControlResponseLimit, installedEffectRecipeForControlEntryLimit, captureInstalledEffectPlanRecipe, prepareInstalledEffectRequestChild, prepareInstalledEffectCaptureChild, prepareInstalledEffectOwnedRequestChild, prepareInstalledEffectCredentialChild} from './installed-effect-plan.mjs';
import {installedRowCredentialOperationSite} from './installed-row-source.mjs';
import {createHash} from 'node:crypto';
import {types as nodeTypes} from 'node:util';
import {createInstalledRowEffectDriverControls} from './installed-row-effect-driver.mjs';
import {createInstalledRowEffectConstruction} from './installed-row-effect-construction.mjs';
import {createInstalledRowEffectPhysicalOperation, createInstalledRowEffectReadChild,
  createInstalledRowEffectReadOperations} from './installed-row-effect-physical-read.mjs';
import {createInstalledRowEffectCapability, createInstalledRowEffectReadDecision,
  createInstalledRowEffectTargetAuthorization} from './installed-row-effect-authorization.mjs';
import {createInstalledRowEffectMembers, createInstalledRowEffectRequests} from './installed-row-effect-members.mjs';
import {createInstalledRowEffectRunControls, createInstalledRowEffectRunLimits} from './installed-row-effect-run-controls.mjs';
import {createInstalledRowEffectOwnerProjection} from './installed-row-effect-owner-projection.mjs';
import {invokeDeclaredRowUpdate} from '../host-common/owned-invocation-context.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {refusedEffectPreparation} from
  '../host-common/effect-preparation-result.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {issueCompletedEffectfulComputationEvidence,
  releaseCompletedRunPreparedPayloads, storeCompletedRunResultSet} from
  '../host-common/completed-run-publication.mjs';
import {canonicalJson} from './local-account-config.mjs';
import {canonicalJson as canonicalValueJson} from
  '../../packages/sdk/host-port.mjs';
import {preparePinnedEffectSourceHoldings, preparePinnedEffectSourceSet,
  retainPinnedEffectDependencyPayloads} from './effect-input-export.mjs';
import {verifyPinnedEffectPlan} from './effect-plan-verify.mjs';
import {retireEffectCommandKeyWorkspace} from './effect-command-key.mjs';
import {openInstalledEffectLedger} from './installed-effect-ledger-open.mjs';
import {captureClaimedEffectResponse, snapshotEffectDispatchClaim} from
  './effect-physical-dispatch.mjs';
import {recoverProjectedEffectResponse} from './effect-response-recovery.mjs';
import {localContractLimits} from './local-values-plan.mjs';
import {prepareInstalledRowCaptureChild, retainInstalledRowCaptureChild, releaseInstalledRowCapture} from './installed-row-capture-cleanup.mjs';
import {assertUpdateTargetSelectionMembersCurrent} from './update-target-original-shape.mjs';
import {closeInstalledSourceConstruction} from './installed-host-services.mjs';

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

// The same constructor limits used by the installed owner and its pure recipe.
export const installedRowEffectConstructionLimits = supplied => Object.freeze({...defaultLimits, ...supplied});

const fail = (code, cause) => {
  throw Object.assign(new Error(code, {cause}), {code});
};
const text = value => typeof value === 'string' && value.length > 0;
const {captureManagedPlanDefinition, captureManagedDriverConstruction, captureManagedPlanRecipes,
  prepareInstalledTargetPlanRecipes: prepareManagedTargetPlanRecipes} = createInstalledRowEffectPlanCapture({fail, text});
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
const managedTargetPlanOriginals = new WeakMap();

export function prepareInstalledTargetPlanRecipes(mappings, recipes) {
  return prepareManagedTargetPlanRecipes(mappings, recipes, cidPattern, localContractLimits,
    managedTargetPlanOriginals);
}

const {captureEffectResources, requireSynchronousEffectResource, installedEffectKinds,
  installedEffectWriteOperation, checkDriver, captureBeforeSendCheck, captureResponseConfirmation} =
  createInstalledRowEffectDriverControls({fail, text, optionalFunction, kinds, guarded});

const {installationFacts, selectionChanged, validateOwnerSelections, installedRowEffectOwnerBinding,
  installedRowEffectUpdateTargetReadAccess, installedRowEffectUpdateObservation,
  collectInstalledRowEffectUpdateObservations, installedRowEffectUpdateObservations, validateInstalledUpdateOwnerSelections} =
  createInstalledRowEffectOwnerProjection({rowInstallations, installedEffectKinds});

export {installedRowEffectOwnerBinding, installedRowEffectUpdateTargetReadAccess, installedRowEffectUpdateObservation,
  collectInstalledRowEffectUpdateObservations, installedRowEffectUpdateObservations, validateInstalledUpdateOwnerSelections};

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

const {installedRowEffectUnit, installedRowEffectDescriptors, createInstalledRowEffect} =
  createInstalledRowEffectConstruction({
    fail, text, optionalFunction, cid, cidPattern, defaultProfile, defaultLimits, localContractLimits,
    installedRowEffectConstructionLimits, managedTargetPlanOriginals, createRowEffectStage,
    captureEffectResources, checkDriver, captureBeforeSendCheck, captureResponseConfirmation,
    captureManagedPlanDefinition, captureManagedPlanRecipes, captureManagedDriverConstruction,
  });

export {installedRowEffectUnit, installedRowEffectDescriptors, createInstalledRowEffect};

// Each physical occurrence retains its own admitted installation. Shared Run,
// Preview, claims and publication remain the existing stage's responsibility.
// This profile admits one existing CREATE or UPDATE family at a time. A retained-request driver
// must explicitly support recovery of its original members in the whole Set.
export function composeInstalledRowEffectOwners(effects, descriptors, environmentWire) {
  if (!Array.isArray(effects) || !Array.isArray(descriptors) ||
      effects.length !== descriptors.length || effects.length < 2 ||
      !['create', 'update'].includes(descriptors[0]?.kind) ||
      descriptors.some(value => value.kind !== descriptors[0].kind) ||
      new Set(descriptors.map(value => value.effectId)).size !== descriptors.length) {
    fail('InstalledEffectSetOwnerMismatch');
  }
  const owners = effects.map(effect => rowInstallations.get(effect));
  if (owners.some(owner => owner === undefined || Array.isArray(owner) ||
      (owner.owned.recoverRequests !== undefined &&
        owner.owned.recoverMemberRequests === undefined))) fail('InstalledEffectSetOwnerMismatch');
  const first = owners[0];
  // This standalone composition has no original Request construction borrow.
  // Preserve its installed envelope; a later managed Plan cannot retroactively
  // fund the Set, route and owner vectors constructed here.
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
  const readManagedShape = moon.clientProgramInstalledEffectManagedPlanShape;
  const runLimits = createInstalledRowEffectRunLimits({moon, readManagedShape, limits, owners, fail});
  const recipes = owners.flatMap(owner => owner.managedTargetPlanRecipes !== undefined ? []
    : owner.managedPlanRecipes === undefined ? [owner.managedPlanRecipe] : Object.values(owner.managedPlanRecipes));
  let controlEntryBytes = installedEffectSavedControlEntryLimit(recipes);
  let controlResponseBytes = installedEffectSavedControlResponseLimit(recipes);
  for (const owner of owners) {
    const prepared = owner.managedTargetPlanRecipes;
    if (prepared === undefined) continue;
    controlEntryBytes = Math.max(controlEntryBytes, prepared.maxEntryBytes);
    controlResponseBytes = Math.max(controlResponseBytes, prepared.maxResponseBytes);
  }
  const controlRecipes = new Map(recipes.map(recipe => [recipe,
    installedEffectRecipeForControlEntryLimit(recipe, controlEntryBytes, controlResponseBytes)]));
  const singular = routes === undefined ? owners[0] : undefined;
  const assertPrepared = ({moon: runMoon, compilation}) => {
    if (singular !== undefined) return;
    if (runMoon !== moon || compilation === undefined) fail('InstalledEffectSetOwnerMismatch');
    const program = JSON.parse(moon.clientProgramEffectCompilationPlanWire(compilation))
      .execution_material?.program;
    const stage = program?.stages?.[0];
    // Routed UPDATE uses the existing checked Source/Model capture and the
    // member-scoped original-request recovery below. CREATE retains its
    // existing source-free profile; neither path admits multiple stages here.
    const update = routes.every(route => route.descriptor.kind === 'update');
    if (program?.stages?.length !== 1 || stage === undefined ||
        !Array.isArray(stage.steps) || stage.steps.length === 0 ||
        (!update && (Object.keys(stage.inputs ?? {}).length !== 0 ||
          stage.steps.some(step => !Object.hasOwn(step, 'values'))))) {
      fail('InstalledEffectSetOwnerMismatch');
    }
  };
  const ownerOf = member => {
    const owner = memberInstallations.get(member);
    if (owner === undefined || !owners.includes(owner)) fail('ForeignInstalledEffectOccurrence');
    return owner;
  };
  const targetPlanOf = (member, owner) => {
    if (owner.managedTargetPlanRecipes === undefined) return undefined;
    const plan = owner.managedTargetPlanRecipes.byMapping[member.mapping?.mappingCid];
    if (member.kind !== 'update' || plan === undefined) fail('ForeignInstalledEffectOccurrence');
    return plan;
  };
  const recipeOf = member => {
    const owner = ownerOf(member), target = targetPlanOf(member, owner);
    if (target !== undefined) return controlEntryBytes > target.entryLimit ||
      controlResponseBytes > target.responseLimit ? target.fallback : target.recipe;
    const recipe = owner.managedPlanRecipes === undefined
      ? owner.managedPlanRecipe : owner.managedPlanRecipes[member.kind];
    return controlRecipes.get(recipe);
  };
  const projectOwnedResponse = (member, facts, construction) => {
    const {owned} = ownerOf(member);
    const method = owned.project;
    if (construction === undefined) return Reflect.apply(method, owned, [facts]);
    const selected = recipeOf(member)?.projectConstruction;
    return selected !== undefined && selected.receiver === owned && selected.method === method
      ? construction(owned, method, [facts], selected.capacity)
      : construction(owned, method, [facts]);
  };
  const retainMember = (owner, member) => {
    const retained = Object.freeze(member);
    memberInstallations.set(retained, owner);
    return retained;
  };
  const {bindRunResources, resourceFields, selectionFence} = createInstalledRowEffectRunControls({
    owners, ownerOf, fail, selectionChanged,
    requireSynchronousEffectResource, validateOwnerSelections, assertUpdateTargetSelectionMembersCurrent,
  });
  const {selectOwner, scopes, permissionsOf, membersOf, prepareManagedPlan} = createInstalledRowEffectMembers({
    moon, limits, owners, singular, routes, installedEffectKinds, retainMember, ownerOf,
    assertPrepared, installedRowEffectUnit, recipeOf, fail,
  });
  const effect = runtimeCore(moon).effectApplicationControl;
  const openLedger = (identity, controlConstruction) => openInstalledEffectLedger(
    moon, ledgerRoot, identity, controlEntryBytes, controlResponseBytes, controlConstruction);
  const memberDispatch = (runInvocationCid, member) => cid({
    version: ownerOf(member).profile.dispatch, run_invocation_cid: runInvocationCid,
    effect_id: member.effectId});
  const recoveryCid = (member, dispatch) => cid({version: ownerOf(member).profile.recovery,
    dispatch_request_cid: dispatch});

  const {entryOf, requestEntry, requestsOf} = createInstalledRowEffectRequests({
    ownerOf, cidPattern, targeted, sameEffectValue, sameValue, resourceFields, commandContentRow, fail,
  });

  const {admitCapability, routeOf} = createInstalledRowEffectCapability({
    moon, ownerOf, cid, cidPattern, CAPABILITY_VERSION, contractCidOf, installedEffectWriteOperation, fail,
  });
  const readDecision = createInstalledRowEffectReadDecision({ownerOf});
  const checkSubject = (runInvocationCid, member) => cid({
    version: ownerOf(member).profile.targetCheck, run_invocation_cid: runInvocationCid,
    effect_id: member.effectId});

  const prepareCredentialOperation = createInstalledRowEffectPhysicalOperation({
    moon, recipeOf, fail, installedRowCredentialOperationSite, prepareInstalledRowCaptureChild, prepareInstalledEffectCredentialChild,
  });
  const managedReadChild = createInstalledRowEffectReadChild({ownerOf, recipeOf, requireSynchronousEffectResource, fail});
  const {describeMember, checkRows, observeRows} = createInstalledRowEffectReadOperations({
    ownerOf, recipeOf, managedReadChild, resourceFields, readDecision, sameValue, cidPattern, fail,
  });

  const decideTargetRead = createInstalledRowEffectTargetAuthorization({ownerOf, targetPlanOf, recipeOf, fail});

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
    ownerOf(member).owned.assertRequestFinalized?.(entry.request, effect.dispatchKeyCid(claim.key));
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
      (recipeOf(member)?.credentialOperations !== undefined ||
        recipeOf(member)?.physicalWrite !== undefined))) {
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
          const description = await describeMember({member, maxRows: entries[index].length, runInvocationCid,
            dispatchRequestCid: dispatches[index], label: `apply-${index}`,
            approval: reads[index]?.approval, signal, assertCurrent, physicalOperations, operationPhase, controlConstruction});
          assertCurrent?.();
          await owned.recheckRequests?.({member, entries: entries[index],
            current: description, controlConstruction, ...resourceFields(member)});
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
            current: fresh[index], read: reads[index], signal, assertCurrent, physicalOperations, operationPhase,
            runInvocationCid, dispatchRequestCid: dispatches[index]});
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
          dispatches[index], controlConstruction));
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
    const confirmResponse = async ({memberIndex, rowIndex, projected, current: description, signal}) => {
      const member = members[memberIndex];
      if (member === undefined) fail('InvalidInstalledRowEffectConfirmation');
      const {site, responseConfirmation} = ownerOf(member);
      if (responseConfirmation === undefined || projected?.kind !== 'provider-response' ||
          projected.providerEvidence === undefined) return projected;
      requireOpen();
      active++;
      try {
        const sourceIndex = dispatchIndexes[memberIndex]?.[rowIndex];
        const entry = entries[memberIndex]?.[sourceIndex];
        if (entry === undefined || !['apply', 'resume'].includes(operationPhase) ||
            typeof physicalOperations !== 'function') fail('InstalledEffectConfirmationPlanUnavailable');
        signal?.throwIfAborted();
        assertClaimedCurrent();
        // Effect approval/current cannot stand in for this separately scoped
        // read. Keep the original request/dispatch and already captured reply.
        const decision = await readDecision(member, responseConfirmation.resource,
          subjectCid, signal, assertClaimedCurrent);
        assertClaimedCurrent();
        const facts = {operation: responseConfirmation.operation, decision,
          resource: responseConfirmation.resource, runInvocationCid,
          dispatchRequestCid: dispatches[memberIndex], maxUses: 1};
        const originalAuthorization = controlConstruction === undefined ? site.issueReadGrant(facts)
          : (controlConstruction.grant ?? controlConstruction)(site, site.issueReadGrant, [facts]);
        assertClaimedCurrent();
        const confirmed = await physicalOperations({member, rowIndex: sourceIndex,
          phase: `${operationPhase}-confirm`, operation: responseConfirmation.operation,
          site, originalAuthorization,
          useId: `${dispatches[memberIndex]}-${operationPhase}-confirm-${subjectCid}-${rowIndex}`,
          resource: responseConfirmation.resource, purpose: 'read', runInvocationCid,
          dispatchRequestCid: dispatches[memberIndex], assertCurrent: assertClaimedCurrent, signal,
          invoke: context => Reflect.apply(responseConfirmation.request, responseConfirmation.receiver,
            [{member, request: entry.request, current: description, ...context,
              providerEvidence: projected.providerEvidence, signal, controlConstruction}])});
        assertClaimedCurrent();
        signal?.throwIfAborted();
        return confirmed === undefined ? projected : confirmed;
      } finally {active--;}
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
          const {owned, site, beforeSendCheck, updateWriteSlot} = ownerOf(member);
          const managedPlanRecipe = recipeOf(member);
          signal?.throwIfAborted();
          requireApproval(member, commits.get(scopeKey(member)));
          const ownedClaim = admitRow({applyPreview, memberIndex, rowIndex,
            claim, member, entry,
            previewRow: previewRows[memberIndex][sourceIndex]});
          await owned.recheckRequests?.({member, entries: [entry],
            current: now[memberIndex], controlConstruction, ...resourceFields(member)});
          assertCurrent?.();
          const grantFacts = {operation: installedEffectWriteOperation(owned, member, updateWriteSlot),
            decision: commits.get(scopeKey(member)), resource: member.resource,
            runInvocationCid, dispatchRequestCid: dispatches[memberIndex], subjectCid};
          const grantConstructor = managedPlanRecipe?.grantConstruction;
          const grant = controlConstruction === undefined ? site.issueEffectGrant(grantFacts)
            : grantConstructor !== undefined && grantConstructor.receiver === site &&
                grantConstructor.method === site.issueEffectGrant
              ? controlConstruction(site, grantConstructor.method, [grantFacts], grantConstructor.capacity)
              : (controlConstruction.grant ?? controlConstruction)(site, site.issueEffectGrant, [grantFacts]);
          const captured = await captureClaimedEffectResponse({ledger,
            claim: ownedClaim, requestCid: entry.requestCid,
            execute: () => {
              assertClaimedCurrent();
              const useId = `${dispatches[memberIndex]}-write-${subjectCid}-${rowIndex}`;
              if (managedPlanRecipe?.physicalWrite !== undefined) {
                if (typeof physicalOperations !== 'function') fail('InstalledEffectPhysicalPlanUnavailable');
                return physicalOperations({member, rowIndex: sourceIndex, phase: 'write',
                  operation: installedEffectWriteOperation(owned, member, updateWriteSlot), assertCurrent: assertClaimedCurrent, signal,
                  invoke: physicalOperation => owned.send({member, request: entry.request, current: now[memberIndex],
                    authorization: {...grant, useId}, credential: site.credential, signal, physicalOperation,
                    ...resourceFields(member)})});
              }
              if (managedPlanRecipe?.credentialOperations !== undefined) {
                if (typeof physicalOperations !== 'function') fail('InstalledEffectPhysicalPlanUnavailable');
                const send = () => physicalOperations({member, rowIndex: sourceIndex, phase: 'write',
                  operation: installedEffectWriteOperation(owned, member, updateWriteSlot), site, originalAuthorization: grant, useId,
                  resource: member.resource, purpose: 'effect', runInvocationCid,
                  dispatchRequestCid: dispatches[memberIndex], assertCurrent: assertClaimedCurrent, signal,
                  invoke: ({authorization, credential, callResource}) => {
                    const invocation = {member, request: entry.request, current: now[memberIndex],
                      authorization, credential, callResource, signal, ...resourceFields(member)};
                    return updateWriteSlot === undefined ? owned.send(invocation)
                      : invokeDeclaredRowUpdate(owned, invocation,
                        managedPlanRecipe.rowOperations[updateWriteSlot.operationIndex].operation, updateWriteSlot);
                  }});
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
                    : (controlConstruction.grant ?? controlConstruction)(site, site.issueReadGrant, [checkGrantFacts]);
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
          let projected = projectOwnedResponse(member, projectionFacts, controlConstruction);
          if (ownerOf(member).responseConfirmation !== undefined && projected?.kind === 'provider-response' &&
              projected.providerEvidence !== undefined) {
            projected = await confirmResponse({memberIndex, rowIndex, projected,
              current: now[memberIndex], signal});
          }
          const settled = settle({ledger, claim: ownedClaim, applyPreview,
            memberIndex, rowIndex, projected});
          return Object.freeze({claimed: true, physical: projected,
            ...(settled ?? {})});
        } finally { active--; }
      };
    };
    return {current, bindDispatch, confirmResponse, assertClaimedCurrent, retire};
  };

  const basePreflight = ({effects, members, requestScope, keys, limits}) => ({
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
  const footprintOf = (member, entries, controlConstruction) => {
    const {owned, connectorRegistration} = ownerOf(member);
    const facts = {member, entries};
    const constructor = recipeOf(member)?.footprintConstruction;
    const footprint = controlConstruction === undefined ? owned.footprint(facts)
      : constructor === undefined || controlConstruction.footprint === undefined
        ? controlConstruction(owned, owned.footprint, [facts])
        : controlConstruction.footprint(member.memberIndex, constructor.operationIndex,
          owned, owned.footprint, [facts]);
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
  function authorPreview({control, prepared, inputs, context, requestScope, limits, managedEffect,
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
      if (rows.length > limits.maxRowsPerMember || rowCount > limits.maxRows) fail('InstalledRowEffectRowLimit');
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
    const authored = managedEffect === undefined
      ? checked(moon.clientProgramAuthorEffectPreview(
        canonical, draft.run_identity_cid, authoringCid, requestScope,
        maxWireBytes, maxNodes, maxDepth, members.length, rowCount,
        limits.key.maxBytes, limits.key.maxNodes, limits.key.maxDepth))
      : checked(managedEffect.controlConstruction(moon, moon.clientProgramAuthorInstalledEffectPreview, [
        managedEffect.value, prepared, managedEffect.request, managedEffect.operationPlan,
        managedEffect.definitionOriginal.allowed, context.runDefinition, context.runInvocation,
        canonical, draft.run_identity_cid, authoringCid, requestScope,
        maxWireBytes, maxNodes, maxDepth, members.length, rowCount,
        limits.key.maxBytes, limits.key.maxNodes, limits.key.maxDepth]));
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
  // These three newly owned structural envelopes are final DATA for the
  // existing Ledger-family geometry. Keep original claim/opaque references;
  // do not freeze caller inputs or turn geometry into validation/currentness.
  const claimsOf = ({body, keys, entries, requestScope, unit, dispatches,
    unitCids, members, retentionId}) => Object.freeze(body.effects.map((member, memberIndex) => Object.freeze({
    claims: Object.freeze(orderedSourceIndexes(member).map(rowIndex => {
      const change = member.changes[rowIndex];
      const key = keys[memberIndex][rowIndex];
      const locator = effect.logicalItemLocator(requestScope,
        unit.programId, unit.stageId, member.effect_id,
        effect.dispatchKeyCorrelationWire(key), limits.locator.maxBytes,
        limits.key.maxBytes, limits.key.maxNodes, limits.key.maxDepth);
      const canonicalRequestCid = entries[memberIndex][rowIndex].requestCid;
      ownerOf(members[memberIndex]).owned.assertRequestFinalized?.(
        entries[memberIndex][rowIndex].request, effect.dispatchKeyCid(key));
      const basis = effect.ledgerBasis(requestScope, locator, key, unitCids[memberIndex],
        member.effect_member_preview_cid, change.row_preview_cid,
        canonicalRequestCid, recoveryCid(members[memberIndex], dispatches[memberIndex]),
        // A write without a provider idempotency key.
        'unavailable', member.capability_evidence_cid, retentionId);
      return {scope: requestScope, locator, key, basis,
        intentFingerprintCid: change.row_preview_cid, canonicalRequestCid};
    }))})));

  async function captureStage({control, store, execution, checkedHost,
    prepared, identity, plan, previewContext, unit, members,
    runInvocationCid, dispatches, requestScope, storedResults, signal,
    targetReads, contentOwner, managedEffect, updateTargetSelections, own, ownInputs, ownChildren, assertCurrent}) {
    assertCurrent?.();
    const limits = runLimits(managedEffect);
    const controlConstruction = managedEffect?.controlConstruction;
    if (managedEffect !== undefined && typeof controlConstruction !== 'function') fail('InstalledEffectControlRuntimeUnavailable');
    const dependencyOriginal = managedEffect === undefined ? undefined
      : installedEffectDependencyOriginal(controlConstruction,moon);
    if(dependencyOriginal!==undefined&&(dependencyOriginal.parent!==managedEffect.value||
        dependencyOriginal.prepared!==prepared||dependencyOriginal.request!==identity||
        dependencyOriginal.plan!==managedEffect.operationPlan))fail('ForeignInstalledEffectManagedRun');
    if (dependencyOriginal !== undefined && plan.sourceFreeInvocationOriginal !== undefined) {
      control.bindCheckedInstalledEffectSourceFreeInvocation(dependencyOriginal.parent,
        prepared, identity, dependencyOriginal.plan, checkedHost, plan.admission,
        plan.runDefinition, plan.sourceFreeInvocationOriginal);
      dependencyOriginal.current();
    }
    const inputs = dependencyOriginal === undefined
      ? checked(moon.clientProgramPinEffectSources(checkedHost, limits.maxPinnedResults))
      : checked(moon.clientProgramInstalledEffectDependencySourcesPin(dependencyOriginal.parent,
        prepared,identity,dependencyOriginal.plan,checkedHost,limits.maxPinnedResults));
    dependencyOriginal?.current();
    const commandWorkspaces = [];
    const commandKeys = [];
    const contentBorrowers = [];
    const contentArtifacts = [];
    const requestChildren = [];
    const memberCaptures = [];
    const proposals = [], currents = [], rowsOf = [], observations = [];
    let sourceSet;
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
    if (managedEffect !== undefined) {
      if (typeof controlConstruction.retainInputs !== 'function') fail('InstalledEffectOperationRuntimeUnavailable');
      controlConstruction.retainInputs(inputs);
    }
    memberCaptures.length = members.length;
    // Reserve each original member's capture body before export can append
    // proposal rows, parse their values or issue canonical CREATE inventory.
    // These SAME arrays and children survive through ordinary route retirement.
    for (const member of members) {
      const recipe = recipeOf(member);
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
          const observed = selected.inputExtent !== undefined;
          if (observed && recipe.requestConstruction?.inputExtent === undefined) fail('InstalledEffectCaptureConstructionUnavailable');
          original = (observed ? prepareInstalledEffectCaptureChild : prepareInstalledEffectRequestChild)({run: managedEffect,
            memberIndex: member.memberIndex, perRow: false, rowIndex: 0,
            operationIndex: selected.operationIndex, operation,
            ...(observed ? {inputExtent: () => controlConstruction(undefined, selected.inputExtent,
              [proposals[member.memberIndex]])} : {}),
            construct: observed ? () => {
              const construct = rowsOf[member.memberIndex];
              if (typeof construct !== 'function') fail('InstalledEffectCaptureConstructionUnavailable');
              return construct();
            } : () => recoveryEntry === undefined ? undefined :
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
      dependencyConstruction: controlConstruction,
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
            rowIndex >= limits.maxRowsPerMember || proposalCount >= limits.maxRows) {
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
      const {owned, updateWriteSlot} = ownerOf(member);
      assertCurrent?.();
      if (proposals[index].length === 0) fail('InstalledRowEffectEmptyMember');
      const description = await describeMember({member, maxRows: proposals[index].length, runInvocationCid,
        dispatchRequestCid: dispatches[index], label: `preview-${index}`,
        approval: reads[index]?.approval, signal, assertCurrent, physicalOperations, operationPhase: 'capture', controlConstruction});
      assertCurrent?.();
      currents.push(description);
      const contentOf = member.kind !== 'command' ? undefined : commandContentBorrower({
        control, prepared, inputs, memberIndex: member.memberIndex,
        artifact: sourceSet.members[index].payload.localResultArtifact,
        limits, assertCurrent});
      if (contentOf !== undefined) contentBorrowers.push(contentOf);
      let memberEntries;
      const constructRows = async () => {
        const selectedCreate = member.kind === 'create'
          ? prepareInstalledCreateRows(moon, proposals[index], limits.preview) : undefined;
        const rows = selectedCreate?.rows ?? proposals[index].map(proposal => {
          const changes = JSON.parse(proposal.changesWire);
          return {value: changes.value, selector: targeted(member.kind)
            ? JSON.parse(proposal.selectorWire) : undefined};
        });
        const createRows = selectedCreate?.createRows;
        let entries;
        const recipe = recipeOf(member);
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
            if (rowIndex >= limits.maxRowsPerMember) fail('InstalledRowEffectRowLimit');
            const context = {member, value: row.value, selector: row.selector,
              ...(member.kind === 'create' ? {createRowIdentity: createRows[rowIndex].identity,
                proposalWire: row.proposalWire} : {}),
              current: description, content: commandContentRow(contentOf, rowIndex), signal,
              ...(contentOwner === undefined ? {} : {contentOwner}),
              ...resourceFields(member),
              ...(guarded(member.kind) ? {rowIndex, assertCurrent,
                ...(updateWriteSlot === undefined ?
                  {authorizationForRow: () => reads[index].authorizationForRow(rowIndex)} : {})} :
                {authorizationForRow: reads[index]?.authorizationForRow})};
            const preparedRequest = await prepareInstalledRowCaptureChild({children: requestChildren,
              create: () => constructor === undefined ? owned.prepareRequestChild(context) :
                (owned.prepareRequestChild === undefined ? prepareInstalledEffectRequestChild :
                  prepareInstalledEffectOwnedRequestChild)({run: managedEffect, memberIndex: member.memberIndex,
                  rowIndex, operationIndex: constructor.operationIndex,
                  operation: recipe.rowOperations[constructor.operationIndex].operation,
                  ...(constructor.inputExtent === undefined ? {} : {inputExtent: () =>
                    controlConstruction(undefined, constructor.inputExtent, [proposals[index][rowIndex]])}),
                  ...(owned.prepareRequestChild === undefined
                    ? {construct: () => owned.prepareRequest(context)}
                    : {constructChild: () => owned.prepareRequestChild(context)}),
                  requestsRetired: retireRequestAliases}),
              assertCurrent, signal});
            // The Native constructor has returned, but requestFacts can still
            // parse its returned JSON. Use the SAME existing control frame for
            // that synchronous projection, before publishing the row entry.
            preparedEntries.push(controlConstruction === undefined
              ? requestEntry(member, row, preparedRequest)
              : constructor === undefined || controlConstruction.requestProjection === undefined
                ? controlConstruction(undefined, requestEntry, [member, row, preparedRequest])
                : controlConstruction.requestProjection(member.memberIndex, constructor.operationIndex, rowIndex,
                  undefined, requestEntry, [member, row, preparedRequest]));
          }
          entries = Object.freeze(preparedEntries);
        } else entries = requestsOf(member, rows, description, contentOf, createRows);
        memberEntries = entries;
        if (member.kind === 'create') {
          // Reuse the SAME Common inventory for Preview and requests.
          for (const [row, entry] of entries.entries()) {
            createRows[row].entry = entry;
            Object.freeze(createRows[row]);
          }
          rowsOf[index] = Object.freeze(createRows);
          observations[index] = undefined;
          return;
        }
        if (member.kind === 'command') {
          await owned.recheckRequests({member, entries, current: description, controlConstruction, ...resourceFields(member)});
          assertCurrent?.();
          rowsOf[index] = Object.freeze(entries.map(entry => Object.freeze({entry})));
          observations[index] = undefined;
          return;
        }
        const observed = await observeRows({member, entries,
          current: description, read: reads[index], signal, assertCurrent, physicalOperations, operationPhase: 'capture',
          runInvocationCid, dispatchRequestCid: dispatches[index]});
        assertCurrent?.();
        observations[index] = observed;
        rowsOf[index] = Object.freeze(entries.map((entry, row) => Object.freeze({
          entry, state: observed[row].state, versionCid: observed[row].versionCid,
          before: observed[row].before})));
      };
      const observedCapture = recipeOf(member)?.captureConstruction?.inputExtent !== undefined;
      if (observedCapture) {
        // The proposal Strings are borrowed from the completed original Read.
        // Its same constructor now funds every native map/parse/request below
        // BEFORE entry and joins the actual asynchronous task before completion.
        rowsOf[index] = async () => {
          await constructRows();
          return owned.recoveryEntry?.({member, current: description, entries: memberEntries});
        };
        observations[index] = await memberCaptures[index].prepare();
      } else await constructRows();
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
      dispatches[index], controlConstruction));
    const footprints = members.map((member, index) =>
      footprintOf(member, entries[index], controlConstruction));
    if (sourceSet.dependencies !== undefined) {
      retainPinnedEffectDependencyPayloads({sources: sourceSet, execution,
        store, storedResults, control, runDefinition: plan.runDefinition});
    }
    const payloads = sourceSet.members.map(member => member.payload);
    const preview = authorPreview({control, prepared, inputs, limits, managedEffect,
      context: {runDefinition: previewContext.runDefinition,
        runInvocation: previewContext.runInvocation,
        compiledPlan: previewContext.compiledPlan,
        storeAuthorityCid: store.storeAuthorityCid},
      requestScope, members, rowsOf, capabilities, footprints, payloads});
    const body = managedEffect === undefined ? JSON.parse(preview.wire)
      : managedEffect.controlConstruction.parsePreview(preview.wire);
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
    let applyPreview;
    if (members.some(member => ownerOf(member).owned.finalizeRequest !== undefined)) {
      applyPreview = effect.admitPreviewIdentity(preview.wire,
        body.run_identity_cid, preview.authoringCid, requestScope,
        preview.keys, limits.preview.maxWireBytes, limits.preview.maxNodes,
        limits.preview.maxDepth);
      const finalized = [];
      for (const [memberIndex, member] of members.entries()) {
        const {owned} = ownerOf(member);
        const recipe = recipeOf(member);
        if (owned.finalizeRequest === undefined) {finalized.push(entries[memberIndex]); continue;}
        const constructor = recipe?.requestFinalization;
        const operationIndex = constructor?.operationIndex;
        if (managedEffect?.runtime !== moon || managedEffect.prepared !== prepared ||
            managedEffect.request !== identity || !Number.isSafeInteger(operationIndex) ||
            operationIndex < 0 || operationIndex >= recipe.rowOperations.length ||
            operationIndex === recipe.requestConstruction?.operationIndex) {
          fail('InstalledEffectRequestFinalizationPlanUnavailable');
        }
        const rows = [];
        for (const [rowIndex, original] of entries[memberIndex].entries()) {
          const requestTag = effect.dispatchKeyCid(preview.keys[memberIndex][rowIndex]);
          const preparedRequest = await prepareInstalledRowCaptureChild({children: requestChildren,
            create: () => prepareInstalledEffectRequestChild({run: managedEffect,
              memberIndex: member.memberIndex, rowIndex, operationIndex,
              operation: recipe.rowOperations[operationIndex].operation,
              construct: () => owned.finalizeRequest({request: original.request, requestTag}),
              requestsRetired: retireRequestAliases}), assertCurrent, signal});
          const entry = requestEntry(member, {value: original.value, selector: original.target}, preparedRequest);
          owned.assertRequestFinalized(entry.request, requestTag);
          rows.push(entry);
        }
        finalized.push(Object.freeze(rows));
      }
      entries = Object.freeze(finalized);
    }
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
      const observedCapture = recipeOf(member)?.captureConstruction?.inputExtent !== undefined;
      const entry = observedCapture ? observations[index] : retained === undefined
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
      applyPreview ??= effect.admitPreviewIdentity(preview.wire,
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
        ...basePreflight({effects: body.effects, members, requestScope, limits,
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
    const members = membersOf(prepared, unit, runLimits(facts.managedEffect).maxMembers);
    bindRunResources(facts, members);
    const updateTargetSelections = facts.updateTargetSelections;
    const assertCurrent = selectionFence(facts, members, unit.stageIndex, updateTargetSelections);
    const runInvocationCid = plan.invocation.identity;
    const dispatches = members.map(member =>
      memberDispatch(runInvocationCid, member));
    const requestScope = moon.clientProgramEffectRequestScope(prepared,
      identity);
    const resultProgress = facts.managedEffect === undefined ? undefined
      : prepareInstalledEffectResultProgress(facts.managedEffect, checkedHost);
    const storedResults = await storeCompletedRunResultSet({execution,
      store, control, runDefinition: plan.runDefinition,
      invocation: plan.invocation, results: plan.results,
      outputLimits: plan.outputLimits, contractLimits: plan.contractLimits,
      signal, resultProgress});
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
  const recoveredMembers = (body, provider, selected, maxMembers) => {
    if (body.effects.length > maxMembers || body.effects.length !== provider.members.length) {
      fail('InstalledEffectContinuationMismatch');
    }
    return Object.freeze(body.effects.map((member, index) => {
      const saved = provider.members[index];
      const owner = selectOwner(runtimeTupleFromFields({1: member.effect_id, 2: member.effect_kind, 3: member.target, 4: member.mapping, 5: member.resolved_mapping_contract_cid}));
      const {installed, installedCommands} = owner;
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
        if (command === undefined || !installedEffectKinds(owner).includes('command')) {
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
      if (mapping === undefined || !installedEffectKinds(owner).includes(member.effect_kind)) {
        if (selected) selectionChanged();
        fail('InstalledRowEffectMappingNotInstalled');
      }
      return retainMember(owner, {effectId: member.effect_id, memberIndex: index,
        kind: member.effect_kind, mapping, resource: mapping.resource});
    }));
  };

  // Repeatable checked DATA comparison, never a request constructor or send
  // admission. Hot observation must recheck the actual current Ledger claims
  // against the SAME still-backed requests and approved original Preview.
  const validateRecoveredEntries = ({members, body, recorded}, entries) => {
    if (!Array.isArray(entries) || entries.length !== members.length) fail('InstalledEffectContinuationMismatch');
    members.forEach((member, index) => {
      const changes = body.effects[index].changes, claims = recorded.members[index]?.claims ?? [];
      const rows = entries[index], sourceIndexes = orderedSourceIndexes(body.effects[index]);
      const claimBySource = new Map(sourceIndexes.map((sourceIndex, dispatchIndex) =>
        [sourceIndex, claims[dispatchIndex]]));
      if (!Array.isArray(rows) || rows.length !== changes.length || claims.length !== changes.length) {
        fail('InstalledEffectContinuationMismatch');
      }
      rows.forEach((entry, row) => {
        if (entry.requestCid !== claimBySource.get(row)?.canonicalRequestCid ||
            !sameEffectValue(member.kind, entry.value, approvedValue(member.kind, changes[row])) ||
            (targeted(member.kind) && !sameValue(entry.target, changes[row].target_row_identity))) {
          fail('ForeignInstalledRowEffectRequest');
        }
      });
    });
  };

  // Each recovered row's request, rebuilt from its approved Preview row (a
  // create) or from the provider's retained data (an update), and held to
  // exactly the request its durable claim names, the value the Preview
  // approved and, for an update, the Preview's target.
  const recoveredEntries = ({members, body, durable, recorded, maxRows,
    previewWire, runInvocationCid, dispatches, requestTags, controlConstruction, reserveRecoveryInput}) => {
    const restore = (owned, method, facts) => controlConstruction === undefined || owned.finalizeRequest === undefined
      ? Reflect.apply(method, owned, [facts]) : controlConstruction(owned, method, [facts]);
    const rebuilt = singular?.owned.recoverRequests === undefined ? undefined :
      restore(singular.owned, singular.owned.recoverRequests, {durable, recorded, previewWire, body, maxRows,
        members, runInvocationCid, dispatches, requestTags, reserveRecoveryInput,
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
        const recovered = restore(owner.owned, owner.owned.recoverMemberRequests, {durable, recorded, maxRows,
          previewWire, body, memberIndexes, members, runInvocationCid, dispatches, requestTags, reserveRecoveryInput,
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
      const changes = body.effects[index].changes;
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
      return Object.freeze(rows);
    });
    validateRecoveredEntries({members, body, recorded}, entries);
    return {entries: Object.freeze(entries), currents: Object.freeze(currents)};
  };

  // Every original member's native recovery constructor is backed BEFORE
  // the first provider rebuild. Nest only our frozen synchronous native body
  // constructors: all original workspaces coexist while the whole-Set vendor
  // recovery runs once. Cleanup stays in the SAME already-retained ledger
  // owner's requestChildren; no physical occurrence or grant is reconstructed.
  const prepareRecoveredEntries = ({managedEffect, requestChildren, retireRequestAliases,
    assertCurrent, signal, ...facts}) => {
    if (managedEffect === undefined) return recoveredEntries(facts);
    if (managedEffect.runtime !== moon || managedEffect.closed) fail('ForeignInstalledEffectManagedRun');
    const controlConstruction = managedEffect.controlConstruction;
    if (typeof controlConstruction !== 'function') fail('InstalledEffectControlRuntimeUnavailable');
    let input = managedEffect.recoveredRequestInput;
    if (input === undefined) {
      // This input remains on the SAME Plan's original constructor backing.
      // The transient recovery stage borrows it; closing that stage is not
      // retirement of a still-needed hot-reconciliation request body.
      input = controlConstruction(undefined, () => ({
        body: facts.body, previewWire: facts.previewWire, members: facts.members,
        connectorRecovery: facts.durable.connectorRecovery, result: undefined,
        children: [], borrowers: 0, retiring: false, draining: false, failed: false, failure: undefined,
        retire() {
          if (this.borrowers !== 0 || this.draining) return false;
          this.draining = true;
          try {
            this.retiring = true;
            this.result = this.body = this.members = this.connectorRecovery = undefined;
            for (const child of this.children) {
              if (child.status().pending && child.release() !== true) return false;
            }
            this.children.length = 0;
            this.failure = undefined;
            return true;
          } finally {this.draining = false;}
        },
      }), []);
      managedEffect.recoveredRequestInput = input;
      try {
        const calls = [], growers = new Map(), members = facts.members;
        const reserveRecoveryInput = (memberIndex, metadata) => {
          const grow = growers.get(memberIndex);
          if (typeof grow !== 'function') fail('InstalledEffectRecoveryConstructionUnavailable');
          grow(metadata);
        };
        for (const [index, member] of members.entries()) {
          const recipe = recipeOf(member), selected = recipe?.recoveryConstruction;
          const operation = selected === undefined ? undefined : recipe.memberOperations[selected.operationIndex]?.operation;
          if (operation === undefined || selected.operationIndex === recipe.captureConstruction?.operationIndex) {
            fail('InstalledEffectRecoveryConstructionUnavailable');
          }
          const original = prepareInstalledEffectRequestChild({run: managedEffect,
            memberIndex: member.memberIndex, perRow: false, rowIndex: 0,
            operationIndex: selected.operationIndex, operation,
            ...(selected.inputExtent === undefined ? {} : {inputExtent: () =>
              controlConstruction(undefined, selected.inputExtent,
                [facts.previewWire, facts.durable.connectorRecovery, member.memberIndex])}),
            construct: grow => {
              if (selected.inputExtent !== undefined) growers.set(member.memberIndex, metadata =>
                grow(controlConstruction(undefined, selected.inputExtent,
                  [facts.previewWire, facts.durable.connectorRecovery, member.memberIndex, metadata])));
              try {
                return index + 1 === members.length
                  ? recoveredEntries({...facts, reserveRecoveryInput}) : calls[index + 1]();
              } finally {growers.delete(member.memberIndex);}
            },
            requestsRetired: () => input.retiring && input.borrowers === 0 && input.result === undefined});
          // The raw selected constructor is synchronous. Retain before any
          // subsequent fence/failure; only final control retirement releases it.
          input.children.push(original);
          original.checkOriginal();
          const prepare = original.prepare;
          calls.push(() => Reflect.apply(prepare, original, []));
        }
        signal?.throwIfAborted();assertCurrent?.();
        input.result = calls[0]();
        signal?.throwIfAborted();assertCurrent?.();
      } catch (cause) {input.failed = true;input.failure = cause;throw cause;}
    } else {
      if (input.retiring) fail('InstalledEffectRecoveryInputRetired');
      if (input.failed) throw input.failure;
      if (input.result === undefined) fail('InstalledEffectRecoveryInputPending');
      // Actual admitted Preview and original installed member owners remain
      // mandatory. A matching request CID, copied graph or new installation
      // cannot substitute for the original input or its physical backing.
      controlConstruction(undefined, () => {
        if (input.body !== facts.body || input.previewWire !== facts.previewWire ||
            input.members.length !== facts.members.length ||
            !sameValue(input.connectorRecovery, facts.durable.connectorRecovery) ||
            input.members.some((member, index) => ownerOf(member) !== ownerOf(facts.members[index]) ||
              member.kind !== facts.members[index].kind || member.memberIndex !== facts.members[index].memberIndex ||
              member.effectId !== facts.members[index].effectId || member.mapping !== facts.members[index].mapping ||
              member.command !== facts.members[index].command)) fail('ForeignInstalledRowEffectRequest');
        for (const child of input.children) {
          if (child.status().pending !== true) fail('InstalledEffectRecoveryInputRetired');
          child.checkOriginal();
        }
        facts.members.forEach((member, index) => {
          for (const entry of input.result.entries[index]) {
            if (entry.requestCid !== ownerOf(member).owned.requestCid(entry.request)) {
              fail('ForeignInstalledRowEffectRequest');
            }
          }
        });
        validateRecoveredEntries(facts, input.result.entries);
      }, []);
    }
    signal?.throwIfAborted();assertCurrent?.();
    if (input.borrowers !== 0) fail('InstalledEffectRecoveryInputBorrowed');
    let returned = false, borrowed = input, retireAliases = retireRequestAliases;
    const release = () => {
      if (returned) return;
      if (retireAliases() !== true) return false;
      returned = true;
      borrowed.borrowers--;
      borrowed = retireAliases = undefined;
    };
    // Keep the original borrow in the existing stage cleanup bag before its
    // value escapes. Only its actual alias/route retirement returns the borrow.
    input.borrowers++;
    requestChildren.push({prepared: Object.freeze({release, retry: release,
      status: () => Object.freeze({pending: !returned})})});
    return input.result;
  };

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
    const body = managedEffect === undefined ? JSON.parse(previewWire)
      : managedEffect.controlConstruction.parsePreview(previewWire, true);
    const limits = runLimits(managedEffect);
    const members = recoveredMembers(body, provider, selected, limits.maxMembers);
    bindRunResources(facts, members);
    const assertCurrent = selectionFence(facts, members, provider.stage_index, updateTargetSelections);
    const runInvocationCid = body.invocation_cid;
    const dispatches = members.map(member =>
      memberDispatch(runInvocationCid, member));
    if (dispatches.some((dispatch, index) =>
      dispatch !== provider.members[index].dispatch_request_cid)) {
      fail('InstalledEffectContinuationMismatch');
    }
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
      // The original admitted Preview, compiled Run and Request supply the
      // cold row inventory before recovered member request construction.
      // The existing synchronous control frame owns current/reentry/failure.
      controlConstruction.retainRecoveredInputs(control,
        managedEffect.definitionOriginal.allowed, managedEffect.definitionOriginal.definition,
        durable.invocation, preview);
    }
    const admitted = control.effectComputationPreviewLedgerIdentity(preview);
    const keys = managedEffect === undefined
      ? effect.recoveredPreviewKeys(admitted, requestScope,
        members.length, limits.maxRows, limits.maxWork, limits.key.maxBytes,
        limits.key.maxNodes, limits.key.maxDepth)
      : control.recoverInstalledEffectPreviewKeys(managedEffect.value, managedEffect.prepared,
        managedEffect.request, managedEffect.operationPlan, managedEffect.definitionOriginal.allowed,
        managedEffect.definitionOriginal.definition, durable.invocation, preview, requestScope,
        members.length, limits.maxRows, limits.maxWork, limits.key.maxBytes,
        limits.key.maxNodes, limits.key.maxDepth, controlConstruction);
    let recoveredRows = 0, recoveredMemberRows = 0;
    for (const member of body.effects) {
      if (!Array.isArray(member.changes)) fail('InstalledEffectContinuationMismatch');
      recoveredRows += member.changes.length;
      recoveredMemberRows = Math.max(recoveredMemberRows, member.changes.length);
      if (member.changes.length > limits.maxRowsPerMember || recoveredRows > limits.maxRows) {
        fail('InstalledRowEffectRowLimit');
      }
    }
    // Run limits remain rejection ceilings. Ledger recovery consumes this
    // verified whole cohort; each native member constructor consumes only the
    // widest actual member. Neither receiver inherits the Run's policy size.
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
        // The recovered Content child owns the original physical writer.
        // Let it acknowledge close before the operation token checks that
        // same writer; neither pending child may release the parent Ledger.
        for (const child of recoveryChildren) await child.release();
        for (const child of requestChildren) {
          const retry = child.recoveryReleaseAttempted === true;
          child.recoveryReleaseAttempted = true;
          await (retry ? child.prepared.retry() : child.prepared.release());
        }
        if (requestsPending() || recoveryPending()) return false;
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
        nodeId: provider.stage_id, maxRows: recoveredRows,
        maxWork: limits.maxWork}, keys);
      assertCurrent?.();
      ({entries, currents} = prepareRecoveredEntries({members, body, durable, maxRows: recoveredMemberRows,
        recorded, previewWire, runInvocationCid, dispatches,
        requestTags: keys.map((rows, index) => ownerOf(members[index]).owned.finalizeRequest === undefined
          ? undefined : rows.map(key => effect.dispatchKeyCid(key))), controlConstruction,
        managedEffect, requestChildren, retireRequestAliases, assertCurrent, signal}));
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
              currents[index], runInvocationCid, dispatches[index], controlConstruction);
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
          preview: ledgerPreview, signal: recoverySignal = signal}) => {
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
                let retainedOutcome = false;
                const recovery = await recoverProjectedEffectResponse({ledger,
                  claims: ownedClaim, commonMoon: moon,
                  expectedRequestCid: entry.requestCid,
                  authorizeEvidenceRead: async () => true,
                  projectStored: stored => {
                    assertRecoveredCurrent();
                    const {responseConfirmation} = ownerOf(members[memberIndex]);
                    // Presence alone is not a terminal fact. Reuse the
                    // existing complete receipt/current/history admission and
                    // original CAS continuation, never another provider read
                    // to replace an already recorded outcome or lost COMMIT.
                    if (responseConfirmation !== undefined && ledger.readClaimedOutcome(ownedClaim) !== undefined) {
                      ledger.commitAdmittedRowOutcome({claim: ownedClaim, preview: ledgerPreview,
                        memberIndex, previewRowIndex: rowIndex});
                      retainedOutcome = true;
                      return undefined;
                    }
                    const projectionFacts = {member: members[memberIndex], memberIndex, rowIndex,
                      preview: ledgerPreview, request: entry.request, current: currents[memberIndex],
                      observation: Object.freeze({useCid: stored.credentialUseCid,
                        statusCode: stored.statusCode, body: stored.responseBytes}), headers: undefined};
                    return projectOwnedResponse(members[memberIndex], projectionFacts, controlConstruction);
                  }});
                assertRecoveredCurrent();
                if (retainedOutcome) continue;
                let projected = recovery.recovered;
                if (ownerOf(members[memberIndex]).responseConfirmation !== undefined && projected?.kind === 'provider-response' &&
                    projected.providerEvidence !== undefined) {
                  projected = await route.confirmResponse({memberIndex, rowIndex, projected,
                    current: currents[memberIndex], signal: recoverySignal});
                  assertRecoveredCurrent();
                }
                settle({ledger, claim: ownedClaim, applyPreview: ledgerPreview,
                  memberIndex, rowIndex, projected});
              }
            }
          } finally {reconciling--;}
        };
        return Object.freeze({preview, computation, storedResults,
          ...(requestedStop === undefined ? {} : {requestedStop, assertRequestedStopCurrent}),
          apply: {moon, store, publicationControl: control, computation,
            preview, ledger, requestScope, programId: provider.program_id,
            nodeId: provider.stage_id, maxRows: recoveredRows,
            maxFrontierWork: limits.maxFrontierWork,
            maxRecoveryWork: limits.maxWork,
            keyLimits: {...limits.key, maxWork: limits.maxWork},
            reconcileStoredResponses,
            refreshPreflight: ({signal: refreshSignal} = {}) => route.current({
              signal: refreshSignal, preflight: basePreflight({
                effects: body.effects, members, requestScope, limits})}),
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
          assertCurrent, limits, ...resourceFields(members[memberIndexes[0]]),
          managedContext: managedEffect});
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
  const {installed, installedCommands, connectorId, bindingCid,
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
      [...new Set(installedEffectKinds(singular))].filter(kind =>
        mapping.rules.some(rule => rule.effect_kind === kind)).map(kind =>
        Object.freeze({kind, target: mapping.target,
          mappingRef: mapping.mappingRef, mappingCid: mapping.mappingCid}))),
    ...(!installedEffectKinds(singular).includes('command') ? [] : installedCommands.map(command =>
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
