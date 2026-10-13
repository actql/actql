///|
/// Private DATA codec, not a physical response/profile/custody issuer.
#export_name("clientProgramProjectNativeDecisionAnswers")
pub fn client_program_project_native_decision_answers(
  original : @model.NativeDecisionRequest,
  provider : @model.AdmittedModelProvider,
  request : @model.ModelRequest,
  response : @decode.Cursor,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_work : Int,
) -> Result[(String, Int), @model.NativeDecisionAnswerIssue] {
  @model.project_native_decision_answers(
    original, provider, request, response, max_bytes, max_nodes, max_depth, max_work,
  )
}
