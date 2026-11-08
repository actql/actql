///|
/// Project the request/response identities from this original generated view.
/// This is installation DATA, not a capability, request or successful read.
pub fn row_declaration_keyed_read_schema_identities(
  declaration : RowDeclaration,
  source_ref : String,
) -> (String, String)? {
  for index, view in declaration.views {
    if view.source_ref != source_ref {
      continue
    }
    let parsed = @json.parse(declaration.view_bodies[index]) catch {
      _ => return None
    }
    guard parsed is Object(root) &&
      root.get("acquisition") is Some(Object(acquisition)) &&
      acquisition.get("kind") == Some(Json::string("fetch")) &&
      acquisition.get("authority") == Some(Json::string("read_content")) &&
      acquisition.get("request_schema") is Some(Object(request)) &&
      request.get("cid") is Some(String(request_cid)) else {
      return None
    }
    return Some((request_cid, view.carrier_schema_cid))
  }
  None
}
