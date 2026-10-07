// Shared actual capture setup for Table recovery fixtures. No Catalog receipt,
// approval or send permission is fabricated by this helper.
import {storeCompletedRunResultSet} from '../../host-common/completed-run-publication.mjs';
import {capturedTableRecoveryRecord} from '../table-capture-recovery.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;

export async function completedTableCaptureOptions({fixture: f, retained, preview,
  tableInputs = [f.tableInput], tablePreviews = [f.tablePreview]}) {
  const control = f.sourceControl, limits = f.options.contractLimits;
  const context = f.options.localEvidenceContext;
  const authoringContext = control.admitRunEvidence('authoring_context',
    JSON.stringify(JSON.parse(f.authored._0).authoring_context), limits);
  const storedResults = await storeCompletedRunResultSet({execution: f.execution,
    store: f.physicalStore, control, runDefinition: context.runDefinition,
    invocation: context.runInvocation,
    results: f.execution.resultInventory.map(() => ({retention: f.options.retention,
      evidenceContext: {computationContractCid: cid('2'), inputRelationCids: [],
        scopeCid: cid('3'), effectiveDataPolicyCid: cid('d'), authorityScopeCid: cid('a')}})),
    outputLimits: f.outputLimits, contractLimits: limits});
  const normalizationJournal = control.sealRunEvidence('normalization_journal',
    JSON.stringify({version: 'actql-normalization-journal/0.1',
      rule_catalog_cid: cid('1'), entries: []}), limits);
  return {execution: f.execution, store: f.physicalStore, storedResults, control,
    admission: context.admission, runDefinition: context.runDefinition,
    invocation: context.runInvocation, observation: context.observation,
    normalizationJournal, authoringContext,
    receiptEvidence: {bindings: [], sourceEvidence: [], modelEvidence: [],
      barrierAttemptReceiptCids: []},
    captureEvidence: {pendingSourceStateAdvances: [], modelEvidence: []},
    preview, plans: [], effectSourceHoldings: retained.holdings,
    connectorRecovery: tableInputs.map((tableInput, index) =>
      capturedTableRecoveryRecord({control, tableInput, tablePreview: tablePreviews[index]})),
    contractLimits: limits};
}
