// Private legacy test projection; production selects the exact checked task.

///|
// The same managed generation and physical rows serve ordinary publication
// and private Effect Result evidence. Neither path obtains new execution or
// permission, and both retain the original bridge cleanup on every failure.
#cfg(target="js")
fn LocalValuesExecution::prepare_publication_bridge(
  self : LocalValuesExecution,
  row_limits : @execution.RetainedRowDecodeLimits,
  bridge_max_entries : Int,
  bridge_max_name_bytes : Int,
  limits : @publication_host.PublicationOutputExportLimits,
) -> Result[
  (@execution.ManagedPublicationBridge[Int], @execution.CompletedOutput),
  LocalValuesPublicationBridgeIssue,
] {
  self.prepare_publication_bridge_for_task(
    @strategy.graph_result_task(@strategy.captured_dag_graph(self.run), 0).unwrap_or(
      0,
    ),
    row_limits,
    bridge_max_entries,
    bridge_max_name_bytes,
    limits,
  )
}

///|
// Select the exact checked Named Result's original physical task. The retained
// graph may have independent roots and intermediate tasks; task zero or the
// last executed task is not a replacement result identity.
#cfg(target="js")
fn LocalValuesExecution::prepare_publication_bridge_for_task(
  self : LocalValuesExecution,
  task : Int,
  row_limits : @execution.RetainedRowDecodeLimits,
  bridge_max_entries : Int,
  bridge_max_name_bytes : Int,
  limits : @publication_host.PublicationOutputExportLimits,
) -> Result[
  (@execution.ManagedPublicationBridge[Int], @execution.CompletedOutput),
  LocalValuesPublicationBridgeIssue,
] {
  guard self.publication_original_for_task(task)
    is Some((operations, completed)) else {
    return Err(MissingOutput)
  }
  self.prepare_publication_bridge_for_original(
    operations, completed, row_limits, bridge_max_entries, bridge_max_name_bytes,
    limits,
  )
}
