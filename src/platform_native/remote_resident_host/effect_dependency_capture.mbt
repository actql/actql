///|
pub(all) enum ResidentEffectDependencyCaptureIssue {
  Unavailable
  ForeignInput
  Native(ResidentSourceComputeIssue)
  Export(@execution.CompletedExportIssue)
  Evidence(@host.ClientEffectDependencyCaptureIssue)
}

///|
/// Reify the actual retained local Result for the existing dependency inventory
/// Owner. This reads the completed view without acquiring a Source or executing
/// a task. All private export/snapshot work is retired on success and failure;
/// original input pins, Transfer holdings and Store custody remain with their
/// existing owners. A complete inventory and encrypted capture are still needed
/// before a waiting transition can be committed.
pub fn ResidentSourceCompute::capture_effect_dependency(
  self : ResidentSourceCompute,
  materials : @host.ClientEffectRunMaterials,
  inputs : @strategy.CapturedEffectInputs,
  artifact : @host.ClientEffectLocalResultArtifact,
  local_result : Int,
  limits : @host.PublicationOutputExportLimits,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @host.ClientEffectDependencyCapture,
  ResidentEffectDependencyCaptureIssue,
] {
  let current = () => self.resident_effect_inputs_current(inputs)
  if !current() {
    return Err(Unavailable)
  }
  if !@host.client_effect_dependency_capture_matches(
      materials, inputs, artifact, local_result,
    ) {
    return Err(ForeignInput)
  }
  if max_bytes < 1 || max_bytes > 16777216 {
    return Err(Evidence(Dependency(InvalidLimits)))
  }
  let exported = match
    self.prepare_effect_result_export(inputs, local_result, limits) {
    Ok(value) => value
    Err(issue) => return Err(Native(issue))
  }
  let preparation = @strategy.captured_effect_local_result_export_preparation(
    exported,
  )
  let prepare = () => {
    while true {
      if !current() {
        return Err(ResidentEffectDependencyCaptureIssue::Unavailable)
      }
      match
        @execution.advance_completed_result_relation_export(preparation, 16) {
        Ok((true, _)) => break
        Ok(_) => ()
        Err(issue) => return Err(Export(issue))
      }
    }
    @execution.finish_completed_result_relation_export_preparation(preparation).map_err(issue => {
        Export(issue)
      },
    )
  }
  let output = match prepare() {
    Ok(value) => value
    Err(issue) => {
      @execution.cancel_completed_result_relation_export(preparation) |> ignore
      return Err(issue)
    }
  }
  let receipt : Ref[@execution.CompletedRelationExportReceipt?] = Ref(None)
  let snapshot : Ref[@execution.CompletedRelationSnapshotPreparation?] = Ref(
    None,
  )
  let capture = () => {
    while true {
      if !current() {
        return Err(ResidentEffectDependencyCaptureIssue::Unavailable)
      }
      match @execution.next_completed_output_export(output) {
        Ok(Some(_)) => ()
        Ok(None) => break
        Err(issue) => return Err(Export(issue))
      }
    }
    let completed = match @execution.finish_completed_relation_export(output) {
      Ok((value, _)) => value
      Err(issue) => return Err(Export(issue))
    }
    receipt.val = Some(completed)
    let child = match
      @execution.start_completed_relation_export_snapshot(
        output,
        completed,
        max_bytes,
        max_nodes,
        max_depth,
        limits.max_result_workspace_entries,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Export(issue))
    }
    snapshot.val = Some(child)
    while true {
      if !current() {
        return Err(ResidentEffectDependencyCaptureIssue::Unavailable)
      }
      match child.advance(16) {
        Ok((true, _)) => break
        Ok(_) => ()
        Err(issue) => return Err(Export(issue))
      }
    }
    let (rows, _) = match child.finish() {
      Ok(value) => value
      Err(issue) => return Err(Export(issue))
    }
    if !current() {
      return Err(ResidentEffectDependencyCaptureIssue::Unavailable)
    }
    let evidence = match
      @host.admit_client_effect_dependency_capture(
        materials, inputs, artifact, local_result, exported, completed, rows, max_bytes,
        max_nodes, max_depth,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Evidence(issue))
    }
    if !current() {
      return Err(ResidentEffectDependencyCaptureIssue::Unavailable)
    }
    Ok(evidence)
  }
  let result = capture()
  if snapshot.val is Some(value) {
    value.cancel()
  }
  if receipt.val is Some(value) {
    @execution.cancel_completed_relation_export_receipt(value)
  }
  @execution.cancel_completed_output_export(output)
  @execution.cancel_completed_result_relation_export(preparation) |> ignore
  result
}
