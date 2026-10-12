///|
pub(all) enum OpenAIChatProjectionIssue {
  ForeignRequest
  Unsupported
  Limit
} derive(Eq, Debug)

///|
/// Finite read-only convenience for non-driving consumers. Physical preflight
/// uses the same original child cursor one advance at a time, not this loop.
pub fn project_openai_chat_request(
  provider : AdmittedModelProvider,
  request : ModelRequest,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_frames : Int,
  max_work : Int,
) -> Result[
  (String, String, String, String, String, String, String),
  OpenAIChatProjectionIssue,
] {
  let cursor = match
    start_openai_chat_projection(
      provider, request, max_bytes, max_nodes, max_depth, max_frames, max_work,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  while true {
    match advance_openai_chat_projection(cursor) {
      Ok(Some(value)) => {
        retire_openai_chat_projection(cursor)
        return Ok(value)
      }
      Ok(None) => ()
      Err(issue) => return Err(issue)
    }
  } nobreak {
    Err(Limit)
  }
}
