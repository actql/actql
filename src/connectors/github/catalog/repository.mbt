///|
/// A repository's stable identity, as observed by an explicit installation
/// or discovery step: the numeric id and node id GitHub keeps across renames
/// and transfers, and the owner/name used for access at that time.
pub(all) struct RepositoryIdentity {
  id : Int64
  node_id : String
  owner : String
  name : String
} derive(Eq, Debug)

///|
/// Project a 200 `GET /repos/{owner}/{repo}` body. Every field is required.
pub fn project_repository(body : Bytes, max_bytes : Int) -> RepositoryIdentity? {
  if max_bytes <= 0 || body.length() > max_bytes {
    return None
  }
  guard @source.parse_json_bytes(body, {
      max_input_bytes: max_bytes,
      max_nodes: 20000,
      max_depth: 32,
    })
    is Ok(node) &&
    @decode.admit(node, {
      max_nodes: 20000,
      max_depth: 32,
      max_string_bytes: max_bytes,
      max_total_string_bytes: max_bytes,
    })
    is Ok(root) &&
    @decode.open_object(root) is Ok(object) &&
    @decode.lookup(object, "id") is Some(id_cursor) &&
    @decode.safe_integer(id_cursor) is Ok(id) &&
    id > 0L &&
    @decode.lookup(object, "node_id") is Some(node_cursor) &&
    @decode.text(node_cursor) is Ok(node_id) &&
    node_id.length() > 0 &&
    @decode.lookup(object, "name") is Some(name_cursor) &&
    @decode.text(name_cursor) is Ok(name) &&
    @decode.lookup(object, "owner") is Some(owner_cursor) &&
    @decode.open_object(owner_cursor) is Ok(owner_object) &&
    @decode.lookup(owner_object, "login") is Some(login_cursor) &&
    @decode.text(login_cursor) is Ok(owner) else {
    return None
  }
  Some({ id, node_id, owner, name, })
}
