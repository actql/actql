///|
#export_name("clientProgramStartInferOriginalCurrentStateDecode")
pub fn client_program_start_infer_original_current_state_decode(
  active : @infer_host.Execution,
  scope : @publication_host.ClientModelReadScope,
  park : @publication_host.ClientModelResourcePark,
  wire : String,
  parse_limits : @source.ParseLimits,
  tree_limits : @decode.Limits,
  max_work : Int,
) -> Result[@infer_host.OriginalModelCurrentStateDecode, @infer_host.OriginalModelCurrentStateDecodeIssue] {
  @infer_host.start_original_model_current_state_decode(active, scope, park, wire, parse_limits, tree_limits, max_work)
}

///|
#export_name("clientProgramAdvanceInferOriginalCurrentStateDecode")
pub fn client_program_advance_infer_original_current_state_decode(
  active : @infer_host.Execution,
  scope : @publication_host.ClientModelReadScope,
  park : @publication_host.ClientModelResourcePark,
  value : @infer_host.OriginalModelCurrentStateDecode,
  quantum : Int,
) -> @infer_host.OriginalModelCurrentStateDecodePoll {
  @infer_host.advance_original_model_current_state_decode(active, scope, park, value, quantum)
}

///|
#export_name("clientProgramInferOriginalCurrentStateDecodePoll")
pub fn client_program_infer_original_current_state_decode_poll(
  poll : @infer_host.OriginalModelCurrentStateDecodePoll,
) -> (String, Int, @infer_host.OriginalModelCurrentStateDecodeIssue?, @resources.OriginalCurrentStateDocument?) {
  match poll {
    @infer_host.CurrentDecodeContinue(work~) => ("continue", work, None, None)
    @infer_host.CurrentDecodeComplete(document, work~) => ("complete", work, None, Some(document))
    @infer_host.CurrentDecodeFailed(issue, work~) => ("failed", work, Some(issue), None)
  }
}

///|
#export_name("clientProgramCancelInferOriginalCurrentStateDecode")
pub fn client_program_cancel_infer_original_current_state_decode(
  value : @infer_host.OriginalModelCurrentStateDecode,
) -> Unit {
  @infer_host.cancel_original_model_current_state_decode(value)
}

///|
#export_name("clientProgramRetireInferOriginalCurrentStateDocument")
pub fn client_program_retire_infer_original_current_state_document(
  value : @resources.OriginalCurrentStateDocument,
) -> Unit {
  @resources.retire_original_current_state_document(value)
}

///|
#export_name("clientProgramStartInferOriginalCurrentStateComparison")
pub fn client_program_start_infer_original_current_state_comparison(
  active : @infer_host.Execution,
  scope : @publication_host.ClientModelReadScope,
  park : @publication_host.ClientModelResourcePark,
  document : @resources.OriginalCurrentStateDocument,
  max_work : Int,
) -> Result[@publication_host.ClientModelCurrentStateComparison, @resources.OriginalStateComparisonIssue] {
  @infer_host.start_original_model_current_state_comparison(active, scope, park, document, max_work)
}

///|
#export_name("clientProgramAdvanceInferOriginalCurrentStateComparison")
pub fn client_program_advance_infer_original_current_state_comparison(
  active : @infer_host.Execution,
  scope : @publication_host.ClientModelReadScope,
  park : @publication_host.ClientModelResourcePark,
  value : @publication_host.ClientModelCurrentStateComparison,
  quantum : Int,
) -> Result[@resources.OriginalStateComparisonPoll, @publication_host.ClientModelReadPreparationIssue] {
  @infer_host.advance_original_model_current_state_comparison(active, scope, park, value, quantum)
}

///|
#export_name("clientProgramInferOriginalCurrentStateComparisonPoll")
pub fn client_program_infer_original_current_state_comparison_poll(
  poll : @resources.OriginalStateComparisonPoll,
) -> (String, Int, @resources.OriginalStateComparisonIssue?) {
  match poll {
    @resources.ComparisonContinue(work~) => ("continue", work, None)
    @resources.ComparisonComplete(work~) => ("complete", work, None)
    @resources.ComparisonFailed(issue, work~) => ("failed", work, Some(issue))
  }
}

///|
#export_name("clientProgramCancelInferOriginalCurrentStateComparison")
pub fn client_program_cancel_infer_original_current_state_comparison(
  value : @publication_host.ClientModelCurrentStateComparison,
) -> Unit {
  @publication_host.cancel_client_model_current_state_comparison(value)
}
