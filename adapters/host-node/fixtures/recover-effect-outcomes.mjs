// Recover recorded Effect claims and optionally publish in a fresh process.
// This uses the real Store and SQLite Ledger; it never opens a write Site.
import {createPublicKey} from 'node:crypto';
import {readFileSync} from 'node:fs';
import * as moon from
  '../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as salesforceMoon from
  '../../../_build/js/release/build/connectors/salesforce/host_node/host_node.js';
import {publishCompletedEffectfulRun, recoverCompletedEffectfulComputation} from
  '../../host-common/completed-run-publication.mjs';
import {runtimeCore} from '../../host-common/runtime-core.mjs';
import {checked} from '../../host-common/runtime-result.mjs';
import {openLocalPublicationStore} from
  '../../store-local/publication-store.mjs';
import {openEffectLedger} from '../effect-ledger.mjs';
import {issueAuthorizedEffectSetReceipt} from
  '../effect-response-recovery.mjs';
import {recoverCapturedSalesforceSingleRequests} from
  '../salesforce-effect-write.mjs';
import {captureSalesforceSingleEffectWrite} from
  '../salesforce-effect-write.mjs';
import {applyRecoveredEffectSet} from '../effect-run-apply.mjs';
import {syncSalesforceCatalog} from
  '../../site-node/salesforce-catalog-sync.mjs';
import {refreshSalesforceEffectWriteCatalogs} from
  '../../site-node/salesforce-effect-current-catalog.mjs';
import {observeSalesforceTargetSet} from
  '../../site-node/salesforce-target-observation.mjs';
import {openSqliteCredentialJournal} from
  '../../site-node/sqlite-credential-journal.mjs';

function restoreSiteConnection(connection, control) {
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
    list: authorization(connection.list, 'restart-catalog-list'),
    describe: authorization(connection.describe, 'restart-describe'),
    observe: authorization(connection.observe, 'restart-observe'),
    write: authorization(connection.write, 'restart-write'),
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
  ledger = openEffectLedger({moon, root: input.ledgerRoot,
    authorityScopeCid: input.authorityScopeCid,
    callerRequestId: input.callerRequestId, maxEntryBytes: 4096});
  const scope = core.effectApplicationControl.logicalRequestScope(
    input.authorityScopeCid, input.callerRequestId, 256);
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
  if (input.applyPrepared === true) {
    if (!recoveredSalesforce ||
        !Array.isArray(input.salesforceRecovery.sites) ||
        input.salesforceRecovery.sites.length !== recorded.members.length ||
        typeof input.riskWire !== 'string') {
      throw new Error('InvalidPreparedEffectSiteRecovery');
    }
    const credentialControl = core.remoteCredentialControl;
    activeSites = input.salesforceRecovery.sites.map(connection =>
      restoreSiteConnection(connection, credentialControl));
    const riskBody = JSON.parse(input.riskWire);
    const risk = checked(moon.clientProgramAdmitEffectRiskAcceptanceBody(
      input.riskWire, 8192, 256, 12));
    let currentCatalogs;
    const applied = await applyRecoveredEffectSet({
      moon, store, publicationControl: control,
      computation: recovered.computation, preview: recovered.preview,
      ledger, requestScope: scope, programId: input.programId,
      nodeId: input.nodeId, maxRows: input.maxRows,
      maxFrontierWork: input.maxWork,
      maxRecoveryWork: input.maxWork,
      keyLimits: {maxBytes: 128, maxNodes: 8, maxDepth: 3,
        maxWork: input.maxWork},
      refreshPreflight: async ({signal}) => {
        currentCatalogs = await refreshSalesforceEffectWriteCatalogs({
          moon: salesforceMoon,
          members: activeSites.map((site, memberIndex) => ({
            requests: recoveredSalesforce.requests[memberIndex],
            refreshCatalog: async () => syncSalesforceCatalog({
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
          })), maxMembers: recorded.members.length,
          maxRows: input.maxRows, signal,
        });
        const targets = await observeSalesforceTargetSet({
          moon: salesforceMoon,
          members: activeSites.map((site, memberIndex) => ({
            requests: recoveredSalesforce.requests[memberIndex],
            currentCatalog: currentCatalogs[memberIndex],
            authorizationForRow: async rowIndex => ({...site.observe,
              useId: `restart-observe-${rowIndex}`}),
            credential: site.credential,
            limits: {maxResponseBytes: 1024, maxNodes: 32,
              maxDepth: 5, maxIdentityBytes: 4096},
          })), maxMembers: recorded.members.length,
          maxRows: input.maxRows, maxTotalResponseBytes: 4096, signal,
        });
        const effects = previewBody.effects;
        return {
          sources: effects.map(member => member.source_binding_cid),
          contracts: effects.map(member =>
            member.resolved_mapping_contract_cid),
          capabilities: effects.map(member =>
            member.capability_evidence_cid),
          authorities: effects.map(member => member.authority_scope_cid),
          observedRows: effects.flatMap(member => member.row_order),
          guardVersions: targets.flatMap(member => member.map(target =>
            target.versionCid)),
          routes: effects.map(member =>
            checked(moon.clientProgramEffectApplyCapabilityFromCodes(
              member.capability_evidence_cid, 0, 0, 0,
              true, true, 2, 1))),
          risk, reviewProjectionCid: riskBody.review_projection_cid,
          authorityScopeCid: riskBody.authority_scope_cid,
          policyCid: riskBody.policy_cid,
          validityCid: riskBody.validity_evidence_cid,
          issuerCid: riskBody.issuer_evidence_cid,
          authenticationCid: riskBody.authentication_evidence_cid,
          issuerKind: riskBody.issuer_kind, decision: riskBody.decision,
          requestScope: scope,
          maxMembers: effects.length, maxRows: input.maxRows,
          maxFootprintWork: input.maxRows, maxWork: input.maxWork,
        };
      },
      dispatchRow: async ({memberIndex, rowIndex, claim}) => {
        const site = activeSites[memberIndex];
        const received = await captureSalesforceSingleEffectWrite({
          ledger, commonMoon: moon, admittedPreview,
          memberIndex, rowIndex,
          rowPreviewCid: previewBody.effects[memberIndex]
            .changes[rowIndex].row_preview_cid,
          claim, moon: salesforceMoon,
          request: recoveredSalesforce.requests[memberIndex][rowIndex],
          currentObservation: currentCatalogs[memberIndex],
          authorization: {...site.write,
            useId: `restart-write-${memberIndex}-${rowIndex}`},
          credential: site.credential,
          limits: {maxRequestBytes: 1024, maxResponseBytes: 1024,
            maxNodes: 32, maxDepth: 5},
        });
        if (!received.terminal?.created) {
          throw new Error('PreparedEffectWriteUnsettled');
        }
      },
    });
    dispatched = applied.dispatched;
    recorded = ledger.recoverRecordedClaims({
      preview: admittedPreview, scope,
      programId: input.programId, nodeId: input.nodeId,
      maxRows: input.maxRows, maxWork: input.maxWork,
    });
  }
  const issued = input.prepared === true && input.applyPrepared !== true
    ? undefined :
    await issueAuthorizedEffectSetReceipt({
    ledger, preview: admittedPreview, publicationPreview: recovered.preview,
    commonMoon: moon, authorizeEvidenceRead: async () => true,
    members: recorded.members.map(member => ({
      rowOwners: member.claims.map(claim => ({claim})), replayed: true,
    })),
    limits: input.limits,
    });
  const publication = input.publish === true
    ? await publishCompletedEffectfulRun({
      execution: null, store, storedResults: recovered.storedResults,
      control, computation: recovered.computation,
      preview: recovered.preview, ledger, issuedSet: issued,
      request: input.request,
      attempt: {...input.attempt,
        externalIdempotencyKey: input.attempt.externalIdempotencyKey},
      contractLimits: input.limits,
      now: () => input.publicationTime, signal: undefined,
    })
    : undefined;
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
