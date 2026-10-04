// The standard Host's provider-neutral installed row source. A connector
// whose Site driver returns pages of JSON rows (keyed by its declared field
// names) is installed through this adapter: declaration restore, Check
// Environment, read decisions, credential grants, acquisition, capture and
// Source Evidence are the common runtime's and this module's; the connector
// supplies only its view specification, its physical target and its page
// driver. No provider name or type appears here.
import {createHash, createPrivateKey, createPublicKey, randomUUID} from
  'node:crypto';
import {readFile} from 'node:fs/promises';
import {isAbsolute} from 'node:path';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {acquisitionFailure} from '../host-common/acquisition-outcome.mjs';
import {authorizationRuntimeCode} from '../host-common/authorization-gate.mjs';
import {checkpointApprovalFacts} from '../host-common/checkpoint-approval.mjs';
import {canonicalJson, contentCid, createLocalAuthorizationGate} from
  './local-account-config.mjs';
import {openSqliteCredentialJournal} from
  '../site-node/sqlite-credential-journal.mjs';
import {signRemoteCredentialGrant} from
  '../site-node/remote-credential-signature.mjs';
import {callHttpsCredentialResource} from
  '../site-node/https-credential-resource.mjs';

const fail = (code, cause) => {
  throw Object.assign(new Error(code, {cause}), {code});
};
const text = value => typeof value === 'string' && value.length > 0;
const cidPattern = /^sha256:[0-9a-f]{64}$/u;
const cid = value => `sha256:${createHash('sha256')
  .update(canonicalJson(value)).digest('hex')}`;
const contractRoot = new URL('../../spec/contracts/', import.meta.url);

const byCid = values => values.map(value => JSON.parse(value))
  .sort((a, b) => {
    const left = contentCid(a);
    const right = contentCid(b);
    return left < right ? -1 : left > right ? 1 : 0;
  });

// The Check Environment of a restored row declaration: the Host's base
// environment with the declaration's Catalog, source views, contracts,
// manifest entry and evidence members. Built only from the declaration the
// common runtime regenerated; nothing is read from the provider.
export function rowSourceCheckEnvironment(baseWire, declared) {
  const base = JSON.parse(baseWire);
  const {evidence_bundle_cid: _, ...body} = base;
  if (body.version !== 'actql-check-environment/0.1' ||
      body.connector_catalogs.length !== 0 ||
      body.schema_snapshots.length !== 0 ||
      body.connector_capabilities.length !== 0 ||
      body.connector_manifest !== undefined ||
      declared.evidence_schemas.length !== declared.view_bodies.length ||
      declared.evidence_capabilities.length !== declared.view_bodies.length) {
    fail('InvalidRowSourceCheckEnvironmentBase');
  }
  const environment = {...body,
    schema_snapshots: byCid(declared.evidence_schemas),
    connector_capabilities: byCid(declared.evidence_capabilities),
    source_views: byCid(declared.view_bodies),
    contract_registry: byCid(declared.contracts),
    connector_catalogs: [JSON.parse(declared.catalog)],
    connector_manifest: {version: 'actql-connectors/0.1',
      connectors: [JSON.parse(declared.manifest_entry)]}};
  const evidenceCid = contentCid(environment);
  return Object.freeze({
    wire: canonicalJson({...environment, evidence_bundle_cid: evidenceCid}),
    evidenceCid});
}

// The Host account gate of one installed row source, under its own context.
export async function installRowSourceAuthorization({accountConfiguration,
  principalId, root, connectorRegistration}) {
  if (!text(accountConfiguration) || !text(principalId) || !text(root) ||
      !text(connectorRegistration)) {
    fail('InvalidRowSourceAuthorizationInstallation');
  }
  const context = Object.freeze({principal: principalId,
    contextCid: cid({version: 'actql-installed-row-source-context/0.1',
      root, principalId, connectorRegistration})});
  const gate = await createLocalAuthorizationGate({accountConfiguration,
    principal: principalId, context});
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

// The credential Site of one installed row source: the credential authority
// key, the credential journal and the secret resolver. Grants are signed
// only for a read decision the installed gate returned as dispatch for this
// connection and Resource, or for a Checkpoint approval of exactly this
// installation's physical target.
// `responseHeaders` is the installation's declared response header names
// (its `host-bundle.json`); the Site's `callResource` refuses, before any
// credential use, an operation that would observe any other header.
export async function openRowSourceCredentialSite({profile, principalId,
  authorization, connection, connectorRegistration, connectorRevision,
  runtimeBundleCid, commonMoon, resolveSecret, ca, admitsApprovalTarget,
  responseHeaders = [],
  now = () => Date.now(), grantLifetimeMs = 15 * 60 * 1000,
  openCredentialJournal = openSqliteCredentialJournal}) {
  if (!text(profile?.credentialPrivateKeyPath) ||
      !isAbsolute(profile.credentialPrivateKeyPath) ||
      !text(profile.credentialAuthorityId) || !text(profile.credentialKeyId) ||
      !text(profile.journalRoot) || !isAbsolute(profile.journalRoot) ||
      !text(profile.resourceOrigin) || !text(profile.namespaceId) ||
      !text(profile.environment) || !text(profile.siteKey) ||
      !Number.isSafeInteger(profile.siteGeneration) ||
      typeof resolveSecret !== 'function' ||
      typeof admitsApprovalTarget !== 'function') {
    fail('InvalidRowSourceCredentialSite');
  }
  let privateKey;
  try {
    privateKey = createPrivateKey(await readFile(profile.credentialPrivateKeyPath,
      'utf8'));
  } catch (error) {
    fail('InvalidRowSourceCredentialSite', error);
  }
  if (privateKey.asymmetricKeyType !== 'ed25519') {
    fail('InvalidRowSourceCredentialSite');
  }
  const control = runtimeCore(commonMoon).remoteCredentialControl;
  const journal = openCredentialJournal(profile.journalRoot, {
    credentialAuthorities: new Map([[profile.credentialAuthorityId,
      new Map([[profile.credentialKeyId, createPublicKey(privateKey)]])]]),
  });
  let closing = false;
  const credential = Object.freeze({control, journal, resolveSecret, ca, now});
  const approvals = new WeakMap();
  const ensureOpen = () => {
    if (closing) fail('RowSourceSiteClosed');
  };
  function sign({operation, runInvocationCid, dispatchRequestCid, maxUses}) {
    if (!cidPattern.test(runInvocationCid ?? '') ||
        !cidPattern.test(dispatchRequestCid ?? '') ||
        !Number.isSafeInteger(maxUses) || maxUses < 1 || maxUses > 10_000) {
      fail('InvalidRowSourceGrantRequest');
    }
    const scope = Object.freeze({
      issuerAuthority: profile.credentialAuthorityId, principal: principalId,
      namespaceId: profile.namespaceId, environment: profile.environment,
      siteKey: profile.siteKey, siteGeneration: profile.siteGeneration,
      runtimeBundleCid, connectorRegistration, connectorRevision,
      resourceOrigin: profile.resourceOrigin, operation, runInvocationCid,
      taskAttempt: 1, dispatchRequestCid,
      expiresUnixMilliseconds: BigInt(now() + grantLifetimeMs), maxUses,
    });
    const grant = control.prepare(scope);
    journal.acceptGrant(signRemoteCredentialGrant(grant, control, {
      keyId: profile.credentialKeyId, privateKey}), control);
    return Object.freeze({grant, scope});
  }
  if (!Array.isArray(responseHeaders) ||
      responseHeaders.some(name => !text(name))) {
    fail('InvalidRowSourceCredentialSite');
  }
  const declaredHeaders = new Set(responseHeaders);
  const callResource = options => {
    for (const operation of options?.operations?.values?.() ?? []) {
      for (const name of operation?.responseHeaders ?? []) {
        if (!declaredHeaders.has(name)) fail('UndeclaredResponseHeader');
      }
    }
    return callHttpsCredentialResource(options);
  };
  return Object.freeze({
    credential, connection, callResource,
    // Admit a resumed Checkpoint approval only for this installation's own
    // physical target of the same Resource.
    admitCheckpointReadApproval(decision) {
      ensureOpen();
      const facts = checkpointApprovalFacts(decision);
      if (facts === undefined || decision.action !== 'dispatch' ||
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
    issueReadGrant({operation, decision, resource, runInvocationCid,
      dispatchRequestCid, maxUses}) {
      ensureOpen();
      const approved = approvals.get(decision);
      if (approved !== undefined) {
        if (approved !== resource) fail('RowSourceGrantNotAuthorized');
      } else if (!authorization.issued(decision) ||
          decision.action !== 'dispatch' ||
          decision.boundary !== 'acquisition' ||
          decision.contextCid !== authorization.context.contextCid ||
          decision.tuple?.connection !== connection ||
          decision.tuple?.resource !== resource ||
          decision.tuple?.operation !== 'read') {
        fail('RowSourceGrantNotAuthorized');
      }
      return sign({operation, runInvocationCid, dispatchRequestCid, maxUses});
    },
    close() {
      closing = true;
      journal.close();
    },
  });
}

// The installed source adapter of one row declaration (see
// `installed-source.mjs`). `readPages({resource, columns, operation,
// authorizationFor, consumePage, signal})` is the connector's Site driver;
// `physicalTarget(resource, fields)` the exact target an approval covers.
export async function createInstalledRowSource({moon, declaration,
  declared, environmentWire, connectorId, connectorRegistration,
  connectorRevision, site, authorization, readOperation, physicalTarget,
  readPages, bindingCid, limits}) {
  const [queryContract, evidenceContract] = await Promise.all([
    'actql-query-acquisition.json', 'actql-query-process-evidence.json',
  ].map(name => readFile(new URL(name, contractRoot), 'utf8')));
  const sourceRefs = new Set(declared.views.map(view => view.source_ref));
  const preparations = new WeakMap();
  const sourceAccess = Object.freeze({authorization,
    connection: site.connection});
  const decideRead = (prepared, access, signal) =>
    access.authorization.authorize('acquisition', prepared.readTuple, {
      subjectCid: cid({version: 'actql-row-source-acquisition-read/0.1',
        requirementCid: prepared.checkedSource.requirementCid,
        physicalBinding: prepared.physicalBinding}), signal});
  const currentRead = async (prepared, access, signal) => {
    const decision = await decideRead(prepared, access, signal);
    if (decision?.action !== 'dispatch') {
      throw Object.assign(new Error('ExecutionAuthorizationDenied'),
        {code: 'ExecutionAuthorizationDenied', decision});
    }
    return decision;
  };

  async function prepare({preparedProgram, preparedEffect, registry, values,
    fragment, ordered, sourceAccess: access = sourceAccess}) {
    if ((preparedProgram === undefined) === (preparedEffect === undefined)) {
      fail('InvalidInstalledSourcePreparation');
    }
    const effectful = preparedEffect !== undefined;
    const checkedOwner = preparedEffect ?? preparedProgram;
    checked(effectful
      ? moon.clientProgramEffectPrepareQueryAcquisition(checkedOwner, 0, 0)
      : moon.clientProgramPrepareQueryAcquisition(checkedOwner, 0, 0));
    const requirement = checked(effectful
      ? moon.clientProgramEffectPrepareLocalQueryRequirement(checkedOwner, 0,
        0, registry, values, fragment, ordered)
      : moon.clientProgramPrepareLocalQueryRequirement(checkedOwner, 0, 0,
        registry, values, fragment, ordered));
    const facts = checked(
      moon.clientProgramQueryRequirementSourceEvidenceFacts(requirement));
    if (!Array.isArray(facts) || facts.length !== 6 ||
        !facts.every(value => typeof value === 'string')) {
      fail('InstalledSourceEvidenceFactsUnavailable');
    }
    const [sourceRef, sourceContractCid, carrierSchemaContractCid,
      sourceDataPolicyCid, dataClassification, sourceViewContractCid] = facts;
    if (!sourceRefs.has(sourceRef)) fail('InstalledSourceProgramMismatch');
    const [resource, ...fields] = checked(
      moon.clientProgramRowSourceTarget(declaration, requirement));
    const prepared = Object.freeze({
      checkedSource: Object.freeze({
        requirementCid: moon.clientProgramQueryRequirementCid(requirement),
        sourceRef, sourceContractCid, carrierSchemaContractCid,
        sourceDataPolicyCid, dataClassification, sourceViewContractCid,
        inputContractCid:
          moon.clientProgramQueryRequirementInputContractCid(requirement),
        outputContractCid:
          moon.clientProgramQueryRequirementOutputContractCid(requirement),
      }),
      readTuple: Object.freeze({connection: site.connection, resource,
        operation: 'read'}),
      physicalBinding: physicalTarget(resource, fields),
    });
    const decision = await decideRead(prepared, access);
    const refused = decision?.action === 'deny'
      ? authorizationRuntimeCode(decision) : undefined;
    if (refused !== undefined) {
      throw Object.assign(new Error(refused), {code: refused,
        authorization: decision});
    }
    preparations.set(prepared, Object.freeze({checkedOwner, effectful,
      requirement, resource, access}));
    return prepared;
  }

  async function open(options) {
    const state = {started: false, closeFailed: false};
    try {
      return await acquire(state, options);
    } catch (error) {
      throw acquisitionFailure(error, !state.started ? 'not_started'
        : state.closeFailed ? 'unknown' : 'stopped');
    }
  }

  async function acquire(state, {preparedProgram, preparedEffect, registry,
    values, fragment, ordered, sourceAccess: access = sourceAccess, signal,
    preparedSource}) {
    const prepared = preparedSource ?? await prepare({preparedProgram,
      preparedEffect, registry, values, fragment, ordered,
      sourceAccess: access});
    const owner = preparations.get(prepared);
    if (owner === undefined ||
        owner.checkedOwner !== (preparedEffect ?? preparedProgram) ||
        owner.effectful !== (preparedEffect !== undefined) ||
        owner.access !== access) {
      fail('InstalledSourcePreparationMismatch');
    }
    const decision = await currentRead(prepared, access, signal);
    const granted = decision.basis === 'resumed_approval'
      ? site.admitCheckpointReadApproval(decision) : decision;
    const acquisition = checked(moon.clientProgramRowSourcePrepareAcquisition(
      declaration, owner.requirement, queryContract, evidenceContract));
    const columns = [...moon.clientProgramRowSourceColumns(acquisition)];
    const nonce = randomUUID();
    const runInvocationCid = cid({version: 'actql-row-source-acquisition/0.1',
      requirementCid: prepared.checkedSource.requirementCid, nonce});
    const dispatchRequestCid = cid({
      version: 'actql-row-source-acquisition-dispatch/0.1', runInvocationCid});
    const settled = new Set();
    const run = checked(moon.clientProgramRowSourceStart(acquisition, nonce,
      attempt => settled.has(attempt)));
    let closed = false;
    const close = () => {
      if (closed) return;
      closed = true;
      moon.clientProgramRowSourceClose(run);
    };
    try {
      checked(moon.clientProgramRowSourceBegin(run, limits.maxPageBytes,
        limits.maxPageRows, limits.maxCaptureRows));
      const grant = site.issueReadGrant({operation: readOperation,
        decision: granted, resource: owner.resource, runInvocationCid,
        dispatchRequestCid, maxUses: limits.maxPages});
      state.started = true;
      await readPages({resource: owner.resource, columns,
        operation: readOperation, signal,
        // The current read decision is taken again before every request.
        authorizationFor: async index => {
          if (index > 0) await currentRead(prepared, access, signal);
          return {...grant, useId: `${nonce}-read-${index}`};
        },
        consumePage: rows => checked(moon.clientProgramRowSourceAcceptPage(
          run, Buffer.from(JSON.stringify(rows), 'utf8')))});
      checked(moon.clientProgramRowSourceFinish(run));
      // The Site transport for this attempt has returned: its physical read
      // is settled.
      settled.add(moon.clientProgramRowSourceAttempt(run));
      const capture = checked(moon.clientProgramRowSourceCapture(run));
      const source = () => checked(
        moon.clientProgramRowSourceCaptureSource(capture));
      const {checkedOwner, effectful} = owner;
      if ((effectful
        ? moon.clientProgramEffectCapturedSourceMatches(checkedOwner, source())
        : moon.clientProgramCapturedSourceMatches(checkedOwner, source()))
        !== true) {
        fail('InstalledSourceProgramMismatch');
      }
      const identity = checked(effectful
        ? moon.clientProgramIdentifyCapturedEffectSourceRelation(source())
        : moon.clientProgramIdentifyCapturedSourceRelation(source()));
      const logicalInput = checked(effectful
        ? moon.clientProgramEffectIssueCapturedSourceLogical(checkedOwner,
          source(), identity, owner.requirement)
        : moon.clientProgramIssueCapturedSourceLogical(checkedOwner,
          source(), identity, owner.requirement));
      const setup = effectful ? undefined :
        moon.clientProgramOpenCapturedLocalHost(checkedOwner, source(),
          registry, values, 1n, 0n, 0n, 0n, fragment, ordered);
      if (!effectful && setup === undefined) {
        fail('InstalledSourceHostUnavailable');
      }
      return Object.freeze({checkedSource: prepared.checkedSource, identity,
        logicalInput, requirement: owner.requirement, setup,
        capture: Object.freeze({source}),
        issueSourceEvidence: async ({authorityScopeCid,
          effectiveDataPolicyCid}) => {
          await currentRead(prepared, access, signal);
          return checked(moon.clientProgramRowSourceIssueSourceEvidence(
            acquisition, capture, identity, logicalInput, authorityScopeCid,
            effectiveDataPolicyCid, new Date().toISOString()));
        },
        close});
    } catch (error) {
      try { close(); }
      catch { state.closeFailed = true; }
      throw error;
    }
  }

  return Object.freeze({
    realizationKey: 'row-source-acquired',
    connectorRegistration, connectorRevision,
    environmentWire,
    connectorBindings: Object.freeze([Object.freeze({connectorId,
      bindingCid})]),
    readAuthorization: Object.freeze({
      accountConfiguration: authorization.accountConfiguration,
      context: authorization.context}),
    sourceAccess,
    admitsSource: sourceRef => sourceRefs.has(sourceRef),
    prepare, open,
    close: () => site.close(),
  });
}
