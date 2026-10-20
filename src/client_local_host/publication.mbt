///|
/// Retains the re-admitted Local output until its exact checked Named Result
/// export and any replay are finished. The physical Store remains a caller
/// responsibility; this owner neither publishes nor grants Result access.
pub struct LocalValuesResultExport {
  stream : @publication_host.PublicationOutputExport
  bridge : @execution.ManagedPublicationBridge[Int]
  mut closed : Bool
}

///|
pub(all) enum LocalValuesResultExportIssue {
  MissingOutput
  UnknownResult
  Bridge(@execution.ManagedProducerBridgeIssue)
  Export(@publication_host.PublicationOutputExportIssue)
}

///|
/// Re-admit physical rows against the completed managed output and derive
/// the Result definition and projection from the same captured graph. The
/// caller must have accepted the Run before executing this occurrence.
pub fn LocalValuesExecution::prepare_result_export(
  self : LocalValuesExecution,
  result_index : Int,
  row_limits : @execution.RetainedRowDecodeLimits,
  bridge_max_entries : Int,
  bridge_max_name_bytes : Int,
  limits : @publication_host.PublicationOutputExportLimits,
) -> Result[LocalValuesResultExport, LocalValuesResultExportIssue] {
  if !self.available.val {
    return Err(MissingOutput)
  }
  let graph = @strategy.captured_dag_graph(self.run)
  guard @strategy.graph_result_task(graph, result_index) is Some(task) &&
    @strategy.graph_result_occurrence(graph, result_index) is Some(occurrence) &&
    @strategy.graph_result_name(graph, result_index) is Some(result_name) else {
    return Err(UnknownResult)
  }
  let (bridge, output) = match
    self.prepare_publication_bridge_for_task(
      task, row_limits, bridge_max_entries, bridge_max_name_bytes, limits,
    ) {
    Ok(value) => value
    Err(MissingOutput) => return Err(MissingOutput)
    Err(Bridge(issue)) => return Err(Bridge(issue))
  }
  let definition = match
    @publication.prepare_result_definition(
      @strategy.graph_program_definition_cid(graph),
      result_name,
    ) {
    Ok(value) => @publication.result_definition_contract(value)
    Err(_) => {
      @execution.close_managed_publication_bridge(bridge)
      return Err(UnknownResult)
    }
  }
  let stream = match
    @publication_host.prepare_result_publication_export(
      output, occurrence, definition, limits,
    ) {
    Ok(value) => value
    Err(issue) => {
      @execution.close_managed_publication_bridge(bridge)
      return Err(Export(issue))
    }
  }
  Ok({ stream, bridge, closed: false, })
}

///|
pub fn LocalValuesResultExport::output_export(
  self : LocalValuesResultExport,
) -> @publication_host.PublicationOutputExport {
  self.stream
}

///|
/// Close after the export, replay and Store custody have finished. This does
/// not stop or rerun Compute; the Local execution has its own close operation.
pub fn LocalValuesResultExport::close(self : LocalValuesResultExport) -> Unit {
  if !self.closed {
    self.closed = true
    self.stream.cancel()
    @execution.close_managed_publication_bridge(self.bridge)
  }
}

///|
priv enum LocalValuesPublicationBridgeIssue {
  MissingOutput
  Bridge(@execution.ManagedProducerBridgeIssue)
}

///|
// The same managed generation and physical rows serve ordinary publication
// and private Effect Result evidence. Neither path obtains new execution or
// permission, and both retain the original bridge cleanup on every failure.
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
  if !self.available.val {
    return Err(MissingOutput)
  }
  let (operations, completed) = if self.tasks is Some((lookup, _)) {
    guard lookup(task) is Some(output) else { return Err(MissingOutput) }
    output
  } else {
    if task != 0 {
      return Err(MissingOutput)
    }
    (self.operations, self.completed)
  }
  guard (operations.material)() is Some(material) else {
    return Err(MissingOutput)
  }
  let bridge = match
    @execution.prepare_managed_publication_bridge(
      completed,
      material,
      limits.max_rows,
      limits.values,
      bridge_max_entries,
      bridge_max_name_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Bridge(issue))
  }
  for index in 0..<(operations.output_rows)() {
    let row = match (operations.output_row)(index) {
      Ok(value) => value
      Err(_) => {
        @execution.close_managed_publication_bridge(bridge)
        return Err(MissingOutput)
      }
    }
    match
      @execution.append_managed_publication_bridge_wire(bridge, row, row_limits) {
      Ok(_) => ()
      Err(issue) => {
        @execution.close_managed_publication_bridge(bridge)
        return Err(Bridge(issue))
      }
    }
  }
  let output = match @execution.finish_managed_publication_bridge(bridge) {
    Ok(value) => value
    Err(issue) => {
      @execution.close_managed_publication_bridge(bridge)
      return Err(Bridge(issue))
    }
  }
  Ok((bridge, output))
}
