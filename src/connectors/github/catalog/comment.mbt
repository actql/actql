///|
/// The settled meaning of one comment-create exchange. Only a documented
/// success or a documented refusal settles the row; every other observation
/// leaves the send unknown, and nothing here infers success from content.
pub(all) enum CommentOutcome {
  Created(id~ : Int64, node_id~ : String)
  Refused(status~ : Int)
  Unknown
} derive(Eq, Debug)

///|
/// Classify a comment-create response. 201 with the created comment's `id`
/// and `node_id` is success. 403/404/410/422 are documented refusals that
/// created nothing, except a 403 that is a rate limit: GitHub may have
/// throttled a request it did not apply, but the documentation does not
/// promise that, so a rate-limited send stays unknown. Everything else
/// (5xx, 429, unexpected statuses, malformed success bodies) is unknown.
pub fn classify_comment_response(
  status : Int,
  headers : HeaderObservation,
  body : Bytes,
  max_bytes : Int,
) -> CommentOutcome {
  if status == 201 {
    if body.length() > max_bytes || max_bytes <= 0 {
      return Unknown
    }
    let parsed = @source.parse_json_bytes(body, {
      max_input_bytes: max_bytes,
      max_nodes: 4096,
      max_depth: 16,
    })
    guard parsed is Ok(node) else { return Unknown }
    let admitted = @decode.admit(node, {
      max_nodes: 4096,
      max_depth: 16,
      max_string_bytes: max_bytes,
      max_total_string_bytes: max_bytes,
    })
    guard admitted is Ok(root) else { return Unknown }
    guard @decode.open_object(root) is Ok(object) else { return Unknown }
    let id = match @decode.field(object, "id") {
      Present(value) =>
        match @decode.safe_integer(value) {
          Ok(id) if id > 0L => id
          _ => return Unknown
        }
      _ => return Unknown
    }
    let node_id = match @decode.field(object, "node_id") {
      Present(value) =>
        match @decode.text(value) {
          Ok(text) if text.length() > 0 => text
          _ => return Unknown
        }
      _ => return Unknown
    }
    return Created(id~, node_id~)
  }
  match classify_failure(status, headers) {
    PermissionDenied | NotFound | Gone | Unprocessable => Refused(status~)
    RateLimited(_) | ProviderUnavailable | Unexpected(_) => Unknown
  }
}
