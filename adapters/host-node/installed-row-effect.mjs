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
import {installedEffectSavedControlEntryLimit, installedEffectSavedControlResponseLimit, installedEffectRecipeForControlEntryLimit, captureInstalledEffectPlanRecipe, prepareInstalledEffectRequestChild, prepareInstalledEffectCredentialChild} from './installed-effect-plan.mjs';
import {installedRowCredentialOperationSite} from './installed-row-source.mjs';
import {createHash} from 'node:crypto';
import {types as nodeTypes} from 'node:util';
import {createInstalledRowEffectDriverControls} from './installed-row-effect-driver.mjs';
import {createInstalledRowEffectConstruction} from './installed-row-effect-construction.mjs';
import {createInstalledRowEffectClaims, createInstalledRowEffectRecoveryEntries} from './installed-row-effect-claims.mjs';
import {createInstalledRowEffectRecoveredMembers, createInstalledRowEffectRecoveryBacking} from './installed-row-effect-recovery-backing.mjs';
import {createInstalledRowEffectPhysicalRoute} from './installed-row-effect-physical-route.mjs';
import {createInstalledRowEffectRecovery} from './installed-row-effect-recovery.mjs';
import {createInstalledRowEffectCaptureEntry} from './installed-row-effect-capture-entry.mjs';
import {prepareInstalledRowEffectCaptureInputs} from './installed-row-effect-capture-inputs.mjs';
import {createInstalledRowEffectCaptureRows} from './installed-row-effect-capture-rows.mjs';
import {createInstalledRowEffectCaptureValues} from './installed-row-effect-capture-values.mjs';
import {createInstalledRowEffectFootprint, createInstalledRowEffectPreview,
  createInstalledRowEffectPreviewContext} from './installed-row-effect-preview.mjs';
import {approvalOf, approvedValue, createInstalledRowEffectApproval, createInstalledRowEffectCommit} from './installed-row-effect-commit.mjs';
import {createInstalledRowEffectPhysicalOperation, createInstalledRowEffectReadChild,
  createInstalledRowEffectReadOperations} from './installed-row-effect-physical-read.mjs';
import {createInstalledRowEffectCapability, createInstalledRowEffectReadDecision,
  createInstalledRowEffectTargetAuthorization} from './installed-row-effect-authorization.mjs';
import {createInstalledRowEffectMembers, createInstalledRowEffectRequests} from './installed-row-effect-members.mjs';
import {createInstalledRowEffectRunControls, createInstalledRowEffectRunLimits} from './installed-row-effect-run-controls.mjs';
import {createInstalledRowEffectOwnerProjection} from './installed-row-effect-owner-projection.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {issueCompletedEffectfulComputationEvidence} from '../host-common/completed-run-publication.mjs';
import {canonicalJson} from './local-account-config.mjs';
import {canonicalJson as canonicalValueJson} from
  '../../packages/sdk/host-port.mjs';
import {preparePinnedEffectSourceHoldings, preparePinnedEffectSourceSet,
  retainPinnedEffectDependencyPayloads} from './effect-input-export.mjs';
import {verifyPinnedEffectPlan} from './effect-plan-verify.mjs';
import {openInstalledEffectLedger} from './installed-effect-ledger-open.mjs';
import {recoverProjectedEffectResponse} from './effect-response-recovery.mjs';
import {localContractLimits} from './local-values-plan.mjs';
import {prepareInstalledRowCaptureChild} from './installed-row-capture-cleanup.mjs';
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

const {commandContentBorrower, commandContentRow, prepareInstalledCreateRows} = createInstalledRowEffectCaptureValues(fail);

const exportLimits = output => [output.maxResultFields,
  output.maxResultMappingWork, output.maxResultOrderWork,
  output.maxResultWorkspaceEntries, output.maxRows, output.maxValueNodes,
  output.maxValueTextBytes, output.maxValueDepth, output.maxValueWork,
  output.maxWireBytes, output.maxWireNodes, output.maxWireDepth,
  output.maxColumns, output.maxOrderWork, output.maxLogicalWireBytes,
  output.maxLogicalWireNodes, output.maxLogicalWireDepth,
  output.maxSchemaFields, output.maxSchemaBytes, output.maxSchemaNodes,
  output.maxSchemaDepth, output.maxBatchBytes];

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

  const {scopeKey, commitDecisions, settle, admitRow} = createInstalledRowEffectCommit({
    moon, effect, ownerOf, sameEffectValue, sameValue, targeted, fail,
  });
  const requireApproval = createInstalledRowEffectApproval(text);

  const physicalRoute = createInstalledRowEffectPhysicalRoute({
    recipeOf, ownerOf, fail, guarded, decideTargetRead, describeMember, resourceFields, checkRows,
    observeRows, admitCapability, routeOf, readDecision, commitDecisions, requireApproval, scopeKey,
    admitRow, installedEffectWriteOperation, projectOwnedResponse, settle,
  });

  const {basePreflight, continuationOf} = createInstalledRowEffectPreviewContext({
    moon, contractCidOf, guarded, singular, ROUTING_VERSION, ownerOf, installationFacts,
  });
  const footprintOf = createInstalledRowEffectFootprint({
    ownerOf, recipeOf, footprintKinds, cidPattern, text, cid, contractCidOf, fail,
  });
  const authorPreview = createInstalledRowEffectPreview({moon, permissionsOf, pendingCid, fail});

  const {orderedSourceIndexes, claimsOf} = createInstalledRowEffectClaims({effect, limits, ownerOf, recoveryCid, fail});

  async function captureStage({control, store, execution, checkedHost,
    prepared, identity, plan, previewContext, unit, members,
    runInvocationCid, dispatches, requestScope, storedResults, signal,
    targetReads, contentOwner, managedEffect, updateTargetSelections, own, ownInputs, ownChildren, assertCurrent}) {
    let sourceSet, entries, route;
    const {limits, controlConstruction, inputs, commandKeys, contentBorrowers, requestChildren, memberCaptures,
      proposals, currents, rowsOf, observations, publishedTargets, physicalOperations, retireRequestAliases,
      childrenPending, releaseInputs, sourceExport} = prepareInstalledRowEffectCaptureInputs({
      moon, control, store, execution, checkedHost, prepared, identity, plan, members, runInvocationCid, signal,
      managedEffect, assertCurrent, ownInputs, ownChildren, runLimits, prepareCredentialOperation, ownerOf, recipeOf,
      singular, cid, exportLimits, preparePinnedEffectSourceSet, fail,
      readSourceSet: () => sourceSet,
      readEntries: () => entries,
      retireRoute() {
        if (route !== undefined && !route.retire()) return false;
        entries = undefined;
        return true;
      },
    });
    sourceSet = await sourceExport;
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
      const {constructRows, recoverObservedRows} = createInstalledRowEffectCaptureRows({
        member, index, owned, updateWriteSlot, description, contentOf, moon, proposals, limits, recipeOf,
        managedEffect, prepared, identity, reads, controlConstruction, runInvocationCid, dispatches, signal,
        assertCurrent, contentOwner, resourceFields, physicalOperations, guarded, targeted, requestChildren,
        rowsOf, observations, prepareInstalledCreateRows, commandContentRow, requestEntry, requestsOf,
        observeRows, retireRequestAliases, fail,
      });
      const observedCapture = recipeOf(member)?.captureConstruction?.inputExtent !== undefined;
      if (observedCapture) {
        // The proposal Strings are borrowed from the completed original Read.
        // Its same constructor now funds every native map/parse/request below
        // BEFORE entry and joins the actual asynchronous task before completion.
        rowsOf[index] = recoverObservedRows;
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

  const prepareCaptured = createInstalledRowEffectCaptureEntry({
    moon, assertPrepared, installedRowEffectUnit, membersOf, runLimits, bindRunResources, selectionFence,
    memberDispatch, captureStage, fail,
  });

  const recoveredMembers = createInstalledRowEffectRecoveredMembers({
    singular, selectOwner, sameValue, installationFacts, selectionChanged, installedEffectKinds, retainMember, fail,
  });

  const {validateRecoveredEntries, recoveredEntries} = createInstalledRowEffectRecoveryEntries({
    owners, singular, ownerOf, orderedSourceIndexes, resourceFields, entryOf, sameEffectValue, sameValue, targeted, fail,
  });

  const prepareRecoveredEntries = createInstalledRowEffectRecoveryBacking({
    moon, recipeOf, ownerOf, sameValue, prepareInstalledEffectRequestChild, recoveredEntries, validateRecoveredEntries, fail,
  });

  const prepareRecovered = createInstalledRowEffectRecovery({
    moon, localContractLimits, ROUTING_VERSION, singular, owners, ownerOf, text, selectionChanged, runLimits,
    recoveredMembers, bindRunResources, selectionFence, memberDispatch, effect, openLedger, prepareCredentialOperation,
    prepareRecoveredEntries, admitCapability, orderedSourceIndexes, physicalRoute, admitRow, projectOwnedResponse,
    recoverProjectedEffectResponse, settle, basePreflight, scopes, resourceFields, fail,
  });

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
