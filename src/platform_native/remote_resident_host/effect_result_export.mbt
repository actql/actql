///|
/// Read one exact pinned local Result through the Native output owner. The
/// common exporter retains the checked projection, occurrence and receipt;
/// this is private Preview input custody, not public Result publication or an
/// Effect approval. The caller keeps its input pins until capture or cleanup.
pub fn ResidentSourceCompute::prepare_effect_result_export(
  self : ResidentSourceCompute,
  inputs : @strategy.CapturedEffectInputs,
  local_result : Int,
  limits : @host.PublicationOutputExportLimits,
) -> Result[
  @strategy.CapturedEffectLocalResultExport,
  ResidentSourceComputeIssue,
] {
  guard !self.stopping && self.effect_run is Some(run) else {
    return Err(Unavailable)
  }
  if !@strategy.captured_effect_inputs_match_run(inputs, run) {
    return Err(Source(ForeignInput))
  }
  guard @strategy.captured_effect_local_result_at(inputs, local_result)
    is Some(result) else {
    return Err(Unavailable)
  }
  let task = @strategy.captured_effect_local_result_task(result)
  let output = if @strategy.captured_any_result_borrow_cell_output(
      @strategy.captured_effect_local_result_borrow(result),
    )
    is Some(_) {
    match
      @duckdb_native.read_native_standard_task_output(
        self.compute,
        task,
        limits.max_rows,
        limits.values,
        limits.payload_wire,
        limits.max_batch_bytes,
      ) {
      Ok(value) => Some(value)
      Err(_) => return Err(Unavailable)
    }
  } else {
    // An acquired root uses its exact capture directly. It cannot be replaced
    // by a converted cell output or by another source with equal row bytes.
    None
  }
  match
    @strategy.start_captured_effect_local_result_export(
      inputs,
      local_result,
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
      converted_output?=output,
    ) {
    Ok(value) => Ok(value)
    Err(@strategy.CapturedEffectLocalResultExportIssue::Export(issue)) =>
      Err(Export(Output(issue)))
    Err(@strategy.CapturedEffectLocalResultExportIssue::ForeignOutput) =>
      Err(Source(ForeignInput))
    Err(@strategy.CapturedEffectLocalResultExportIssue::MissingResult) =>
      Err(Unavailable)
  }
}
