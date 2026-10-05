// The standard Host's provider-neutral installed Effect for connectors whose
// writes change one provider object per row through a checked execution
// Mapping (see installed-row-source.mjs for the common Mapping generator and
// the credential Site). Capture, the Effect Set Preview, the Effect Ledger
// claims, apply, the Receipt, publication and recovery are the common
// owners'. The path of a member is selected by its Mapping's checked
// `effect_kind`: a `create` has no target; an `update` or `upsert` selects
// an existing target whose observed version guards the write.
//
// A connector supplies a write driver. Every kind:
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
//   each row, `{identity, versionCid, before}`. When the Host decides target
//   reads through a resumed Checkpoint (`targetReads`), the driver's
//   `admitTargetReadApproval({member, decision})` admits the approval for
//   exactly the member's physical binding; the admitted approval grants the
//   reads and the describe.
// - `recoveryEntry({member, current})`: data retained with the captured
//   computation to rebuild requests on recovery, and `recoverRequests({durable,
//   recorded, previewWire, body})`. Retained data is checked, never
//   authority: every rebuilt request must be exactly the one its claim and
//   approved Preview row name.
// - `requestCid(request)`: a rebuilt request's identity.
//
// The identities this factory issues (dispatch, recovery, unit, source,
// target check and continuation) use the versions of the installation's
// registered identity profile (`host-bundle.json`, generated into the
// installed connector table), or the common default. No provider name or
// type appears here.
import {createHash} from 'node:crypto';
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
import {canonicalJson} from './local-account-config.mjs';
import {preparePinnedEffectSourceHoldings, preparePinnedEffectSourceSet,
  retainPinnedEffectDependencyPayloads} from './effect-input-export.mjs';
import {verifyPinnedEffectPlan} from './effect-plan-verify.mjs';
import {openEffectLedger} from './effect-ledger.mjs';
import {captureClaimedEffectResponse, snapshotEffectDispatchClaim} from
  './effect-physical-dispatch.mjs';
import {recoverProjectedEffectResponse} from './effect-response-recovery.mjs';
import {localContractLimits} from './local-values-plan.mjs';

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
const kinds = Object.freeze(['create', 'update', 'upsert']);
// A guarded write selects an existing target and is guarded by its observed
// version.
const guarded = kind => kind !== 'create';
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
const sameValue = (left, right) => canonicalJson(left) === canonicalJson(right);

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
        driver.requestCid, driver.checkRequest,
        driver.admitTargetReadApproval].every(optionalFunction) ||
      (driver.check !== undefined && (!text(driver.check?.resource) ||
        !text(driver.check.operation) ||
        typeof driver.checkRequest !== 'function')) ||
      (driver.kinds.some(guarded) && (!text(driver.targetRead?.operation) ||
        typeof driver.observeTargets !== 'function' ||
        typeof driver.recoverRequests !== 'function' ||
        typeof driver.requestCid !== 'function')) ||
      ((driver.recoveryEntry === undefined) !==
        (driver.recoverRequests === undefined))) {
    fail('InvalidInstalledRowEffectDriver');
  }
  return driver;
}

// The identity profile of an installation: the one its connector registered
// in the installed connector table, or the common default. Only an entry of
// the generated table is accepted, never a constructed one.
function profileOf(installation) {
  if (installation === undefined) return defaultProfile;
  if (!installedConnectors.includes(installation) ||
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

// The installed Effect over `mappings` (each `{resource, mappingRef,
// mappingCid, body}`, checked by the Check Environment it is installed in)
// on the credential `site` and installation gate `authorization`.
// `installation` is the connector's installed table entry, whose registered
// identity profile names the identities issued here; `continuationBinding`
// is the value the continuation binds the installation by.
export async function createInstalledRowEffect({moon, mappings,
  environmentWire, connectorId, connectorRegistration, connectorRevision,
  connection, site, authorization, runtimeBundleCid, bindingCid, driver,
  ledgerRoot, installation, continuationBinding = bindingCid,
  openLedger: openLedgerAt = openEffectLedger, limits: suppliedLimits}) {
  const limits = Object.freeze({...defaultLimits, ...suppliedLimits});
  const owned = checkDriver(driver);
  const profile = profileOf(installation);
  if (!moon || !Array.isArray(mappings) || mappings.length === 0 ||
      !text(environmentWire) || !text(connectorId) ||
      !text(connectorRegistration) || !text(connectorRevision) ||
      (installation !== undefined &&
        (installation.registration !== connectorRegistration ||
          installation.revision !== connectorRevision)) ||
      !text(connection) || typeof site?.issueEffectGrant !== 'function' ||
      typeof site.issueReadGrant !== 'function' ||
      typeof authorization?.authorize !== 'function' ||
      !cidPattern.test(runtimeBundleCid ?? '') ||
      !text(bindingCid) || !text(continuationBinding) || !text(ledgerRoot) ||
      typeof openLedgerAt !== 'function') {
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
      approval: body.minimum_approval});
  }));
  await mkdir(ledgerRoot, {recursive: true, mode: 0o700});
  const effect = runtimeCore(moon).effectApplicationControl;
  const openLedger = identity => openLedgerAt({moon, root: ledgerRoot,
    authorityScopeCid: moon.clientRequestAuthorityScopeCid(identity),
    callerRequestId: moon.clientRequestCallerId(identity),
    maxEntryBytes: 1_000_000});
  const scopes = members => Object.freeze(members.map(member =>
    Object.freeze({connection, resource: member.resource})));
  const permissionsOf = member => {
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
    const mapping = installed.find(candidate =>
      candidate.mappingCid === descriptor._5 &&
      candidate.mappingRef === descriptor._4);
    if (mapping === undefined || !owned.kinds.includes(descriptor._2) ||
        descriptor._6 === undefined) {
      fail('InstalledRowEffectMappingNotInstalled');
    }
    const member = Object.freeze({stageIndex, effectId: descriptor._1,
      memberIndex: descriptor._0, kind: descriptor._2, mapping,
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
  const memberDispatch = (runInvocationCid, member) => cid({
    version: profile.dispatch, run_invocation_cid: runInvocationCid,
    effect_id: member.effectId});
  const recoveryCid = dispatch => cid({version: profile.recovery,
    dispatch_request_cid: dispatch});

  // One row's request with the facts the common owner holds it to: the
  // value it writes and, for an update, the target it selects.
  const entryOf = (member, request, requestCid) => {
    const facts = owned.requestFacts(request);
    if (!request || !cidPattern.test(requestCid ?? '') ||
        facts === null || typeof facts !== 'object' ||
        facts.value === null || typeof facts.value !== 'object' ||
        guarded(member.kind) === (facts.target === undefined)) {
      fail('InvalidInstalledRowEffectRequest');
    }
    return Object.freeze({request, requestCid, value: facts.value,
      target: facts.target});
  };

  // The exact request of every row of a member, from its mapped values and
  // selectors. A request that writes another value, or selects another
  // target, than the Program's row is refused.
  const requestsOf = (member, rows, current) => Object.freeze(rows.map(row => {
    const prepared = owned.prepareRequest({member, value: row.value,
      selector: row.selector, current});
    const entry = entryOf(member, prepared?.request, prepared?.requestCid);
    if (!sameValue(entry.value, row.value) ||
        (guarded(member.kind) && !sameValue(entry.target, row.selector))) {
      fail('ForeignInstalledRowEffectRequest');
    }
    return entry;
  }));

  // The common sealed capability of an installation whose driver issues
  // none: its runtime, connection and Mapping, and the exact requests.
  const commonCapability = (member, entries) => Object.freeze({
    identity: cid({
      version: CAPABILITY_VERSION,
      connector_registration: connectorRegistration,
      connector_revision: connectorRevision,
      runtime_bundle_cid: runtimeBundleCid, binding_cid: bindingCid,
      connection, resource: member.resource,
      mapping_cid: member.mapping.mappingCid,
      operation: owned.writeOperation(member),
      route: 'single_serial', idempotency: 'unavailable',
      request_cids: entries.map(entry => entry.requestCid)}),
    route: 'single_serial'});

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
  const readDecision = async (resource, subjectCid, signal) => {
    const decision = await authorization.authorize('acquisition', {
      connection, resource, operation: 'read'}, {subjectCid, signal});
    if (decision?.action !== 'dispatch') {
      throw Object.assign(new Error('InstalledRowEffectCheckNotAuthorized'),
        {code: 'InstalledRowEffectCheckNotAuthorized',
          action: decision?.action});
    }
    return decision;
  };
  const checkSubject = (runInvocationCid, member) => cid({
    version: profile.targetCheck, run_invocation_cid: runInvocationCid,
    effect_id: member.effectId});

  // Every create row's provider check, under a current read decision.
  const checkRows = async ({members, entries, runInvocationCid, dispatches,
    subjectOf, signal}) => {
    if (owned.check === undefined) return;
    for (const [index, member] of members.entries()) {
      if (member.kind !== 'create') continue;
      const subjectCid = subjectOf(member);
      const decision = await readDecision(owned.check.resource, subjectCid,
        signal);
      for (const [rowIndex, entry] of entries[index].entries()) {
        signal?.throwIfAborted();
        const grant = site.issueReadGrant({operation: owned.check.operation,
          decision, resource: owned.check.resource, runInvocationCid,
          dispatchRequestCid: dispatches[index], maxUses: 1});
        await owned.checkRequest({member, request: entry.request,
          authorization: {...grant,
            useId: `${dispatches[index]}-check-${subjectCid}-${rowIndex}`},
          credential: site.credential, callResource: site.callResource,
          signal});
      }
    }
  };

  // A current read decision of an update member's targets for `subjectCid`:
  // on the installation's gate, or through the Host's resumed target-read
  // Checkpoint (`targetReads`), whose approval the driver admits for exactly
  // this member. A held or denied read reads nothing.
  const decideTargetRead = async ({member, runInvocationCid,
    dispatchRequestCid, subjectCid, signal, targetReads}) => {
    const tuple = {connection, resource: member.resource, operation: 'read'};
    const decision = targetReads === undefined
      ? await authorization.authorize('acquisition', tuple, {subjectCid, signal})
      : await targetReads.authorize(tuple, {subjectCid, signal});
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
      authorizationForRow: async rowIndex => ({...site.issueReadGrant({
        operation: owned.targetRead.operation, decision: approval ?? decision,
        resource: member.resource, runInvocationCid, dispatchRequestCid,
        maxUses: 1}),
      useId: `${dispatchRequestCid}-check-${subjectCid}-${rowIndex}-${use++}`})});
  };

  // The observed target of every update row under its read decision. Each
  // observation must be of exactly the target the row's request selects.
  const observeRows = async ({member, entries, current, read, signal}) => {
    const observed = await owned.observeTargets({member, entries, current,
      authorizationForRow: read.authorizationForRow, signal});
    if (!Array.isArray(observed) || observed.length !== entries.length ||
        observed.some((row, index) => !cidPattern.test(row?.versionCid ?? '') ||
          !sameValue(row.identity, entries[index].target) ||
          row.before === null || typeof row.before !== 'object')) {
      fail('ForeignInstalledRowEffectObservation');
    }
    return observed;
  };

  // The whole-set commit decisions of one claim generation, by Resource.
  const commitDecisions = (decisions, subjectCid, members) => {
    const byResource = new Map();
    for (const decision of decisions ?? []) {
      if (decision?.action !== 'dispatch' ||
          decision.boundary !== 'effect_commit' ||
          decision.subjectCid !== subjectCid ||
          decision.tuple?.connection !== connection ||
          decision.tuple?.operation !== 'effect' ||
          byResource.has(decision.tuple.resource)) {
        fail('InstalledRowEffectCommitNotAuthorized');
      }
      byResource.set(decision.tuple.resource, decision);
    }
    for (const member of members) {
      if (!byResource.has(member.resource)) {
        fail('InstalledRowEffectCommitNotAuthorized');
      }
    }
    return byResource;
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
      outcomeWire: canonicalJson(outcome)});
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
    if (member.mapping.approval === 'required' &&
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
        !sameValue(entry.value, previewRow.after?.value) ||
        (guarded(member.kind) &&
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
    dispatches, subjectCid, applyPreview, ledger, targetReads}) => {
    let currents;
    const current = async ({signal, preflight}) => {
      if (preflight === null || typeof preflight !== 'object') {
        fail('InvalidInstalledRowEffectRoute');
      }
      for (const member of members) {
        if (!installed.some(mapping =>
          mapping.mappingCid === member.mapping.mappingCid)) {
          fail('InstalledRowEffectMappingNotInstalled');
        }
      }
      // Every read is decided before this refresh's provider I/O.
      const reads = [];
      for (const [index, member] of members.entries()) {
        reads.push(!guarded(member.kind) ? undefined :
          await decideTargetRead({member, runInvocationCid,
            dispatchRequestCid: dispatches[index], subjectCid, signal,
            targetReads}));
      }
      const fresh = [];
      for (const [index, member] of members.entries()) {
        const description = owned.describe === undefined ? undefined :
          await owned.describe({member, runInvocationCid,
            dispatchRequestCid: dispatches[index], label: `apply-${index}`,
            approval: reads[index]?.approval, signal});
        owned.recheckRequests?.({member, entries: entries[index],
          current: description});
        fresh.push(description);
      }
      await checkRows({members, entries, runInvocationCid, dispatches,
        subjectOf: () => subjectCid, signal});
      const guardVersions = [];
      for (const [index, member] of members.entries()) {
        if (!guarded(member.kind)) continue;
        const observed = await observeRows({member, entries: entries[index],
          current: fresh[index], read: reads[index], signal});
        guardVersions.push(...observed.map(row => row.versionCid));
      }
      const capabilities = members.map((member, index) => admitCapability(
        member, entries[index], fresh[index], runInvocationCid,
        dispatches[index]));
      signal?.throwIfAborted();
      currents = fresh;
      return Object.freeze({...preflight,
        guardVersions: Object.freeze(guardVersions),
        capabilities: Object.freeze(capabilities.map(value => value.identity)),
        routes: Object.freeze(capabilities.map(routeOf))});
    };
    const bindDispatch = ({members: claims, subjectCid: active, signal,
      decisions}) => {
      if (active !== subjectCid || currents === undefined) {
        fail('InvalidInstalledRowEffectRoute');
      }
      const commits = commitDecisions(decisions, subjectCid, members);
      const now = currents;
      return async ({memberIndex, rowIndex, claim}) => {
        const member = members[memberIndex];
        const entry = entries[memberIndex]?.[rowIndex];
        const expected = claims[memberIndex]?.claims[rowIndex];
        if (member === undefined || entry === undefined || !claim ||
            !expected || ['scope', 'locator', 'key', 'basis',
              'intentFingerprintCid', 'canonicalRequestCid'].some(field =>
              expected[field] === undefined ||
              expected[field] !== claim[field])) {
          fail('InvalidInstalledRowEffectDispatch');
        }
        signal?.throwIfAborted();
        requireApproval(member, commits.get(member.resource));
        const ownedClaim = admitRow({applyPreview, memberIndex, rowIndex,
          claim, member, entry,
          previewRow: previewRows[memberIndex][rowIndex]});
        owned.recheckRequests?.({member, entries: [entry],
          current: now[memberIndex]});
        const grant = site.issueEffectGrant({
          operation: owned.writeOperation(member),
          decision: commits.get(member.resource), resource: member.resource,
          runInvocationCid, dispatchRequestCid: dispatches[memberIndex],
          subjectCid});
        const captured = await captureClaimedEffectResponse({ledger,
          claim: ownedClaim, requestCid: entry.requestCid,
          execute: () => owned.send({member, request: entry.request,
            current: now[memberIndex],
            authorization: {...grant, useId:
              `${dispatches[memberIndex]}-write-${subjectCid}-${rowIndex}`},
            credential: site.credential, callResource: site.callResource,
            signal})});
        if (!captured.claimed) {
          return Object.freeze({claimed: false,
            ownership: Object.freeze({action: captured.ownership.action})});
        }
        const projected = owned.project({member, memberIndex, rowIndex,
          preview: applyPreview, request: entry.request,
          current: now[memberIndex],
          observation: captured.physical.observation,
          headers: captured.physical.headers});
        const settled = settle({ledger, claim: ownedClaim, applyPreview,
          memberIndex, rowIndex, projected});
        return Object.freeze({claimed: true, physical: projected,
          ...(settled ?? {})});
      };
    };
    return {current, bindDispatch};
  };

  const basePreflight = ({effects, members, requestScope, keys}) => ({
    sources: effects.map(member => member.source_binding_cid),
    contracts: members.map(member => member.mapping.mappingCid),
    capabilities: effects.map(member => member.capability_evidence_cid),
    authorities: effects.map(() => moon.clientProgramEffectRequestAuthority(
      requestScope)),
    observedRows: effects.flatMap(member => member.effect_kind === 'create'
      ? [] : member.row_order),
    guardVersions: [], routes: [],
    risk: undefined, reviewProjectionCid: '', authorityScopeCid: '',
    policyCid: '', validityCid: '', issuerCid: '', authenticationCid: '',
    issuerKind: '', decision: '',
    requestScope, ...(keys === undefined ? {} : {keys}),
    maxMembers: members.length, maxRows: limits.maxRows,
    maxFootprintWork: limits.maxRows, maxWork: limits.maxWork,
  });

  const continuationOf = (plan, unit, members, dispatches) => canonicalJson({
    version: profile.continuation,
    [profile.continuationBinding]: continuationBinding,
    program_id: unit.programId, stage_id: unit.stageId,
    request: plan.request, attempt: plan.attempt,
    members: members.map((member, index) => ({
      effect_id: member.effectId, mapping_cid: member.mapping.mappingCid,
      dispatch_request_cid: dispatches[index]}))});

  // A member's create rows in the common canonical create order, each with
  // its target row identity. This order is settled once, before any identity
  // is derived from the rows: the capability, the Preview, the claims, apply
  // and recovery all use the same ordered requests.
  const canonicalRows = rows => {
    const {maxWireBytes, maxNodes, maxDepth} = limits.preview;
    const inventory = checked(moon.clientProgramEffectCreateRowInventory(
      rows.map(entry => JSON.stringify({state: 'present',
        value: entry.value})), rows.length, maxWireBytes, maxNodes,
      maxDepth));
    if (inventory.length !== rows.length ||
        new Set(inventory.map(item => item._0)).size !== rows.length) {
      fail('InvalidInstalledRowEffectInventory');
    }
    return Object.freeze(inventory.map(item => Object.freeze({
      entry: rows[item._0], identity: parseExactJson(item._1)})));
  };

  // A member's write footprint: the provider's complete footprint, or the
  // opaque footprint of its boundary.
  const footprintOf = (member, entries) => {
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
        primary_identity: member.mapping.primaryIdentity}),
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
        descriptor._6, context.storeAuthorityCid);
      const identity = control.issueSourceFreeLocalEffectIdentity(
        prepared, inputs, descriptor._0, payloads[index].localResultArtifact,
        {maxWork: limits.planWork, maxWireBytes, maxNodes, maxDepth});
      identities.push(identity);
      const rows = rowsOf[index];
      rowCount += rows.length;
      if (rowCount > limits.maxRows) fail('InstalledRowEffectRowLimit');
      const planCid = checked(moon.clientProgramEffectPlanCid(prepared,
        descriptor._0, limits.maxFields, limits.planWork, maxWireBytes,
        maxNodes, maxDepth));
      return {
        effect_id: descriptor._1, effect_kind: descriptor._2,
        target: descriptor._3, mapping: descriptor._4,
        resolved_mapping_contract_cid: descriptor._5,
        effect_identity_cid: identity.identity,
        source_result: descriptor._6,
        ...(planCid === undefined ? {} : {effect_plan_logical_cid: planCid}),
        result_artifact_cid: source._0, preview_strength: 'full_diff',
        source_binding_cid: source._1,
        capability_evidence_cid: capabilities[index].identity,
        authority_scope_cid: requestAuthority,
        write_footprint: footprints[index],
        count: rows.length, max_items: rows.length,
        required_permissions: permissionsOf(member),
        approval: member.mapping.approval,
        on_item_failure: descriptor._7,
        changes: rows.map(row => member.kind === 'create' ? {
          target_row_identity: row.identity,
          target_guard: {state: 'not_applicable'},
          before: {state: 'absent'},
          after: {state: 'present', value: row.entry.value},
          intended_changes: {state: 'present', value: row.entry.value},
          row_preview_cid: pendingCid, row_idempotency_key: pendingCid,
        } : {
          target_row_identity: row.entry.target,
          target_guard: {state: 'version', version_cid: row.versionCid},
          before: {state: 'present', value: row.before},
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
      authored._0, draft.run_identity_cid, authoringCid, identities,
      {maxWireBytes, maxNodes, maxDepth});
    return Object.freeze({wire: authored._0, authoringCid,
      keys: authored._1});
  }

  // The Ledger claims of every row of the admitted Preview.
  const claimsOf = ({body, keys, entries, requestScope, unit, dispatches,
    unitCid, retentionId}) => body.effects.map((member, memberIndex) => ({
    claims: member.changes.map((change, rowIndex) => {
      const key = keys[memberIndex][rowIndex];
      const locator = effect.logicalItemLocator(requestScope,
        unit.programId, unit.stageId, member.effect_id,
        canonicalJson(change.target_row_identity), limits.locator.maxBytes,
        limits.key.maxBytes, limits.key.maxNodes, limits.key.maxDepth);
      const canonicalRequestCid = entries[memberIndex][rowIndex].requestCid;
      const basis = effect.ledgerBasis(requestScope, locator, key, unitCid,
        member.effect_member_preview_cid, change.row_preview_cid,
        canonicalRequestCid, recoveryCid(dispatches[memberIndex]),
        // A write without a provider idempotency key.
        'unavailable', member.capability_evidence_cid, retentionId);
      return {scope: requestScope, locator, key, basis,
        intentFingerprintCid: change.row_preview_cid, canonicalRequestCid};
    })}));

  async function captureStage({control, store, execution, checkedHost,
    prepared, identity, plan, previewContext, unit, members,
    runInvocationCid, dispatches, requestScope, storedResults, signal,
    targetReads, own, ownInputs}) {
    const inputs = checked(moon.clientProgramPinEffectSources(checkedHost,
      limits.maxPinnedResults));
    const releaseInputs = () => {
      moon.clientProgramReleaseEffectInputs(inputs);
    };
    ownInputs(releaseInputs);
    const proposals = members.map(() => []);
    const sourceSet = await preparePinnedEffectSourceSet({moon,
      checkedOwner: prepared, execution, inputs,
      maxMembers: members.length,
      maxGroupingWork: (members.length + limits.maxPinnedResults) * 2,
      limits: moon.clientProgramEffectInputExportLimits(
        ...exportLimits(plan.outputLimits)),
      store, maxBytes: plan.outputLimits.maxWireBytes, control,
      invocation: plan.invocation, retention: plan.results[0].retention,
      sourceBindingCid: cid({version: profile.source,
        run_invocation_cid: runInvocationCid,
        store_authority_cid: store.storeAuthorityCid}),
      contractLimits: plan.contractLimits,
      localEvidenceContext: plan.localEvidenceContext,
      proposalLimits: {maxFields: limits.maxFields, maxWork: limits.maxWork,
        maxBytes: limits.body.maxBytes, maxNodes: limits.body.maxNodes,
        maxDepth: limits.body.maxDepth,
        maxUtf16Units: limits.body.maxBytes},
      onProposalRow(memberIndex, rowIndex, proposal) {
        if (rowIndex !== proposals[memberIndex]?.length ||
            rowIndex >= limits.maxRows) {
          fail('InstalledRowEffectRowLimit');
        }
        proposals[memberIndex].push(proposal);
      },
      signal});
    own(sourceSet);
    // Reads of each update member's targets are decided before any provider
    // I/O: a held or denied read authors no Preview.
    const reads = [];
    for (const [index, member] of members.entries()) {
      reads.push(!guarded(member.kind) ? undefined :
        await decideTargetRead({member, runInvocationCid,
          dispatchRequestCid: dispatches[index],
          subjectCid: checkSubject(runInvocationCid, member), signal,
          targetReads}));
    }
    const currents = [];
    const rowsOf = [];
    const observations = [];
    for (const [index, member] of members.entries()) {
      if (proposals[index].length === 0) fail('InstalledRowEffectEmptyMember');
      const description = owned.describe === undefined ? undefined :
        await owned.describe({member, runInvocationCid,
          dispatchRequestCid: dispatches[index], label: `preview-${index}`,
          approval: reads[index]?.approval, signal});
      currents.push(description);
      const entries = requestsOf(member, proposals[index].map(proposal => {
        const changes = JSON.parse(proposal.changesWire);
        return {value: changes.value,
          selector: guarded(member.kind)
            ? JSON.parse(proposal.selectorWire) : undefined};
      }), description);
      if (member.kind === 'create') {
        // Rows are put in canonical order before anything is derived.
        rowsOf.push(canonicalRows(entries));
        observations.push(undefined);
        continue;
      }
      const observed = await observeRows({member, entries,
        current: description, read: reads[index], signal});
      observations.push(observed);
      rowsOf.push(Object.freeze(entries.map((entry, row) => Object.freeze({
        entry, versionCid: observed[row].versionCid,
        before: observed[row].before}))));
    }
    const entries = Object.freeze(rowsOf.map(rows =>
      Object.freeze(rows.map(row => row.entry))));
    // Every create row passes the provider check before a Preview.
    await checkRows({members, entries, runInvocationCid, dispatches,
      subjectOf: member => checkSubject(runInvocationCid, member), signal});
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
            !sameValue(change.after?.value, entries[index][row].value) ||
            (guarded(members[index].kind) && !sameValue(
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
      invocation: plan.invocation}).commit();
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
    // An update's write plan is verified against its pinned input.
    const plans = [];
    for (const member of members) {
      if (member.kind === 'create') continue;
      const chunks = [];
      const verified = await verifyPinnedEffectPlan({moon, execution,
        previewInputs, previewIndex: member.memberIndex,
        limits: moon.clientProgramEffectInputExportLimits(
          ...exportLimits(plan.outputLimits)),
        planLimits: {maxFields: limits.maxFields, maxWork: limits.planWork,
          maxBytes: limits.preview.maxWireBytes,
          maxNodes: limits.preview.maxNodes,
          maxDepth: limits.preview.maxDepth,
          maxUtf16Units: limits.preview.maxWireBytes},
        onChunk: chunk => { chunks.push(chunk); }, signal});
      plans.push({name: member.effectId, wire: chunks.join(''),
        proof: verified.proof});
    }
    const connectorRecovery = owned.recoveryEntry === undefined ? [] :
      members.map((member, index) => {
        const entry = owned.recoveryEntry({member, current: currents[index]});
        return {memberIndex: index, kind: entry?.kind,
          observationCid: entry?.observationCid, wire: entry?.wire};
      });
    const computation = await issueCompletedEffectfulComputationEvidence({
      execution, store, storedResults, control, admission: plan.admission,
      runDefinition: plan.runDefinition, invocation: plan.invocation,
      observation: plan.observation,
      normalizationJournal: plan.normalizationJournal, authoringContext,
      receiptEvidence: plan.receiptEvidence,
      captureEvidence: plan.captureEvidence, preview: admittedPreview,
      plans: plans.map(({name, wire}) => ({name, wire})),
      effectSourceHoldings: holdings, connectorRecovery,
      contractLimits: plan.contractLimits});
    for (const payload of sourceSet.payloads) {
      if (payload.prepared.status().pending) await payload.prepared.release();
    }
    const ledger = openLedger(identity);
    try {
      const applyPreview = effect.admitPreviewIdentity(preview.wire,
        body.run_identity_cid, preview.authoringCid, requestScope,
        preview.keys, limits.preview.maxWireBytes, limits.preview.maxNodes,
        limits.preview.maxDepth);
      const claims = claimsOf({body, keys: preview.keys, entries,
        requestScope, unit, dispatches,
        unitCid: cid({version: profile.unit,
          run_definition_cid: plan.runDefinition.identity,
          stage_index: members[0].stageIndex}),
        retentionId: plan.results[0].retention.identity});
      const route = physicalRoute({members, entries,
        previewRows: body.effects.map(member => member.changes),
        runInvocationCid, dispatches,
        subjectCid: moon.clientProgramEffectApplySubjectCid(previewInputs),
        applyPreview, ledger, targetReads});
      const preflight = {proofs: plans.map(item => item.proof),
        ...basePreflight({effects: body.effects, members, requestScope,
          keys: preview.keys})};
      return Object.freeze({preview: admittedPreview, computation,
        storedResults,
        apply: {moon, capturedInputs: previewInputs, preflight, ledger,
          members: claims, maxFrontierWork: limits.maxFrontierWork,
          refreshPreflight: route.current, bindDispatch: route.bindDispatch,
          authorization: {gate: authorization, scopes: scopes(members)}},
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
        continuationWire: continuationOf(plan, unit, members, dispatches),
        releaseInputs,
        dispose: () => { releaseInputs(); ledger.close(); }});
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
    const {moon: runMoon, control, store, execution, checkedHost, prepared,
      identity, definition, compilation, signal, targetReads} = facts ?? {};
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
    try {
      return await captureStage({control, store, execution, checkedHost,
        prepared, identity, plan, previewContext, unit, members,
        runInvocationCid, dispatches, requestScope, storedResults, signal,
        targetReads, own: value => { sourceSet = value; },
        ownInputs: release => { releaseInputs = release; }});
    } catch (error) {
      try {
        for (const payload of sourceSet?.payloads ?? []) {
          if (payload.prepared.status().pending) {
            await payload.prepared.release();
          }
        }
        await releaseCompletedRunPreparedPayloads(storedResults, control);
      } catch (cleanupError) {
        if (error !== null && typeof error === 'object') {
          error.cleanupFailure ??= cleanupError;
        }
      }
      try { releaseInputs?.(); }
      catch (cleanupError) {
        if (error !== null && typeof error === 'object') {
          error.cleanupFailure ??= cleanupError;
        }
      }
      throw error;
    }
  }

  // The members of a recovered capture, from its exact saved Preview and
  // continuation. The installation must still hold each Mapping.
  const recoveredMembers = (body, provider) => {
    if (body.effects.length !== provider.members.length) {
      fail('InstalledEffectContinuationMismatch');
    }
    return Object.freeze(body.effects.map((member, index) => {
      const saved = provider.members[index];
      const mapping = installed.find(candidate =>
        candidate.mappingCid === member.resolved_mapping_contract_cid);
      if (saved?.effect_id !== member.effect_id ||
          saved.mapping_cid !== member.resolved_mapping_contract_cid) {
        fail('InstalledEffectContinuationMismatch');
      }
      if (mapping === undefined || !owned.kinds.includes(member.effect_kind)) {
        fail('InstalledRowEffectMappingNotInstalled');
      }
      return Object.freeze({effectId: member.effect_id, memberIndex: index,
        kind: member.effect_kind, mapping, resource: mapping.resource});
    }));
  };

  // Each recovered row's request, rebuilt from its approved Preview row (a
  // create) or from the provider's retained data (an update), and held to
  // exactly the request its durable claim names, the value the Preview
  // approved and, for an update, the Preview's target.
  const recoveredEntries = ({members, body, durable, recorded,
    previewWire}) => {
    const rebuilt = owned.recoverRequests === undefined ? undefined :
      owned.recoverRequests({durable, recorded, previewWire, body});
    const entries = members.map((member, index) => {
      const claims = recorded.members[index]?.claims ?? [];
      const changes = body.effects[index].changes;
      if (claims.length !== changes.length) {
        fail('InstalledEffectContinuationMismatch');
      }
      const rows = rebuilt === undefined
        ? changes.map(change => {
          const prepared = owned.prepareRequest({member,
            value: change.after?.value, selector: undefined,
            current: rebuilt?.currents?.[index]});
          return entryOf(member, prepared?.request, prepared?.requestCid);
        })
        : (rebuilt?.requests?.[index] ?? []).map(request =>
          entryOf(member, request, owned.requestCid(request)));
      if (rows.length !== changes.length) {
        fail('InstalledEffectContinuationMismatch');
      }
      rows.forEach((entry, row) => {
        if (entry.requestCid !== claims[row].canonicalRequestCid ||
            !sameValue(entry.value, changes[row].after?.value) ||
            (guarded(member.kind) && !sameValue(entry.target,
              changes[row].target_row_identity))) {
          fail('ForeignInstalledRowEffectRequest');
        }
      });
      return Object.freeze(rows);
    });
    return {entries: Object.freeze(entries),
      currents: members.map((_, index) => rebuilt?.currents?.[index])};
  };

  // Continue a recovered capture: the exact saved Preview, requests rebuilt
  // and held to their claims and approved rows, and the Ledger's durable
  // claims. The installation must still be the one the Preview was authored
  // against: a changed Mapping, binding, runtime or capability is refused
  // before any provider I/O.
  function prepareRecovered(facts) {
    const {moon: runMoon, control, store, recovered, continuation, signal,
      retainRecoveryOwner, targetReads} = facts ?? {};
    if (runMoon !== moon || !recovered?.computation || !continuation) {
      fail('InvalidInstalledEffectRecovery');
    }
    signal?.throwIfAborted();
    const contractLimits = localContractLimits;
    const provider = continuation.provider ?? continuation;
    // The continuation's installation binding is recorded, not compared: a
    // republished installation resumes only if every Mapping is still
    // installed and it issues and admits the very capability the Preview
    // carries (both checked below).
    if (provider?.version !== profile.continuation ||
        !text(provider[profile.continuationBinding]) ||
        !Array.isArray(provider.members) || !text(provider.program_id) ||
        !text(provider.stage_id)) {
      fail('InstalledEffectContinuationMismatch');
    }
    const {requestIdentity, requestScope, computation: durable} = recovered;
    const {computation, preview, storedResults} = durable;
    const previewWire = control.effectComputationPreviewWire(preview);
    const body = JSON.parse(previewWire);
    const members = recoveredMembers(body, provider);
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
    const ledger = openLedger(requestIdentity);
    // The handle is released exactly once: it is marked released only after
    // its close succeeds, so a failed close stays this owner's pending
    // cleanup and a retry by the same owner closes it.
    let closed = false;
    const releaseLedger = () => {
      if (closed) return;
      ledger.close();
      closed = true;
    };
    const ledgerOwner = Object.freeze({
      async close() { releaseLedger(); },
      async cleanup() { releaseLedger(); return true; },
      cleanupPending: () => !closed});
    if (retainRecoveryOwner !== undefined) {
      try { retainRecoveryOwner(ledgerOwner); }
      catch (error) { releaseLedger(); throw error; }
    }
    try {
      const recorded = ledger.recoverClaimFacts({preview: admitted,
        scope: requestScope, programId: provider.program_id,
        nodeId: provider.stage_id, maxRows: limits.maxRows,
        maxWork: limits.maxWork});
      const {entries, currents} = recoveredEntries({members, body, durable,
        recorded, previewWire});
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
      const route = physicalRoute({members, entries, previewRows,
        runInvocationCid, dispatches,
        subjectCid: control.effectComputationPreviewSemanticCid(preview),
        applyPreview, ledger, targetReads});
      const reconcileStoredResponses = async ({members: claims,
        preview: ledgerPreview}) => {
        for (const [memberIndex, member] of claims.entries()) {
          for (const [rowIndex, claim] of member.claims.entries()) {
            if (ledger.readClaimedResponse(claim) === undefined) continue;
            const entry = entries[memberIndex][rowIndex];
            const ownedClaim = admitRow({applyPreview: ledgerPreview,
              memberIndex, rowIndex, claim, member: members[memberIndex],
              entry, previewRow: previewRows[memberIndex][rowIndex]});
            const recovery = await recoverProjectedEffectResponse({ledger,
              claims: ownedClaim, commonMoon: moon,
              expectedRequestCid: entry.requestCid,
              authorizeEvidenceRead: async () => true,
              projectStored: stored => owned.project({
                member: members[memberIndex], memberIndex, rowIndex,
                preview: ledgerPreview, request: entry.request,
                current: currents[memberIndex],
                observation: Object.freeze({useCid: stored.credentialUseCid,
                  statusCode: stored.statusCode,
                  body: stored.responseBytes}),
                headers: undefined})});
            settle({ledger, claim: ownedClaim, applyPreview: ledgerPreview,
              memberIndex, rowIndex, projected: recovery.recovered});
          }
        }
      };
      return Object.freeze({preview, computation, storedResults,
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
          authorization: {gate: authorization, scopes: scopes(members)}},
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
        dispose: () => { releaseLedger(); }});
    } catch (error) {
      if (retainRecoveryOwner === undefined) releaseLedger();
      throw error;
    }
  }

  return Object.freeze({
    environmentWire,
    connectorBindings: Object.freeze([Object.freeze({connectorId,
      bindingCid})]),
    connectorRegistration, connectorRevision, connection,
    mappings: Object.freeze(installed.map(mapping => Object.freeze({
      resource: mapping.resource, target: mapping.target,
      mappingRef: mapping.mappingRef, mappingCid: mapping.mappingCid}))),
    prepareCaptured, prepareRecovered,
    close: () => site.close(),
  });
}
