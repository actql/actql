///|
priv enum ManagedRecordSelection {
  Query(@rows.RowAcquisition)
  Whole(@rows.RowInputAcquisition)
}

///|
/// DATA-only native protocol adopted by the already-accounted generic reader.
/// No RowRun, response charge, credential or cleanup acknowledgement is issued.
/// Aggregate row/response/attempt ceilings remain with the generic reader and
/// Common RowRun; this protocol preserves the constant native per-page request.
pub struct ManagedRecordRead {
  priv selection : ManagedRecordSelection
  priv original : RecordDeclaration
  priv columns : Array[String]
  priv names : Array[String]
  priv contracts : Array[@contract.Contract]
  priv page_limits : @catalog.RecordPageLimits
  priv value_limits : @catalog.RecordValueLimits
  priv max_contract_pairs : Int
  priv per_page : Int
  priv mut cursor : String?
  priv mut needs_form : Bool
  priv mut terminal_page : Bool
  priv mut retired : Bool
  priv mut failed : Bool
  priv mut observed_form : @catalog.FormFieldCatalog?
  priv mut page : @catalog.OriginalRecordPage?
}

///|
fn managed_record_read(
  original : RecordDeclaration,
  selection : ManagedRecordSelection,
  page_limits : @catalog.RecordPageLimits,
  value_limits : @catalog.RecordValueLimits,
  max_contract_pairs : Int,
  per_page : Int,
) -> Result[ManagedRecordRead, RecordReadIssue] {
  if per_page <= 0 ||
    per_page > 500 ||
    per_page > page_limits.max_rows ||
    page_limits.max_bytes <= 0 ||
    page_limits.max_nodes <= 0 ||
    page_limits.max_depth <= 0 ||
    page_limits.max_rows <= 0 ||
    page_limits.max_columns <= 0 ||
    page_limits.max_cells <= 0 ||
    page_limits.max_table_rows <= 0 ||
    value_limits.max_columns <= 0 ||
    value_limits.max_name_bytes <= 0 ||
    value_limits.max_nodes <= 0 ||
    value_limits.max_depth <= 0 ||
    value_limits.max_text_bytes <= 0 ||
    max_contract_pairs <= 0 {
    return Err(InvalidLimits)
  }
  let columns = match selection {
    Query(value) => {
      match
        @rows.check_row_acquisition_original(
          value,
          original.declaration,
          @rows.row_acquisition_requirement(value),
        ) {
        Ok(_) => ()
        Err(issue) => return Err(Host(issue))
      }
      @rows.row_acquisition_columns(value)
    }
    Whole(value) => {
      match
        @rows.check_row_input_acquisition_declaration(
          value,
          original.declaration,
        ) {
        Ok(_) => ()
        Err(issue) => return Err(Host(issue))
      }
      @rows.row_input_acquisition_columns(value)
    }
  }
  let contracts : Array[@contract.Contract] = []
  for index in 0..<columns.length() {
    let contract = match selection {
      Query(value) => @rows.row_acquisition_column_contract(value, index)
      Whole(value) => @rows.row_input_acquisition_column_contract(value, index)
    }
    guard contract is Some(contract) else { return Err(ForeignDeclaration) }
    contracts.push(contract)
  }
  Ok({
    selection,
    original,
    columns,
    contracts,
    names: columns.filter(name => name != "$id"),
    page_limits,
    value_limits,
    max_contract_pairs,
    per_page,
    cursor: None,
    needs_form: true,
    terminal_page: false,
    retired: false,
    failed: false,
    observed_form: None,
    page: None,
  })
}

///|
pub fn adopt_managed_record_query(
  original : RecordDeclaration,
  acquisition : @rows.RowAcquisition,
  page_limits : @catalog.RecordPageLimits,
  value_limits : @catalog.RecordValueLimits,
  max_contract_pairs : Int,
  per_page : Int,
) -> Result[ManagedRecordRead, RecordReadIssue] {
  managed_record_read(
    original,
    Query(acquisition),
    page_limits,
    value_limits,
    max_contract_pairs,
    per_page,
  )
}

///|
pub fn adopt_managed_record_whole(
  original : RecordDeclaration,
  acquisition : @rows.RowInputAcquisition,
  page_limits : @catalog.RecordPageLimits,
  value_limits : @catalog.RecordValueLimits,
  max_contract_pairs : Int,
  per_page : Int,
) -> Result[ManagedRecordRead, RecordReadIssue] {
  managed_record_read(
    original,
    Whole(acquisition),
    page_limits,
    value_limits,
    max_contract_pairs,
    per_page,
  )
}

///|
pub fn managed_record_query_matches(
  read : ManagedRecordRead,
  original : @rows.RowAcquisition,
) -> Bool {
  if read.retired || read.failed {
    return false
  }
  match read.selection {
    Query(value) => physical_equal(value, original)
    Whole(_) => false
  }
}

///|
pub fn managed_record_whole_matches(
  read : ManagedRecordRead,
  original : @rows.RowInputAcquisition,
) -> Bool {
  if read.retired || read.failed {
    return false
  }
  match read.selection {
    Whole(value) => physical_equal(value, original)
    Query(_) => false
  }
}

///|
fn[T] refuse_managed_record(
  read : ManagedRecordRead,
  issue : RecordReadIssue,
) -> Result[T, RecordReadIssue] {
  read.failed = true
  Err(issue)
}

///|
/// The generic reader has already charged these exact bytes. Keep the Form
/// observation until DATA retirement, including a drift refusal.
pub fn managed_record_recheck_form(
  read : ManagedRecordRead,
  bytes : Bytes,
  limits : @catalog.FormFieldLimits,
) -> Result[Unit, RecordReadIssue] {
  if read.retired || read.failed || !read.needs_form {
    return Err(Closed)
  }
  let original = read.original.catalog
  let observed = match
    @catalog.project_form_fields(bytes, original.app_id, limits) {
    Ok(value) => value
    Err(issue) => return refuse_managed_record(read, Form(issue))
  }
  read.observed_form = Some(observed)
  let paths = @catalog.form_field_paths(original)
  if paths.length() != @catalog.form_field_paths(observed).length() ||
    original.app_id != observed.app_id ||
    original.revision != observed.revision {
    return refuse_managed_record(read, ForeignDeclaration)
  }
  for path in paths {
    if !@catalog.form_field_definition_matches(original, observed, path) {
      return refuse_managed_record(read, ForeignDeclaration)
    }
  }
  read.needs_form = false
  Ok(())
}

///|
/// Exact CheckedValues carry the adopted input contracts into the generic
/// reader's consumeValues sink. This projection never charges or admits a Run.
pub fn managed_record_project_page(
  read : ManagedRecordRead,
  bytes : Bytes,
) -> Result[Array[Array[@admitted.CheckedValue]], RecordReadIssue] {
  if read.retired || read.failed || read.needs_form || read.terminal_page {
    return Err(Closed)
  }
  let page = match
    @catalog.project_record_page(
      bytes,
      read.original.catalog,
      read.names,
      read.page_limits,
    ) {
    Ok(value) => value
    Err(issue) => return refuse_managed_record(read, Page(issue))
  }
  read.page = Some(page)
  let records = @catalog.record_page_records(page)
  if records.length() > read.per_page {
    return refuse_managed_record(read, InvalidPageOrder)
  }
  let mut cursor = read.cursor
  for record in records {
    let id = record.record_id
    if !record_request_id(id) {
      return refuse_managed_record(read, InvalidPageOrder)
    }
    if cursor is Some(prior) && !record_id_after(id, prior) {
      return refuse_managed_record(read, InvalidPageOrder)
    }
    cursor = Some(id)
  }
  let values = match
    @catalog.admit_record_page_contracts(
      page,
      read.original.settings,
      read.columns,
      read.contracts,
      read.value_limits,
      read.max_contract_pairs,
    ) {
    Ok(value) => value
    Err(issue) => return refuse_managed_record(read, Catalog(issue))
  }
  read.cursor = cursor
  read.terminal_page = records.length() < read.per_page
  read.needs_form = true
  Ok(values)
}

///|
pub fn managed_record_columns(read : ManagedRecordRead) -> Array[String] {
  read.columns.copy()
}

///|
pub fn managed_record_complete(read : ManagedRecordRead) -> Bool {
  !read.retired &&
  !read.failed &&
  read.terminal_page &&
  !read.needs_form &&
  read.page is Some(_) &&
  read.observed_form is Some(_)
}

///|
/// DATA alias retirement only. The generic reader owns physical cleanup.
pub fn retire_managed_record(read : ManagedRecordRead) -> Unit {
  read.retired = true
  read.page = None
  read.observed_form = None
}

///|
pub fn managed_record_form_request(
  read : ManagedRecordRead,
  max_bytes : Int,
) -> Result[String, RecordReadIssue] {
  if read.retired || read.failed || !read.needs_form {
    return Err(Closed)
  }
  record_form_body(read.original.catalog.app_id, max_bytes)
}

///|
pub fn managed_record_page_request(
  read : ManagedRecordRead,
  max_bytes : Int,
) -> Result[String, RecordReadIssue] {
  if read.retired || read.failed || read.needs_form || read.terminal_page {
    return Err(Closed)
  }
  record_page_body(
    read.original.catalog.app_id,
    read.names,
    read.cursor,
    read.per_page,
    max_bytes,
  )
}
