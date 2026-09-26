// Recover Effect claims and optionally resume or publish in a fresh process.
// This uses the real Store and SQLite Ledger.
import assert from 'node:assert/strict';
import {createPublicKey} from 'node:crypto';
import {readFileSync} from 'node:fs';
import * as moon from
  '../../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as salesforceMoon from
  '../../../../../_build/js/release/build/connectors/salesforce/host_node/host_node.js';
import {recoverCompletedEffectfulComputation} from
  '../../../../host-common/completed-run-publication.mjs';
import {runtimeCore} from '../../../../host-common/runtime-core.mjs';
import {checked} from '../../../../host-common/runtime-result.mjs';
import {openLocalPublicationStore} from
  '../../../../store-local/publication-store.mjs';
import {openEffectLedger} from '../../../../host-node/effect-ledger.mjs';
import {openClientRequestJournal} from
  '../../../../host-node/client-request-journal.mjs';
import {issueAuthorizedEffectSetReceipt} from
  '../../../../host-node/effect-response-recovery.mjs';
import {recoverCapturedSalesforceSingleRequests} from
  '../../host/salesforce-effect-write.mjs';
import {reconcileStoredSalesforceSingleEffectWrite} from
  '../../host/salesforce-effect-write.mjs';
import {installSalesforceEffectCurrentUse} from
  '../../host/salesforce-effect-current-use.mjs';
import {installSalesforceEffectDispatch} from
  '../../host/salesforce-effect-dispatch.mjs';
import {issueSalesforceEffectCapability} from
  '../../site/salesforce-effect-capability.mjs';
import {applyRecoveredEffectSet} from '../../../../host-node/effect-run-apply.mjs';
import {completeRecoveredEffectRun} from '../../../../host-node/entry.mjs';
import {allowAllAuthorization} from '../../../../host-node/authorization-fixture.mjs';
import {syncSalesforceCatalog} from
  '../../site/salesforce-catalog-sync.mjs';
import {openSqliteCredentialJournal} from
  '../../../../site-node/sqlite-credential-journal.mjs';

function restoreSiteConnection(connection, control, usePrefix) {
  const journal = openSqliteCredentialJournal(connection.journalRoot, {
    credentialAuthorities: new Map([['credential-authority-a',
      new Map([['credential-key-a', createPublicKey(
        connection.authorityPublicKey)]])]]),
  });
  const authorization = (entry, useId) => {
    const grant = control.admitJson(entry.wire, entry.cid);
    const p = control.projection(grant);
    return Object.freeze({grant, useId, scope: Object.freeze({
      issuerAuthority: p[1], principal: p[2], tenant: p[3],
      environment: p[4], siteKey: p[5], siteGeneration: Number(p[6]),
      runtimeBundleCid: p[7], connectorRegistration: p[8],
      connectorRevision: p[9], resourceOrigin: p[10], operation: p[11],
      runInvocationCid: p[12], taskAttempt: Number(p[13]),
      dispatchRequestCid: p[14], expiresUnixMilliseconds: BigInt(p[15]),
      maxUses: Number(p[16]),
    })});
  };
  return Object.freeze({journal, origin: connection.origin,
    orgId: connection.orgId,
    list: authorization(connection.list, `${usePrefix}-catalog-list`),
    describe: authorization(connection.describe, `${usePrefix}-describe`),
    observe: authorization(connection.observe, `${usePrefix}-observe`),
    write: authorization(connection.write, `${usePrefix}-write`),
    credential: Object.freeze({orgId: connection.orgId, control, journal,
      ca: Buffer.from(connection.caBase64, 'base64'),
      now: () => 1_999_999_999_999,
      resolveSecret: async () => 'test-only-secret'}),
  });
}

const input = JSON.parse(readFileSync(0, 'utf8'));
if (input.prepared === true && input.publish === true &&
    input.applyPrepared !== true) {
  throw new Error('PreparedEffectCannotPublish');
}
const core = runtimeCore(moon);
const control = core.publicationControl;
const store = await openLocalPublicationStore({
  directory: input.directory,
  storeAuthorityCid: input.storeAuthorityCid,
  capacityBytes: input.capacityBytes,
  maxObjectBytes: input.maxObjectBytes,
  maxObjects: input.maxObjects,
  maxContractNodes: input.maxContractNodes,
  maxContractDepth: input.maxContractDepth,
  privateEvidenceKey: Buffer.alloc(32, 4),
}, control);
let ledger;
let failure;
let activeSites = [];
try {
  const runDefinition = control.admit('run_definition',
    input.runDefinitionWire, input.limits);
  const recovered = await recoverCompletedEffectfulComputation({
    store, control, runDefinition, contractLimits: input.limits,
  });
  const requests = openClientRequestJournal(input.requestJournalRoot);
  let requestIdentity;
  try {
    const key = {tenantId: 'tenant-a',
      authorityScopeCid: input.authorityScopeCid,
      requestId: input.callerRequestId};
    const retained = requests.lookupDefinition(key, moon, control);
    assert.equal(retained?.runDefinition.identity, runDefinition.identity);
    requestIdentity = requests.lookupIdentity(key, moon);
    assert.ok(requestIdentity);
  } finally {
    requests.close();
  }
  ledger = openEffectLedger({moon, root: input.ledgerRoot,
    authorityScopeCid: moon.clientRequestAuthorityScopeCid(requestIdentity),
    callerRequestId: moon.clientRequestCallerId(requestIdentity),
    maxEntryBytes: 4096});
  const scope = moon.clientRequestLogicalScope(requestIdentity);
  const admittedPreview = control.effectComputationPreviewLedgerIdentity(
    recovered.preview);
  let recorded = (input.prepared === true
    ? ledger.recoverClaimFacts
    : ledger.recoverRecordedClaims)({
    preview: admittedPreview, scope,
    programId: input.programId, nodeId: input.nodeId,
    maxRows: input.maxRows, maxWork: input.maxWork,
  });
  const previewWire = control.effectComputationPreviewWire(
    recovered.preview);
  const previewBody = JSON.parse(previewWire);
  const recoveredKeys = input.prepared === true
    ? core.effectApplicationControl.recoveredPreviewKeys(
      admittedPreview, scope, recorded.members.length, input.maxRows,
      input.maxWork, 128, 8, 3)
    : undefined;
  const recoveredSalesforce = input.prepared === true &&
    input.salesforceRecovery !== undefined
    ? recoverCapturedSalesforceSingleRequests({
      moon: salesforceMoon, recovered, recorded, previewWire,
      runIdentityCid: previewBody.run_identity_cid,
      authoringContextCid:
        previewBody.authoring_context.authoring_context_cid,
      previewLimits: input.limits,
      bodyLimits: input.salesforceRecovery.bodyLimits,
      requestLimits: input.salesforceRecovery.requestLimits,
      maxMembers: recorded.members.length, maxRows: input.maxRows,
      maxRetainedBytes: input.salesforceRecovery.maxRetainedBytes,
    }) : undefined;
  let dispatched = null;
  let reconciledResponse = null;
  if (input.applyPrepared === true) {
    if (!recoveredSalesforce ||
        !Array.isArray(input.salesforceRecovery.sites) ||
        input.salesforceRecovery.sites.length !== recorded.members.length ||
        (input.riskWire !== undefined &&
          typeof input.riskWire !== 'string') ||
        !input.preflightContext) {
      throw new Error('InvalidPreparedEffectSiteRecovery');
    }
    const credentialControl = core.remoteCredentialControl;
    const usePrefix = input.recoveryPass === undefined ? 'restart' :
      `restart-${input.recoveryPass}`;
    activeSites = input.salesforceRecovery.sites.map(connection =>
      restoreSiteConnection(connection, credentialControl, usePrefix));
    const riskBody = input.riskWire === undefined
      ? undefined : JSON.parse(input.riskWire);
    const risk = input.riskWire === undefined ? undefined : checked(
      moon.clientProgramAdmitEffectRiskAcceptanceBody(
        input.riskWire, 8192, 256, 12));
    const preflightContext = riskBody ?? input.preflightContext;
    const reconcileStoredResponses = input.reconcileSavedResponse === true
      ? async ({members, preview}) => {
        const usesBefore = activeSites.map(site =>
          site.journal.recover().length);
        const recoveryOptions = {
          ledger, commonMoon: moon, admittedPreview: preview,
          memberIndex: 0, rowIndex: 0,
          rowPreviewCid: previewBody.effects[0].changes[0].row_preview_cid,
          claim: members[0].claims[0], moon: salesforceMoon,
          request: recoveredSalesforce.requests[0][0],
          resourceOrigin: activeSites[0].origin,
          authorizeEvidenceRead: async () => true,
          limits: {maxRequestBytes: 1024, maxResponseBytes: 1024,
            maxNodes: 32, maxDepth: 5},
        };
        await assert.rejects(
          reconcileStoredSalesforceSingleEffectWrite({
            ...recoveryOptions, authorizeEvidenceRead: async () => false,
          }), {code: 'EffectEvidenceAccessDenied'});
        await assert.rejects(
          reconcileStoredSalesforceSingleEffectWrite({
            ...recoveryOptions,
            resourceOrigin: `${activeSites[0].origin}/foreign`,
          }), {code: 'ForeignSalesforceEffectResponse'});
        const settled = await reconcileStoredSalesforceSingleEffectWrite(
          recoveryOptions);
        const repeated = await reconcileStoredSalesforceSingleEffectWrite(
          recoveryOptions);
        if (!settled.terminal?.created ||
            repeated.outcomeReceipt?.identity !==
              settled.outcomeReceipt?.identity ||
            activeSites.some((site, index) =>
              site.journal.recover().length !== usesBefore[index])) {
          throw new Error('PreparedEffectResponseNotReconciled');
        }
        reconciledResponse = true;
      } : undefined;
    const effects = previewBody.effects;
    const prepareCurrentUse = () => {
      const capabilities = activeSites.map((site, memberIndex) =>
        issueSalesforceEffectCapability({moon: salesforceMoon,
          requests: recoveredSalesforce.requests[memberIndex],
          currentObservation: recoveredSalesforce.catalogs[memberIndex],
          authorization: site.write, credential: site.credential,
          maxRows: input.maxRows, maxBytes: 20000}));
      return installSalesforceEffectCurrentUse({
        moon: salesforceMoon, commonMoon: moon,
        observedRows: effects.flatMap(member => member.row_order),
        members: activeSites.map((site, memberIndex) => ({
          requests: recoveredSalesforce.requests[memberIndex],
          capability: capabilities[memberIndex],
          refreshCatalog: async ({signal} = {}) => syncSalesforceCatalog({
            moon: salesforceMoon, apiVersion: 'v62.0',
            connectionRevision: 'connection-revision-a',
            orgId: site.orgId, syncOccurrence: 'catalog-sync-restart',
            maxObservationBytes: 10000,
            listAuthorization: site.list,
            authorizationForDescribe: async () => site.describe,
            credential: site.credential,
            listLimits: {maxBytes: 10000, maxNodes: 1000, maxDepth: 20,
              maxResources: 20, maxSelected: 20, maxNameUnits: 1000},
            describeLimits: {maxBytes: 10000, maxNodes: 1000,
              maxDepth: 20, maxFields: 20, maxNameUnits: 1000}, signal,
          }),
          target: {
            authorizationForRow: async rowIndex => ({...site.observe,
              useId: `${usePrefix}-observe-${rowIndex}`}),
            credential: site.credential,
            limits: {maxResponseBytes: 1024, maxNodes: 32,
              maxDepth: 5, maxIdentityBytes: 4096},
          },
        })), maxMembers: effects.length, maxRows: input.maxRows,
        maxTotalResponseBytes: 4096,
      });
    };
    let currentUse;
    const preflight = {
      sources: effects.map(member => member.source_binding_cid),
      contracts: effects.map(member => member.resolved_mapping_contract_cid),
      capabilities: effects.map(member => member.capability_evidence_cid),
      authorities: effects.map(member => member.authority_scope_cid),
      routes: effects.map(member =>
        checked(moon.clientProgramEffectApplyCapabilityFromCodes(
          member.capability_evidence_cid, 0, 0, 0,
          true, true, 2, 1))),
      risk, reviewProjectionCid: preflightContext.review_projection_cid,
      authorityScopeCid: preflightContext.authority_scope_cid,
      policyCid: preflightContext.policy_cid,
      validityCid: preflightContext.validity_evidence_cid,
      issuerCid: preflightContext.issuer_evidence_cid,
      authenticationCid: preflightContext.authentication_evidence_cid,
      issuerKind: preflightContext.issuer_kind,
      decision: preflightContext.decision,
      requestScope: scope,
      maxMembers: effects.length, maxRows: input.maxRows,
      maxFootprintWork: input.maxRows, maxWork: input.maxWork,
    };
    const applied = await applyRecoveredEffectSet({
      moon, store, publicationControl: control,
      computation: recovered.computation, preview: recovered.preview,
      ledger, requestScope: scope, programId: input.programId,
      nodeId: input.nodeId, maxRows: input.maxRows,
      maxFrontierWork: input.maxWork,
      maxRecoveryWork: input.maxWork,
      keyLimits: {maxBytes: 128, maxNodes: 8, maxDepth: 3,
        maxWork: input.maxWork},
      authorization: {gate: await allowAllAuthorization(),
        scopes: activeSites.map(site => ({
          connection: `salesforce:${site.orgId}`,
          resource: 'Test_Record__c',
        }))},
      reconcileStoredResponses,
      refreshPreflight: ({signal}) => {
        currentUse = prepareCurrentUse();
        return currentUse.refreshPreflight({signal, preflight});
      },
      bindDispatch: ({members, subjectCid, signal}) => {
        assert.equal(subjectCid, previewBody.effect_preview_cid);
        const physicalLedger = input.faultAfterSavedResponse === true
          ? Object.freeze({
            ...ledger,
            recordResponse(observation) {
              ledger.recordResponse(observation);
              throw new Error('LostAfterSavedSalesforceResponse');
            },
          }) : ledger;
        const dispatch = installSalesforceEffectDispatch({
          ledger: physicalLedger, commonMoon: moon, admittedPreview,
          moon: salesforceMoon, currentUse, signal,
          members: activeSites.map((site, memberIndex) => ({
            requests: recoveredSalesforce.requests[memberIndex],
            claims: members[memberIndex].claims,
            authorizationForRow: rowIndex => ({...site.write,
              useId: `${usePrefix}-write-${memberIndex}-${rowIndex}`}),
            credential: site.credential,
            limits: {maxRequestBytes: 1024, maxResponseBytes: 1024,
              maxNodes: 32, maxDepth: 5},
          })),
        });
        return async row => {
          const received = await dispatch(row);
          if (!received.terminal?.created) {
            throw new Error('PreparedEffectWriteUnsettled');
          }
        };
      },
    });
    dispatched = applied.dispatched;
    recorded = ledger.recoverRecordedClaims({
      preview: admittedPreview, scope,
      programId: input.programId, nodeId: input.nodeId,
      maxRows: input.maxRows, maxWork: input.maxWork,
    });
  }
  const receiptOptions = {
    ledger, preview: admittedPreview, publicationPreview: recovered.preview,
    commonMoon: moon, authorizeEvidenceRead: async () => true,
    members: recorded.members.map(member => ({
      rowOwners: member.claims.map(claim => ({claim})), replayed: true,
    })),
    limits: input.limits,
  };
  const publicationOptions = input.publish === true ? {
      execution: null, store, storedResults: recovered.storedResults,
      control, computation: recovered.computation,
      preview: recovered.preview, ledger,
      request: input.request,
      attempt: {...input.attempt,
        externalIdempotencyKey: input.attempt.externalIdempotencyKey},
      contractLimits: input.limits,
      now: () => input.publicationTime, signal: undefined,
  } : undefined;
  let issued, publication;
  if (input.publish === true) {
    const completed = await completeRecoveredEffectRun({
      apply: {moon, store, publicationControl: control,
        computation: recovered.computation, preview: recovered.preview,
        ledger, requestScope: scope, programId: input.programId,
        nodeId: input.nodeId, maxRows: input.maxRows,
        maxFrontierWork: input.maxWork, maxRecoveryWork: input.maxWork,
        keyLimits: {maxBytes: 128, maxNodes: 8, maxDepth: 3,
          maxWork: input.maxWork},
        refreshPreflight: () => {
          throw new Error('SettledRecoveryRefreshedCurrentSite');
        },
        dispatchRow: () => {
          throw new Error('SettledRecoveryResentEffectRow');
        }},
      receipt: receiptOptions,
      publication: publicationOptions,
    });
    assert.equal(completed.status, 'published');
    assert.equal(completed.progress.dispatched, 0);
    issued = completed.issuedSet;
    publication = completed.completed;
  } else if (input.prepared !== true || input.applyPrepared === true) {
    issued = await issueAuthorizedEffectSetReceipt(receiptOptions);
  }
  const answer = {
    capturedRunCid: recovered.computation.capturedRun.identity,
    localInventory: JSON.parse(recovered.computation.capturedRun.wire)
      .effect_source_local_inventory,
    effectIdentities: JSON.parse(control.effectComputationPreviewWire(
      recovered.preview)).effects.map(
      member => member.effect_identity_cid),
    readyRows: Array.from({length: core.effectApplicationControl
      .setFrontierReadyCount(recorded.frontier)}, (_, index) => [
      core.effectApplicationControl.setFrontierReadyMember(
        recorded.frontier, index),
      core.effectApplicationControl.setFrontierReadyRow(
        recorded.frontier, index),
    ]),
    requestCids: recorded.members.map(member => member.claims.map(
      claim => claim.canonicalRequestCid)),
    recoveredKeyCids: recoveredKeys?.map(member => member.map(key =>
      core.effectApplicationControl.dispatchKeyCid(key))) ?? null,
    recoveredCatalogCids: recoveredSalesforce?.catalogs.map(catalog =>
      salesforceMoon.salesforceCatalogObservationCid(catalog)) ?? null,
    dispatched,
    reconciledResponse,
    setReceiptCid: issued?.set.identity ?? null,
    setStatus: issued === undefined ? null : JSON.parse(issued.set.wire).status,
    rowCounts: recorded.members.map(member => member.claims.length),
    publication: publication === undefined ? null : {
      state: publication.publication.state,
      indexCid: publication.publication.index.identity,
    },
  };
  for (const result of recovered.storedResults.results) {
    if (result.prepared.status().pending) {
      await result.prepared.release();
    }
  }
  process.stdout.write(JSON.stringify(answer));
} catch (error) {
  failure = error;
  throw error;
} finally {
  ledger?.close();
  for (const site of activeSites) site.journal.close();
  try { await store.close(); }
  catch (error) { if (failure === undefined) throw error; }
}
