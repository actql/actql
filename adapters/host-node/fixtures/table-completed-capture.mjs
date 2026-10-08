// Shared actual capture setup for Table recovery fixtures. No Catalog receipt,
// approval or send permission is fabricated by this helper.
import {storeCompletedRunResultSet} from '../../host-common/completed-run-publication.mjs';
import {capturedTableRecoveryRecord} from '../table-capture-recovery.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;

export const tableFixtureWriteFootprint = index => ({
  kind: 'collection', resource_identity_scheme_cid: cid('f'),
  provider_namespace: 'reference', provider_boundary_cid: cid(String(index)),
  resource_kind: 'Account', provider_object_identity_cids: [],
});

export async function completedTableCaptureOptions({fixture: f, retained, preview,
  tableInputs = [f.tableInput], tablePreviews = [f.tablePreview]}) {
  const control = f.sourceControl, limits = f.options.contractLimits;
  const plan = tableFixturePublicationPlan(f);
  const authoringContext = control.admitRunEvidence('authoring_context',
    JSON.stringify(JSON.parse(f.authored._0).authoring_context), limits);
  const storedResults = f.capturedResults ?? await storeCompletedRunResultSet({execution: f.execution,
    store: f.physicalStore, control, runDefinition: plan.runDefinition,
    invocation: plan.invocation, results: plan.results,
    outputLimits: f.outputLimits, contractLimits: limits});
  return {execution: f.execution, store: f.physicalStore, storedResults, control,
    admission: plan.admission, runDefinition: plan.runDefinition,
    invocation: plan.invocation, observation: plan.observation,
    normalizationJournal: plan.normalizationJournal, authoringContext,
    receiptEvidence: plan.receiptEvidence, captureEvidence: plan.captureEvidence,
    preview, plans: [], effectSourceHoldings: retained.holdings,
    connectorRecovery: tableInputs.map((tableInput, index) =>
      capturedTableRecoveryRecord({control, tableInput, tablePreview: tablePreviews[index]})),
    contractLimits: limits};
}

// Actual checked computation/publication facts reused by the production hook
// fixture. This does not create a captured Run, Preview, input or Ledger claim.
export function tableFixturePublicationPlan(f) {
  const context = f.options.localEvidenceContext;
  const normalizationJournal = f.sourceControl.sealRunEvidence('normalization_journal',
    JSON.stringify({version: 'actql-normalization-journal/0.1',
      rule_catalog_cid: cid('1'), entries: []}), f.options.contractLimits);
  return {admission: context.admission, runDefinition: context.runDefinition,
    invocation: context.runInvocation, observation: context.observation,
    normalizationJournal,
    results: f.execution.resultInventory.map(() => ({retention: f.options.retention,
      evidenceContext: {computationContractCid: cid('2'), inputRelationCids: [],
        scopeCid: cid('3'), effectiveDataPolicyCid: cid('d'), authorityScopeCid: cid('a')}})),
    receiptEvidence: {bindings: [], sourceEvidence: [], modelEvidence: [],
      barrierAttemptReceiptCids: []},
    captureEvidence: {pendingSourceStateAdvances: [], modelEvidence: []},
    localEvidenceContext: f.options.localEvidenceContext,
    outputLimits: f.outputLimits, contractLimits: f.options.contractLimits,
    request: {namespaceId: 'namespace-a', authorityScopeCid: cid('e'),
      publicationPolicyCid: cid('5'), publicationTargetCid: cid('7'),
      requestedAt: '2026-09-24T00:00:00.000Z'},
    attempt: {attemptId: 'table-hook-attempt', fenceCid: cid('6'),
      externalIdempotencyKey: 'table-hook', attemptedAt: '2026-09-24T00:00:00.000Z'},
    now: () => '2026-09-24T00:00:00.000Z'};
}
