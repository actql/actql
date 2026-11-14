///|
fn declared_file_read_fields(
  identity : String,
  name : String,
  version : String,
  media_type : String,
  content_utf8 : String,
  path : String?,
  items_path : Array[String],
  key_path : Array[String],
) -> @client_row_source_host.DeclaredFileReadFields {
  {
    identity,
    name,
    version,
    media_type,
    content_utf8,
    path,
    items_path,
    key_path,
  }
}

///|
/// The original Source initialization funds this exact borrowed metadata before
/// the descriptor/binding constructor. Policy read/file limits are not inputs.
#export_name("clientProgramRowSourceFileReadProfileConstructionCapacity")
pub fn client_program_row_source_file_read_profile_construction_capacity(
  declaration : @client_row_source_host.RowDeclaration,
  physical : @client_row_source_host.RowDeclaration,
  identity : String,
  name : String,
  version : String,
  media_type : String,
  content_utf8 : String,
  path : String?,
  items_path : Array[String],
  key_path : Array[String],
  prior_profiles : Int,
) -> @execution.ExecutionCapacity? {
  let fields = declared_file_read_fields(
    identity, name, version, media_type, content_utf8, path, items_path, key_path,
  )
  guard @client_row_source_host.declared_file_read_profile_construction_inventory(
      declaration,
      physical,
      fields,
      prior_profiles~,
    )
    is Some(retained) else {
    return None
  }
  @execution.preparation_execution_capacity({
    retained,
    workspace: {
      record_headers: 0L,
      reference_slots: 0L,
      scalar_words: 0L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
    retained_nodes: 0L,
    workspace_nodes: 0L,
    retained_bytes: 0L,
    workspace_bytes: 0L,
  })
}

///|
/// Finish this SAME initialization's actual logical/physical View binding.
/// Resource and field names are implementation DATA, never read permission.
#export_name("clientProgramRowSourceBindFileReadProfile")
pub fn client_program_row_source_bind_file_read_profile(
  declaration : @client_row_source_host.RowDeclaration,
  resource : String,
  physical : @client_row_source_host.RowDeclaration,
  physical_resource : String,
  identity : String,
  name : String,
  version : String,
  media_type : String,
  content_utf8 : String,
  path : String?,
  items_path : Array[String],
  key_path : Array[String],
) -> Result[
  @client_row_source_host.RowDeclaration,
  @client_row_source_host.RowMappingIssue,
] {
  guard declaration.views.iter().find_first(view => view.resource == resource)
    is Some(view) else {
    return Err(@client_row_source_host.InvalidSpecification)
  }
  @client_row_source_host.bind_declared_file_read_profile(
    declaration,
    view.source_ref,
    physical,
    physical_resource,
    declared_file_read_fields(
      identity, name, version, media_type, content_utf8, path, items_path, key_path,
    ),
  )
}

///|
#export_name("clientProgramRowSourceFileReadProfile")
pub fn client_program_row_source_file_read_profile(
  declaration : @client_row_source_host.RowDeclaration,
  source_ref : String,
) -> @publication.PublicationContract? {
  @client_row_source_host.row_declaration_file_read_profile(
    declaration, source_ref,
  )
}

///|
/// Before constructing the actual file supplier, preserve original physical
/// View correspondence separately from matching descriptor identities.
#export_name("clientProgramRowSourceFileReadProfileMatches")
pub fn client_program_row_source_file_read_profile_matches(
  declaration : @client_row_source_host.RowDeclaration,
  source_ref : String,
  physical : @client_row_source_host.RowDeclaration,
  physical_resource : String,
  identity : String,
  name : String,
  version : String,
  media_type : String,
  content_utf8 : String,
  path : String?,
  items_path : Array[String],
  key_path : Array[String],
) -> Bool {
  @client_row_source_host.row_declaration_file_read_profile_matches(
    declaration,
    source_ref,
    physical,
    physical_resource,
    declared_file_read_fields(
      identity, name, version, media_type, content_utf8, path, items_path, key_path,
    ),
  )
}
