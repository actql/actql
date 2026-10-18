///|
/// The fixed installed Node Root alone owns the nominal original. Return its
/// unstarted imported child first so the same Host retains it before a later
/// fallible begin; neither an error nor a copied external reference loses or
/// recreates that custody. This Node-only bridge is not a portable issuer.
#export_name("clientProgramNodeOriginalSourceChildPrepare")
pub fn client_program_node_original_source_child_prepare(
  original : @resources.OriginalNodeSourceReference,
) -> Result[@resources.ImportedChildLedger, @resources.ImportedChildLedgerIssue] {
  @resources.prepare_node_original_source_child(original)
}

///|
/// Report the retained child's actual Core usage, not JS counters or limits.
#export_name("clientProgramNodeOriginalSourceChildReport")
pub fn client_program_node_original_source_child_report(
  child : @resources.ImportedChildLedger,
) -> Result[Unit, @resources.ImportedChildLedgerIssue] {
  @resources.report_imported_child_ledger(child)
}

///|
/// Logical stop only. Physical FD/reader/backing and parent ACKs stay with the
/// original supplier, independently of this observation or managed retirement.
#export_name("clientProgramNodeOriginalSourceChildStop")
pub fn client_program_node_original_source_child_stop(
  child : @resources.ImportedChildLedger,
) -> Result[Unit, @resources.ImportedChildLedgerIssue] {
  @resources.stop_imported_child_ledger(child)
}
