///|
/// A logical staging view retained by the existing per-read Reader, not a
/// Resource, Catalog/current proof or physical cleanup owner. The opaque parser
/// stays in this provider runtime; only sizing DATA crosses to Common.
pub struct PropertyResponseSource {
  priv bytes : Bytes
  priv path : String
  priv digest : String
  priv object_type : String
  priv limits : PropertyLimits
  priv preflight : @source.JsonSourcePreflight
  priv geometry : @source.JsonSourceGeometry
  priv mut taken : Bool
  priv mut retired : Bool
}

///|
/// The existing Reader funds decoded text/preflight before this call. Failure
/// is retained as DATA until the original HTTP accepted/status projection.
pub fn prepare_property_response_source(
  bytes : Bytes,
  path : String,
  object_type : String,
  limits : PropertyLimits,
) -> Result[PropertyResponseSource, PropertyIssue] {
  if property_input_issue(bytes, object_type, limits) is Some(issue) {
    return Err(issue)
  }
  // Bind the original before decoding/preflight; later Resource reentry is
  // checked against these bytes, not a digest first taken after staging.
  let digest = @sha.hex(bytes)
  let text = @utf8.decode(bytes[:], ignore_bom=false) catch {
    _ => return Err(InvalidResponse)
  }
  let preflight = match
    @source.start_json_source_preflight(text, {
      max_input_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(value) => value
    Err(issue) => return Err(property_source_issue(issue))
  }
  let geometry = for tick = 0 {
    match @source.advance_json_source_preflight(preflight, 4096) {
      Ok(JsonSourceContinue(..)) => continue tick + 1
      Ok(JsonSourceReady(value, ..)) => break value
      Ok(JsonSourceFailed(issue, ..)) => {
        @source.cancel_json_source_preflight(preflight)
        return Err(property_source_issue(issue))
      }
      Err(_) => {
        @source.cancel_json_source_preflight(preflight)
        return Err(InvalidResponse)
      }
    }
  }
  Ok({
    bytes,
    path,
    digest,
    object_type,
    limits,
    preflight,
    geometry,
    taken: false,
    retired: false,
  })
}

///|
/// Pure geometry DATA from this same preflight, never syntax/permission. A
/// failed prepare is not thrown ahead of the existing HTTP refusal boundary.
pub fn property_response_source_geometry(
  prepared : Result[PropertyResponseSource, PropertyIssue],
) -> @source.JsonSourceGeometry? {
  guard prepared is Ok(original) && !original.taken && !original.retired else {
    return None
  }
  Some(original.geometry)
}

///|
pub fn property_response_source_geometry_data(
  prepared : Result[PropertyResponseSource, PropertyIssue],
) -> Array[Int] {
  guard property_response_source_geometry(prepared) is Some(g) else {
    return []
  }
  [
    g.input_bytes,
    g.input_utf16_units,
    g.objects,
    g.arrays,
    g.fields,
    g.quoted_tokens,
    g.quoted_raw_utf16_units,
    g.longest_quoted_raw_utf16,
    g.atoms,
    g.longest_atom_utf16,
    g.depth_upper,
    g.node_upper,
  ]
}

///|
pub fn consume_property_response_source(
  prepared : Result[PropertyResponseSource, PropertyIssue],
  path : String,
  bytes : Bytes,
) -> Result[PropertyCatalog, PropertyIssue] {
  let original = match prepared {
    Ok(original) => original
    Err(issue) => return Err(issue)
  }
  if original.taken || original.retired {
    return Err(InvalidResponse)
  }
  if original.path != path ||
    !physical_equal(original.bytes, bytes) ||
    original.digest != @sha.hex(bytes) {
    retire_property_response_source(prepared)
    return Err(InvalidResponse)
  }
  original.taken = true
  let parser = match @source.take_json_source_parser(original.preflight) {
    Ok(value) => value
    Err(_) => {
      retire_property_response_source(prepared)
      return Err(InvalidResponse)
    }
  }
  let parsed = for tick = 0 {
    match @source.advance_json_parse(parser, 4096) {
      Ok(JsonParseContinue(..)) => continue tick + 1
      Ok(JsonParseComplete(value, ..)) => break value.node
      Ok(JsonParseFailed(issue, ..)) => return Err(property_source_issue(issue))
      Err(_) => return Err(InvalidResponse)
    }
  }
  let catalog = match
    project_property_node(parsed, bytes, original.object_type, original.limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // Keep the original projector's complete final hash. Preflight identity is
  // not a replacement for that duty or for the newly projected Catalog CID.
  if catalog.response_sha256 != original.digest {
    retire_property_response_source(prepared)
    return Err(InvalidResponse)
  }
  Ok(catalog)
}

///|
/// Idempotent logical cursor retirement only. The generic Reader retains all
/// original bodies and its physical/current/charge/close duties independently.
pub fn retire_property_response_source(
  prepared : Result[PropertyResponseSource, PropertyIssue],
) -> Unit {
  if prepared is Ok(original) && !original.retired {
    @source.cancel_json_source_preflight(original.preflight)
    original.retired = true
  }
}
