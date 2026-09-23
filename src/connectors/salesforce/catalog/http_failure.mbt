///|
/// Classifies a bounded Salesforce REST failure body. The HTTP adapter owns
/// transport observation; this Connector owns provider-specific error meaning.
pub fn catalog_http_failure(
  status : Int,
  body : Bytes,
  max_body_bytes : Int,
) -> DescribeFailure {
  if status == 429 {
    return RateLimited
  }
  if status == 403 && max_body_bytes >= 0 && body.length() <= max_body_bytes {
    let parsed = @source.parse_json_bytes(body, {
      max_input_bytes: max_body_bytes,
      max_nodes: 32,
      max_depth: 4,
    })
    match parsed {
      Ok(value) => {
        let admitted = @decode.admit(value, {
          max_nodes: 32,
          max_depth: 4,
          max_string_bytes: max_body_bytes,
          max_total_string_bytes: max_body_bytes,
        })
        match admitted {
          Ok(root) =>
            match @decode.array_length(root) {
              Some(count) if count > 0 =>
                match
                  @decode.open_object(@decode.element_at(root, 0).unwrap()) {
                  Ok(error) =>
                    if required_text(error, "errorCode")
                      is Some("REQUEST_LIMIT_EXCEEDED") {
                      return RateLimited
                    }
                  Err(_) => ()
                }
              _ => ()
            }
          Err(_) => ()
        }
      }
      Err(_) => ()
    }
  }
  if status == 401 || status == 403 {
    return PermissionDenied
  }
  if status >= 500 && status <= 599 {
    return ProviderUnavailable
  }
  InvalidMetadata
}
