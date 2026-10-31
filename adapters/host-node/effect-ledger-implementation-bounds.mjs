// The actual Effect Ledger's existing rejection bounds, shared with its
// construction quote. Pure DATA: reading it must not load SQLite, open a
// Ledger, supply capacity or observe current authorization/physical state.
export const effectLedgerImplementationBounds = Object.freeze({
  maxEntries: 100_000, maxEntryBytes: 1_000_000, maxResponseBytes: 1_000_000,
  maxStoredBytes: 134_217_728, maxBatchRows: 1000, maxNodes: 64, maxDepth: 4,
  maxOutcomeNodes: 512, maxOutcomeDepth: 16, maxCallerBytes: 256,
});
