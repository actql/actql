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

///|
/// Named pinned SDK-v4 DATA profile on the original read-only codec child.
#export_name("clientProgramFinishOpenAIChatSdkV4Projection")
pub fn client_program_finish_openai_chat_sdk_v4_projection(
  cursor : @model.OpenAIChatProjection,
  model_id : String,
  max_request_bytes : Int,
) -> Result[
  (String, String, String, String, String, String, String, String),
  @model.OpenAIChatProjectionIssue,
] {
  @model.finish_openai_chat_sdk_v4_projection(
    cursor, model_id, max_request_bytes,
  )
}

///|
#export_name("clientProgramProjectOpenAIChatSdkV4Request")
pub fn client_program_project_openai_chat_sdk_v4_request(
  provider : @model.AdmittedModelProvider,
  request : @model.ModelRequest,
  model_id : String,
  max_request_bytes : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_frames : Int,
  max_work : Int,
) -> Result[
  (String, String, String, String, String, String, String, String),
  @model.OpenAIChatProjectionIssue,
] {
  @model.project_openai_chat_sdk_v4_request(
    provider, request, model_id, max_request_bytes, max_bytes, max_nodes, max_depth,
    max_frames, max_work,
  )
}
