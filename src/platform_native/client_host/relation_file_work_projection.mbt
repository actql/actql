///|
/// Observe the actual captured Source cut before the Common suffix begins.
/// This immutable snapshot is retained under the Work control quote.
pub fn NativeClientRelationFileWork::source_capture_usage(
  self : NativeClientRelationFileWork,
) -> @resources.LedgerUsage {
  self.source_usage
}

///|
pub fn NativeClientRelationFileWork::usage(
  self : NativeClientRelationFileWork,
) -> @resources.LedgerUsage {
  @resources.ledger_usage(@strategy.captured_dag_ledger(self.run))
}
