///|
pub(all) enum NativeClientSubmittedEffectValuesCaptureIssue {
  Work(NativeClientSubmittedEffectValuesWorkIssue)
  Pin(@strategy.RunIssue)
  Export(@local.LocalValuesEffectResultExportIssue)
}

///|
/// Borrow the original checked Result/Table inventory from this accepted Work.
/// These are existing consumer pins, not new physical backing, permission,
/// Artifact evidence, a Preview or a Checkpoint. The caller owns their release.
pub fn NativeClientSubmittedEffectValuesWork::pin_original_capture_inputs(
  self : NativeClientSubmittedEffectValuesWork,
  max_pins : Int,
  max_dependency_work? : Int = 65536,
  max_dependency_depth? : Int = 64,
) -> Result[
  @strategy.CapturedEffectInputs,
  NativeClientSubmittedEffectValuesCaptureIssue,
] {
  let captured = match self.run_for_capture() {
    Ok(value) => value
    Err(issue) => return Err(Work(issue))
  }
  let inputs = match
    @strategy.pin_captured_effect_sources(
      captured,
      max_pins,
      max_dependency_work~,
      max_dependency_depth~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Pin(issue))
  }
  match self.run_for_capture() {
    Ok(_) => ()
    Err(issue) => {
      @strategy.release_captured_effect_inputs(inputs) |> ignore
      return Err(Work(issue))
    }
  }
  // No callback follows the existing terminal Work/current checks. The new
  // pins cannot be replaced by equal rows or a different captured generation.
  if !@strategy.captured_effect_inputs_match_run(inputs, captured) {
    @strategy.release_captured_effect_inputs(inputs) |> ignore
    return Err(Export(ForeignInput))
  }
  Ok(inputs)
}

///|
/// Export one original local Result occurrence through the existing managed
/// Values bridge. The original input inventory, rather than a public Result
/// array position or caller bytes, selects the occurrence. Current authority
/// and lifetime are rechecked after every trusted callback before returning.
pub fn NativeClientSubmittedEffectValuesWork::prepare_original_result_export(
  self : NativeClientSubmittedEffectValuesWork,
  inputs : @strategy.CapturedEffectInputs,
  local_result : Int,
  row_limits : @execution.RetainedRowDecodeLimits,
  max_entries : Int,
  max_name_bytes : Int,
  limits : @host.PublicationOutputExportLimits,
) -> Result[
  @local.LocalValuesEffectResultExport,
  NativeClientSubmittedEffectValuesCaptureIssue,
] {
  let captured = match self.run_for_capture() {
    Ok(value) => value
    Err(issue) => return Err(Work(issue))
  }
  let output = match
    self.work.execution.prepare_effect_result_export(
      captured, inputs, local_result, row_limits, max_entries, max_name_bytes, limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Export(issue))
  }
  // The physical availability port may itself call back. Borrow before the
  // final current fence; retain only its opaque identity across that fence.
  let exported = output.captured_export()
  match self.run_for_capture() {
    Ok(_) => ()
    Err(issue) => {
      output.close()
      return Err(Work(issue))
    }
  }
  guard exported is Some(exported) &&
    @strategy.captured_effect_local_result_export_retained(inputs, exported) else {
    output.close()
    return Err(Export(MissingOutput))
  }
  // The final predicate above has no callback. Retirement during UTC/current
  // cannot escape through an earlier successful bridge or availability read.
  Ok(output)
}
