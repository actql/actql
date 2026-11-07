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
  Transformation(@publication_host.CapturedClientResultTransformationIssue)
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
  guard @strategy.graph_result_task(graph, result_index) is Some(task) else {
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
  let managed = if self.tasks is Some((lookup, _)) {
    guard lookup(task) is Some((_, original)) else {
      @execution.close_managed_publication_bridge(bridge)
      return Err(MissingOutput)
    }
    original
  } else {
    self.completed
  }
  // Retain the original Run occurrence through the existing checked managed
  // bridge. A standalone equal-content export cannot fund a captured snapshot.
  let transformation = match
    @publication_host.start_captured_managed_result_publication_export(
      self.run,
      result_index,
      managed,
      bridge,
      output,
      limits,
    ) {
    Ok(value) => value
    Err(issue) => {
      @execution.close_managed_publication_bridge(bridge)
      return Err(local_values_transformation_issue(issue))
    }
  }
  let mut done = false
  while !done {
    match transformation.advance(256) {
      Ok((ready, _)) => done = ready
      Err(issue) => {
        transformation.cancel()
        @execution.close_managed_publication_bridge(bridge)
        return Err(local_values_transformation_issue(issue))
      }
    }
  }
  let stream = match transformation.finish() {
    Ok(value) => value
    Err(issue) => {
      transformation.cancel()
      @execution.close_managed_publication_bridge(bridge)
      return Err(local_values_transformation_issue(issue))
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

///|
fn local_values_transformation_issue(
  issue : @publication_host.CapturedClientResultTransformationIssue,
) -> LocalValuesResultExportIssue {
  match issue {
    Transform(Output(original)) => Export(@publication_host.Output(original))
    Retain(original) => Export(@publication_host.Retain(original))
    _ => Transformation(issue)
  }
}
