///|
/// Installed Relation views can declare finite snapshot acquisition semantics.
/// The builder supplies its own Request envelope; a connector cannot substitute
/// that CID, add a second registry, or turn a profile flag into fetch authority.
fn row_acquisition_body(
  specification : Json?,
  request : Json,
  limits : RowDeclarationLimits,
  max_work : Int,
) -> Result[(Json, Int), RowDeclarationIssue] {
  let fields = [
    ("default_mode", Json::string("snapshot")),
    ("request_schema", request),
    (
      "modes",
      Json::array([
        object([
          ("bounded", Json::boolean(true)),
          ("mode", Json::string("snapshot")),
        ]),
      ]),
    ),
  ]
  match specification {
    None => {
      fields.push(("kind", Json::string("scan")))
      fields.push(("authority", Json::string("read_content")))
    }
    Some(Object(entries)) => {
      if entries.length() < 2 ||
        entries.length() > 3 ||
        !entries.contains("kind") ||
        !entries.contains("authority") {
        return Err(InvalidAcquisition)
      }
      for (name, value) in entries {
        if !["kind", "authority", "correlation"].contains(name) {
          return Err(InvalidAcquisition)
        }
        fields.push((name, value))
      }
    }
    _ => return Err(InvalidAcquisition)
  }
  let body = object(fields)
  let wire = canonical_text(body, limits) catch { _ => return Err(OutputLimit) }
  let parsed = match
    @source.parse_json(wire, {
      max_input_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(value) => value
    Err(_) => return Err(InvalidAcquisition)
  }
  let cursor = match
    @decode.admit(parsed, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_bytes,
      max_total_string_bytes: limits.max_bytes,
    }) {
    Ok(value) => value
    Err(_) => return Err(InvalidAcquisition)
  }
  match @environment.check_source_view_acquisition_shape(cursor, max_work) {
    Ok(work) => Ok((body, work))
    Err(_) => Err(InvalidAcquisition)
  }
}
