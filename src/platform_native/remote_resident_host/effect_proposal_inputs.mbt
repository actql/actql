///|
pub(all) enum ResidentEffectProposalIssue {
  Unavailable
  ForeignInput
  ReceiverRejected
  NativeExport(ResidentSourceComputeIssue)
  Export(@execution.CompletedExportIssue)
  Proposal(@strategy.CapturedEffectProposalIssue)
}

///|
/// Read the checked selector and intended changes from an actual pinned Native
/// Result. The receiver may prepare Provider reads, but these proposals are not
/// Preview evidence, approval or permission to write. It must discard an
/// incomplete batch on failure. Input, receiver and capture custody stay with
/// their existing owners; cancelling this export never releases those owners.
pub fn ResidentSourceCompute::read_effect_proposals(
  self : ResidentSourceCompute,
  inputs : @strategy.CapturedEffectInputs,
  member_index : Int,
  local_result : Int,
  limits : @host.PublicationOutputExportLimits,
  max_fields : Int,
  max_work : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_utf16_units : Int,
  receive : (Int, String, String) -> Result[Unit, Unit],
) -> Result[Int, ResidentEffectProposalIssue] {
  if !self.resident_effect_inputs_current(inputs) {
    return Err(Unavailable)
  }
  guard @strategy.captured_effect_input_at(inputs, member_index) is Some(input) &&
    @strategy.captured_effect_local_result_at(inputs, local_result)
    is Some(result) &&
    @strategy.captured_effect_local_result_matches_member(
      inputs, local_result, member_index,
    ) &&
    @strategy.captured_any_result_borrows_share_view(
      @strategy.captured_effect_input_borrow(input),
      @strategy.captured_effect_local_result_borrow(result),
    ) else {
    return Err(ForeignInput)
  }
  let plan = match
    @strategy.prepare_captured_effect_proposal_plan(
      inputs, member_index, max_fields, max_work,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Proposal(issue))
  }
  let exported = match
    self.prepare_effect_result_export(inputs, local_result, limits) {
    Ok(value) => value
    Err(issue) => {
      @strategy.cancel_captured_effect_proposal_plan(plan)
      return Err(NativeExport(issue))
    }
  }
  let preparation = @strategy.captured_effect_local_result_export_preparation(
    exported,
  )
  let prepare = () => {
    while true {
      if !self.resident_effect_inputs_current(inputs) {
        return Err(ResidentEffectProposalIssue::Unavailable)
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
  let stream = match prepare() {
    Ok(value) => value
    Err(issue) => {
      @execution.cancel_completed_result_relation_export(preparation) |> ignore
      @strategy.cancel_captured_effect_proposal_plan(plan)
      return Err(issue)
    }
  }
  let read = () => {
    let mut count = 0
    while true {
      if !self.resident_effect_inputs_current(inputs) {
        return Err(ResidentEffectProposalIssue::Unavailable)
      }
      match
        @execution.next_completed_output_export_canonical_row(
          stream, max_nodes, max_depth, max_utf16_units,
        ) {
        Ok(None) => break
        Ok(Some((index, _, row))) => {
          let (selector, changes) = match
            @strategy.project_captured_effect_proposal_row(
              plan, row, index, max_fields, max_work, max_bytes, max_nodes, max_depth,
            ) {
            Ok(value) => value
            Err(issue) => return Err(Proposal(issue))
          }
          if receive(index, selector, changes) is Err(_) {
            return Err(ReceiverRejected)
          }
          if !self.resident_effect_inputs_current(inputs) {
            return Err(Unavailable)
          }
          count += 1
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
      return Err(Unavailable)
    }
    match @strategy.finish_captured_effect_proposal_plan(plan, count) {
      Ok(_) => ()
      Err(issue) => return Err(Proposal(issue))
    }
    Ok(count)
  }
  let outcome = read()
  @execution.cancel_completed_output_export(stream)
  @execution.cancel_completed_result_relation_export(preparation) |> ignore
  @strategy.cancel_captured_effect_proposal_plan(plan)
  outcome
}
