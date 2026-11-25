import {checked} from './runtime-result.mjs';

// View of the existing Common JS calls. Opaque arguments and raised results
// cross this boundary unchanged and remain subject to the original Common checks.
type CommonEffectBindings = {
  strategyEffectLogicalRequestScope(
    authorityScopeCid: string, callerRequestId: string, maxCallerBytes: number,
  ): unknown;
  strategyEffectLogicalRequestScopeCid(scope: unknown): string;
  strategyEffectDispatchKey(
    scope: unknown, effectPreviewCid: string, rowOrItemKeyWire: string, maxKeyBytes: number,
    maxKeyNodes: number, maxKeyDepth: number,
  ): unknown;
  strategyEffectDispatchKeyCid(key: unknown): string;
  strategyEffectDispatchKeyCorrelationWire(key: unknown): string;
  strategyEffectRecoveredPreviewKeys(
    preview: unknown, scope: unknown, maxMembers: number, maxRows: number, maxWork: number,
    maxKeyBytes: number, maxKeyNodes: number, maxKeyDepth: number,
  ): unknown;
  strategyEffectBatchRowsShareMember(
    firstLocator: unknown, firstKey: unknown, nextLocator: unknown, nextKey: unknown,
  ): boolean;
  strategyEffectLogicalItemLocator(
    scope: unknown, programId: string, nodeId: string, effectId: string, itemCorrelationWire: string,
    maxNameBytes: number, maxItemBytes: number, maxItemNodes: number, maxItemDepth: number,
  ): unknown;
  strategyEffectLogicalItemLocatorCid(locator: unknown): string;
  strategyEffectApplyKey(
    scope: unknown, effectPreviewCid: string, effectId: string, effectMemberPreviewCid: string,
    maxEffectBytes: number,
  ): unknown;
  strategyEffectApplyKeyCid(key: unknown): string;
  strategyEffectRowRecoveryAction(
    expectedLocator: unknown, intentFingerprintCid: string, expectedKey: unknown,
    canonicalRequestCid: string, storedLocatorCid: string, storedFingerprintCid: string,
    storedKeyCid: string, storedRequestCid: string, storedState: number, activeOwner: boolean,
  ): number;
  strategyEffectRowRecoveryActionFromEntry(
    expectedLocator: unknown, intentFingerprintCid: string, expectedKey: unknown,
    canonicalRequestCid: string, stored: unknown, activeOwner: boolean,
  ): number;
  strategyEffectSetFrontier(
    effectIds: unknown, policies: unknown, rowStates: unknown, maxMembers: number, maxRows: number,
    maxWork: number,
  ): unknown;
  strategyEffectSetFrontierFromLedger(
    preview: unknown, scopes: unknown, locators: unknown, keys: unknown, expectedBases: unknown,
    heads: unknown, activeOwners: unknown, maxMembers: number, maxRows: number, maxWork: number,
  ): unknown;
  clientProgramRecoverEffectTargetGuards(
    preview: unknown, scopes: unknown, locators: unknown, keys: unknown, bases: unknown, heads: unknown,
    activeOwners: unknown, maxMembers: number, maxRows: number, maxWork: number,
  ): unknown;
  strategyEffectSetFrontierOutcome(frontier: unknown): number;
  strategyEffectSetFrontierReadyCount(frontier: unknown): number;
  strategyEffectSetFrontierReadyMember(frontier: unknown, index: number): number;
  strategyEffectSetFrontierReadyRow(frontier: unknown, index: number): number;
  strategyEffectSetFootprintConflictsCheck(
    effectIds: unknown, kinds: unknown, namespaces: unknown, boundaryCids: unknown, schemeCids: unknown,
    resourceKinds: unknown, targetCids: unknown, maxMembers: number, maxTargets: number,
    maxWork: number,
  ): unknown;
  strategyEffectPreviewFootprintConflictsCheck(
    previewWire: string, declaredEffectIds: unknown, declaredFailurePolicies: unknown,
    declaredEffectIdentityCids: unknown, maxWireBytes: number, maxNodes: number, maxDepth: number,
    maxMembers: number, maxTargets: number, maxWork: number,
  ): unknown;
  strategyEffectPreviewIdentities(
    previewWire: string, maxWireBytes: number, maxNodes: number, maxDepth: number,
  ): unknown;
  strategyEffectPreviewRowIdentities(
    previewWire: string, maxWireBytes: number, maxNodes: number, maxDepth: number,
  ): unknown;
  strategyEffectPreviewApplyIdentityAdmit(
    previewWire: string, expectedRunIdentityCid: string, expectedAuthoringContextCid: string,
    scope: unknown, expectedKeys: unknown, maxWireBytes: number, maxNodes: number, maxDepth: number,
  ): unknown;
  strategyEffectPreviewApplyIdentity(
    previewWire: string, expectedRunIdentityCid: string, expectedAuthoringContextCid: string,
    scope: unknown, expectedKeys: unknown, maxWireBytes: number, maxNodes: number, maxDepth: number,
  ): unknown;
  strategyEffectPreviewTargetGuardsCheck(
    preview: unknown, rowPreviewCids: unknown, versionCids: unknown, maxRows: number, maxWork: number,
  ): unknown;
  strategyEffectCollectionBatchAdmit(
    preview: unknown, memberIndex: number, firstRow: number, effectKind: string, scope: unknown,
    rowCids: unknown, locators: unknown, keys: unknown, maxRows: number, maxWork: number,
  ): unknown;
  strategyEffectMemberRowAdmit(
    preview: unknown, memberIndex: number, rowIndex: number, effectKind: string, scope: unknown,
    rowCid: string, locator: unknown, key: unknown,
  ): unknown;
  strategyEffectPreviewMemberKind(preview: unknown, memberIndex: number): string | undefined;
  strategyEffectPreviewOrderedRowCid(
    preview: unknown, memberIndex: number, rowIndex: number,
  ): string | undefined;
  strategyEffectRecoveryBindings(
    preview: unknown, scope: unknown, programId: string, nodeId: string, maxRows: number,
    maxWork: number,
  ): unknown;
  clientProgramEffectRecoveryBindingsFromKeys(
    preview: unknown, scope: unknown, programId: string, nodeId: string, keys: unknown, maxRows: number,
    maxWork: number,
  ): unknown;
  strategyEffectRecoveryBindingLocatorCid(binding: unknown): string;
  strategyEffectRecoverClaimsFromHeads(bindings: unknown, heads: unknown, maxRows: number): unknown;
  strategyEffectRecoveredClaimScope(claim: unknown): unknown;
  strategyEffectRecoveredClaimLocator(claim: unknown): unknown;
  strategyEffectRecoveredClaimKey(claim: unknown): unknown;
  strategyEffectRecoveredClaimBasis(claim: unknown): unknown;
  strategyEffectRecoveredClaimIntentFingerprintCid(claim: unknown): string;
  strategyEffectRecoveredClaimCanonicalRequestCid(claim: unknown): string;
  strategyIssueEffectRowOutcomeReceipt(
    preview: unknown, memberIndex: number, rowIndex: number, dispatchEntryCid: string,
    credentialUseCid: string, responseBytes: Uint8Array, httpStatusCode: number, outcomeWire: string,
    maxResponseBytes: number, maxWireBytes: number, maxNodes: number, maxDepth: number,
  ): unknown;
  strategyPublicationContractIdentity(contract: unknown): string;
  strategyPublicationContractJson(contract: unknown): string;
  strategyEffectRowOutcomeReceiptTerminalState(receipt: unknown): string | undefined;
  strategyAdmitEffectSavedResponseEvidence(
    dispatchEntryCids: unknown, credentialUseCid: string, responseBytes: Uint8Array,
    httpStatusCode: number, maxResponseBytes: number,
  ): unknown;
  strategyIssueEffectRowOutcomeReceiptFromResponse(
    preview: unknown, memberIndex: number, rowIndex: number, dispatchEntryCid: string,
    response: unknown, outcomeWire: string, maxWireBytes: number, maxNodes: number, maxDepth: number,
  ): unknown;
  strategyAdmitEffectRowOutcomeReceipt(
    preview: unknown, memberIndex: number, rowIndex: number, dispatchEntryCid: string,
    credentialUseCid: string, responseBytes: Uint8Array, httpStatusCode: number, receiptWire: string,
    maxResponseBytes: number, maxWireBytes: number, maxNodes: number, maxDepth: number,
  ): unknown;
  strategyAdmitEffectRowOutcomeReceiptFromResponse(
    preview: unknown, memberIndex: number, rowIndex: number, dispatchEntryCid: string,
    response: unknown, receiptWire: string, maxWireBytes: number, maxNodes: number, maxDepth: number,
  ): unknown;
  strategyIssueEffectRowReceiptTerminalEntry(
    preview: unknown, memberIndex: number, rowIndex: number, scope: unknown, locator: unknown,
    key: unknown, canonicalRequestCid: string, current: unknown, history: unknown,
    dispatchEntryCid: string, credentialUseCid: string, responseBytes: Uint8Array,
    httpStatusCode: number, receiptWire: string, maxResponseBytes: number, maxWireBytes: number,
    maxNodes: number, maxDepth: number,
  ): unknown;
  strategyIssueEffectRowReceiptTerminalEntryFromResponse(
    preview: unknown, memberIndex: number, rowIndex: number, scope: unknown, locator: unknown,
    key: unknown, canonicalRequestCid: string, current: unknown, history: unknown,
    dispatchEntryCid: string, response: unknown, receiptWire: string, maxWireBytes: number,
    maxNodes: number, maxDepth: number,
  ): unknown;
  strategyCheckEffectMemberReceiptRowPartitionEvidence(
    preview: unknown, memberIndex: number, scopes: unknown, locators: unknown, keys: unknown,
    bases: unknown, heads: unknown, activeOwners: unknown, terminalReceiptWires: unknown,
    memberReceiptWire: string, maxRows: number, maxWireBytes: number, maxNodes: number,
    maxDepth: number,
  ): unknown;
  strategyIssueEffectMemberReceiptFromRowPartition(
    preview: unknown, memberIndex: number, scopes: unknown, locators: unknown, keys: unknown,
    bases: unknown, heads: unknown, activeOwners: unknown, terminalReceiptWires: unknown,
    maxRows: number, maxWireBytes: number, maxNodes: number, maxDepth: number,
  ): unknown;
  strategyIssueEffectSetApplyReceiptFromMembers(
    preview: unknown, memberReceiptWires: unknown, replayed: unknown, maxWireBytes: number,
    maxNodes: number, maxDepth: number,
  ): unknown;
  strategyEffectAdmitLedgerEntry(
    wire: string, maxWireBytes: number, maxNodes: number, maxDepth: number,
  ): unknown;
  strategyEffectLedgerEntryFollows(previous: unknown, next: unknown): boolean;
  strategyEffectLedgerEntryCid(entry: unknown): string;
  strategyEffectLedgerEntryStateCode(entry: unknown): number;
  strategyEffectLedgerEntryLocatorCid(entry: unknown): string;
  strategyEffectLedgerEntryScopeCid(entry: unknown): string;
  strategyEffectLedgerEntryWire(entry: unknown): string;
  strategyEffectLedgerEntryAdmitsDispatch(
    entry: unknown, scope: unknown, locator: unknown, key: unknown, canonicalRequestCid: string,
  ): boolean;
  strategyEffectLedgerEntryMatchesBasis(entry: unknown, basis: unknown): boolean;
  strategyEffectLedgerClaimFactsStatus?(
    basis: unknown, scope: unknown, locator: unknown, key: unknown, intentFingerprintCid: string,
    canonicalRequestCid: string, expectedScopeCid: string, maxWireBytes: number, maxNodes: number,
    maxDepth: number,
  ): number;
  strategyEffectLedgerBasis(
    scope: unknown, locator: unknown, key: unknown, unitDefinitionCid: string,
    originalMembershipCid: string, intentFingerprintCid: string, canonicalRequestCid: string,
    recoveryContractCid: string, capability: string, reservationEvidenceCid: string,
    retentionContractCid: string,
  ): unknown;
  strategyEffectIssuePreparedLedgerEntry(
    basis: unknown, maxWireBytes: number, maxNodes: number, maxDepth: number,
  ): unknown;
  strategyEffectIssueNextLedgerEntry(
    prior: unknown, nextState: string, outcomeReceiptCid: string, maxWireBytes: number,
    maxNodes: number, maxDepth: number,
  ): unknown;
};

const effectApplicationControls = new WeakMap<object, ReturnType<typeof createEffectApplicationControl>>();

export function effectApplicationControl(moon: CommonEffectBindings) {
  let control = effectApplicationControls.get(moon);
  if (control !== undefined) return control;
  control = createEffectApplicationControl(moon);
  effectApplicationControls.set(moon, control);
  return control;
}

function createEffectApplicationControl(moon: CommonEffectBindings) {
  return Object.freeze({
    logicalRequestScope: (...args: Parameters<CommonEffectBindings['strategyEffectLogicalRequestScope']>) =>
      checked(moon.strategyEffectLogicalRequestScope(...args)),
    logicalRequestScopeCid: moon.strategyEffectLogicalRequestScopeCid,
    dispatchKey: (...args: Parameters<CommonEffectBindings['strategyEffectDispatchKey']>) =>
      checked(moon.strategyEffectDispatchKey(...args)),
    dispatchKeyCid: moon.strategyEffectDispatchKeyCid,
    dispatchKeyCorrelationWire: moon.strategyEffectDispatchKeyCorrelationWire,
    recoveredPreviewKeys: (...args: Parameters<CommonEffectBindings['strategyEffectRecoveredPreviewKeys']>) => checked(
      moon.strategyEffectRecoveredPreviewKeys(...args)),
    batchRowsShareMember: moon.strategyEffectBatchRowsShareMember,
    logicalItemLocator: (...args: Parameters<CommonEffectBindings['strategyEffectLogicalItemLocator']>) =>
      checked(moon.strategyEffectLogicalItemLocator(...args)),
    logicalItemLocatorCid: moon.strategyEffectLogicalItemLocatorCid,
    applyKey: (...args: Parameters<CommonEffectBindings['strategyEffectApplyKey']>) =>
      checked(moon.strategyEffectApplyKey(...args)),
    applyKeyCid: moon.strategyEffectApplyKeyCid,
    recoveryAction: moon.strategyEffectRowRecoveryAction,
    recoveryActionFromEntry: moon.strategyEffectRowRecoveryActionFromEntry,
    setFrontier: (...args: Parameters<CommonEffectBindings['strategyEffectSetFrontier']>) => checked(moon.strategyEffectSetFrontier(...args)),
    setFrontierFromLedger: (...args: Parameters<CommonEffectBindings['strategyEffectSetFrontierFromLedger']>) => checked(
      moon.strategyEffectSetFrontierFromLedger(...args)),
    recoveredTargetGuards: (...args: Parameters<CommonEffectBindings['clientProgramRecoverEffectTargetGuards']>) => checked(
      moon.clientProgramRecoverEffectTargetGuards(...args)),
    setFrontierOutcome: moon.strategyEffectSetFrontierOutcome,
    setFrontierReadyCount: moon.strategyEffectSetFrontierReadyCount,
    setFrontierReadyMember: moon.strategyEffectSetFrontierReadyMember,
    setFrontierReadyRow: moon.strategyEffectSetFrontierReadyRow,
    checkSetFootprintConflicts: (...args: Parameters<CommonEffectBindings['strategyEffectSetFootprintConflictsCheck']>) => checked(
      moon.strategyEffectSetFootprintConflictsCheck(...args),
    ),
    checkPreviewFootprintConflicts: (...args: Parameters<CommonEffectBindings['strategyEffectPreviewFootprintConflictsCheck']>) => checked(
      moon.strategyEffectPreviewFootprintConflictsCheck(...args),
    ),
    derivePreviewIdentities: (...args: Parameters<CommonEffectBindings['strategyEffectPreviewIdentities']>) => checked(
      moon.strategyEffectPreviewIdentities(...args),
    ) as readonly string[],
    derivePreviewRowIdentities: (...args: Parameters<CommonEffectBindings['strategyEffectPreviewRowIdentities']>) => checked(
      moon.strategyEffectPreviewRowIdentities(...args),
    ) as readonly (readonly string[])[],
    admitPreviewApplyIdentity: (...args: Parameters<CommonEffectBindings['strategyEffectPreviewApplyIdentityAdmit']>) => checked(
      moon.strategyEffectPreviewApplyIdentityAdmit(...args),
    ),
    admitPreviewIdentity: (...args: Parameters<CommonEffectBindings['strategyEffectPreviewApplyIdentity']>) => checked(
      moon.strategyEffectPreviewApplyIdentity(...args),
    ),
    checkPreviewTargetGuards: (...args: Parameters<CommonEffectBindings['strategyEffectPreviewTargetGuardsCheck']>) => checked(
      moon.strategyEffectPreviewTargetGuardsCheck(...args),
    ),
    admitCollectionBatch: (...args: Parameters<CommonEffectBindings['strategyEffectCollectionBatchAdmit']>) => checked(
      moon.strategyEffectCollectionBatchAdmit(...args),
    ),
    admitMemberRow: (...args: Parameters<CommonEffectBindings['strategyEffectMemberRowAdmit']>) => checked(
      moon.strategyEffectMemberRowAdmit(...args),
    ),
    previewMemberKind: moon.strategyEffectPreviewMemberKind,
    previewOrderedRowCid: moon.strategyEffectPreviewOrderedRowCid,
    recoveryBindings: (...args: Parameters<CommonEffectBindings['strategyEffectRecoveryBindings']>) => checked(
      moon.strategyEffectRecoveryBindings(...args)),
    recoveryBindingsFromKeys: (...args: Parameters<CommonEffectBindings['clientProgramEffectRecoveryBindingsFromKeys']>) => checked(
      moon.clientProgramEffectRecoveryBindingsFromKeys(...args)),
    recoveryBindingLocatorCid:
      moon.strategyEffectRecoveryBindingLocatorCid,
    recoverClaimsFromHeads: (...args: Parameters<CommonEffectBindings['strategyEffectRecoverClaimsFromHeads']>) => checked(
      moon.strategyEffectRecoverClaimsFromHeads(...args)),
    recoveredClaimScope: moon.strategyEffectRecoveredClaimScope,
    recoveredClaimLocator: moon.strategyEffectRecoveredClaimLocator,
    recoveredClaimKey: moon.strategyEffectRecoveredClaimKey,
    recoveredClaimBasis: moon.strategyEffectRecoveredClaimBasis,
    recoveredClaimIntentFingerprintCid:
      moon.strategyEffectRecoveredClaimIntentFingerprintCid,
    recoveredClaimCanonicalRequestCid:
      moon.strategyEffectRecoveredClaimCanonicalRequestCid,
    issueRowOutcomeReceipt: (...args: Parameters<CommonEffectBindings['strategyIssueEffectRowOutcomeReceipt']>) => {
      const value = checked(moon.strategyIssueEffectRowOutcomeReceipt(...args));
      return Object.freeze({
        identity: moon.strategyPublicationContractIdentity(value),
        wire: moon.strategyPublicationContractJson(value),
        terminalState: moon.strategyEffectRowOutcomeReceiptTerminalState(value),
      });
    },
    admitSavedResponseEvidence: (...args: Parameters<CommonEffectBindings['strategyAdmitEffectSavedResponseEvidence']>) => checked(
      moon.strategyAdmitEffectSavedResponseEvidence(...args)),
    issueRowOutcomeReceiptFromResponse: (...args: Parameters<CommonEffectBindings['strategyIssueEffectRowOutcomeReceiptFromResponse']>) => {
      const value = checked(
        moon.strategyIssueEffectRowOutcomeReceiptFromResponse(...args));
      return Object.freeze({
        identity: moon.strategyPublicationContractIdentity(value),
        wire: moon.strategyPublicationContractJson(value),
        terminalState: moon.strategyEffectRowOutcomeReceiptTerminalState(value),
      });
    },
    admitRowOutcomeReceipt: (...args: Parameters<CommonEffectBindings['strategyAdmitEffectRowOutcomeReceipt']>) => {
      const value = checked(moon.strategyAdmitEffectRowOutcomeReceipt(...args));
      return Object.freeze({
        identity: moon.strategyPublicationContractIdentity(value),
        wire: moon.strategyPublicationContractJson(value),
        terminalState: moon.strategyEffectRowOutcomeReceiptTerminalState(value),
      });
    },
    admitRowOutcomeReceiptFromResponse: (...args: Parameters<CommonEffectBindings['strategyAdmitEffectRowOutcomeReceiptFromResponse']>) => {
      const value = checked(
        moon.strategyAdmitEffectRowOutcomeReceiptFromResponse(...args));
      return Object.freeze({
        identity: moon.strategyPublicationContractIdentity(value),
        wire: moon.strategyPublicationContractJson(value),
        terminalState: moon.strategyEffectRowOutcomeReceiptTerminalState(value),
      });
    },
    issueRowReceiptTerminalEntry: (...args: Parameters<CommonEffectBindings['strategyIssueEffectRowReceiptTerminalEntry']>) => checked(
      moon.strategyIssueEffectRowReceiptTerminalEntry(...args),
    ),
    issueRowReceiptTerminalEntryFromResponse: (...args: Parameters<CommonEffectBindings['strategyIssueEffectRowReceiptTerminalEntryFromResponse']>) => checked(
      moon.strategyIssueEffectRowReceiptTerminalEntryFromResponse(...args),
    ),
    checkMemberReceiptRowPartitionEvidence: (...args: Parameters<CommonEffectBindings['strategyCheckEffectMemberReceiptRowPartitionEvidence']>) => checked(
      moon.strategyCheckEffectMemberReceiptRowPartitionEvidence(...args),
    ),
    issueMemberReceiptFromRowPartition: (...args: Parameters<CommonEffectBindings['strategyIssueEffectMemberReceiptFromRowPartition']>) => {
      const value = checked(
        moon.strategyIssueEffectMemberReceiptFromRowPartition(...args));
      return Object.freeze({
        identity: moon.strategyPublicationContractIdentity(value),
        wire: moon.strategyPublicationContractJson(value),
      });
    },
    issueSetReceiptFromMembers: (...args: Parameters<CommonEffectBindings['strategyIssueEffectSetApplyReceiptFromMembers']>) => {
      const value = checked(
        moon.strategyIssueEffectSetApplyReceiptFromMembers(...args));
      return Object.freeze({
        identity: moon.strategyPublicationContractIdentity(value),
        wire: moon.strategyPublicationContractJson(value),
      });
    },
    admitLedgerEntry: (...args: Parameters<CommonEffectBindings['strategyEffectAdmitLedgerEntry']>) => checked(
      moon.strategyEffectAdmitLedgerEntry(...args),
    ),
    ledgerEntryFollows: moon.strategyEffectLedgerEntryFollows,
    ledgerEntryCid: moon.strategyEffectLedgerEntryCid,
    ledgerEntryStateCode: moon.strategyEffectLedgerEntryStateCode,
    ledgerEntryLocatorCid: moon.strategyEffectLedgerEntryLocatorCid,
    ledgerEntryScopeCid: moon.strategyEffectLedgerEntryScopeCid,
    ledgerEntryWire: moon.strategyEffectLedgerEntryWire,
    ledgerEntryAdmitsDispatch: moon.strategyEffectLedgerEntryAdmitsDispatch,
    ledgerEntryMatchesBasis: moon.strategyEffectLedgerEntryMatchesBasis,
    // Optional only for older component runtimes. The Ledger keeps its full
    // codec path when this inert, allocation-free facts check is unavailable.
    ledgerClaimFactsStatus: moon.strategyEffectLedgerClaimFactsStatus,
    ledgerBasis: (...args: Parameters<CommonEffectBindings['strategyEffectLedgerBasis']>) => checked(moon.strategyEffectLedgerBasis(...args)),
    issuePreparedLedgerEntry: (...args: Parameters<CommonEffectBindings['strategyEffectIssuePreparedLedgerEntry']>) => checked(
      moon.strategyEffectIssuePreparedLedgerEntry(...args),
    ),
    issueNextLedgerEntry: (...args: Parameters<CommonEffectBindings['strategyEffectIssueNextLedgerEntry']>) => checked(
      moon.strategyEffectIssueNextLedgerEntry(...args),
    ),
  });
}
