import assert from 'node:assert/strict';
import test from 'node:test';
import requests from './host-journal-native-requests.cjs';

const input = (overrides = {}) => ({databaseBytes:4194304n, pageBytes:4096n,
  walFrames:4062n, preparedStatements:10n, sqlCalls:100n, sqlBytes:10000n,
  statementCalls:100n, resultRows:128n, parameterBytes:4096n, ...overrides});

test('Node allocation history includes lookahead, terminal and return independently of active vectors', () => {
  const value = requests.hostJournalNativeStructureRequests(input());
  const history = value.nodeAllocationHistory;
  assert.equal(history.quantityKind, 'conditional-operation-attempt-history');
  assert.equal(history.wrapperRequests, 111n);
  assert.equal(history.pointerDataRequests, 111n);
  assert.equal(history.membershipNodeRequests, 10n);
  assert.equal(history.membershipBucketRequests, 10n);
  assert.equal(history.resultRowsIncludingLookahead, 12900n);
  assert.equal(history.iteratorResultsIncludingReturn, 13000n);
  assert.equal(history.columnVectorRequests, 25800n);
  assert.equal(history.protocolVectorRequests, 26000n);
  assert.equal(history.strongRootEntryRequests, 51800n);
  assert.equal(history.payloadAllocatorAttempts, 1238400n);
  assert.equal(history.payloadSuccessfulOriginalsUpper, 309600n);
  assert.equal(history.resultControlRequests, 928800n);
  assert.equal(history.clientAllocatorAttemptsUpper, 2271042n);
  assert.equal(history.clientFreeCallsUpper, 1342242n);
  assert.equal(value.nodeResults.simultaneousVectors, 4n);
  assert(history.strongRootEntryRequests > value.nodeResults.simultaneousVectors);
  assert.equal(history.completeNativeHistory, false);
  assert.equal(history.numericalBackingClaim, false);
  assert.equal(history.allocationSuccessGuaranteed, false);
  assert.equal(history.allocatorInternalAllocationAttemptsIncluded, false);
  assert.equal(history.allocatorInternalFreeCallsIncluded, false);
  assert.equal(history.replenishedOnClose, false);
  assert.equal(history.freeReturnsCredit, false);
  assert(Object.isFrozen(history));
});

test('same Node lifetime history never replaces cumulative requests with live cardinality or payload retries', () => {
  const first = requests.hostJournalNativeStructureRequests(input({preparedStatements:1n,
    statementCalls:1n, resultRows:1n}));
  const next = requests.hostJournalNativeStructureRequests(input({preparedStatements:2n,
    statementCalls:1n, resultRows:1n}));
  const doubled = requests.hostJournalNativeStructureRequests(input({preparedStatements:1n,
    statementCalls:2n, resultRows:1n}));
  assert.equal(first.nodeAllocationHistory.clientAllocatorAttemptsUpper, 364n);
  assert.equal(first.nodeAllocationHistory.clientFreeCallsUpper, 220n);
  assert.equal(next.nodeAllocationHistory.clientAllocatorAttemptsUpper -
    first.nodeAllocationHistory.clientAllocatorAttemptsUpper, 4n);
  assert.equal(next.nodeAllocationHistory.clientFreeCallsUpper -
    first.nodeAllocationHistory.clientFreeCallsUpper, 4n);
  assert.equal(doubled.nodeAllocationHistory.resultRowsIncludingLookahead, 4n);
  assert.equal(doubled.nodeAllocationHistory.iteratorResultsIncludingReturn, 6n);
  // One database and its PointerData are not recreated when X doubles:
  // fixed requests10 + payload attempts384 + controls288 + vectors40.
  assert.equal(doubled.nodeAllocationHistory.clientAllocatorAttemptsUpper, 722n);
  assert.equal(doubled.nodeAllocationHistory.clientFreeCallsUpper, 434n);
  assert.equal(first.nodeResults.simultaneousVectors, doubled.nodeResults.simultaneousVectors);
  assert.equal(first.nodeAllocationHistory.payloadAllocatorAttempts,
    4n * first.nodeAllocationHistory.payloadSuccessfulOriginalsUpper);
  assert.equal(first.nodeAllocationHistory.clientAllocatorAttemptsUpper -
    first.nodeAllocationHistory.clientFreeCallsUpper,
    3n * first.nodeAllocationHistory.payloadSuccessfulOriginalsUpper);
  assert.equal(first.completePhase, false);
  assert.equal(doubled.completePhase, false);
  assert.equal(typeof requests.prepareHostJournalInstallation, 'undefined');
});
