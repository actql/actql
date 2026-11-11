///|
/// The installing declared-file supplier's immutable projection DATA. This
/// binds original declarations, never Resource resolution, permission or IO.
pub(all) struct DeclaredFileReadFields {
  identity : String
  name : String
  version : String
  media_type : String
  content_utf8 : String
  path : String?
  items_path : Array[String]
  key_path : Array[String]
}

///|
priv struct DeclaredFileReadProfile {
  source_ref : String
  physical_view : RowDeclaredView
  physical_wire : String
  physical_resource : String
  fields : DeclaredFileReadFields
  contract : @publication.PublicationContract
}

///|
fn declared_file_read_text_units(fields : DeclaredFileReadFields) -> Int64? {
  let mut units = 0L
  for
    name in [
      fields.identity,
      fields.name,
      fields.version,
      fields.media_type,
      fields.content_utf8,
    ] {
    if name.is_empty() || name.contains("\u0000") {
      return None
    }
    units += name.length().to_int64()
  }
  if fields.path is Some(name) {
    if name.is_empty() || name.contains("\u0000") {
      return None
    }
    units += name.length().to_int64()
  }
  for path in [fields.items_path, fields.key_path] {
    for name in path {
      if name.is_empty() || name.contains("\u0000") {
        return None
      }
      guard @execution.checked_preparation_add_product(
          units,
          name.length().to_int64(),
          1L,
        )
        is Some(next) else {
        return None
      }
      units = next
    }
  }
  Some(units)
}

///|
fn declared_file_read_profile_wire_bound(
  fields : DeclaredFileReadFields,
) -> Int? {
  guard declared_file_read_text_units(fields) is Some(units) &&
    @execution.checked_preparation_add_product(4096L, units, 6L) is Some(bytes) &&
    bytes <= 2147483647L else {
    return None
  }
  Some(bytes.to_int())
}

///|
/// Before-call geometry from the SAME retained declaration strings and field
/// inventory. No schema parse, second serialization or policy ceiling is used
/// to discover demand. The original Source material admits this quantity.
pub fn declared_file_read_profile_construction_inventory(
  declaration : RowDeclaration,
  physical : RowDeclaration,
  fields : DeclaredFileReadFields,
  prior_profiles? : Int = 0,
) -> @execution.PreparationRepresentationUnits? {
  if prior_profiles < 0 { return None }
  guard declared_file_read_profile_wire_bound(fields) is Some(bytes) else {
    return None
  }
  let mut source_units = 0L
  for wires in [declaration.view_bodies, physical.contracts, physical.view_bodies] {
    for wire in wires {
      guard @execution.checked_preparation_add_product(source_units, wire.length().to_int64(), 1L)
        is Some(next) else { return None }
      source_units = next
    }
  }
  guard source_units < 357913940L else { return None }
  // A JSON node consumes at least one original code unit. These are actual
  // retained metadata bodies; the bound does not scale with a file/read limit.
  let source_bytes = (6L * source_units + 1L).to_int()
  let source_nodes = (source_units + 1L).to_int()
  let profile_nodes = 40 + fields.items_path.length() + fields.key_path.length()
  guard relation_construction_decoded_construction(
      source_bytes, source_nodes, source_nodes, false,
    )
    is Some(parsed) &&
    relation_construction_contract_units(
      source_nodes, source_bytes, source_nodes,
    )
    is Some(contracts) &&
    relation_construction_json_forest(4L * source_nodes.to_int64())
    is Some(forests) &&
    relation_construction_decoded_construction(bytes, profile_nodes, 5, false)
    is Some(profile) &&
    relation_construction_writer_units(bytes, profile_nodes, 5) is Some(writer) &&
    @encode.hash_writer_construction_inventory(profile_nodes, 5) is Some(hash) &&
    relation_construction_json_forest(4L * profile_nodes.to_int64())
    is Some(profile_forests) &&
    @shape.collection_construction_extent({
      records: 6L,
      record_references: 26L,
      record_words: 2L,
      reference_arrays: 4L,
      reference_items: prior_profiles.to_int64() + fields.items_path.length().to_int64() +
      fields.key_path.length().to_int64() +
      declaration.file_read_profiles
      .map(profiles => profiles.length().to_int64())
      .unwrap_or(0L) +
      32L,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(controls) else {
    return None
  }
  @execution.compose_preparation_representation([
    parsed,
    {
      record_headers: hash.record_headers, reference_slots: hash.reference_slots,
      scalar_words: hash.scalar_words, owned_utf16_units: hash.owned_utf16_units,
      owned_wire_bytes: hash.owned_wire_bytes,
    },
    contracts,
    relation_construction_collection_units(forests),
    profile,
    writer,
    relation_construction_collection_units(profile_forests),
    relation_construction_collection_units(controls),
  ])
}

///|
/// Finalize the original installation declaration before it is exported or
/// supplied to a reader. Existing SourceView/Catalog identities stay exact;
/// only this implementation's genuine profile augments its capability member.
pub fn bind_declared_file_read_profile(
  declaration : RowDeclaration,
  source_ref : String,
  physical : RowDeclaration,
  physical_resource : String,
  fields : DeclaredFileReadFields,
) -> Result[RowDeclaration, RowMappingIssue] {
  guard !declaration.file_read_profiles
    .map(profiles => profiles.any(profile => profile.source_ref == source_ref))
    .unwrap_or(false) &&
    row_declaration_view(declaration, source_ref) is Some(view) &&
    physical.views.iter().find_first(view => view.resource == physical_resource)
    is Some(physical_view) &&
    row_declaration_keyed_read_schema_identities(declaration, source_ref)
    is Some((request, response)) &&
    declared_file_read_profile_wire_bound(fields) is Some(bytes) &&
    !fields.items_path.is_empty() &&
    !fields.key_path.is_empty() else {
    return Err(InvalidSpecification)
  }
  guard physical.views.search_by(view => physical_equal(view, physical_view)) is Some(physical_index) &&
    physical.view_bodies.get(physical_index) is Some(physical_wire) else {
    return Err(InvalidSpecification)
  }
  let mut wire_units = 0L
  for wire in physical.view_bodies { wire_units += wire.length().to_int64() }
  for wire in physical.contracts {
    wire_units += wire.length().to_int64()
  }
  if wire_units >= 357913940L {
    return Err(OutputLimit)
  }
  let bound = (6L * wire_units + 1L).to_int()
  let (_, original) = match
    mapping_original_relation(physical, physical_resource, fields.identity, {
      max_bytes: bound,
      max_nodes: bound,
      max_depth: bound,
      max_views: physical.views.length(),
      max_fields: bound,
    }) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard physical.views.get(physical_index) is Some(same_view) &&
    physical_equal(same_view, physical_view) &&
    physical.view_bodies.get(physical_index) == Some(physical_wire) else {
    return Err(InvalidSpecification)
  }
  guard original.shape is @contract.Object(columns) else {
    return Err(InvalidSpecification)
  }
  let text = (name, nullable) => {
    for index in 0..<@contract.field_count(columns) {
      let field = @contract.field_at(columns, index).unwrap()
      if field.name == name {
        return field.contract.shape is @contract.Text(_) &&
          (nullable || !field.contract.nullable)
      }
    }
    false
  }
  if ![
      fields.identity,
      fields.name,
      fields.version,
      fields.media_type,
      fields.content_utf8,
    ].all(name => text(name, false)) ||
    !fields.path.map(name => text(name, true)).unwrap_or(true) {
    return Err(InvalidSpecification)
  }
  let body = try {
    let writer = @encode.writer(
      bytes,
      40 + fields.items_path.length() + fields.key_path.length(),
      5,
    )
    @encode.begin_object(writer)
    for
      (key, value) in [
        ("physical_source_view_contract_cid", physical_view.view_cid),
        ("request_schema_cid", request),
        ("response_schema_cid", response),
        ("source_view_contract_cid", view.view_cid),
        ("version", "actql-declared-file-content-read/0.1"),
      ] {
      @encode.key(writer, key)
      @encode.string_value(writer, value)
    }
    @encode.key(writer, "projection")
    @encode.begin_object(writer)
    for
      (key, value) in [
        ("identity_field", fields.identity),
        ("name_field", fields.name),
        ("version_field", fields.version),
        ("media_type_field", fields.media_type),
        ("content_utf8_field", fields.content_utf8),
      ] {
      @encode.key(writer, key)
      @encode.string_value(writer, value)
    }
    @encode.key(writer, "path_field")
    match fields.path {
      None => @encode.null_value(writer)
      Some(value) => @encode.string_value(writer, value)
    }
    for
      (key, path) in [
        ("items_path", fields.items_path),
        ("key_path", fields.key_path),
      ] {
      @encode.key(writer, key)
      @encode.begin_array(writer)
      for part in path {
        @encode.string_value(writer, part)
      }
      @encode.end_array(writer)
    }
    @encode.end_object(writer)
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => return Err(OutputLimit)
  }
  let contract = match
    @publication.seal_publication_contract(
      "declared_file_content_read",
      body,
      bytes,
      40 + fields.items_path.length() + fields.key_path.length(),
      5,
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidSpecification)
  }
  let profile = {
    source_ref,
    physical_view,
    physical_wire,
    physical_resource,
    fields: {
      ..fields,
      items_path: fields.items_path.copy(),
      key_path: fields.key_path.copy(),
    },
    contract,
  }
  Ok({
    ..declaration,
    file_read_profiles: Some(
      match declaration.file_read_profiles {
        None => [profile]
        Some(profiles) => [..profiles, profile]
      },
    ),
  })
}

///|
/// Borrow only this exact original declaration's installed profile. A schema
/// CID, profile label or copied field record cannot install another binding.
pub fn row_declaration_file_read_profile(
  declaration : RowDeclaration,
  source_ref : String,
) -> @publication.PublicationContract? {
  match declaration.file_read_profiles {
    None => None
    Some(profiles) =>
      profiles
      .iter()
      .find_first(profile => profile.source_ref == source_ref)
      .map(profile => profile.contract)
  }
}

///|
/// The actual installing supplier presents the SAME physical declaration and
/// closed role/path selection before its reader is built. Its exact original
/// physical View survives final declaration composition; equal CIDs do not replace it; this observes no IO or current permission.
pub fn row_declaration_file_read_profile_matches(
  declaration : RowDeclaration,
  source_ref : String,
  physical : RowDeclaration,
  physical_resource : String,
  fields : DeclaredFileReadFields,
) -> Bool {
  guard declaration.file_read_profiles is Some(profiles) &&
    profiles.iter().find_first(profile => profile.source_ref == source_ref)
    is Some(profile) else {
    return false
  }
  let original = profile.fields
  let same_path = (left : Array[String], right : Array[String]) => {
    if left.length() != right.length() {
      return false
    }
    for index, part in left {
      if right[index] != part {
        return false
      }
    }
    true
  }
  profile.physical_resource == physical_resource &&
  physical.views.iter().find_first(view => view.resource == physical_resource) is Some(view) &&
  physical_equal(profile.physical_view, view) &&
  original.identity == fields.identity &&
  original.name == fields.name &&
  original.version == fields.version &&
  original.media_type == fields.media_type &&
  original.content_utf8 == fields.content_utf8 &&
  original.path == fields.path &&
  same_path(original.items_path, fields.items_path) &&
  same_path(original.key_path, fields.key_path)
}


///|
/// Original installing View body retained by the profile's existing Mapping
/// validation. Equal-CID profiles cannot select this borrowed publication DATA.
/// This performs no schema/identity check, allocation grant or Source read.
pub fn row_declaration_file_read_physical_source(
  declaration : RowDeclaration,
  profile : @publication.PublicationContract,
) -> (String, String)? {
  declaration.file_read_profiles.bind(profiles =>
    profiles.iter().find_first(value => physical_equal(value.contract, profile))
      .map(value => (value.physical_view.view_cid, value.physical_wire)))
}
