///|
/// Catalog-owned listing declaration, not a count proof or read authority.
struct FileListProfile {
  body : @decode.Cursor
  facts_cid : String
  paths : Bool
  glob : Bool
  unfiltered : Bool
  limits : Array[(String, Int64)]
}

///|
pub fn source_request_file_listing(
  v : SourceViewRequestContract,
) -> FileListProfile? {
  v.file_listing
}

///|
pub fn file_listing_accepts(
  profile : FileListProfile,
  selector : String,
) -> Bool {
  match selector {
    "paths" => profile.paths
    "glob" => profile.glob
    "all" => profile.unfiltered
    _ => false
  }
}

///|
pub fn file_listing_limit_candidates(
  profile : FileListProfile,
) -> Array[(String, Int64)] {
  profile.limits.copy()
}

///|
// Inspect an admitted Catalog candidate without copying its whole Array.
// This is not a resolved selected-row ceiling, observed count, byte grant or
// read authority. The receiving funded frame still owns result/control cost.
pub fn file_listing_declared_limit(
  profile : FileListProfile,
  quantity : String,
) -> Int64? {
  for (name, bound) in profile.limits {
    if name == quantity && bound > 0L {
      return Some(bound)
    }
  }
  None
}

///|
pub fn file_listing_source(profile : FileListProfile) -> @decode.Cursor {
  profile.body
}

///|
pub fn file_listing_facts_cid(profile : FileListProfile) -> String {
  profile.facts_cid
}

///|
fn file_list_text(
  object : @decode.ObjectView,
  name : String,
  b : SourceRequestBudget,
) -> String raise SourceRequestStop {
  let source = match @decode.lookup(object, name) {
    Some(value) => value
    None =>
      raise SourceRequestStop({ kind: InvalidFileListProfile, source: None, })
  }
  let text = match @decode.text(source) {
    Ok(value) => value
    Err(_) => request_fail(InvalidFileListProfile, source)
  }
  request_charge(b, text.length() + 1, source)
  text
}

///|
fn file_list_cid(value : String) -> Bool {
  value.length() == 71 &&
  value.has_prefix("sha256:") &&
  value[7:].iter().all(c => (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))
}

///|
fn file_list_object(
  source : @decode.Cursor,
  b : SourceRequestBudget,
) -> @decode.ObjectView raise SourceRequestStop {
  if @decode.object_length(source) is None {
    request_fail(InvalidFileListProfile, source)
  }
  request_object(source, b)
}

///|
// Same original interpreter field list; quantity inspection does not own a
// second schema/allow table or authorize a listing.
fn file_listing_allowed_fields() -> Array[String] {
  [
    "version", "kind", "selectable", "allow_unfiltered_listing", "admitted_scope_contract_cid",
    "listing_schema_contract_cid", "path_profile_cid", "version_capability", "max_listing_items",
    "max_examined_items", "max_listing_pages", "max_request_attempts", "max_listing_bytes",
    "max_listing_duration_ms", "maximum_path_length",
  ]
}

///|
// The two existing file profiles share this closed capability record shape.
fn file_version_capability_fields() -> Int {
  2
}

///|
fn read_file_list_profile(
  view : Member,
  catalog : Catalog,
  carriers : CarrierSchemas,
  request_schema : @row.Schema,
  b : SourceRequestBudget,
) -> FileListProfile? raise SourceRequestStop {
  let root = request_object(member_body(view), b)
  let output = request_object(@decode.required(root, "output").unwrap(), b)
  let reference = request_object(@decode.required(output, "facts").unwrap(), b)
  let envelope = match
    resolve_catalog_contract(
      catalog,
      file_list_text(reference, "id", b),
      file_list_text(reference, "version", b),
      file_list_text(reference, "cid", b),
      "carrier_facts",
    ) {
    Ok(value) => value
    Err(_) => request_fail(InvalidFileListProfile, member_body(view))
  }
  // Other carrier facts need not declare a file listing profile.
  if @decode.object_length(envelope.body) is None {
    return None
  }
  let facts = request_object(envelope.body, b)
  let source = match @decode.lookup(facts, "file_listing") {
    None => return None
    Some(value) => value
  }
  let profile = file_list_object(source, b)
  let allowed = file_listing_allowed_fields()
  let limits = []
  for i in 0..<@decode.object_length(source).unwrap() {
    let (name, value) = @decode.field_at(source, i).unwrap()
    request_charge(b, name.length() + 1, value)
    if !allowed.contains(name) {
      request_fail(InvalidFileListProfile, value)
    }
    if name.has_prefix("max_") || name == "maximum_path_length" {
      let n = match @decode.safe_integer(value) {
        Ok(n) if n > 0 => n
        _ => request_fail(InvalidFileListProfile, value)
      }
      limits.push((name, n))
    }
  }
  if file_list_text(profile, "version", b) != "actql-file-list/0.1" ||
    file_list_text(profile, "kind", b) != "file_listing" ||
    !file_list_cid(file_list_text(profile, "admitted_scope_contract_cid", b)) {
    request_fail(InvalidFileListProfile, source)
  }
  let schema_ref = request_object(
    @decode.required(output, "schema").unwrap(),
    b,
  )
  if file_list_text(profile, "listing_schema_contract_cid", b) !=
    file_list_text(schema_ref, "cid", b) {
    request_fail(InvalidFileListProfile, source)
  }
  if @decode.lookup(profile, "path_profile_cid") is Some(value) {
    if !file_list_cid(file_list_text(profile, "path_profile_cid", b)) {
      request_fail(InvalidFileListProfile, value)
    }
  }
  let selectable = match @decode.lookup(profile, "selectable") {
    Some(value) => value
    None => request_fail(InvalidFileListProfile, source)
  }
  let count = match @decode.array_length(selectable) {
    Some(n) if n <= 2 => n
    _ => request_fail(InvalidFileListProfile, selectable)
  }
  let mut paths = false
  let mut glob = false
  for i in 0..<count {
    let value = @decode.element_at(selectable, i).unwrap()
    request_charge(b, 1, value)
    match @decode.text(value) {
      Ok("paths") if !paths => paths = true
      Ok("glob") if !glob => glob = true
      _ => request_fail(InvalidFileListProfile, value)
    }
  }
  let unfiltered = match @decode.lookup(profile, "allow_unfiltered_listing") {
    Some(value) =>
      match @decode.boolean(value) {
        Ok(value) => value
        Err(_) => request_fail(InvalidFileListProfile, value)
      }
    None => request_fail(InvalidFileListProfile, source)
  }
  let mut nonnull_version = false
  if @decode.lookup(profile, "version_capability") is Some(value) {
    if @decode.object_length(value) != Some(file_version_capability_fields()) {
      request_fail(InvalidFileListProfile, value)
    }
    let capability = request_object(value, b)
    if !file_list_cid(file_list_text(capability, "contract_cid", b)) {
      request_fail(InvalidFileListProfile, value)
    }
    nonnull_version = match @decode.lookup(capability, "required_nonnull") {
      Some(field) =>
        match @decode.boolean(field) {
          Ok(value) => value
          Err(_) => request_fail(InvalidFileListProfile, field)
        }
      None => request_fail(InvalidFileListProfile, value)
    }
  }
  // NULL denotes the inactive Request alternative, never absent listing data.
  // The Request owner checks exclusivity and selected nonnull parameters.
  for name in ["paths", "glob"] {
    let contract = match @row.lookup(request_schema, @row.Unqualified(name)) {
      Some(value) => value
      None => request_fail(InvalidFileListProfile, source)
    }
    request_charge(b, 1, source)
    let valid = contract.nullable &&
      (match (name, contract.shape) {
        ("glob", @value_contract.Text(_)) => true
        ("paths", @value_contract.Array(element, ..)) =>
          !element.nullable && element.shape is @value_contract.Text(_)
        _ => false
      })
    if !valid {
      request_fail(InvalidFileListProfile, source)
    }
  }
  let carrier = carriers.views[member_index(view)].schema.carrier
  let records = match carrier {
    @carrier.Relation(records) => records
    _ => request_fail(InvalidFileListProfile, source)
  }
  let schema = match @carrier.complete_schema(records) {
    Some(schema) if @row.field_count(schema) >= 7 => schema
    _ => request_fail(InvalidFileListProfile, source)
  }
  // The seven roles are a required base, not a projection of the Source's
  // complete declared metadata. Carrier admission already checks every field
  // contract; include the additional fields in this interpreter's work too.
  request_charge(b, @row.field_count(schema) - 7, source)
  let resource_kind = file_list_text(root, "resource_kind", b)
  for
    name in [
      "resource", "version", "name", "path", "media_type", "size_bytes", "modified_at",
    ] {
    request_charge(b, 1, source)
    guard @row.lookup_reference(schema, name) is Some(field) &&
      @row.field_presence(field) == @row.Required else {
      request_fail(InvalidFileListProfile, source)
    }
    let contract = @row.field_contract(field)
    let matches = match (name, contract.shape) {
      ("resource", @value_contract.ResourceRef(resource_kind=kind)) =>
        !contract.nullable && kind == resource_kind
      ("version", @value_contract.Text(_)) =>
        !nonnull_version || !contract.nullable
      ("name", @value_contract.Text(_)) => !contract.nullable
      ("path" | "media_type", @value_contract.Text(_)) => true
      ("size_bytes", @value_contract.Number) => true
      ("modified_at", @value_contract.Timestamp) => true
      _ => false
    }
    if !matches {
      request_fail(InvalidFileListProfile, source)
    }
  }
  Some({
    body: source,
    facts_cid: envelope.cid,
    paths,
    glob,
    unfiltered,
    limits,
  })
}
