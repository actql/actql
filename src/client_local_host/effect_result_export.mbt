///|
/// The existing Values execution's managed bridge and exact Effect Result
/// export. This facade owns only these private exports, never the caller's
/// input pins, Compute, publication, approval or original physical funding.
struct LocalValuesEffectResultExport {
  execution : LocalValuesExecution
  captured : @strategy.CapturedEffectRunDAG
  inputs : @strategy.CapturedEffectInputs
  exported : @strategy.CapturedEffectLocalResultExport
  bridge : @execution.ManagedPublicationBridge[Int]
  mut closed : Bool
}

///|
pub(all) enum LocalValuesEffectResultExportIssue {
  MissingOutput
  ForeignInput
  MissingResult
  Bridge(@execution.ManagedProducerBridgeIssue)
  Export(@execution.CompletedExportIssue)
  Binding(@strategy.CapturedEffectLocalResultExportIssue)
}

///|
/// Export the selected local Result occurrence from the same completed Values
/// generation. Local Result indexes come from the original captured inventory;
/// a public Named Result index, equal row bytes or another Run cannot replace it.
pub fn LocalValuesExecution::prepare_effect_result_export(
  self : LocalValuesExecution,
  captured : @strategy.CapturedEffectRunDAG,
  inputs : @strategy.CapturedEffectInputs,
  local_result : Int,
  row_limits : @execution.RetainedRowDecodeLimits,
  bridge_max_entries : Int,
  bridge_max_name_bytes : Int,
  limits : @publication_host.PublicationOutputExportLimits,
  before_row? : ((String) -> Bool)? = None,
) -> Result[LocalValuesEffectResultExport, LocalValuesEffectResultExportIssue] {
  if !self.available.val {
    return Err(MissingOutput)
  }
  if !physical_equal(@strategy.captured_effect_run_dag(captured), self.run) ||
    !@strategy.captured_effect_inputs_match_run(inputs, captured) {
    return Err(ForeignInput)
  }
  guard @strategy.captured_effect_local_result_at(inputs, local_result)
    is Some(result) else {
    return Err(MissingResult)
  }
  let task = @strategy.captured_effect_local_result_task(result)
  guard self.publication_original_for_task(task)
    is Some((operations, completed)) else {
    return Err(MissingOutput)
  }
  if !@strategy.captured_any_result_borrow_matches_managed(
      @strategy.captured_effect_local_result_borrow(result),
      completed,
    ) {
    return Err(ForeignInput)
  }
  let (bridge, output) = match
    self.prepare_publication_bridge_for_original(
      operations,
      completed,
      row_limits,
      bridge_max_entries,
      bridge_max_name_bytes,
      limits,
      before_row~,
    ) {
    Ok(value) => value
    Err(MissingOutput) => return Err(MissingOutput)
    Err(Bridge(issue)) => return Err(Bridge(issue))
  }
  let occurrence = @strategy.captured_any_result_borrow_occurrence(
    @strategy.captured_effect_local_result_borrow(result),
  )
  let preparation = match
    @execution.start_completed_result_relation_export(
      output,
      occurrence,
      {
        max_fields: limits.max_result_fields,
        max_mapping_work: limits.max_result_mapping_work,
        max_order_work: limits.max_result_order_work,
        max_workspace_entries: limits.max_result_workspace_entries,
      },
      limits.max_rows,
      limits.values,
      limits.payload_wire,
      limits.logical_wire,
      limits.schema,
      limits.max_batch_bytes,
    ) {
    Ok(value) => value
    Err(issue) => {
      @execution.close_managed_publication_bridge(bridge)
      return Err(Export(issue))
    }
  }
  let exported = match
    @strategy.bind_captured_effect_local_result_managed_export(
      inputs, local_result, completed, bridge, preparation,
    ) {
    Ok(value) => value
    Err(issue) => {
      @execution.cancel_completed_result_relation_export(preparation) |> ignore
      @execution.close_managed_publication_bridge(bridge)
      return Err(Binding(issue))
    }
  }
  let value : LocalValuesEffectResultExport = {
    execution: self,
    captured,
    inputs,
    exported,
    bridge,
    closed: false,
  }
  if value.captured_export() is None {
    value.close()
    return Err(MissingOutput)
  }
  Ok(value)
}

///|
/// Borrow the existing export while its original execution/pins remain live.
/// The Artifact/Preview owners still admit the exact receipt and current Host
/// authorization remains an independent caller boundary.
pub fn LocalValuesEffectResultExport::captured_export(
  self : LocalValuesEffectResultExport,
) -> @strategy.CapturedEffectLocalResultExport? {
  let borrow = @strategy.captured_effect_local_result_borrow(
    @strategy.captured_effect_local_result_export_result(self.exported),
  )
  if self.closed ||
    !self.execution.available.val ||
    !@strategy.captured_effect_inputs_match_run(self.inputs, self.captured) ||
    !@strategy.captured_any_result_borrow_available(borrow) {
    return None
  }
  // Availability may call the physical holding. No callback follows this
  // final original lifetime fence; released aliases cannot escape as live.
  if self.closed ||
    !self.execution.available.val ||
    !@strategy.captured_effect_inputs_match_run(self.inputs, self.captured) ||
    !@strategy.captured_effect_local_result_export_retained(
      self.inputs,
      self.exported,
    ) {
    return None
  }
  Some(self.exported)
}

///|
/// Retire only this export and bridge. Input pins and the original execution
/// retain their own cleanup responsibility, including after a failed capture.
pub fn LocalValuesEffectResultExport::close(
  self : LocalValuesEffectResultExport,
) -> Unit {
  if !self.closed {
    self.closed = true
    @execution.cancel_completed_result_relation_export(
      @strategy.captured_effect_local_result_export_preparation(self.exported),
    )
    |> ignore
    @execution.close_managed_publication_bridge(self.bridge)
  }
}
