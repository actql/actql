// The standard Host's provider-neutral installed Effect for connectors whose
// writes create one provider object per row from a common execution Mapping
// (see installed-row-source.mjs for the Mapping and the credential Site).
// Capture, the Effect Set Preview, the Effect Ledger claims, apply, the
// Receipt, publication and recovery are the common owners'; a connector
// supplies only a write driver:
//
// - `prepareRequest({resource, value})`: the exact request of one row from
//   its mapped target value, and the identity of its exact bytes. Pure.
// - `check` (optional) `{resource, operation}` and
//   `checkRequest({resource, request, authorization, credential,
//   callResource, signal})`: a provider read that must pass for every row
//   before the Preview is authored and again before the Set is applied. It
//   is decided as a read of `check.resource` on the installation's gate.
// - `writeOperation(resource)`: the grant operation of a row's send.
// - `send({resource, request, authorization, credential, callResource,
//   signal})`: one physical send, called only inside a fresh durable claim.
// - `project({resource, request, observation, headers})`: the provider's
//   classification `{kind, outcome?}`. Only a typed success or failure
//   carries an `effect_outcome` and settles the row; anything else leaves
//   the row unknown, and nothing is ever resent.
// - `footprint(resource)`: `{providerNamespace, resourceKind,
//   boundaryCid}` of the opaque write footprint.
//
// No provider name or type appears here. Only `create` Mappings are
// installed: a create has no target to observe, so the Preview's row is the
// exact mapped value and the request is rebuilt from it on recovery.
import {createHash} from 'node:crypto';
import {mkdir} from 'node:fs/promises';
import {checked} from '../host-common/runtime-result.mjs';
import {refusedEffectPreparation} from
  '../host-common/effect-preparation-result.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {issueCompletedEffectfulComputationEvidence,
  releaseCompletedRunPreparedPayloads, storeCompletedRunResultSet} from
  '../host-common/completed-run-publication.mjs';
import {canonicalJson} from './local-account-config.mjs';
import {preparePinnedEffectSourceHoldings, preparePinnedEffectSourceSet,
  retainPinnedEffectDependencyPayloads} from './effect-input-export.mjs';
import {openEffectLedger} from './effect-ledger.mjs';
import {captureClaimedEffectResponse, snapshotEffectDispatchClaim} from
  './effect-physical-dispatch.mjs';
import {recoverProjectedEffectResponse} from './effect-response-recovery.mjs';
import {localContractLimits} from './local-values-plan.mjs';

const CAPABILITY_VERSION = 'actql-installed-row-effect-capability/0.1';
const CONTINUATION_VERSION = 'actql-installed-row-effect-continuation/0.1';

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
const cid = value => `sha256:${createHash('sha256')
  .update(canonicalJson(value)).digest('hex')}`;
const pendingCid = `sha256:${'0'.repeat(64)}`;

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

function checkDriver(driver) {
  if (driver === null || typeof driver !== 'object' ||
      typeof driver.prepareRequest !== 'function' ||
      typeof driver.writeOperation !== 'function' ||
      typeof driver.send !== 'function' ||
      typeof driver.project !== 'function' ||
      typeof driver.footprint !== 'function' ||
      (driver.check !== undefined && (!text(driver.check?.resource) ||
        !text(driver.check.operation) ||
        typeof driver.checkRequest !== 'function'))) {
    fail('InvalidInstalledRowEffectDriver');
  }
  return driver;
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
// mappingCid, body}` as the common runtime generated it) on the credential
// `site` and installation gate `authorization`.
export async function createInstalledRowEffect({moon, mappings,
  environmentWire, connectorId, connectorRegistration, connectorRevision,
  connection, site, authorization, runtimeBundleCid, bindingCid, driver,
  ledgerRoot, limits: suppliedLimits}) {
  const limits = Object.freeze({...defaultLimits, ...suppliedLimits});
  const owned = checkDriver(driver);
  if (!moon || !Array.isArray(mappings) || mappings.length === 0 ||
      !text(environmentWire) || !text(connectorId) ||
      !text(connectorRegistration) || !text(connectorRevision) ||
      !text(connection) || typeof site?.issueEffectGrant !== 'function' ||
      typeof site.issueReadGrant !== 'function' ||
      typeof authorization?.authorize !== 'function' ||
      !/^sha256:[0-9a-f]{64}$/u.test(runtimeBundleCid ?? '') ||
      !text(bindingCid) || !text(ledgerRoot)) {
    fail('InvalidInstalledRowEffect');
  }
  const installed = Object.freeze(mappings.map(mapping => {
    const body = JSON.parse(mapping.body);
    const rule = body.permission_rules?.find(item =>
      item.effect_kind === 'create');
    if (!text(mapping.resource) || !text(mapping.mappingRef) ||
        !text(mapping.mappingCid) || body.mapping_contract_cid !==
          mapping.mappingCid || !Array.isArray(rule?.permissions) ||
        !['required', 'none'].includes(body.minimum_approval)) {
      fail('InvalidInstalledRowEffect');
    }
    return Object.freeze({...mapping, target: body.target_ref,
      requiredPermissions: Object.freeze([...rule.permissions]),
      approval: body.minimum_approval});
  }));
  await mkdir(ledgerRoot, {recursive: true, mode: 0o700});
  const effect = runtimeCore(moon).effectApplicationControl;
  const openLedger = identity => openEffectLedger({moon, root: ledgerRoot,
    authorityScopeCid: moon.clientRequestAuthorityScopeCid(identity),
    callerRequestId: moon.clientRequestCallerId(identity),
    maxEntryBytes: 1_000_000});
  const scopes = members => Object.freeze(members.map(member =>
    Object.freeze({connection, resource: member.resource})));

  // One member of the Effect Unit: its Program descriptor and the installed
  // Mapping the Program resolved. Refused before any I/O when the Program's
  // Mapping is not installed or is not a create.
  const resolveMember = (prepared, {stageIndex, effectId}) => {
    const descriptor = checked(moon.clientProgramEffectMemberDescriptor(
      prepared, stageIndex, effectId, limits.planWork));
    const mapping = installed.find(candidate =>
      candidate.mappingCid === descriptor._5 &&
      candidate.mappingRef === descriptor._4);
    if (mapping === undefined || descriptor._2 !== 'create' ||
        descriptor._6 === undefined) {
      fail('InstalledRowEffectMappingNotInstalled');
    }
    return Object.freeze({stageIndex, effectId: descriptor._1,
      memberIndex: descriptor._0, mapping, resource: mapping.resource});
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
    version: 'actql-installed-row-effect-dispatch/0.1',
    run_invocation_cid: runInvocationCid, effect_id: member.effectId});

  // The exact request of every row of a member, from its mapped values.
  const requestsOf = (member, values) => Object.freeze(values.map(value => {
    const prepared = owned.prepareRequest({resource: member.resource, value});
    if (!prepared?.request || !/^sha256:[0-9a-f]{64}$/u.test(
      prepared.requestCid ?? '')) {
      fail('InvalidInstalledRowEffectRequest');
    }
    return Object.freeze({request: prepared.request,
      requestCid: prepared.requestCid, value});
  }));

  // The capability of a member's requests: this installation's runtime,
  // connection and Mapping, and the exact requests. A changed runtime,
  // binding, Mapping or request is a different capability.
  const capabilityOf = (member, requests) => cid({
    version: CAPABILITY_VERSION,
    connector_registration: connectorRegistration,
    connector_revision: connectorRevision,
    runtime_bundle_cid: runtimeBundleCid, binding_cid: bindingCid,
    connection, resource: member.resource,
    mapping_cid: member.mapping.mappingCid,
    operation: owned.writeOperation(member.resource),
    route: 'single_serial', idempotency: 'unavailable',
    request_cids: requests.map(entry => entry.requestCid)});

  // Every row's provider check, under a current read decision of the check
  // Resource for `subjectCid`. A held or denied read checks nothing.
  const checkRows = async ({members, requests, runInvocationCid, dispatches,
    subjectCid, signal}) => {
    if (owned.check === undefined) return;
    const decision = await authorization.authorize('acquisition', {
      connection, resource: owned.check.resource, operation: 'read'},
    {subjectCid, signal});
    if (decision?.action !== 'dispatch') {
      throw Object.assign(new Error('InstalledRowEffectCheckNotAuthorized'),
        {code: 'InstalledRowEffectCheckNotAuthorized',
          action: decision?.action});
    }
    for (const [index, member] of members.entries()) {
      for (const [rowIndex, entry] of requests[index].entries()) {
        signal?.throwIfAborted();
        const grant = site.issueReadGrant({operation: owned.check.operation,
          decision, resource: owned.check.resource, runInvocationCid,
          dispatchRequestCid: dispatches[index], maxUses: 1});
        await owned.checkRequest({resource: member.resource,
          request: entry.request,
          authorization: {...grant,
            useId: `${dispatches[index]}-check-${subjectCid}-${rowIndex}`},
          credential: site.credential, callResource: site.callResource,
          signal});
      }
    }
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

  // Bind a row's request to its admitted Preview row: the request must be
  // exactly the one the approved row's value prepares, under its claim.
  const admitRow = ({applyPreview, memberIndex, rowIndex, claim, member,
    entry, previewValue}) => {
    const again = owned.prepareRequest({resource: member.resource,
      value: previewValue});
    if (again?.requestCid !== entry.requestCid ||
        claim.canonicalRequestCid !== entry.requestCid) {
      fail('ForeignInstalledRowEffectRequest');
    }
    const rowPreviewCid = moon.strategyEffectPreviewOrderedRowCid(
      applyPreview, memberIndex, rowIndex);
    if (typeof rowPreviewCid !== 'string') {
      fail('InvalidInstalledRowEffectDispatch');
    }
    const ownedClaim = snapshotEffectDispatchClaim(claim);
    effect.admitMemberRow(applyPreview, memberIndex, rowIndex, 'create',
      ownedClaim.scope, rowPreviewCid, ownedClaim.locator, ownedClaim.key);
    return ownedClaim;
  };

  // Current use and physical dispatch over one set of members.
  const physicalRoute = ({members, requests, previewValues, runInvocationCid,
    dispatches, subjectCid, applyPreview, ledger}) => {
    let refreshed = false;
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
      await checkRows({members, requests, runInvocationCid, dispatches,
        subjectCid, signal});
      const capabilities = members.map((member, index) =>
        capabilityOf(member, requests[index]));
      signal?.throwIfAborted();
      refreshed = true;
      return Object.freeze({...preflight, observedRows: Object.freeze([]),
        guardVersions: Object.freeze([]),
        capabilities: Object.freeze(capabilities),
        routes: Object.freeze(capabilities.map(identity => checked(
          moon.clientProgramEffectApplyCapabilityFromCodes(identity, 0, 0, 0,
            true, true, 2, 1))))});
    };
    const bindDispatch = ({members: claims, subjectCid: active, signal,
      decisions}) => {
      if (active !== subjectCid || !refreshed) {
        fail('InvalidInstalledRowEffectRoute');
      }
      const commits = commitDecisions(decisions, subjectCid, members);
      return async ({memberIndex, rowIndex, claim}) => {
        const member = members[memberIndex];
        const entry = requests[memberIndex]?.[rowIndex];
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
          previewValue: previewValues[memberIndex][rowIndex]});
        const grant = site.issueEffectGrant({
          operation: owned.writeOperation(member.resource),
          decision: commits.get(member.resource), resource: member.resource,
          runInvocationCid, dispatchRequestCid: dispatches[memberIndex],
          subjectCid});
        const captured = await captureClaimedEffectResponse({ledger,
          claim: ownedClaim, requestCid: entry.requestCid,
          execute: () => owned.send({resource: member.resource,
            request: entry.request,
            authorization: {...grant, useId:
              `${dispatches[memberIndex]}-write-${subjectCid}-${rowIndex}`},
            credential: site.credential, callResource: site.callResource,
            signal})});
        if (!captured.claimed) {
          return Object.freeze({claimed: false,
            ownership: Object.freeze({action: captured.ownership.action})});
        }
        const projected = owned.project({resource: member.resource,
          request: entry.request,
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
    observedRows: [], guardVersions: [], routes: [],
    risk: undefined, reviewProjectionCid: '', authorityScopeCid: '',
    policyCid: '', validityCid: '', issuerCid: '', authenticationCid: '',
    issuerKind: '', decision: '',
    requestScope, ...(keys === undefined ? {} : {keys}),
    maxMembers: members.length, maxRows: limits.maxRows,
    maxFootprintWork: limits.maxRows, maxWork: limits.maxWork,
  });

  const continuationOf = (plan, unit, members, dispatches) => canonicalJson({
    version: CONTINUATION_VERSION, binding_cid: bindingCid,
    program_id: unit.programId, stage_id: unit.stageId,
    request: plan.request, attempt: plan.attempt,
    members: members.map((member, index) => ({
      effect_id: member.effectId, mapping_cid: member.mapping.mappingCid,
      dispatch_request_cid: dispatches[index]}))});

  // The Preview of the Effect Unit: the common draft with each member's
  // created rows stated as their exact mapped values.
  function authorPreview({control, prepared, inputs, context, requestScope,
    members, requests, capabilities, payloads}) {
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
    const requestOrder = [];
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
      const footprint = owned.footprint(member.resource);
      if (!text(footprint?.providerNamespace) ||
          !text(footprint.resourceKind) ||
          !/^sha256:[0-9a-f]{64}$/u.test(footprint.boundaryCid ?? '')) {
        fail('InvalidInstalledRowEffectDriver');
      }
      const rows = requests[index];
      rowCount += rows.length;
      if (rowCount > limits.maxRows) fail('InstalledRowEffectRowLimit');
      const afterWires = rows.map(entry => JSON.stringify({state: 'present',
        value: entry.value}));
      const inventory = checked(moon.clientProgramEffectCreateRowInventory(
        afterWires, rows.length, maxWireBytes, maxNodes, maxDepth));
      requestOrder.push(Object.freeze(inventory.map(item => item._0)));
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
        capability_evidence_cid: capabilities[index],
        authority_scope_cid: requestAuthority,
        write_footprint: {kind: 'opaque',
          provider_boundary_cid: footprint.boundaryCid,
          provider_namespace: footprint.providerNamespace,
          resource_kind: footprint.resourceKind,
          resource_identity_scheme_cid: cid({
            version: 'actql-installed-row-effect-identity-scheme/0.1',
            connector_registration: connectorRegistration,
            resource: member.resource,
            primary_identity: JSON.parse(member.mapping.body)
              .primary_identity}),
          provider_object_identity_cids: []},
        count: rows.length, max_items: rows.length,
        required_permissions: [...member.mapping.requiredPermissions],
        approval: member.mapping.approval,
        on_item_failure: descriptor._7,
        changes: inventory.map(item => ({
          target_row_identity: parseExactJson(item._1),
          target_guard: {state: 'not_applicable'},
          before: {state: 'absent'},
          after: {state: 'present', value: rows[item._0].value},
          intended_changes: {state: 'present', value: rows[item._0].value},
          row_preview_cid: pendingCid, row_idempotency_key: pendingCid})),
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
      keys: authored._1, requestOrder: Object.freeze(requestOrder)});
  }

  // The Ledger claims of every row of the admitted Preview.
  const claimsOf = ({body, keys, requests, requestScope, unit, dispatches,
    unitCid, retentionId}) => body.effects.map((member, memberIndex) => ({
    claims: member.changes.map((change, rowIndex) => {
      const key = keys[memberIndex][rowIndex];
      const locator = effect.logicalItemLocator(requestScope,
        unit.programId, unit.stageId, member.effect_id,
        canonicalJson(change.target_row_identity), limits.locator.maxBytes,
        limits.key.maxBytes, limits.key.maxNodes, limits.key.maxDepth);
      const canonicalRequestCid = requests[memberIndex][rowIndex].requestCid;
      const basis = effect.ledgerBasis(requestScope, locator, key, unitCid,
        member.effect_member_preview_cid, change.row_preview_cid,
        canonicalRequestCid, cid({
          version: 'actql-installed-row-effect-recovery/0.1',
          dispatch_request_cid: dispatches[memberIndex]}),
        // A create without a provider idempotency key.
        'unavailable', member.capability_evidence_cid, retentionId);
      return {scope: requestScope, locator, key, basis,
        intentFingerprintCid: change.row_preview_cid, canonicalRequestCid};
    })}));

  async function captureStage({control, store, execution, checkedHost,
    prepared, identity, plan, previewContext, unit, members,
    runInvocationCid, dispatches, requestScope, storedResults, signal, own,
    ownInputs}) {
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
      sourceBindingCid: cid({
        version: 'actql-installed-row-effect-source/0.1',
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
    let requests = members.map((member, index) => {
      if (proposals[index].length === 0) fail('InstalledRowEffectEmptyMember');
      return requestsOf(member, proposals[index].map(proposal =>
        JSON.parse(proposal.changesWire).value));
    });
    // Every row passes the provider check before a Preview is authored.
    await checkRows({members, requests, runInvocationCid, dispatches,
      subjectCid: cid({version: 'actql-installed-row-effect-check/0.1',
        run_invocation_cid: runInvocationCid}), signal});
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
      requestScope, members, requests,
      capabilities: members.map((member, index) =>
        capabilityOf(member, requests[index])), payloads});
    // Created rows are applied in the Preview's canonical row order.
    requests = requests.map((rows, index) =>
      Object.freeze(preview.requestOrder[index].map(row => rows[row])));
    const body = JSON.parse(preview.wire);
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
    const computation = await issueCompletedEffectfulComputationEvidence({
      execution, store, storedResults, control, admission: plan.admission,
      runDefinition: plan.runDefinition, invocation: plan.invocation,
      observation: plan.observation,
      normalizationJournal: plan.normalizationJournal, authoringContext,
      receiptEvidence: plan.receiptEvidence,
      captureEvidence: plan.captureEvidence, preview: admittedPreview,
      plans: [], effectSourceHoldings: holdings, connectorRecovery: [],
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
      const claims = claimsOf({body, keys: preview.keys, requests,
        requestScope, unit, dispatches,
        unitCid: cid({version: 'actql-installed-row-effect-unit/0.1',
          run_definition_cid: plan.runDefinition.identity,
          stage_index: members[0].stageIndex}),
        retentionId: plan.results[0].retention.identity});
      const route = physicalRoute({members, requests,
        previewValues: body.effects.map(member => member.changes.map(
          change => change.after.value)),
        runInvocationCid, dispatches,
        subjectCid: moon.clientProgramEffectApplySubjectCid(previewInputs),
        applyPreview, ledger});
      const preflight = {proofs: [], ...basePreflight({
        effects: body.effects, members, requestScope, keys: preview.keys})};
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
  async function prepareCaptured(facts) {
    const {moon: runMoon, control, store, execution, checkedHost, prepared,
      identity, publicationPlan: plan, definition, compilation,
      signal} = facts ?? {};
    if (runMoon !== moon || !plan || !execution || !checkedHost ||
        !prepared || !identity || !definition || !compilation) {
      fail('InvalidInstalledEffectCapture');
    }
    signal?.throwIfAborted();
    const previewContext = {runDefinition: definition,
      runInvocation: plan.invocationOwner,
      compiledPlan: checked(moon.strategyPublicationAdmit('compiled_plan',
        moon.clientProgramEffectCompilationCompiledPlanWire(compilation),
        plan.contractLimits.maxWireBytes, plan.contractLimits.maxNodes,
        plan.contractLimits.maxDepth))};
    const unit = installedRowEffectUnit(moon, compilation);
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
        own: value => { sourceSet = value; },
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

  // Continue a recovered capture: the exact saved Preview, requests rebuilt
  // from its rows, and the Ledger's durable claims. The installation must
  // still be the one the Preview was authored against: a changed Mapping,
  // binding, runtime or request is refused before any provider I/O.
  function prepareRecovered(facts) {
    const {moon: runMoon, control, store, recovered, continuation, signal,
      retainRecoveryOwner} = facts ?? {};
    if (runMoon !== moon || !recovered?.computation || !continuation) {
      fail('InvalidInstalledEffectRecovery');
    }
    signal?.throwIfAborted();
    const contractLimits = localContractLimits;
    const provider = continuation.provider ?? continuation;
    if (provider?.version !== CONTINUATION_VERSION ||
        provider.binding_cid !== bindingCid ||
        !Array.isArray(provider.members) || !text(provider.program_id) ||
        !text(provider.stage_id)) {
      fail('InstalledEffectContinuationMismatch');
    }
    const {requestIdentity, requestScope, computation: durable} = recovered;
    const {computation, preview, storedResults} = durable;
    const previewWire = control.effectComputationPreviewWire(preview);
    const body = JSON.parse(previewWire);
    if (body.effects.length !== provider.members.length) {
      fail('InstalledEffectContinuationMismatch');
    }
    const members = Object.freeze(body.effects.map((member, index) => {
      const saved = provider.members[index];
      const mapping = installed.find(candidate =>
        candidate.mappingCid === member.resolved_mapping_contract_cid);
      if (saved?.effect_id !== member.effect_id ||
          saved.mapping_cid !== member.resolved_mapping_contract_cid) {
        fail('InstalledEffectContinuationMismatch');
      }
      if (mapping === undefined || member.effect_kind !== 'create') {
        fail('InstalledRowEffectMappingNotInstalled');
      }
      return Object.freeze({effectId: member.effect_id, memberIndex: index,
        mapping, resource: mapping.resource});
    }));
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
    let closed = false;
    const ledgerOwner = Object.freeze({
      async close() { closed = true; ledger.close(); },
      async cleanup() { closed = true; ledger.close(); return true; },
      cleanupPending: () => !closed});
    if (retainRecoveryOwner !== undefined) {
      try { retainRecoveryOwner(ledgerOwner); }
      catch (error) { ledger.close(); throw error; }
    }
    try {
      const recorded = ledger.recoverClaimFacts({preview: admitted,
        scope: requestScope, programId: provider.program_id,
        nodeId: provider.stage_id, maxRows: limits.maxRows,
        maxWork: limits.maxWork});
      const previewValues = body.effects.map(member => member.changes.map(
        change => change.after?.value));
      // Each row's request is rebuilt from its approved Preview value and
      // must be exactly the request its durable claim names.
      const requests = members.map((member, index) => {
        const claims = recorded.members[index]?.claims ?? [];
        if (claims.length !== previewValues[index].length) {
          fail('InstalledEffectContinuationMismatch');
        }
        const rows = requestsOf(member, previewValues[index]);
        rows.forEach((entry, rowIndex) => {
          if (entry.requestCid !== claims[rowIndex].canonicalRequestCid) {
            fail('ForeignInstalledRowEffectRequest');
          }
        });
        return rows;
      });
      // The installation as loaded now must state the same capability the
      // Preview carries, for the same requests, before any provider I/O.
      members.forEach((member, index) => {
        if (capabilityOf(member, requests[index]) !==
            body.effects[index].capability_evidence_cid) {
          fail('InstalledRowEffectInstallationChanged');
        }
      });
      const route = physicalRoute({members, requests, previewValues,
        runInvocationCid, dispatches,
        subjectCid: control.effectComputationPreviewSemanticCid(preview),
        applyPreview, ledger});
      const reconcileStoredResponses = async ({members: claims,
        preview: ledgerPreview}) => {
        for (const [memberIndex, member] of claims.entries()) {
          for (const [rowIndex, claim] of member.claims.entries()) {
            if (ledger.readClaimedResponse(claim) === undefined) continue;
            const ownedClaim = admitRow({applyPreview: ledgerPreview,
              memberIndex, rowIndex, claim, member: members[memberIndex],
              entry: requests[memberIndex][rowIndex],
              previewValue: previewValues[memberIndex][rowIndex]});
            const entry = requests[memberIndex][rowIndex];
            const recovery = await recoverProjectedEffectResponse({ledger,
              claims: ownedClaim, commonMoon: moon,
              expectedRequestCid: entry.requestCid,
              authorizeEvidenceRead: async () => true,
              projectStored: stored => owned.project({
                resource: members[memberIndex].resource,
                request: entry.request,
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
        dispose: () => { closed = true; ledger.close(); }});
    } catch (error) {
      if (retainRecoveryOwner === undefined) ledger.close();
      throw error;
    }
  }

  return Object.freeze({
    environmentWire,
    connectorBindings: Object.freeze([Object.freeze({connectorId,
      bindingCid})]),
    connectorRegistration, connectorRevision, connection,
    mappings: Object.freeze(installed.map(mapping => Object.freeze({
      resource: mapping.resource, kind: 'create', target: mapping.target,
      mappingRef: mapping.mappingRef, mappingCid: mapping.mappingCid}))),
    prepareCaptured, prepareRecovered,
    close: () => site.close(),
  });
}
