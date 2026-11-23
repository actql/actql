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
import {createInstalledRowEffectCaptureStage} from './installed-row-effect-capture-stage.mjs';
import {createInstalledRowEffectCaptureValues} from './installed-row-effect-capture-values.mjs';
import {createInstalledRowEffectFootprint, createInstalledRowEffectPreview,
  createInstalledRowEffectPreviewContext} from './installed-row-effect-preview.mjs';
import {approvalOf, createInstalledRowEffectApproval, createInstalledRowEffectCommit} from './installed-row-effect-commit.mjs';
import {createInstalledRowEffectPhysicalOperation, createInstalledRowEffectReadChild,
  createInstalledRowEffectReadOperations} from './installed-row-effect-physical-read.mjs';
import {createInstalledRowEffectCapability, createInstalledRowEffectReadDecision,
  createInstalledRowEffectTargetAuthorization} from './installed-row-effect-authorization.mjs';
import {createInstalledRowEffectMembers, createInstalledRowEffectRequests} from './installed-row-effect-members.mjs';
import {createInstalledRowEffectRunControls, createInstalledRowEffectRunLimits} from './installed-row-effect-run-controls.mjs';
import {createInstalledRowEffectOwnerProjection} from './installed-row-effect-owner-projection.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {canonicalJson} from './local-account-config.mjs';
import {canonicalJson as canonicalValueJson} from
  '../../packages/sdk/host-port.mjs';
import {preparePinnedEffectSourceHoldings, preparePinnedEffectSourceSet, retainPinnedEffectDependencyPayloads} from './effect-input-export.mjs';
import {openInstalledEffectLedger} from './installed-effect-ledger-open.mjs';
import {recoverProjectedEffectResponse} from './effect-response-recovery.mjs';
import {localContractLimits} from './local-values-plan.mjs';
import {prepareInstalledRowCaptureChild} from './installed-row-capture-cleanup.mjs';
import {assertUpdateTargetSelectionMembersCurrent} from './update-target-original-shape.mjs';
import {closeInstalledSourceConstruction} from './installed-host-services.mjs';

import type {effectApplicationControl} from '../host-common/effect-application-control.mjs';
import type {SynchronousRuntimeData} from '../host-common/runtime-result.mjs';
import type {ControlWork} from './installed-effect-plan.mjs';
import type {InstalledEffectPlanRecipe} from './installed-effect-recipe.mjs';

type Construction = Parameters<typeof createInstalledRowEffectConstruction<{close(): unknown}>>[0];
type ConstructedOwner = Parameters<Construction['createRowEffectStage']>[0][0];
type Limits = Construction['defaultLimits'];
type CaptureControls = Parameters<typeof createInstalledRowEffectCaptureStage>[0];
type Capture = ReturnType<typeof createInstalledRowEffectCaptureStage>;
type CaptureInput = Parameters<Capture>[0];
type Member = CaptureInput['members'][number];
type RowMember = (Omit<Extract<Member, {mapping: object}>, 'stageIndex'> |
  Omit<Extract<Member, {command: object}>, 'stageIndex'>) & Readonly<{stageIndex?: number}>;
type ComposeDescriptor = Readonly<{effectId: string; kind: string; target?: string;
  mappingRef?: string; mappingCid?: string}>;
type RecoveryBase = Parameters<typeof createInstalledRowEffectRecovery>[0];
type RecoveryControls = Parameters<typeof createInstalledRowEffectRecovery<RowMember, RecoveryBase['owners'][number]>>[0];
type TargetControls = Parameters<typeof createInstalledRowEffectTargetAuthorization<RowMember>>[0];
type CapabilityControls = Parameters<typeof createInstalledRowEffectCapability<RowMember>>[0];
type ReadControls = Parameters<typeof createInstalledRowEffectReadOperations<RowMember>>[0];
type RouteControls = Parameters<typeof createInstalledRowEffectPhysicalRoute<RowMember>>[0];
type ProjectionControls = Parameters<typeof createInstalledRowEffectOwnerProjection>[0];
type ProjectionOwner = Exclude<NonNullable<ReturnType<ProjectionControls['rowInstallations']['get']>>, readonly unknown[]>;
type RunControls = Parameters<typeof createInstalledRowEffectRunControls>[0];
type RequestControls = Parameters<typeof createInstalledRowEffectRequests>[0];
type FootprintControls = Parameters<typeof createInstalledRowEffectFootprint<RowMember>>[0];
type RecoveryBackingControls = Parameters<typeof createInstalledRowEffectRecoveryBacking<RowMember>>[0];
type InstalledMapping = Extract<Member,{mapping:object}>['mapping'] & Readonly<{target: string}>;
type InstalledCommand = Extract<Member,{command:object}>['command'];
type Runtime = CaptureControls['moon'] & RecoveryControls['moon'] & CapabilityControls['moon'] &
  Parameters<typeof createInstalledRowEffectMembers>[0]['moon'] & ProjectionOwner['moon'] &
  Parameters<typeof createInstalledRowEffectPreview<Member>>[0]['moon'] &
  Parameters<typeof createInstalledRowEffectPreviewContext<RowMember, unknown>>[0]['moon'] &
  Parameters<typeof createInstalledRowEffectCommit<RowMember>>[0]['moon'] &
  Parameters<typeof openInstalledEffectLedger>[0] &
  Parameters<typeof createInstalledRowEffectCaptureEntry>[0]['moon'] &
  Parameters<typeof createInstalledRowEffectPhysicalOperation<RowMember>>[0]['moon'] &
  RecoveryBackingControls['moon'] & Parameters<ReturnType<typeof createInstalledRowEffectConstruction>['installedRowEffectUnit']>[0] &
  Readonly<{clientProgramInstalledEffectManagedPlanShape?(plan: unknown): readonly [number, number, number]}>;
type CaptureOwner = ReturnType<CaptureControls['ownerOf']>;
type TargetOwner = ReturnType<TargetControls['ownerOf']>;
type Driver = ConstructedOwner['owned'] & CaptureOwner['owned'] & TargetOwner['owned'] &
  ReturnType<CapabilityControls['ownerOf']>['owned'] & ReturnType<ReadControls['ownerOf']>['owned'] &
  ReturnType<RouteControls['ownerOf']>['owned'] & ReturnType<RequestControls['ownerOf']>['owned'] &
  ReturnType<FootprintControls['ownerOf']>['owned'] & ReturnType<RecoveryBackingControls['ownerOf']>['owned'] &
  RecoveryControls['owners'][number]['owned'] &
  Parameters<typeof createInstalledRowEffectRecoveryEntries>[0]['owners'][number]['owned'] & Readonly<{
    assertRequestFinalized?(request: unknown, requestTag: string): SynchronousRuntimeData;
    kinds?: readonly string[];
    project(facts: object): NonNullable<ReturnType<RouteControls['projectOwnedResponse']>> & {then?: never};
  }>;
type Owner = Omit<ConstructedOwner,'moon'|'site'|'installed'|'installedCommands'|'storeMappings'|'owned'> &
  Omit<CaptureOwner & TargetOwner, 'owned' | 'site'> & Readonly<{
  moon: Runtime;
  installed: readonly InstalledMapping[];
  installedCommands: readonly InstalledCommand[];
  storeMappings: readonly (InstalledMapping & RunControls['owners'][number]['storeMappings'][number])[];
  owned: Driver;
  site: ConstructedOwner['site'] & TargetOwner['site'] & ReturnType<RouteControls['ownerOf']>['site'] &
    Readonly<{close(): unknown}>;
}>;
type Route = Readonly<{descriptor: ComposeDescriptor; owner: Owner}>;
type AdapterProjection = Readonly<Partial<Record<'prepareManagedPlan'|'prepareCaptured'|'prepareRecovered'|
  'environmentWire'|'effectSelectors'|'close', unknown>>>;
type OutputLimits = Parameters<ReturnType<typeof createInstalledRowEffectCaptureStage>>[0]['plan']['outputLimits'] &
  Readonly<Record<'maxResultFields'|'maxResultMappingWork'|'maxResultOrderWork'|'maxResultWorkspaceEntries'|
    'maxRows'|'maxValueNodes'|'maxValueTextBytes'|'maxValueDepth'|'maxValueWork'|'maxWireNodes'|'maxWireDepth'|
    'maxColumns'|'maxOrderWork'|'maxLogicalWireBytes'|'maxLogicalWireNodes'|'maxLogicalWireDepth'|
    'maxSchemaFields'|'maxSchemaBytes'|'maxSchemaNodes'|'maxSchemaDepth'|'maxBatchBytes', number>>;
type TargetRecipes = ReturnType<typeof createInstalledRowEffectPlanCapture>['prepareInstalledTargetPlanRecipes'];
type CapturedStage = Awaited<ReturnType<Capture>>;
type RoutedStage = Readonly<{
  environmentWire: string;
  assertPrepared: Parameters<typeof createInstalledRowEffectCaptureEntry>[0]['assertPrepared'];
  prepareManagedPlan: ReturnType<typeof createInstalledRowEffectMembers>['prepareManagedPlan'];
  prepareCaptured(facts: unknown): Promise<CapturedStage | undefined>;
  prepareRecovered(facts: unknown): ReturnType<ReturnType<typeof createInstalledRowEffectRecovery>>;
}>;
type SingleStage = Omit<RoutedStage,'assertPrepared'> & Readonly<{
  connectorBindings: readonly Readonly<{connectorId: string; bindingCid: string}>[];
  connectorRegistration: string; connectorRevision: string; connection: string;
  mappings: readonly Pick<InstalledMapping,'resource'|'target'|'mappingRef'|'mappingCid'>[];
  commands: readonly Pick<InstalledCommand,'resource'|'target'|'commandRef'|'commandCid'>[];
  effectSelectors: readonly (Pick<InstalledMapping,'target'|'mappingRef'|'mappingCid'> & {kind: Exclude<Member['kind'], 'command'>} |
    Pick<InstalledCommand,'target'|'commandRef'|'commandCid'> & {kind: 'command'})[];
  close(): unknown;
}>;

// Private provenance: copies of an adapter cannot introduce an installation.
const rowInstallations = new WeakMap<object, Owner | readonly Owner[]>();
const memberInstallations = new WeakMap<object, Owner>();
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
const guarded = (kind: unknown) => kind === 'update' || kind === 'upsert' || kind === 'delete';
// Commands select a ResourceRef, but do not invent a row version guard or
// before/after state. The checked payload and current target authority are
// independent obligations.
const targeted = (kind: unknown) => guarded(kind) || kind === 'command';
const contractCidOf = (member: RowMember) => member.kind === 'command'
  ? member.command.commandCid : member.mapping.mappingCid;
// A deletion has no proposed value. It must not acquire an empty object,
// null, an UPDATE body or a Command input to satisfy the shared comparison.
const sameEffectValue = (kind: Member['kind'], left: unknown, right: unknown) => kind === 'delete'
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
export const installedRowEffectConstructionLimits = (supplied?: Partial<Limits>): Limits => Object.freeze({...defaultLimits, ...supplied});

const fail: (code: string, cause?: unknown) => never = (code, cause) => {
  throw Object.assign(new Error(code, {cause}), {code});
};
const text = (value: unknown): value is string => typeof value === 'string' && value.length > 0;
const {captureManagedPlanDefinition, captureManagedDriverConstruction, captureManagedPlanRecipes,
  prepareInstalledTargetPlanRecipes: prepareManagedTargetPlanRecipes} = createInstalledRowEffectPlanCapture({fail, text});
const cidPattern = /^sha256:[0-9a-f]{64}$/u;
const cid = (value: unknown) => `sha256:${createHash('sha256')
  .update(canonicalJson(value)).digest('hex')}`;
const pendingCid = `sha256:${'0'.repeat(64)}`;
// Data values (row values, targets, outcomes) keep their exact strings and
// JSON keys through the shared value encoder's explicit data mode. The
// configuration encoder serves only structural identity preimages here.
const sameValue = (left: unknown, right: unknown) =>
  canonicalValueJson(left, {dataKeys: true}) ===
    canonicalValueJson(right, {dataKeys: true});

const {commandContentBorrower, commandContentRow, prepareInstalledCreateRows} = createInstalledRowEffectCaptureValues(fail);

const exportLimits = (output: OutputLimits) => [output.maxResultFields,
  output.maxResultMappingWork, output.maxResultOrderWork,
  output.maxResultWorkspaceEntries, output.maxRows, output.maxValueNodes,
  output.maxValueTextBytes, output.maxValueDepth, output.maxValueWork,
  output.maxWireBytes, output.maxWireNodes, output.maxWireDepth,
  output.maxColumns, output.maxOrderWork, output.maxLogicalWireBytes,
  output.maxLogicalWireNodes, output.maxLogicalWireDepth,
  output.maxSchemaFields, output.maxSchemaBytes, output.maxSchemaNodes,
  output.maxSchemaDepth, output.maxBatchBytes];

const optionalFunction = (value: unknown) => value === undefined ||
  typeof value === 'function';

// The actual Host supplies this private service. Capturing its methods does
// not issue a Run or turn limits into capacity; the retained owner validates
// the original preparation/Run before each physical use.
const managedTargetPlanOriginals = new WeakMap<ReturnType<TargetRecipes>, readonly unknown[]>();

export function prepareInstalledTargetPlanRecipes(mappings: Parameters<TargetRecipes>[0], recipes: Parameters<TargetRecipes>[1]) {
  return prepareManagedTargetPlanRecipes(mappings, recipes, cidPattern, localContractLimits,
    managedTargetPlanOriginals);
}

const {captureEffectResources, requireSynchronousEffectResource, installedEffectKinds,
  installedEffectWriteOperation, checkDriver, captureBeforeSendCheck, captureResponseConfirmation} =
  createInstalledRowEffectDriverControls({fail, text, optionalFunction, kinds, guarded});

const {installationFacts, selectionChanged, validateOwnerSelections, installedRowEffectOwnerBinding,
  installedRowEffectUpdateTargetReadAccess, installedRowEffectUpdateObservation,
  collectInstalledRowEffectUpdateObservations, installedRowEffectUpdateObservations, validateInstalledUpdateOwnerSelections} =
  createInstalledRowEffectOwnerProjection<Owner>({rowInstallations, installedEffectKinds});

export {installedRowEffectOwnerBinding, installedRowEffectUpdateTargetReadAccess, installedRowEffectUpdateObservation,
  collectInstalledRowEffectUpdateObservations, installedRowEffectUpdateObservations, validateInstalledUpdateOwnerSelections};

const {installedRowEffectUnit, installedRowEffectDescriptors, createInstalledRowEffect} =
  createInstalledRowEffectConstruction<SingleStage>({
    fail, text, optionalFunction, cid, cidPattern, defaultProfile, defaultLimits, localContractLimits,
    installedRowEffectConstructionLimits, managedTargetPlanOriginals,
    // Construction retains the checked installation before handing it to the
    // stage. Its public input still accepts the original opaque Core object.
    createRowEffectStage: createRowEffectStage as unknown as Parameters<typeof createInstalledRowEffectConstruction<SingleStage>>[0]['createRowEffectStage'],
    captureEffectResources, checkDriver, captureBeforeSendCheck, captureResponseConfirmation,
    captureManagedPlanDefinition, captureManagedPlanRecipes, captureManagedDriverConstruction,
  });

export {installedRowEffectUnit, installedRowEffectDescriptors, createInstalledRowEffect};

// Each physical occurrence retains its own admitted installation. Shared Run,
// Preview, claims and publication remain the existing stage's responsibility.
// This profile admits one existing CREATE or UPDATE family at a time. A retained-request driver
// must explicitly support recovery of its original members in the whole Set.
export function composeInstalledRowEffectOwners(effects: readonly unknown[], descriptors: readonly ComposeDescriptor[], environmentWire: string): RoutedStage {
  if (!Array.isArray(effects) || !Array.isArray(descriptors) ||
      effects.length !== descriptors.length || effects.length < 2 ||
      !['create', 'update'].includes(descriptors[0]?.kind) ||
      descriptors.some(value => value.kind !== descriptors[0].kind) ||
      new Set(descriptors.map(value => value.effectId)).size !== descriptors.length) {
    fail('InstalledEffectSetOwnerMismatch');
  }
  const owners = effects.map(effect => rowInstallations.get(effect as object)) as readonly (Owner | readonly Owner[] | undefined)[];
  if (owners.some(owner => owner === undefined || Array.isArray(owner) ||
      ((owner as Owner).owned.recoverRequests !== undefined &&
        (owner as Owner).owned.recoverMemberRequests === undefined))) fail('InstalledEffectSetOwnerMismatch');
  const first = owners[0] as Owner;
  // This standalone composition has no original Request construction borrow.
  // Preserve its installed envelope; a later managed Plan cannot retroactively
  // fund the Set, route and owner vectors constructed here.
  if (descriptors.length > first.limits.maxMembers || owners.some(owner => (owner as Owner).moon !== first.moon ||
      (owner as Owner).ledgerRoot !== first.ledgerRoot ||
      canonicalJson((owner as Owner).limits) !== canonicalJson(first.limits))) {
    fail('InstalledEffectSetOwnerMismatch');
  }
  const routes = Object.freeze(descriptors.map((descriptor, index) =>
    Object.freeze({descriptor: Object.freeze({...descriptor}), owner: owners[index] as Owner})));
  const freeze = <Value,>(value: Value): Value => {
    if (value !== null && typeof value === 'object') {
      Object.values(value).forEach(freeze);
      Object.freeze(value);
    }
    return value;
  };
  // Equal limits are data, not shared mutable bootstrap objects. Retain the
  // same numeric ceilings for this stage even if a later table is configured.
  const limits = freeze(JSON.parse(canonicalJson(first.limits)));
  return createRowEffectStage(Object.freeze([...new Set(owners)] as Owner[]), environmentWire, routes, limits);
}

// The installed loader retains the original private port while exposing its
// normal adapter projection. No descriptor or structural marker admits a port.
// Initialization may expose only an already-retained private projection.
// Canonicalize to the exact registered raw adapter, never structural copies
// or equal owner DATA. The original common close remains mandatory here.
export function resolveInstalledRowEffectConstruction<Original>(original: Original, projection: unknown): Original | undefined {
  if (original === projection) return original;
  const owner = rowInstallations.get(original as object);
  if (owner === undefined || rowInstallations.get(projection as object) !== owner ||
      !projection || nodeTypes.isProxy(projection)) return undefined;
  const fields = Object.getOwnPropertyDescriptors(projection);
  for (const key of ['prepareManagedPlan','prepareCaptured','prepareRecovered',
    'environmentWire','effectSelectors','close']) {
    if (!Object.hasOwn(fields[key] ?? {}, 'value') || fields[key].value !== (original as AdapterProjection)[key as keyof AdapterProjection]) return undefined;
  }
  return original;
}

export function retainInstalledRowEffectAdapter<Projection>(original: unknown, projection: Projection): Projection {
  const owner = rowInstallations.get(original as object);
  if (owner === undefined) return projection;
  if ((projection as AdapterProjection).prepareManagedPlan !== (original as AdapterProjection).prepareManagedPlan ||
      (projection as AdapterProjection).prepareCaptured !== (original as AdapterProjection).prepareCaptured ||
      (projection as AdapterProjection).prepareRecovered !== (original as AdapterProjection).prepareRecovered ||
      (projection as AdapterProjection).environmentWire !== (original as AdapterProjection).environmentWire ||
      (projection as AdapterProjection).effectSelectors !== (original as AdapterProjection).effectSelectors) {
    fail('ForeignInstalledEffectOccurrence');
  }
  rowInstallations.set(projection as object, owner);
  return projection;
}

function createRowEffectStage(owners: readonly [Owner], environmentWire: string): SingleStage;
function createRowEffectStage(owners: readonly Owner[], environmentWire: string,
  routes: readonly Route[], retainedLimits: Limits): RoutedStage;
function createRowEffectStage(owners: readonly Owner[], environmentWire: string,
  routes?: readonly Route[], retainedLimits?: Limits): SingleStage | RoutedStage {
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
  const assertPrepared = ({moon: runMoon, compilation}: {moon?: unknown; compilation?: unknown}) => {
    if (singular !== undefined) return;
    if (runMoon !== moon || compilation === undefined) fail('InstalledEffectSetOwnerMismatch');
    const program = JSON.parse(moon.clientProgramEffectCompilationPlanWire(compilation))
        .execution_material?.program as Readonly<{stages?: readonly Readonly<{inputs?: object; steps?: readonly object[]}>[]}> | undefined;
    const stage = program?.stages?.[0];
    // Routed UPDATE uses the existing checked Source/Model capture and the
    // member-scoped original-request recovery below. CREATE retains its
    // existing source-free profile; neither path admits multiple stages here.
    const update = routes!.every(route => route.descriptor.kind === 'update');
    if (program?.stages?.length !== 1 || stage === undefined ||
        !Array.isArray(stage.steps) || stage.steps.length === 0 ||
        (!update && (Object.keys(stage.inputs ?? {}).length !== 0 ||
          stage.steps.some(step => !Object.hasOwn(step, 'values'))))) {
      fail('InstalledEffectSetOwnerMismatch');
    }
  };
  const ownerOf = (member: object): Owner => {
    const owner = memberInstallations.get(member);
    if (owner === undefined || !owners.includes(owner)) fail('ForeignInstalledEffectOccurrence');
    return owner;
  };
  const targetPlanOf = (member: RowMember, owner: TargetOwner) => {
    if ((owner as Owner).managedTargetPlanRecipes === undefined) return undefined;
    const plan = (owner as Owner).managedTargetPlanRecipes!.byMapping[(member as Extract<RowMember, {mapping: object}>).mapping?.mappingCid];
    if (member.kind !== 'update' || plan === undefined) fail('ForeignInstalledEffectOccurrence');
    return plan;
  };
  const recipeOf = (member: RowMember) => {
    const owner = ownerOf(member), target = targetPlanOf(member, owner);
    if (target !== undefined) return controlEntryBytes > target.entryLimit ||
      controlResponseBytes > target.responseLimit ? target.fallback : target.recipe;
    const recipe = owner.managedPlanRecipes === undefined
      ? owner.managedPlanRecipe : owner.managedPlanRecipes[member.kind];
    return controlRecipes.get(recipe);
  };
  const projectOwnedResponse = (member: RowMember, facts: object, construction: ControlWork | undefined): ReturnType<RouteControls['projectOwnedResponse']> => {
    const {owned} = ownerOf(member);
    const method = owned.project;
    if (construction === undefined) return Reflect.apply(method, owned, [facts]);
    const selected = recipeOf(member)?.projectConstruction;
    return selected !== undefined && selected.receiver === owned && selected.method === method
      ? construction(owned, method, [facts], selected.capacity)
      : construction(owned, method, [facts]);
  };
  const retainMember = <Value extends object,>(owner: object, member: Value): Readonly<Value> => {
    const retained = Object.freeze(member);
    memberInstallations.set(retained, owner as Owner);
    return retained;
  };
  const {bindRunResources, resourceFields, selectionFence} = createInstalledRowEffectRunControls<Owner>({
    owners, ownerOf, fail, selectionChanged,
    requireSynchronousEffectResource, validateOwnerSelections, assertUpdateTargetSelectionMembersCurrent,
  });
  const {selectOwner, scopes, permissionsOf, membersOf, prepareManagedPlan} = createInstalledRowEffectMembers<Owner>({
    moon, limits, owners, singular, routes, installedEffectKinds, retainMember, ownerOf,
    assertPrepared, installedRowEffectUnit, recipeOf, fail,
  });
  const effect = runtimeCore(moon).effectApplicationControl as ReturnType<typeof effectApplicationControl>;
  const openLedger = (identity: unknown, controlConstruction: Parameters<typeof openInstalledEffectLedger>[5]) => openInstalledEffectLedger(
    moon, ledgerRoot, identity, controlEntryBytes, controlResponseBytes, controlConstruction);
  const memberDispatch = (runInvocationCid: string, member: RowMember) => cid({
    version: ownerOf(member).profile.dispatch, run_invocation_cid: runInvocationCid,
    effect_id: member.effectId});
  const recoveryCid = (member: RowMember, dispatch: string) => cid({version: ownerOf(member).profile.recovery,
    dispatch_request_cid: dispatch});

  const {entryOf, requestEntry, requestsOf} = createInstalledRowEffectRequests({
    ownerOf, cidPattern, targeted, sameEffectValue, sameValue, resourceFields, commandContentRow, fail,
  });

  const {admitCapability, routeOf} = createInstalledRowEffectCapability<RowMember>({
    moon, ownerOf, cid, cidPattern, CAPABILITY_VERSION, contractCidOf, installedEffectWriteOperation, fail,
  });
  const readDecision = createInstalledRowEffectReadDecision({ownerOf});
  const checkSubject = (runInvocationCid: string, member: RowMember) => cid({
    version: ownerOf(member).profile.targetCheck, run_invocation_cid: runInvocationCid,
    effect_id: member.effectId});

  const prepareCredentialOperation = createInstalledRowEffectPhysicalOperation<RowMember>({
    moon, recipeOf, fail, installedRowCredentialOperationSite, prepareInstalledRowCaptureChild, prepareInstalledEffectCredentialChild,
  });
  const managedReadChild = createInstalledRowEffectReadChild<RowMember>({ownerOf, recipeOf, requireSynchronousEffectResource, fail});
  const {describeMember, checkRows, observeRows} = createInstalledRowEffectReadOperations<RowMember>({
    ownerOf, recipeOf, managedReadChild, resourceFields, readDecision, sameValue, cidPattern, fail,
  }) as ReturnType<typeof createInstalledRowEffectReadOperations<RowMember>> &
    Pick<CaptureControls, 'describeMember' | 'checkRows' | 'observeRows'>;

  const decideTargetRead = createInstalledRowEffectTargetAuthorization<RowMember>({ownerOf, targetPlanOf, recipeOf, fail});

  const {scopeKey, commitDecisions, settle, admitRow} = createInstalledRowEffectCommit<RowMember>({
    moon, effect, ownerOf, sameEffectValue, sameValue, targeted, fail,
  });
  const requireApproval = createInstalledRowEffectApproval(text);

  const physicalRoute = createInstalledRowEffectPhysicalRoute<RowMember>({
    recipeOf, ownerOf, fail, guarded, decideTargetRead, describeMember, resourceFields, checkRows,
    observeRows, admitCapability, routeOf, readDecision, commitDecisions, requireApproval, scopeKey,
    admitRow, installedEffectWriteOperation, projectOwnedResponse, settle,
  }) as ReturnType<typeof createInstalledRowEffectPhysicalRoute<RowMember>> & CaptureControls['physicalRoute'];

  const {basePreflight, continuationOf} = createInstalledRowEffectPreviewContext<RowMember, Owner>({
    moon, contractCidOf, guarded, singular, ROUTING_VERSION, ownerOf, installationFacts,
  });
  const footprintOf = createInstalledRowEffectFootprint<RowMember>({
    ownerOf, recipeOf, footprintKinds, cidPattern, text, cid, contractCidOf, fail,
  });
  const authorPreview = createInstalledRowEffectPreview<Member>({moon, permissionsOf, pendingCid, fail});

  const {orderedSourceIndexes, claimsOf} = createInstalledRowEffectClaims<RowMember>({effect, limits, ownerOf, recoveryCid, fail});

  const captureStage = createInstalledRowEffectCaptureStage({
    moon, fail, ownerOf, runLimits, prepareCredentialOperation, recipeOf, singular, cid, exportLimits,
    preparePinnedEffectSourceSet, guarded, targeted, checkSubject, decideTargetRead, describeMember,
    commandContentBorrower, resourceFields, prepareInstalledCreateRows, commandContentRow, requestEntry, requestsOf,
    observeRows, checkRows, admitCapability, footprintOf, retainPinnedEffectDependencyPayloads, authorPreview,
    sameEffectValue, sameValue, effect, preparePinnedEffectSourceHoldings, openLedger, claimsOf, physicalRoute,
    orderedSourceIndexes, basePreflight, scopes, continuationOf,
  });

  const prepareCaptured = createInstalledRowEffectCaptureEntry<Member, CaptureInput['control'],
    CaptureInput['plan'] & Parameters<Parameters<typeof createInstalledRowEffectCaptureEntry>[0]['captureStage']>[0]['plan'],
    CapturedStage>({
    moon, assertPrepared, installedRowEffectUnit, membersOf, runLimits, bindRunResources, selectionFence,
    memberDispatch, captureStage, fail,
  });

  const recoveredMembers = createInstalledRowEffectRecoveredMembers<InstalledMapping, InstalledCommand, Owner>({
    singular, selectOwner, sameValue, installationFacts, selectionChanged, installedEffectKinds, retainMember, fail,
  });

  const {validateRecoveredEntries, recoveredEntries} = createInstalledRowEffectRecoveryEntries<RowMember, Owner>({
    owners, singular, ownerOf, orderedSourceIndexes, resourceFields, entryOf, sameEffectValue, sameValue, targeted, fail,
  });

  const prepareRecoveredEntries = createInstalledRowEffectRecoveryBacking<RowMember>({
    moon, recipeOf, ownerOf, sameValue, prepareInstalledEffectRequestChild, recoveredEntries, validateRecoveredEntries, fail,
  });

  const prepareRecovered = createInstalledRowEffectRecovery<RowMember, Owner>({
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
        Object.freeze({kind: kind as Exclude<Member['kind'], 'command'>, target: mapping.target,
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
