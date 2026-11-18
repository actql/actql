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

///|
/// Non-driving convenience for the SAME named SDK-v4 profile and child owner.
pub fn project_openai_chat_sdk_v4_request(
  provider : AdmittedModelProvider,
  request : ModelRequest,
  model_id : String,
  max_request_bytes : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_frames : Int,
  max_work : Int,
) -> Result[
  (String, String, String, String, String, String, String, String),
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
      Ok(Some(_)) =>
        return finish_openai_chat_sdk_v4_projection(
          cursor, model_id, max_request_bytes,
        )
      Ok(None) => ()
      Err(issue) => return Err(issue)
    }
  } nobreak {
    Err(Limit)
  }
}
