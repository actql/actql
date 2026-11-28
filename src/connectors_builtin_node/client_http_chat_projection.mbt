///|
/// Original Common codec consumer; not a public provider-installation API.
#export_name("clientProgramProjectHTTPChatRequest")
pub fn client_program_project_http_chat_request(
  provider : @model.AdmittedModelProvider,
  request : @model.ModelRequest,
  model_id : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_frames : Int,
  max_work : Int,
) -> Result[
  (String, String, String, String, String),
  @model.OpenAIChatProjectionIssue,
] {
  @model.project_http_chat_request(
    provider, request, model_id, max_bytes, max_nodes, max_depth, max_frames, max_work,
  )
}
