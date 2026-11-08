///|
/// Immutable implementation DATA retained by the original installed file
/// binding. This is not read permission, a Request or attempt evidence.
struct NativeRelationFileKeyedReadProfile {
  declaration : @rows.RowDeclaration
  source_ref : String
  physical : NativeRelationFilePreparedProvider
  fields : NativeRelationFileListingFields
  content_utf8 : String
  contract : @publication.PublicationContract
}

///|
/// Bind the actual original content view, physical provider and field roles.
/// Caller installation backing precedes construction; no I/O or callback runs.
pub fn prepare_native_relation_file_keyed_read_profile(
  declaration : @rows.RowDeclaration,
  source_ref : String,
  physical : NativeRelationFilePreparedProvider,
  fields : NativeRelationFileListingFields,
  content_utf8 : String,
) -> Result[NativeRelationFileKeyedReadProfile, NativeRelationFileIssue] {
  guard @rows.row_declaration_view(declaration, source_ref) is Some(view) &&
    physical.declaration.views
    .iter()
    .find_first(view => view.resource == physical.selection.resource)
    is Some(physical_view) &&
    @rows.row_declaration_keyed_read_schema_identities(declaration, source_ref)
    is Some((request_schema, response_schema)) &&
    physical.selection.key_path is Some(key_path) &&
    file_listing_fields_valid(physical, fields) &&
    file_capture_text(content_utf8, 64) else {
    return Err(InvalidInput)
  }
  let contract = @rows.relation_document_prepared_contract(
    physical.prepared_contract,
  )
  guard contract.shape is @contract.Object(columns) else {
    return Err(InvalidInput)
  }
  let mut content_field = false
  for index in 0..<@contract.field_count(columns) {
    let field = @contract.field_at(columns, index).unwrap()
    if field.name == content_utf8 {
      content_field = !field.contract.nullable &&
        field.contract.shape is @contract.Text(_)
    }
  }
  if !content_field {
    return Err(InvalidInput)
  }
  // Preserve every already-admitted path/field length. Bound the encoder by
  // the ACTUAL strings and worst-case JSON escape expansion, not a new 16 KiB
  // policy ceiling. Installation backing owns this immutable DATA before entry.
  let mut text_units = physical.selection.primary_identity.length().to_int64() +
    fields.name.length().to_int64() +
    fields.version.length().to_int64() +
    fields.media_type.length().to_int64() +
    content_utf8.length().to_int64() +
    fields.path.map(path => path.length().to_int64()).unwrap_or(0L)
  for path in [physical.selection.items_path, key_path] {
    for item in path {
      text_units += item.length().to_int64()
    }
  }
  guard @execution.checked_preparation_add_product(4096L, text_units, 6L)
    is Some(profile_bytes) &&
    profile_bytes <= 2147483647L else {
    return Err(Capacity)
  }
  let max_bytes = profile_bytes.to_int()
  let body = try {
    let writer = @encode.writer(max_bytes, 1024, 20)
    @encode.begin_object(writer)
    for
      (key, value) in [
        ("physical_source_view_contract_cid", physical_view.view_cid),
        ("request_schema_cid", request_schema),
        ("response_schema_cid", response_schema),
        ("source_view_contract_cid", view.view_cid),
        ("version", "actql-native-file-content-read/0.1"),
      ] {
      @encode.key(writer, key)
      @encode.string_value(writer, value)
    }
    @encode.key(writer, "projection")
    @encode.begin_object(writer)
    for
      (key, value) in [
        ("identity_field", physical.selection.primary_identity),
        ("name_field", fields.name),
        ("version_field", fields.version),
        ("media_type_field", fields.media_type),
        ("content_utf8_field", content_utf8),
      ] {
      @encode.key(writer, key)
      @encode.string_value(writer, value)
    }
    @encode.key(writer, "path_field")
    match fields.path {
      None => @encode.null_value(writer)
      Some(path) => @encode.string_value(writer, path)
    }
    for
      (name, path) in [
        ("items_path", physical.selection.items_path),
        ("key_path", key_path),
      ] {
      @encode.key(writer, name)
      @encode.begin_array(writer)
      for item in path {
        @encode.string_value(writer, item)
      }
      @encode.end_array(writer)
    }
    @encode.end_object(writer)
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => return Err(InvalidInput)
  }
  let contract = match
    @publication.seal_publication_contract(
      "native_file_content_read", body, max_bytes, 1024, 20,
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidInput)
  }
  Ok({ declaration, source_ref, physical, fields, content_utf8, contract, })
}

///|
pub fn NativeRelationFileKeyedReadProfile::contract(
  self : Self,
) -> @publication.PublicationContract {
  self.contract
}

///|
fn native_file_keyed_read_profile_matches(
  profile : NativeRelationFileKeyedReadProfile,
  declaration : @rows.RowDeclaration,
  source_ref : String,
  physical : NativeRelationFilePreparedProvider,
  fields : NativeRelationFileListingFields,
  content_utf8 : String,
) -> Bool {
  physical_equal(profile.declaration, declaration) &&
  profile.source_ref == source_ref &&
  physical_equal(profile.physical, physical) &&
  profile.fields.name == fields.name &&
  profile.fields.version == fields.version &&
  profile.fields.media_type == fields.media_type &&
  profile.fields.path == fields.path &&
  profile.content_utf8 == content_utf8
}
