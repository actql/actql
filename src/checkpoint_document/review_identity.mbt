///|
/// Existing review-content identity, not artifact admission or permission.
/// A legacy complete-byte digest remains distinct from the two self-addressed
/// review forms. In particular, this never constructs a sealed Checkpoint.
pub fn review_bytes_match_cid(
  raw : Bytes,
  expected : String,
  limits : Limits,
) -> Bool {
  if !valid_limits(limits) ||
    !valid_cid(expected) ||
    raw.length() > limits.max_wire_bytes {
    return false
  }
  if "sha256:" + @sha256.hex(raw) == expected {
    return true
  }
  let wire = @utf8.decode(raw) catch { _ => return false }
  let node = match
    @source.parse_json_bytes_preserving(raw, {
      max_input_bytes: limits.max_wire_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(node) => node
    Err(_) => return false
  }
  let fields = match node.value {
    @source.Object(fields) => fields
    _ => return false
  }
  let mut version : String? = None
  for field in fields {
    if field.key == "version" {
      match field.value.value {
        @source.String(text) => version = Some(text)
        _ => return false
      }
    }
  }
  guard version is Some(version) && review_data_keys(version) is Some(data_keys) else {
    return false
  }
  let value = @json.from_source(
    node,
    limits.max_nodes,
    limits.max_depth,
    limits.max_wire_bytes,
    data_keys~,
  ) catch {
    _ => return false
  }
  if string_field(value, "review_projection_cid") != Some(expected) ||
    wire_of(value, limits) != Some(wire) {
    return false
  }
  guard @json.object_without_field(value, "review_projection_cid") is Some(body) else {
    return false
  }
  cid_of(body, limits) == Some(expected)
}
