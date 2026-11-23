// Salesforce record writes (create, update and upsert) as a write driver of
// the Host's provider-neutral
// installed row Effect (adapters/host-node/installed-row-effect.mjs). The
// common owners decide capture, the Preview, approval, the Effect Ledger,
// apply, recovery and publication; this driver keeps only Salesforce's own
// meaning: the Resource's current describe, the typed write body and request,
// the target read and its observed guard, the Site-attested write capability,
// the request footprint, the retained describe that rebuilds requests on
// recovery, the send and the typed classification of its reply. Every
// function here is an existing Salesforce owner; nothing is reimplemented.
import {runtimeField, runtimeIsError} from '../../../host-common/compiler-binding.generated.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {checkpointApprovalFacts} from
  '../../../host-common/checkpoint-approval.mjs';
import {canonicalJson} from '../../../host-node/local-account-config.mjs';
import {checkedEffectPreparation} from
  '../../../host-common/effect-preparation-result.mjs';
import {checkedSalesforceCatalogPreparation} from
  '../site/salesforce-effect-preparation-result.mjs';
import {issueSalesforceEffectCapability,
  inspectSalesforceEffectCapability} from
  '../site/salesforce-effect-capability.mjs';
import {observeSalesforceTargetSet} from
  '../site/salesforce-target-observation.mjs';
import {projectSalesforceSingleObservation,
  sendRawSalesforceSingleRecord} from '../site/salesforce-single-write.mjs';
import {recoverCapturedSalesforceSingleRequests} from
  './salesforce-effect-request-recovery.mjs';

import type {ResourceBinding} from './salesforce-resource-resolver.mjs';
import type {recoverNamedSalesforceObservation} from '../site/salesforce-named-describe.mjs';

type Rebuild = Parameters<typeof recoverCapturedSalesforceSingleRequests>[0];
type Target = Parameters<typeof observeSalesforceTargetSet>[0];
type TargetMember = Target['members'][number];
type Capability = Parameters<typeof issueSalesforceEffectCapability>[0];
type Sender = Parameters<typeof sendRawSalesforceSingleRecord>[0];
type Reply = Parameters<typeof projectSalesforceSingleObservation>[0];
type Runtime = Rebuild['moon'] & Target['moon'] & Capability['moon'] & Sender['moon'] & Readonly<{
  salesforceWriteValueRefusal(projection: unknown, issue: unknown): string | undefined;
  salesforcePrepareExecutionWriteBody(mapping: unknown, projection: unknown, value: Uint8Array,
    bytes: number, nodes: number, depth: number): unknown;
  salesforcePrepareSingleWriteRequest(body: unknown, apiVersion: string, kind: number, target: string,
    targetInteger: number, pathBytes: number, targetBytes: number, bodyBytes: number): unknown;
  salesforceSingleWriteRequestCid(request: unknown, origin: string, maxBytes: number): unknown;
  salesforceSingleWriteRequestTargetJson(request: unknown): string | undefined;
  salesforceSingleWriteRequestValue(request: unknown): string;
  salesforceObservedPreviewRowFields(row: unknown): unknown;
  salesforcePrepareObservedPreviewRow(request: unknown, observation: unknown, bytes: number): unknown;
  salesforceSingleWriteMemberFootprint(requests: readonly unknown[], maxRows: number, bytes: number): unknown;
  salesforceWriteEffectOutcomeWire(outcome: unknown): string;
  salesforceProjectSingleEffectOutcome(preview: unknown, memberIndex: number, rowIndex: number, request: unknown,
    response: unknown, identityBytes: number, maxBytes: number, nodes: number, depth: number): unknown;
}>;
type Kind = keyof typeof kindCodes;
type Member = Readonly<{kind: Kind; effectId: string; memberIndex: number; resource: string;
  mapping: Readonly<{mappingCid: string; mappingRef: string}>}>;
type Installed = Readonly<{write: Readonly<{kind: (typeof installedKinds)[Kind];
  fields?: readonly string[]; sources?: readonly Readonly<{target: string}>[]; key?: string}>; mapping: unknown}>;
type Dispatch = Readonly<{runInvocationCid: string; dispatchRequestCid: string}>;
type Grant = Dispatch & Readonly<{operation: string; decision: unknown; resource: string; subjectCid?: string}>;
type Current = Readonly<{observation: unknown}>;
type CurrentEvidence = Current & Readonly<{observationCid: string;
  evidence: Parameters<typeof recoverNamedSalesforceObservation>[0]['evidence']}>;
type DescribeSite = Dispatch & Readonly<{resources: readonly string[]; occurrence: string; approval?: unknown;
  signal?: AbortSignal; readChild?: unknown; controlConstruction?: unknown}>;
type Site = Readonly<{apiVersion: string; instanceOrigin: string; credential: TargetMember['credential'] & Capability['credential'];
  describeEffectCatalog(input: DescribeSite): CurrentEvidence | PromiseLike<CurrentEvidence>;
  admitCheckpointEffectTargetRead(decision: unknown, binding: Readonly<Record<string, unknown>>): unknown;
  attestEffectCapability(input: Dispatch & Readonly<{operation: string}>): NonNullable<Capability['authority']>;
  issueGrant(input: Grant): unknown;
}>;
type Options = Readonly<{salesforceMoon: Runtime; site: Site; mappingOf(cid: string): Installed | undefined;
  nextOccurrence(label: string): string; siteBindingCid: string; generationCid: string;
  limits: Readonly<{preview: Rebuild['previewLimits']; body: Rebuild['bodyLimits']; request: Rebuild['requestLimits'];
    maxMembers: number; maxRows: number; maxRetainedBytes: number; maxIdentityBytes: number; maxTotalResponseBytes: number;
    write: Sender['limits']; target: TargetMember['limits']}>}>;
type Recovery = Pick<Rebuild, 'recorded' | 'previewWire' | 'memberIndexes' | 'reserveRecoveryInput'> &
  Readonly<{durable: Rebuild['recovered']; body: Readonly<{run_identity_cid: string;
    authoring_context: Readonly<{authoring_context_cid: string}>}>}>;
type MemberInput = Readonly<{member: Member}>;
type RowsInput = Readonly<{entries: readonly Readonly<{request: unknown}>[]}>;
type CurrentInput = Readonly<{current: Current}>;
type Construct = <Value>(scope: undefined, callback: () => Value, inputs: readonly []) => Value;

const fail: (code: string) => never = code => {
  throw Object.assign(new Error(code), {code});
};

const OBSERVE_OPERATION = 'salesforce:record:observe';
// The grant operation, and the Salesforce write projection and request code,
// of each installed write kind.
const grantOperations = Object.freeze({create: 'salesforce:record:create',
  update: 'salesforce:record:update', upsert: 'salesforce:record:upsert'});
const kindCodes = Object.freeze({create: 0, update: 1, upsert: 2});
// The installing recipe names the SAME physical operations as this driver.
// These immutable labels are not grants or operation-selection tokens.
export {grantOperations as salesforceWriteOperations,
  OBSERVE_OPERATION as salesforceTargetReadOperation};
// The installed write kind of each Effect kind (a create is installed from a
// Result).
const installedKinds = Object.freeze({create: 'createFromResult',
  update: 'update', upsert: 'upsert'});

const parseExact = (wire: unknown): unknown => {
  if (typeof wire !== 'string') fail('InvalidSalesforceUpdateDriver');
  const value = JSON.parse(wire);
  if (JSON.stringify(value) !== wire) fail('InvalidSalesforceUpdateDriver');
  return value;
};

// A row body, or its typed refusal when a written value is outside its
// declared type: the Resource, field, type and kind, never the value. It is
// refused before any provider I/O for the row, and nothing is rounded.
function writeBody(salesforceMoon: Runtime, result: unknown, projection: unknown) {
  const refusal = runtimeIsError(result)
    ? salesforceMoon.salesforceWriteValueRefusal(projection, runtimeField(result, 0))
    : undefined;
  if (typeof refusal === 'string') {
    throw Object.assign(new Error('SalesforceWriteValueRefused'), {
      code: 'SalesforceWriteValueRefused',
      refusal: Object.freeze(JSON.parse(refusal))});
  }
  return checked(result);
}

// The write driver over one installed Salesforce Site. `mappingOf(cid)` is
// the installed execution Mapping (`{write, mapping}`) of a Mapping CID;
// `nextOccurrence(label)` names one describe of this installation;
// `siteBindingCid` and `generationCid` are the installed Site binding and
// published generation a resumed target-read approval must name.
export function salesforceWriteDriver({salesforceMoon, site, mappingOf,
  nextOccurrence, siteBindingCid, generationCid, limits}: Options) {
  if (!salesforceMoon || !site || typeof mappingOf !== 'function' ||
      typeof nextOccurrence !== 'function' || typeof siteBindingCid !==
        'string' || typeof generationCid !== 'string' || !limits) {
    fail('InvalidSalesforceUpdateDriver');
  }
  const installedOf = (member: Member) => {
    const installed = mappingOf(member.mapping.mappingCid);
    if (installed?.write?.kind !== installedKinds[member.kind]) {
      fail('SalesforceEffectMappingNotInstalled');
    }
    return installed;
  };
  const fieldsOf = (member: Member) => {
    const write = installedOf(member).write;
    return [...(write.fields ?? write.sources!.map(source => source.target))];
  };
  const keyOf = (member: Member) => installedOf(member).write.key ?? '';
  const projectionOf = (member: Member, observation: unknown) => {
    const binding = JSON.parse(
      salesforceMoon.salesforceCatalogObservationJson(observation)).binding as ResourceBinding;
    const fields = fieldsOf(member);
    return checkedSalesforceCatalogPreparation(
      salesforceMoon.salesforcePrepareWriteProjection(observation,
        binding.namespace_id, binding.principal, binding.environment,
        binding.connection_revision, binding.org_id, binding.site_key,
        binding.site_generation, binding.connector_registration,
        binding.connector_revision, binding.resource_origin,
        binding.run_invocation_cid, binding.dispatch_request_cid,
        binding.sync_occurrence, member.resource, kindCodes[member.kind],
        keyOf(member), fields, fields.length),
      salesforceMoon, observation);
  };
  const requestCid = (request: unknown) => checked(
    salesforceMoon.salesforceSingleWriteRequestCid(request,
      site.instanceOrigin, limits.maxIdentityBytes));

  const recoverRequests = ({durable, recorded, previewWire, body, memberIndexes, reserveRecoveryInput}: Recovery) => {
    const rebuilt = recoverCapturedSalesforceSingleRequests({
      moon: salesforceMoon, recovered: durable, recorded, previewWire,
      runIdentityCid: body.run_identity_cid,
      authoringContextCid: body.authoring_context.authoring_context_cid,
      previewLimits: limits.preview, bodyLimits: limits.body,
      requestLimits: limits.request, maxMembers: limits.maxMembers,
      maxRows: limits.maxRows, maxRetainedBytes: limits.maxRetainedBytes,
      memberIndexes, reserveRecoveryInput});
    return {requests: rebuilt.requests,
      currents: rebuilt.catalogs.map(observation => Object.freeze({observation}))};
  };

  return Object.freeze({
    kinds: Object.freeze(['create', 'update', 'upsert']),
    targetRead: Object.freeze({operation: OBSERVE_OPERATION}),
    writeOperation: (member: Member) => grantOperations[member.kind],

    // The Resource's current describe, bound to the member's dispatch.
    describe: ({member, runInvocationCid, dispatchRequestCid, label,
      approval, signal, readChild, controlConstruction}: MemberInput & Omit<DescribeSite, 'resources' | 'occurrence'> & Readonly<{label: string}>) => site.describeEffectCatalog({
      resources: [member.resource], runInvocationCid, dispatchRequestCid,
      occurrence: nextOccurrence(label), approval, signal, readChild, controlConstruction}),

    // A target read approved through the Host's resumed Checkpoint covers
    // only the physical binding of exactly this member of this installation.
    admitTargetReadApproval({member, decision}: MemberInput & Readonly<{decision: unknown}>) {
      const expected = {site_binding_cid: siteBindingCid,
        generation_cid: generationCid, effect_id: member.effectId,
        member_index: member.memberIndex,
        mapping_cid: member.mapping.mappingCid,
        mapping_ref: member.mapping.mappingRef, resource: member.resource,
        effect_kind: member.kind, key: keyOf(member), fields: fieldsOf(member)};
      const binding = (checkpointApprovalFacts(decision)?.physicalBindings as readonly Readonly<Record<string, unknown>>[] | undefined)
        ?.find(candidate => Object.entries(expected).every(([key, value]) =>
          canonicalJson(candidate[key]) === canonicalJson(value)));
      if (binding === undefined) {
        fail('SalesforceEffectTargetReadApprovalNotAdmitted');
      }
      return site.admitCheckpointEffectTargetRead(decision, binding);
    },

    prepareRequest({member, value, selector, current}: MemberInput & CurrentInput & Readonly<{value: unknown; selector: string}>) {
      const projection = projectionOf(member, current.observation);
      const body = writeBody(salesforceMoon,
        salesforceMoon.salesforcePrepareExecutionWriteBody(
          installedOf(member).mapping, projection,
          Buffer.from(JSON.stringify(value)), limits.body.maxBytes,
          limits.body.maxNodes, limits.body.maxDepth), projection);
      // Pure request validation after the exact describe projection and
      // body are prepared: no target or write I/O has started for the row.
      const request = checkedEffectPreparation(
        salesforceMoon.salesforcePrepareSingleWriteRequest(body,
          site.apiVersion, kindCodes[member.kind],
          member.kind === 'create' ? '' : selector, 0,
          limits.request.maxPathBytes, limits.request.maxTargetBytes,
          limits.request.maxBodyBytes));
      return {request, requestCid: requestCid(request)};
    },

    // The value the request writes (as ActQL values) and the record it
    // selects (its Id or typed external value; none for a create).
    requestFacts: (request: unknown) => {
      const target = salesforceMoon.salesforceSingleWriteRequestTargetJson(
        request);
      return {value: parseExact(
        salesforceMoon.salesforceSingleWriteRequestValue(request)),
      ...(target === undefined ? {} : {target: parseExact(target)})};
    },
    requestCid,

    // A refusal by a fully described current Catalog is definitive; an
    // outage or incomplete describe is not.
    recheckRequests({entries, current, controlConstruction}: RowsInput & CurrentInput & Readonly<{controlConstruction?: Construct}>) {
      const recheck = () => {
        for (const entry of entries) {
          checkedSalesforceCatalogPreparation(
            salesforceMoon.salesforceRecheckSingleWriteRequest(entry.request,
              current.observation), salesforceMoon, current.observation);
        }
      };
      return controlConstruction === undefined ? recheck()
        : controlConstruction(undefined, recheck, []);
    },

    // Each row's target, read now, as its observed Preview row: the target
    // identity, the whole-response guard version and the typed before value.
    async observeTargets({entries, current, authorizationForRow, signal, readChild}: RowsInput & CurrentInput &
      Pick<TargetMember, 'authorizationForRow' | 'readChild'> & Readonly<{signal?: AbortSignal}>) {
      const requests = entries.map(entry => entry.request);
      const [observed] = await observeSalesforceTargetSet({
        moon: salesforceMoon, members: [{requests,
          currentCatalog: current.observation, authorizationForRow, readChild,
          credential: site.credential, limits: limits.target}],
        maxMembers: 1, maxRows: limits.maxRows,
        maxTotalResponseBytes: limits.maxTotalResponseBytes, signal});
      return observed.map((row, index) => {
        const fields = salesforceMoon.salesforceObservedPreviewRowFields(
          checked(salesforceMoon.salesforcePrepareObservedPreviewRow(
            requests[index], row.record, limits.maxIdentityBytes)));
        if (!Array.isArray(fields) || fields.length !== 5 ||
            fields[1] !== row.versionCid) {
          fail('ForeignSalesforceEffectPreviewObservation');
        }
        return Object.freeze({identity: parseExact(fields[0]),
          versionCid: fields[1], before: parseExact(fields[2])});
      });
    },

    // The Site-attested capability of the member's requests: each request is
    // exactly the installed Mapping's write, and the evidence binds the
    // installed runtime, connection and current describe.
    issueCapability({member, entries, current, runInvocationCid,
      dispatchRequestCid}: MemberInput & RowsInput & CurrentInput & Dispatch) {
      const requests = entries.map(entry => entry.request);
      const capability = issueSalesforceEffectCapability({
        moon: salesforceMoon, requests, currentObservation: current.observation,
        authority: site.attestEffectCapability({
          operation: grantOperations[member.kind], runInvocationCid,
          dispatchRequestCid}),
        credential: site.credential, mapping: installedOf(member).mapping,
        maxRows: limits.maxRows, maxBytes: limits.preview.maxWireBytes});
      const inspected = inspectSalesforceEffectCapability(capability,
        requests, {currentObservation: current.observation,
          collection: false});
      return Object.freeze({identity: inspected.identity,
        route: inspected.route === 0 ? 'single_serial' : 'collection',
        binding: Object.freeze(JSON.parse(capability.wire).binding)});
    },

    footprint({entries}: RowsInput) {
      const footprint = checked(
        salesforceMoon.salesforceSingleWriteMemberFootprint(
          entries.map(entry => entry.request), limits.maxRows,
          limits.maxIdentityBytes));
      return {kind: runtimeField(footprint, 0), provider_namespace: runtimeField(footprint, 1),
        provider_boundary_cid: runtimeField(footprint, 2),
        resource_identity_scheme_cid: runtimeField(footprint, 3),
        resource_kind: runtimeField(footprint, 4),
        provider_object_identity_cids: runtimeField(footprint, 5)};
    },

    // The retained describe a recovered capture rebuilds its requests from.
    recoveryEntry: ({member, current}: MemberInput & Readonly<{current: CurrentEvidence}>) => ({
      kind: 'salesforce-named-catalog', observationCid: current.observationCid,
      wire: JSON.stringify({evidence: current.evidence,
        apiVersion: site.apiVersion, resourceName: member.resource,
        operation: member.kind, externalTargetField: keyOf(member),
        fieldNames: fieldsOf(member), resourceOrigin: site.instanceOrigin})}),

    recoverRequests,
    // The full original Preview and durable claims are retained; only this
    // installation's global member positions are decoded by its vendor owner.
    recoverMemberRequests: recoverRequests,

    send: ({request, current, authorization, credential, signal, callResource}: CurrentInput &
      Omit<Sender, 'moon' | 'currentObservation' | 'limits'>) =>
      sendRawSalesforceSingleRecord({moon: salesforceMoon, request,
        currentObservation: current.observation, authorization, credential,
        limits: limits.write, signal, callResource}),

    // The typed reply as the common `effect_outcome`, projected by the
    // Salesforce owner against the admitted Preview row.
    project({memberIndex, rowIndex, preview, request, observation}: Pick<Reply, 'request' | 'observation'> &
      Readonly<{memberIndex: number; rowIndex: number; preview: unknown}>) {
      const projected = projectSalesforceSingleObservation({
        moon: salesforceMoon, request, observation, limits: limits.write});
      if (projected?.kind !== 'typed-success-response' &&
          projected?.kind !== 'typed-failure-response') {
        return {kind: projected?.kind};
      }
      const wire = salesforceMoon.salesforceWriteEffectOutcomeWire(checked(
        salesforceMoon.salesforceProjectSingleEffectOutcome(preview,
          memberIndex, rowIndex, request, (projected as {response: unknown}).response,
          limits.maxIdentityBytes, limits.write.maxResponseBytes,
          limits.write.maxNodes, limits.write.maxDepth)));
      return {kind: projected.kind, outcome: parseExact(wire)};
    },
  });
}

// The installed Salesforce Site as the neutral row Effect's credential Site:
// reads and Effect writes are granted only for this Site's own decisions.
export function salesforceRowEffectSite(site: Pick<Site, 'credential' | 'issueGrant'>) {
  return Object.freeze({
    credential: site.credential, callResource: undefined,
    issueReadGrant: ({operation, decision, resource, runInvocationCid,
      dispatchRequestCid}: Grant) => site.issueGrant({operation, decision, resource,
      runInvocationCid, dispatchRequestCid}),
    issueEffectGrant: ({operation, decision, resource, runInvocationCid,
      dispatchRequestCid, subjectCid}: Grant) => site.issueGrant({operation,
      decision, resource, runInvocationCid, dispatchRequestCid, subjectCid}),
    // The bound constructor attaches the original Site's physical cleanup.
  });
}
