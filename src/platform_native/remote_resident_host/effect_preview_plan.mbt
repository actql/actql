///|
pub(all) enum ResidentEffectPreviewPlanIssue {
  Unavailable
  ForeignInput
  NativeExport(ResidentSourceComputeIssue)
  Export(@execution.CompletedExportIssue)
  Preparation(@execution.CompletedExportIssue)
  Plan(@strategy.CapturedEffectPlanVerifyIssue)
}

///|
/// Verify the authored row plan against the exact Native Result export. A
/// semantic Preview binding alone does not prove that its rows match the held
/// input. This proof is not approval, current target evidence or a write permit.
pub fn ResidentSourceCompute::verify_effect_preview_plan(
  self : ResidentSourceCompute,
  inputs : @strategy.CapturedEffectInputs,
  preview : @strategy.CapturedEffectPreviewInputs,
  preview_index : Int,
  local_result : Int,
  limits : @host.PublicationOutputExportLimits,
  max_fields : Int,
  max_work : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@strategy.CapturedEffectPlanProof, ResidentEffectPreviewPlanIssue] {
  if !self.resident_effect_inputs_current(inputs) {
    return Err(ResidentEffectPreviewPlanIssue::Unavailable)
  }
  guard @strategy.captured_effect_preview_input_at(preview, preview_index)
    is Some(preview_input) &&
    @strategy.captured_effect_local_result_at(inputs, local_result)
    is Some(result) &&
    @strategy.captured_effect_local_result_matches_member(
      inputs,
      local_result,
      @strategy.captured_effect_input_member_index(preview_input),
    ) &&
    @strategy.captured_any_result_borrows_share_view(
      @strategy.captured_effect_input_borrow(preview_input),
      @strategy.captured_effect_local_result_borrow(result),
    ) else {
    return Err(ForeignInput)
  }
  let verifier = match
    @strategy.prepare_captured_effect_plan_verifier(
      preview, preview_index, max_fields, max_work,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Plan(issue))
  }
  let exported = match
    self.prepare_effect_result_export(inputs, local_result, limits) {
    Ok(value) => value
    Err(issue) => {
      @strategy.cancel_captured_effect_plan_verifier(verifier)
      return Err(NativeExport(issue))
    }
  }
  let preparation = @strategy.captured_effect_local_result_export_preparation(
    exported,
  )
  let prepared = () => {
    while true {
      if !self.resident_effect_inputs_current(inputs) {
        return Err(ResidentEffectPreviewPlanIssue::Unavailable)
      }
      match
        @execution.advance_completed_result_relation_export(preparation, 16) {
        Ok((true, _)) => break
        Ok(_) => ()
        Err(issue) => return Err(Preparation(issue))
      }
    }
    @execution.finish_completed_result_relation_export_preparation(preparation).map_err(issue => {
        Preparation(issue)
      },
    )
  }
  let stream = match prepared() {
    Ok(value) => value
    Err(issue) => {
      @execution.cancel_completed_result_relation_export(preparation) |> ignore
      @strategy.cancel_captured_effect_plan_verifier(verifier)
      return Err(issue)
    }
  }
  let read = () => {
    while true {
      if !self.resident_effect_inputs_current(inputs) {
        return Err(ResidentEffectPreviewPlanIssue::Unavailable)
      }
      match
        @execution.next_completed_output_export_canonical_row(
          stream, max_nodes, max_depth, max_fields,
        ) {
        Ok(None) => break
        Ok(Some((index, _, row))) =>
          match
            @strategy.check_captured_effect_plan_row(
              verifier, row, index, max_fields, max_work, max_bytes, max_nodes, max_depth,
            ) {
            Ok(_) => ()
            Err(issue) => return Err(Plan(issue))
          }
        Err(issue) => return Err(Export(issue))
      }
    }
    let receipt = match @execution.finish_completed_relation_export(stream) {
      Ok((receipt, _)) => receipt
      Err(issue) => return Err(Export(issue))
    }
    let exact = @strategy.captured_effect_local_result_export_matches_receipt(
      inputs, exported, receipt,
    )
    @execution.cancel_completed_relation_export_receipt(receipt)
    if !exact {
      return Err(ForeignInput)
    }
    if !self.resident_effect_inputs_current(inputs) {
      return Err(ResidentEffectPreviewPlanIssue::Unavailable)
    }
    @strategy.finish_captured_effect_plan_verifier(verifier).map_err(issue => {
      Plan(issue)
    })
  }
  let proof = read()
  @execution.cancel_completed_output_export(stream)
  @execution.cancel_completed_result_relation_export(preparation) |> ignore
  @strategy.cancel_captured_effect_plan_verifier(verifier)
  proof
}
