///|
pub enum RecordReadIssue {
  InvalidLimits
  ForeignDeclaration
  Closed
  TransportUnsettled
  Catalog(@catalog.RecordValueIssue)
  Page(@catalog.RecordPageIssue)
  Host(@rows.RowHostIssue)
}

///|
/// The original catalog and Common declaration are retained together. This
/// supplies metadata to the existing acquisition Owner, not another Site.
pub struct RecordDeclaration {
  priv catalog : @catalog.FormFieldCatalog
  priv settings : @catalog.AppNumberSettings?
  priv declaration : @rows.RowDeclaration
}

///|
pub fn declare_records(
  catalog : @catalog.FormFieldCatalog,
  settings : @catalog.AppNumberSettings?,
  names : Array[String],
  connector_id : String,
  connector_revision : String,
  resource : String,
  value_limits : @catalog.RecordValueLimits,
  declaration_limits : @rows.RowDeclarationLimits,
) -> Result[RecordDeclaration, RecordReadIssue] {
  let schema = match
    @catalog.record_schema_wire(
      catalog,
      settings,
      names,
      value_limits,
      declaration_limits.max_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Catalog(issue))
  }
  let declaration = match
    @rows.generate_relation_row_declaration(
      connector_id,
      "kintone",
      connector_revision,
      [
        {
          resource,
          resource_kind: "relation",
          schema_wire: schema,
          schema_cid: "sha256:" + @sha.hex(@utf8.encode(schema)),
          request_schema_wire: None,
          facts_wire: None,
          acquisition_wire: None,
        },
      ],
      declaration_limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Host(issue))
  }
  Ok({ catalog, settings, declaration, })
}

///|
pub fn record_declaration(value : RecordDeclaration) -> @rows.RowDeclaration {
  value.declaration
}

///|
pub struct PreparedRecordRead {
  priv original : RecordDeclaration
  priv acquisition : @rows.RowAcquisition
  priv names : Array[String]
}

///|
pub fn prepare_record_read(
  original : RecordDeclaration,
  requirement : @planning.QueryRequirement,
  query_contract : String,
  evidence_contract : String,
) -> Result[PreparedRecordRead, RecordReadIssue] {
  let acquisition = match
    @rows.prepare_row_acquisition(
      original.declaration,
      requirement,
      query_contract,
      evidence_contract,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Host(issue))
  }
  let names = @rows.row_acquisition_columns(acquisition).filter(name => {
    name != "$id"
  })
  Ok({ original, acquisition, names, })
}

///|
pub fn record_read_acquisition(
  value : PreparedRecordRead,
) -> @rows.RowAcquisition {
  value.acquisition
}

///|
/// The Host has already reserved and begun this exact accounted RowRun. This
/// borrowed reader cannot start, finish, capture or close that original root.
pub struct RecordRead {
  priv prepared : PreparedRecordRead
  priv run : @rows.RowRun
  priv borrow : @rows.RowRunResponseBorrow
  priv page_limits : @catalog.RecordPageLimits
  priv value_limits : @catalog.RecordValueLimits
  priv max_contract_pairs : Int
  priv mut cleanup : (() -> Bool)?
  priv mut original : @catalog.OriginalRecordPage?
  priv mut bound : Bool
  priv mut failed : Bool
  priv mut retired : Bool
}

///|
pub fn borrow_record_read(
  prepared : PreparedRecordRead,
  run : @rows.RowRun,
  page_limits : @catalog.RecordPageLimits,
  value_limits : @catalog.RecordValueLimits,
  max_contract_pairs : Int,
) -> Result[RecordRead, RecordReadIssue] {
  if page_limits.max_bytes <= 0 ||
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
  let borrow = match @rows.borrow_row_run_responses(run, prepared.acquisition) {
    Ok(value) => value
    Err(issue) => return Err(Host(issue))
  }
  Ok({
    prepared,
    run,
    borrow,
    page_limits,
    value_limits,
    max_contract_pairs,
    cleanup: None,
    original: None,
    bound: false,
    failed: false,
    retired: false,
  })
}

///|
pub fn bind_record_read_cleanup(
  read : RecordRead,
  stopped : () -> Bool,
) -> Result[Unit, RecordReadIssue] {
  if read.bound || read.failed || read.retired {
    return Err(Closed)
  }
  let cleanup = fn() {
    if read.retired {
      return true
    }
    if !stopped() {
      return false
    }
    // Retire aliases before Common releases the original reservation. A
    // callback invocation, abort or request completion alone is not this ACK.
    read.original = None
    read.retired = true
    read.cleanup = None
    true
  }
  match @rows.bind_row_run_response_borrow_cleanup(read.borrow, cleanup) {
    Ok(_) => {
      read.bound = true
      read.cleanup = Some(cleanup)
      Ok(())
    }
    Err(issue) => Err(Host(issue))
  }
}

///|
fn[T] refuse_record_read(
  read : RecordRead,
  issue : RecordReadIssue,
) -> Result[T, RecordReadIssue] {
  read.failed = true
  @rows.abort_row_run(read.run)
  Err(issue)
}

///|
/// Charge actual original response bytes before either native decode or
/// checked-value admission. No JSON stringify/parse or numeric conversion is
/// interposed. The caller still owns current authority and page completion.
pub fn accept_record_read_page(
  read : RecordRead,
  bytes : Bytes,
) -> Result[Int, RecordReadIssue] {
  if !read.bound || read.failed || read.retired {
    return Err(Closed)
  }
  match @rows.check_row_run_response_borrow_current(read.borrow) {
    Ok(_) => ()
    Err(issue) => return Err(Host(issue))
  }
  let charge = match @rows.charge_row_run_page(read.run, bytes) {
    Ok(value) => value
    Err(issue) => return refuse_record_read(read, Host(issue))
  }
  let original = match
    @catalog.project_record_page(
      bytes,
      read.prepared.original.catalog,
      read.prepared.names,
      read.page_limits,
    ) {
    Ok(value) => value
    Err(issue) => return refuse_record_read(read, Page(issue))
  }
  // Hold the native original through checked admission and physical stop,
  // including a later contract/capture failure. Common retains accepted cells.
  read.original = Some(original)
  let acquisition = read.prepared.acquisition
  let columns = @rows.row_acquisition_columns(acquisition)
  let contracts : Array[@contract.Contract] = []
  for index in 0..<columns.length() {
    guard @rows.row_acquisition_column_contract(acquisition, index)
      is Some(contract) else {
      return refuse_record_read(read, ForeignDeclaration)
    }
    contracts.push(contract)
  }
  let values = match
    @catalog.admit_record_page_contracts(
      original,
      read.prepared.original.settings,
      columns,
      contracts,
      read.value_limits,
      read.max_contract_pairs,
    ) {
    Ok(value) => value
    Err(issue) => return refuse_record_read(read, Catalog(issue))
  }
  match @rows.accept_charged_row_run_values(read.run, charge, columns, values) {
    Ok(count) => Ok(count)
    Err(issue) => refuse_record_read(read, Host(issue))
  }
}

///|
pub fn record_read_original(read : RecordRead) -> @catalog.OriginalRecordPage? {
  read.original
}

///|
pub fn retire_record_read(read : RecordRead) -> Result[Unit, RecordReadIssue] {
  if read.retired {
    return Ok(())
  }
  guard read.cleanup is Some(cleanup) else { return Err(TransportUnsettled) }
  if cleanup() {
    Ok(())
  } else {
    Err(TransportUnsettled)
  }
}
