// Same-runtime kintone original Catalog/RowRun forwarding. No wire or JS
// factory reconstructs an original declaration, acquisition or cleanup owner.

///|
#export_name("clientProgramKintoneFormLimits")
pub fn client_program_kintone_form_limits(
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_fields : Int,
  max_name_units : Int,
) -> @kintone_catalog.FormFieldLimits {
  { max_bytes, max_nodes, max_depth, max_fields, max_name_units, }
}

///|
#export_name("clientProgramKintonePageLimits")
pub fn client_program_kintone_page_limits(
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_rows : Int,
  max_columns : Int,
  max_cells : Int,
  max_table_rows : Int,
) -> @kintone_catalog.RecordPageLimits {
  {
    max_bytes,
    max_nodes,
    max_depth,
    max_rows,
    max_columns,
    max_cells,
    max_table_rows,
  }
}

///|
#export_name("clientProgramKintoneValueLimits")
pub fn client_program_kintone_value_limits(
  max_columns : Int,
  max_name_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_text_bytes : Int,
) -> @kintone_catalog.RecordValueLimits {
  { max_columns, max_name_bytes, max_nodes, max_depth, max_text_bytes, }
}

///|
#export_name("clientProgramKintoneDeclarationLimits")
pub fn client_program_kintone_declaration_limits(
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_views : Int,
  max_fields : Int,
) -> @client_row_source_host.RowDeclarationLimits {
  { max_bytes, max_nodes, max_depth, max_views, max_fields, }
}

///|
#export_name("clientProgramKintoneProjectForm")
pub fn client_program_kintone_project_form(
  body : Bytes,
  app : String,
  limits : @kintone_catalog.FormFieldLimits,
) -> Result[@kintone_catalog.FormFieldCatalog, @kintone_catalog.FormFieldIssue] {
  @kintone_catalog.project_form_fields(body, app, limits)
}

///|
#export_name("clientProgramKintoneDeclareRecords")
pub fn client_program_kintone_declare_records(
  catalog : @kintone_catalog.FormFieldCatalog,
  settings : @kintone_catalog.AppNumberSettings?,
  names : Array[String],
  connector : String,
  revision : String,
  resource : String,
  values : @kintone_catalog.RecordValueLimits,
  declaration : @client_row_source_host.RowDeclarationLimits,
) -> Result[@kintone_host.RecordDeclaration, @kintone_host.RecordReadIssue] {
  @kintone_host.declare_records(
    catalog, settings, names, connector, revision, resource, values, declaration,
  )
}

///|
#export_name("clientProgramKintoneRecordDeclaration")
pub fn client_program_kintone_record_declaration(
  original : @kintone_host.RecordDeclaration,
) -> @client_row_source_host.RowDeclaration {
  @kintone_host.record_declaration(original)
}

///|
#export_name("clientProgramKintonePrepareRead")
pub fn client_program_kintone_prepare_read(
  original : @kintone_host.RecordDeclaration,
  requirement : @planning.QueryRequirement,
  query : String,
  evidence : String,
) -> Result[@kintone_host.PreparedRecordRead, @kintone_host.RecordReadIssue] {
  @kintone_host.prepare_record_read(original, requirement, query, evidence)
}

///|
#export_name("clientProgramKintoneReadAcquisition")
pub fn client_program_kintone_read_acquisition(
  read : @kintone_host.PreparedRecordRead,
) -> @client_row_source_host.RowAcquisition {
  @kintone_host.record_read_acquisition(read)
}

///|
#export_name("clientProgramKintoneReadApp")
pub fn client_program_kintone_read_app(
  read : @kintone_host.PreparedRecordRead,
) -> String {
  @kintone_host.record_read_app_id(read)
}

///|
#export_name("clientProgramKintoneReadFields")
pub fn client_program_kintone_read_fields(
  read : @kintone_host.PreparedRecordRead,
) -> Array[String] {
  @kintone_host.record_read_fields(read)
}

///|
#export_name("clientProgramKintoneBorrowRead")
pub fn client_program_kintone_borrow_read(
  prepared : @kintone_host.PreparedRecordRead,
  run : @client_row_source_host.RowRun,
  page : @kintone_catalog.RecordPageLimits,
  values : @kintone_catalog.RecordValueLimits,
  max_pairs : Int,
) -> Result[@kintone_host.RecordRead, @kintone_host.RecordReadIssue] {
  @kintone_host.borrow_record_read(prepared, run, page, values, max_pairs)
}

///|
#export_name("clientProgramKintoneBindReadCleanup")
pub fn client_program_kintone_bind_read_cleanup(
  read : @kintone_host.RecordRead,
  stopped : () -> Bool,
) -> Result[Unit, @kintone_host.RecordReadIssue] {
  @kintone_host.bind_record_read_cleanup(read, stopped)
}

///|
#export_name("clientProgramKintoneRecheckReadForm")
pub fn client_program_kintone_recheck_read_form(
  read : @kintone_host.RecordRead,
  body : Bytes,
  limits : @kintone_catalog.FormFieldLimits,
) -> Result[Unit, @kintone_host.RecordReadIssue] {
  @kintone_host.recheck_record_read_form(read, body, limits)
}

///|
#export_name("clientProgramKintoneAcceptReadPage")
pub fn client_program_kintone_accept_read_page(
  read : @kintone_host.RecordRead,
  body : Bytes,
) -> Result[Int, @kintone_host.RecordReadIssue] {
  @kintone_host.accept_record_read_page(read, body)
}

///|
#export_name("clientProgramKintoneReadPageIds")
pub fn client_program_kintone_read_page_ids(
  read : @kintone_host.RecordRead,
) -> Result[Array[String], @kintone_host.RecordReadIssue] {
  @kintone_host.record_read_page_ids(read)
}

///|
#export_name("clientProgramKintoneRetireRead")
pub fn client_program_kintone_retire_read(
  read : @kintone_host.RecordRead,
) -> Result[Unit, @kintone_host.RecordReadIssue] {
  @kintone_host.retire_record_read(read)
}

///|
#export_name("clientProgramKintoneFormRequestBody")
pub fn client_program_kintone_form_request_body(
  prepared : @kintone_host.PreparedRecordRead,
  max_bytes : Int,
) -> Result[String, @kintone_host.RecordReadIssue] {
  @kintone_host.record_form_request_body(prepared, max_bytes)
}

///|
#export_name("clientProgramKintonePageRequestBody")
pub fn client_program_kintone_page_request_body(
  prepared : @kintone_host.PreparedRecordRead,
  cursor : Array[String],
  per_page : Int,
  max_bytes : Int,
) -> Result[String, @kintone_host.RecordReadIssue] {
  let original = match @kintone_host.record_request_cursor(cursor) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  @kintone_host.record_page_request_body(
    prepared, original, per_page, max_bytes,
  )
}

///|
#export_name("clientProgramKintonePageNextCursor")
pub fn client_program_kintone_page_next_cursor(
  read : @kintone_host.RecordRead,
  prior : Array[String],
  per_page : Int,
) -> Result[Array[String], @kintone_host.RecordReadIssue] {
  let original = match @kintone_host.record_request_cursor(prior) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  @kintone_host.record_page_next_cursor(read, original, per_page).map(next => {
    match next {
      Some(id) => [id]
      None => []
    }
  })
}

///|
#export_name("clientProgramKintoneReadDeclarationConstructionCapacity")
pub fn client_program_kintone_read_declaration_construction_capacity(
  body_bytes : Int,
  encoded_units : Int,
  selected_count : Int,
  selected_units : Int,
  app_units : Int,
  resource_units : Int,
  connector_units : Int,
  revision_units : Int,
  form : @kintone_catalog.FormFieldLimits,
  values : @kintone_catalog.RecordValueLimits,
  declaration : @client_row_source_host.RowDeclarationLimits,
) -> @execution.ExecutionCapacity? {
  @kintone_host.record_read_declaration_construction_capacity(
    body_bytes, encoded_units, selected_count, selected_units, app_units, resource_units,
    connector_units, revision_units, form, values, declaration,
  )
}

///|
#export_name("clientProgramKintoneAdoptManagedQuery")
pub fn client_program_kintone_adopt_managed_query(
  original : @kintone_host.RecordDeclaration,
  acquisition : @client_row_source_host.RowAcquisition,
  pages : @kintone_catalog.RecordPageLimits,
  values : @kintone_catalog.RecordValueLimits,
  pairs : Int,
  per_page : Int,
) -> Result[@kintone_host.ManagedRecordRead, @kintone_host.RecordReadIssue] {
  @kintone_host.adopt_managed_record_query(
    original, acquisition, pages, values, pairs, per_page,
  )
}

///|
#export_name("clientProgramKintoneManagedQueryMatches")
pub fn client_program_kintone_managed_query_matches(
  read : @kintone_host.ManagedRecordRead,
  original : @client_row_source_host.RowAcquisition,
) -> Bool {
  @kintone_host.managed_record_query_matches(read, original)
}

///|
#export_name("clientProgramKintoneAdoptManagedWhole")
pub fn client_program_kintone_adopt_managed_whole(
  original : @kintone_host.RecordDeclaration,
  acquisition : @client_row_source_host.RowInputAcquisition,
  pages : @kintone_catalog.RecordPageLimits,
  values : @kintone_catalog.RecordValueLimits,
  pairs : Int,
  per_page : Int,
) -> Result[@kintone_host.ManagedRecordRead, @kintone_host.RecordReadIssue] {
  @kintone_host.adopt_managed_record_whole(
    original, acquisition, pages, values, pairs, per_page,
  )
}

///|
#export_name("clientProgramKintoneManagedWholeMatches")
pub fn client_program_kintone_managed_whole_matches(
  read : @kintone_host.ManagedRecordRead,
  original : @client_row_source_host.RowInputAcquisition,
) -> Bool {
  @kintone_host.managed_record_whole_matches(read, original)
}

///|
#export_name("clientProgramKintoneManagedRecheckForm")
pub fn client_program_kintone_managed_recheck_form(
  read : @kintone_host.ManagedRecordRead,
  body : Bytes,
  limits : @kintone_catalog.FormFieldLimits,
) -> Result[Unit, @kintone_host.RecordReadIssue] {
  @kintone_host.managed_record_recheck_form(read, body, limits)
}

///|
#export_name("clientProgramKintoneManagedProjectPage")
pub fn client_program_kintone_managed_project_page(
  read : @kintone_host.ManagedRecordRead,
  body : Bytes,
) -> Result[Array[Array[@admitted.CheckedValue]], @kintone_host.RecordReadIssue] {
  @kintone_host.managed_record_project_page(read, body)
}

///|
#export_name("clientProgramKintoneManagedColumns")
pub fn client_program_kintone_managed_columns(
  read : @kintone_host.ManagedRecordRead,
) -> Array[String] {
  @kintone_host.managed_record_columns(read)
}

///|
#export_name("clientProgramKintoneManagedComplete")
pub fn client_program_kintone_managed_complete(
  read : @kintone_host.ManagedRecordRead,
) -> Bool {
  @kintone_host.managed_record_complete(read)
}

///|
#export_name("clientProgramKintoneManagedRetire")
pub fn client_program_kintone_managed_retire(
  read : @kintone_host.ManagedRecordRead,
) -> Unit {
  @kintone_host.retire_managed_record(read)
}

///|
#export_name("clientProgramKintoneManagedFormRequest")
pub fn client_program_kintone_managed_form_request(
  read : @kintone_host.ManagedRecordRead,
  max_bytes : Int,
) -> Result[String, @kintone_host.RecordReadIssue] {
  @kintone_host.managed_record_form_request(read, max_bytes)
}

///|
#export_name("clientProgramKintoneManagedPageRequest")
pub fn client_program_kintone_managed_page_request(
  read : @kintone_host.ManagedRecordRead,
  max_bytes : Int,
) -> Result[String, @kintone_host.RecordReadIssue] {
  @kintone_host.managed_record_page_request(read, max_bytes)
}

///|
#export_name("clientProgramKintoneAdoptManagedBorrow")
pub fn client_program_kintone_adopt_managed_borrow(
  original : @kintone_host.RecordDeclaration,
  borrow : @client_row_source_host.RowRunResponseBorrow,
  pages : @kintone_catalog.RecordPageLimits,
  values : @kintone_catalog.RecordValueLimits,
  pairs : Int,
  per_page : Int,
) -> Result[@kintone_host.ManagedRecordRead, @kintone_host.RecordReadIssue] {
  @kintone_host.adopt_managed_record_borrow(
    original, borrow, pages, values, pairs, per_page,
  )
}

///|
/// Complete selected native reader base. No body parser is admitted here:
/// each actual charged response adds its original native producer inventory.
#export_name("clientProgramKintoneManagedSourceReaderCapacity")
pub fn client_program_kintone_managed_source_reader_capacity(
  limits : Array[Int],
  secret_bytes : Int,
  original : @kintone_host.RecordDeclaration,
  pages : @kintone_catalog.RecordPageLimits,
  values : @kintone_catalog.RecordValueLimits,
  pairs : Int,
  per_page : Int,
  max_request_bytes : Int,
  origin : String,
  resource : String,
  guest_space : String,
) -> @execution.ExecutionCapacity? {
  let columns = @kintone_host.managed_record_column_count(original)
  if limits.length() != 16 ||
    secret_bytes <= 0 ||
    limits[6] > 10000 ||
    limits[0] != pages.max_bytes ||
    limits[2] != pages.max_nodes ||
    limits[3] != pages.max_depth ||
    limits[4] != pages.max_rows ||
    limits[7] != per_page ||
    limits[11] != values.max_nodes ||
    limits[12] != values.max_text_bytes ||
    columns > values.max_columns {
    return None
  }
  guard @kintone_host.managed_record_construction_capacity(
      original, pages, values, pairs, per_page, max_request_bytes,
    )
    is Some(native) &&
    @kintone_host.managed_record_identity_units(
      original, origin, resource, guest_space,
    )
    is Some(identity) else {
    return None
  }
  let fields = columns.to_int64()
  let requests = limits[6].to_int64() + 1L
  // createKintoneManagedSequence: thirteen lexical closures (81 captured
  // bindings); names/map/eight pairs/method table 11H40R; eight sequential
  // own-method descriptors 8H8R24W; returned/Form/Page DTOs 15H32R;
  // ten native/callback argument vectors 10H24R. The actual factory argument
  // and three-limit bounds records add 2H11R. Co-count transient construction
  // with retained state conservatively; module helpers and native DATA borrow
  // their original backing and are not copied by these references.
  let sequence_headers = 13L + 11L + 8L + 15L + 10L + 2L
  let sequence_refs = 81L + 40L + 8L + 32L + 24L + 11L
  let sequence_words = 24L
  // Installing loader's actual prepare/verify/authorize/quote callbacks carry
  // 16+7+10+3 enclosing bindings. Its one use counter and local index are
  // co-counted through the admitted capture; the original scope is borrowed.
  // Authorize tuple/options/args 3H8R; grant request/args 2H6R1W;
  // supplied+authorization wrappers 2H6R; quote args 1H3R2W.
  let caller_headers = 4L + 8L
  let caller_refs = 36L + 23L
  let caller_words = 2L + 3L
  // Canonical target plus outer binding/operation subject: at most eleven
  // fixed object members and the original selected field vector. Entry pairs,
  // sorting/mapping vectors and scalar argument envelopes are actual callers
  // of canonicalValueJson; no whole declaration/schema is generated here.
  let identity_entries = 11L + fields
  let identity_headers = 8L * identity_entries + 16L
  let identity_refs = 20L * identity_entries + 32L
  let identity_words = identity_entries + 4L
  // The distinct Form binding family is inventoried from the actual Site and
  // HTTPS constructors, never another complete reader or raw response prefix.
  // Its original scope has thirteen fields; bounded credentials retain their
  // own secret and close/current state alongside the root's existing binding.
  // Retained scope/HTTPS state/handle/credential/acquisition/Site/current/child
  // records: 13H72R13W; ten actual closures: 10H30R. Construction overlap:
  // scope map+13 pairs+callback 15H40R, captured-current descriptors 6H9R6W,
  // open arguments 1H6R1W, secret-presentation spread 1H1R, close descriptor
  // 1H1R3W, actual existing-map/Set membership 8R. No nested borrow copies.
  // Count this finite constructor overlap as retained conservatively; no
  // later GC or callback completion grants cleanup credit to the ledger.
  let binding_headers = 23L + 15L + 6L + 1L + 1L + 1L
  let binding_refs = 102L + 40L + 9L + 6L + 1L + 1L + 8L
  let binding_words = 13L + 6L + 1L + 3L
  guard @execution.checked_preparation_add_product(0L, identity, 6L)
    is Some(identity_text) &&
    @execution.checked_preparation_add_product(
      identity_text,
      secret_bytes.to_int64(),
      1L,
    )
    is Some(text) &&
    @execution.checked_preparation_add_product(text, requests, 81L)
    is Some(text) &&
    @execution.checked_preparation_add_product(0L, identity, 6L) is Some(wire) &&
    @execution.checked_preparation_add_product(
      wire,
      max_request_bytes.to_int64(),
      1L,
    )
    is Some(wire) &&
    @execution.checked_preparation_add_product(
      wire,
      secret_bytes.to_int64(),
      1L,
    )
    is Some(wire) &&
    @execution.preparation_execution_capacity({
      retained: {
        record_headers: sequence_headers +
        caller_headers +
        identity_headers +
        binding_headers,
        reference_slots: sequence_refs +
        caller_refs +
        identity_refs +
        binding_refs +
        2L * fields,
        scalar_words: sequence_words +
        caller_words +
        identity_words +
        binding_words,
        owned_utf16_units: text,
        owned_wire_bytes: wire,
      },
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
    is Some(controls) &&
    @execution.add_execution_capacity(native, controls) is Some(domain) &&
    @client_local_host.installed_source_child_grant_construction_capacity()
    is Some(form_grant) &&
    @execution.add_execution_capacity(domain, form_grant) is Some(domain) else {
    return None
  }
  @client_local_host.installed_native_source_reader_capacity(
    limits,
    columns,
    secret_bytes,
    Some(domain),
  )
}

///|
#export_name("clientProgramKintoneManagedResponseCapacity")
pub fn client_program_kintone_managed_response_capacity(
  read : @kintone_host.ManagedRecordRead,
  previous : @execution.ExecutionCapacity,
  bytes : Int,
  is_form : Bool,
  limits : @kintone_catalog.FormFieldLimits,
) -> @execution.ExecutionCapacity? {
  @kintone_host.managed_record_response_construction_capacity(
    read, previous, bytes, is_form, limits,
  )
}

///|
/// Cache the SAME installed metadata identity during its existing initialization
/// admission, instead of serializing the base64 Form again on every read fence.
/// This is the exact five scalar-member canonicalJson producer, not a parser.
#export_name("clientProgramKintoneMetadataIdentityCapacity")
pub fn client_program_kintone_metadata_identity_capacity(
  base : @execution.ExecutionCapacity,
  encoded_units : Int,
  connector_units : Int,
  app_units : Int,
  origin_units : Int,
) -> @execution.ExecutionCapacity? {
  if encoded_units < 0 ||
    connector_units < 0 ||
    app_units < 0 ||
    origin_units < 0 {
    return None
  }
  // Five fixed keys, the metadata version, quotes/colons/commas/braces.
  let authored = encoded_units.to_int64() +
    connector_units.to_int64() +
    app_units.to_int64() +
    origin_units.to_int64()
  guard @execution.checked_preparation_add_product(160L, authored, 6L)
    is Some(wire) &&
    @execution.checked_preparation_add_product(135L, wire, 4L) is Some(text) &&
    @execution.checked_preparation_add_product(32L, wire, 3L) is Some(bytes) &&
    @execution.preparation_execution_capacity({
      retained: {
        // Object.entries and mapped pairs: 10 headers/20 refs; five vectors:
        // 5 headers/25 refs. Six {dataKeys} options and five callbacks plus
        // the original five-entry key Set complete the canonical producer.
        // Its scalar fragments, member strings, join and final wire overlap.
        record_headers: 15L + 6L + 5L + 1L,
        reference_slots: 45L + 2L + 10L + 1L,
        scalar_words: 6L,
        owned_utf16_units: text,
        owned_wire_bytes: bytes,
      },
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
    is Some(identity) else {
    return None
  }
  // Conservative constructor overlap stays with the initializer until its
  // original retirement; no intermediate JS collection earns cleanup credit.
  @execution.add_execution_capacity(base, identity)
}
