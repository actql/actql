///|
/// Read-only original-request child. These exports issue neither call nor
/// capacity authority and do not install a native Decision response codec.
#export_name("clientProgramStartNativeDecisionProjection")
pub fn client_program_start_native_decision_projection(
  provider : @model.AdmittedModelProvider,
  request : @model.ModelRequest,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_frames : Int,
  max_work : Int,
) -> Result[
  @model.NativeDecisionProjection,
  @model.NativeDecisionProjectionIssue,
] {
  @model.start_native_decision_projection(
    provider, request, max_bytes, max_nodes, max_depth, max_frames, max_work,
  )
}

///|
#export_name("clientProgramAdvanceNativeDecisionProjection")
pub fn client_program_advance_native_decision_projection(
  cursor : @model.NativeDecisionProjection,
) -> Result[@model.NativeDecisionRequest?, @model.NativeDecisionProjectionIssue] {
  @model.advance_native_decision_projection(cursor)
}

///|
#export_name("clientProgramRetireNativeDecisionProjection")
pub fn client_program_retire_native_decision_projection(
  cursor : @model.NativeDecisionProjection,
) -> Unit {
  @model.retire_native_decision_projection(cursor)
}

///|
#export_name("clientProgramRetireNativeDecisionRequest")
pub fn client_program_retire_native_decision_request(
  value : @model.NativeDecisionRequest,
) -> Unit {
  @model.retire_native_decision_request(value)
}

///|
#export_name("clientProgramNativeDecisionRequestWires")
pub fn client_program_native_decision_request_wires(
  value : @model.NativeDecisionRequest,
) -> (String, String)? {
  @model.native_decision_request_wires(value)
}

///|
#export_name("clientProgramNativeDecisionRequestMatches")
pub fn client_program_native_decision_request_matches(
  value : @model.NativeDecisionRequest,
  provider : @model.AdmittedModelProvider,
  request : @model.ModelRequest,
) -> Bool {
  @model.native_decision_request_matches(value, provider, request)
}

///|
#export_name("clientProgramNativeDecisionRequestBinding")
pub fn client_program_native_decision_request_binding(
  value : @model.NativeDecisionRequest,
) -> (String, String, String, String)? {
  @model.native_decision_request_binding(value)
}

///|
#export_name("clientProgramNativeDecisionQuestionId")
pub fn client_program_native_decision_question_id(
  value : @model.NativeDecisionRequest,
  index : Int,
) -> String? {
  @model.native_decision_question_id(value, index)
}

///|
#export_name("clientProgramNativeDecisionOptionId")
pub fn client_program_native_decision_option_id(
  value : @model.NativeDecisionRequest,
  question : Int,
  option : Int,
) -> String? {
  @model.native_decision_option_id(value, question, option)
}

///|
#export_name("clientProgramNativeDecisionProjectionIssueKind")
pub fn client_program_native_decision_projection_issue_kind(
  issue : @model.NativeDecisionProjectionIssue,
) -> String {
  match issue {
    @model.ForeignRequest => "foreign_request"
    @model.Unsupported => "unsupported"
    @model.Limit => "limit"
  }
}
