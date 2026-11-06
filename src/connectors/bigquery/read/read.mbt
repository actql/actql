///|
pub(all) enum ReadIssue {
  InvalidLimits
  ForeignDeclaration
  Catalog(@catalog.DescriptionIssue)
  Host(@rows.RowHostIssue)
  Page(@catalog.QueryIssue)
  SchemaMismatch(String)
  WrongPage
  InconsistentTotal
  Incomplete
  Closed
  TransportUnsettled
  BorrowedRun
}

///|
/// A provider projection of the existing checked Common acquisition, not a grant.
pub struct PreparedRead {
  priv acquisition : @rows.RowAcquisition
  priv projection : @catalog.ReadProjection
}

///|
pub fn prepare_declared_read(
  description : @catalog.TableDescription,
  declaration : @rows.RowDeclaration,
  requirement : @planning.QueryRequirement,
  query_contract : String,
  evidence_contract : String,
  limits : @catalog.DescriptionLimits,
  declaration_limits : @rows.RowDeclarationLimits,
) -> Result[PreparedRead, ReadIssue] {
  if declaration.connector_registration != "bigquery" {
    return Err(ForeignDeclaration)
  }
  let source_ref = @planning.query_requirement_source(requirement).0
  guard @rows.row_declaration_view(declaration, source_ref) is Some(view) else {
    return Err(ForeignDeclaration)
  }
  let full = match
    @catalog.prepare_read_projection(description, view.fields, limits) {
    Ok(value) => value
    Err(issue) => return Err(Catalog(issue))
  }
  // A field-map CID is not a carrier-schema envelope CID. Reuse Common's
  // declaration issuer with the original resource/version before comparing
  // the original carrier reference in that same identity domain.
  let observed = match
    @catalog.generate_read_declaration(
      full,
      view.resource,
      declaration.connector_id,
      declaration.connector_version,
      declaration_limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Host(issue))
  }
  guard @rows.row_declaration_view(observed, source_ref) is Some(observed_view) &&
    observed_view.carrier_schema_cid == view.carrier_schema_cid else {
    return Err(ForeignDeclaration)
  }
  let acquisition = match
    @rows.prepare_row_acquisition(
      declaration, requirement, query_contract, evidence_contract,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Host(issue))
  }
  let projection = match
    @catalog.prepare_read_projection(
      description,
      @rows.row_acquisition_columns(acquisition),
      limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Catalog(issue))
  }
  Ok({ acquisition, projection, })
}

///|
pub fn prepared_read_acquisition(read : PreparedRead) -> @rows.RowAcquisition {
  read.acquisition
}

///|
pub fn prepared_read_projection(read : PreparedRead) -> @catalog.ReadProjection {
  read.projection
}

///|
pub struct ReadStartFailure {
  priv issue : ReadIssue
  priv cleanup : Read?
}

///|
pub fn read_start_failure_issue(value : ReadStartFailure) -> ReadIssue {
  value.issue
}

///|
pub fn read_start_failure_cleanup(value : ReadStartFailure) -> Read? {
  value.cleanup
}

///|
priv enum ReadCustody {
  Original((@rows.RowAttempt) -> Bool)
  InstalledBorrow(@rows.RowRunResponseBorrow)
}

///|
/// Only bounded page progress lives here. All capacity, capture and retirement
/// remain with the same original Common RowRun and physical transport owner.
pub struct Read {
  priv prepared : PreparedRead
  priv run : @rows.RowRun
  priv job : @catalog.QueryJob
  priv limits : @catalog.QueryLimits
  priv max_pages : Int
  priv custody : ReadCustody
  priv mut job_bound : Bool
  priv mut pages : Int
  priv mut rows : Int64
  priv mut total : Int64?
  priv mut next : String?
  priv mut finished : Bool
  priv mut interrupted : Bool
  priv mut closed : Bool
  priv mut transport_bound : Bool
  priv mut transport_confirmed : Bool
  priv mut retire_transport : (() -> Bool)?
}

///|
fn valid_limits(limits : @catalog.QueryLimits, max_pages : Int) -> Bool {
  let description = limits.description
  max_pages > 0 &&
  limits.max_rows >= 0 &&
  limits.max_total_rows >= 0L &&
  limits.max_value_nodes > 0 &&
  limits.max_value_text_bytes > 0 &&
  limits.max_job_bytes > 0 &&
  limits.max_page_token_bytes > 0 &&
  description.max_bytes > 0 &&
  description.max_nodes > 0 &&
  description.max_depth > 0 &&
  description.max_fields > 0 &&
  description.max_name_bytes > 0 &&
  description.max_schema_bytes > 0
}

///|
fn new_read(
  prepared : PreparedRead,
  run : @rows.RowRun,
  job : @catalog.QueryJob,
  limits : @catalog.QueryLimits,
  max_pages : Int,
  custody : ReadCustody,
) -> Read {
  {
    prepared,
    run,
    job,
    limits,
    max_pages,
    custody,
    job_bound: false,
    pages: 0,
    rows: 0L,
    total: None,
    next: None,
    finished: false,
    interrupted: false,
    closed: false,
    transport_bound: false,
    transport_confirmed: false,
    retire_transport: None,
  }
}

///|
pub fn start_accounted_read(
  prepared : PreparedRead,
  job : @catalog.QueryJob,
  nonce : String,
  verify_transport : (@rows.RowAttempt) -> Bool,
  ledger : @resources.Ledger,
  transfer_bytes : Int64,
  execution_scratch : Int64,
  limits : @catalog.QueryLimits,
  max_pages : Int,
) -> Result[Read, ReadStartFailure] {
  if !valid_limits(limits, max_pages) || limits.max_total_rows > 2147483647L {
    return Err({ issue: InvalidLimits, cleanup: None, })
  }
  let run = match
    @rows.start_accounted_row_acquisition(
      prepared.acquisition,
      nonce,
      verify_transport,
      ledger,
      transfer_bytes,
      execution_scratch,
    ) {
    Ok(value) => value
    Err(issue) => return Err({ issue: Host(issue), cleanup: None, })
  }
  let read = new_read(
    prepared,
    run,
    job,
    limits,
    max_pages,
    Original(verify_transport),
  )
  match
    @rows.begin_row_run(
      run,
      limits.description.max_bytes,
      limits.max_rows,
      limits.max_total_rows.to_int(),
    ) {
    Ok(_) => Ok(read)
    Err(issue) => {
      read.interrupted = true
      Err({ issue: Host(issue), cleanup: Some(read), })
    }
  }
}

///|
/// This borrows the Host's already-reserved and begun original acquisition.
/// It cannot begin, finish, capture or close another Common root.
pub fn borrow_accounted_read(
  prepared : PreparedRead,
  run : @rows.RowRun,
  job : @catalog.QueryJob,
  limits : @catalog.QueryLimits,
  max_pages : Int,
) -> Result[Read, ReadIssue] {
  if !valid_limits(limits, max_pages) {
    return Err(InvalidLimits)
  }
  let borrow = match @rows.borrow_row_run_responses(run, prepared.acquisition) {
    Ok(value) => value
    Err(issue) => return Err(Host(issue))
  }
  Ok(new_read(prepared, run, job, limits, max_pages, InstalledBorrow(borrow)))
}

///|
fn read_available(read : Read) -> Bool {
  if read.closed || read.interrupted {
    return false
  }
  match read.custody {
    Original(_) => true
    InstalledBorrow(borrow) =>
      read.transport_bound &&
      @rows.check_row_run_response_borrow_current(borrow) is Ok(_)
  }
}

///|
pub fn bind_borrowed_read_transport(
  read : Read,
  observe_stop : () -> Bool,
) -> Result[Unit, ReadIssue] {
  guard !read.closed &&
    !read.interrupted &&
    !read.transport_bound &&
    read.custody is InstalledBorrow(borrow) else {
    return Err(BorrowedRun)
  }
  let cleanup = fn() {
    if !read.transport_confirmed {
      if !observe_stop() {
        return false
      }
      read.transport_confirmed = true
    }
    read.closed = true
    read.retire_transport = None
    true
  }
  match @rows.bind_row_run_response_borrow_cleanup(borrow, cleanup) {
    Ok(_) => {
      read.transport_bound = true
      read.retire_transport = Some(cleanup)
      Ok(())
    }
    Err(issue) => Err(Host(issue))
  }
}

///|
pub fn retire_borrowed_read(read : Read) -> Result[Unit, ReadIssue] {
  guard read.custody is InstalledBorrow(_) else { return Err(BorrowedRun) }
  if read.closed {
    return Ok(())
  }
  if read.transport_bound {
    guard read.retire_transport is Some(cleanup) else {
      return Err(TransportUnsettled)
    }
    if !cleanup() {
      return Err(TransportUnsettled)
    }
  } else {
    read.closed = true
  }
  Ok(())
}

///|
fn[T] fail_read(read : Read, issue : ReadIssue) -> Result[T, ReadIssue] {
  read.interrupted = true
  @rows.abort_row_run(read.run)
  Err(issue)
}

///|
/// Charge the actual envelope before parsing, then admit only the expected
/// original job/projection and preceding opaque page token. Tokens grant no
/// request authority. A failed page keeps the same cleanup responsibility.
pub fn accept_query_page(
  read : Read,
  requested_token : String?,
  body : Bytes,
) -> Result[Int, ReadIssue] {
  if !read_available(read) || read.finished || read.job_bound {
    return Err(Closed)
  }
  let charge = match @rows.charge_row_run_page(read.run, body) {
    Ok(value) => value
    Err(issue) => return fail_read(read, Host(issue))
  }
  let page = match
    @catalog.project_query_page(
      read.prepared.projection,
      read.job,
      body,
      read.limits,
    ) {
    Ok(value) => value
    Err(issue) => return fail_read(read, Page(issue))
  }
  accept_projected_query_page(read, charge, requested_token, page)
}

///|
fn accept_projected_query_page(
  read : Read,
  charge : @rows.RowPageCharge,
  requested_token : String?,
  page : @catalog.QueryPage,
) -> Result[Int, ReadIssue] {
  if requested_token != read.next ||
    read.pages >= read.max_pages ||
    (read.pages > 0 && read.next is None) ||
    !@catalog.query_page_matches_original(
      page,
      read.prepared.projection,
      read.job,
    ) {
    return fail_read(read, WrongPage)
  }
  let total = @catalog.query_page_total_rows(page)
  if read.total is Some(original) && original != total {
    return fail_read(read, InconsistentTotal)
  }
  let count = @catalog.query_page_row_count(page)
  if count.to_int64() > total - read.rows {
    return fail_read(read, InconsistentTotal)
  }
  let values = []
  let mut nodes = read.limits.max_value_nodes
  let mut text_bytes = read.limits.max_value_text_bytes
  let columns = @catalog.read_projection_fields(read.prepared.projection)
  for row in 0..<count {
    let cells = []
    for column in 0..<columns.length() {
      guard @catalog.query_page_cell(page, row, column) is Some(value) else {
        return fail_read(read, Incomplete)
      }
      // Catalog values remain bound to the original metadata Contract. The
      // checked Common acquisition has its own original Contract identity;
      // equal schema bytes never substitute that identity at capture.
      guard @rows.row_acquisition_column_contract(
          read.prepared.acquisition,
          column,
        )
        is Some(contract) &&
        @admitted.recheck_runtime_value_usage(value.value, contract, {
          max_nodes: nodes,
          max_text_bytes: text_bytes,
          max_depth: read.limits.description.max_depth,
        })
        is Some((checked, used_nodes, used_text)) else {
        return fail_read(read, SchemaMismatch(columns[column]))
      }
      nodes -= used_nodes
      text_bytes -= used_text
      cells.push(checked)
    }
    values.push(cells)
  }
  let accepted = match
    @rows.accept_charged_row_run_values(read.run, charge, columns, values) {
    Ok(value) => value
    Err(issue) => return fail_read(read, Host(issue))
  }
  read.total = Some(total)
  read.next = @catalog.query_page_next_token(page)
  read.pages += 1
  read.rows += accepted.to_int64()
  Ok(accepted)
}

///|
pub fn result_read_usage(read : Read) -> (Int, Int64) {
  (read.pages, read.rows)
}

///|
/// This is routing DATA of the original job, including after interrupted page
/// admission. It is neither a launch/cancel grant nor proof of remote stop.
pub fn result_read_job(read : Read) -> @catalog.QueryJob? {
  if read.closed {
    None
  } else {
    Some(read.job)
  }
}

///|
/// Completeness of admitted pages only: no transport stop, capture or publish ACK.
pub fn result_read_complete(read : Read) -> Bool {
  read_available(read) &&
  read.pages > 0 &&
  read.next is None &&
  read.total is Some(total) &&
  read.rows == total
}

///|
pub fn finish_result_read(read : Read) -> Result[Unit, ReadIssue] {
  if read.custody is InstalledBorrow(_) {
    return Err(BorrowedRun)
  }
  if !read_available(read) || read.finished {
    return Err(Closed)
  }
  guard read.total is Some(total) &&
    read.pages > 0 &&
    read.next is None &&
    read.rows == total else {
    return fail_read(read, Incomplete)
  }
  match @rows.finish_row_run(read.run) {
    Ok(_) => {
      read.finished = true
      Ok(())
    }
    Err(issue) => fail_read(read, Host(issue))
  }
}

///|
/// Retry only the stopped original capture child. The Common Owner refuses
/// advancement before close; pending cleanup never resumes capture or pages.
pub fn advance_result_capture_cleanup(
  read : Read,
  quantum : Int,
) -> Result[Bool, ReadIssue] {
  if read.custody is InstalledBorrow(_) {
    return Err(BorrowedRun)
  }
  @rows.advance_row_capture_cleanup(read.run, quantum).map_err(issue => {
    Host(issue)
  })
}

///|
/// Begin only the existing checked acquisition prefix after page completion.
/// The original Common RowRun retains its child, evidence and cleanup duties.
pub fn begin_result_capture(read : Read) -> Result[Unit, ReadIssue] {
  if read.custody is InstalledBorrow(_) {
    return Err(BorrowedRun)
  }
  if !read_available(read) || !read.finished {
    return Err(Closed)
  }
  @rows.begin_row_capture(read.run).map_err(issue => Host(issue))
}

///|
/// Advance that same child by the caller's work quantum. Completion is not a
/// transport or resource-release acknowledgement; final capture still checks it.
pub fn advance_result_capture(
  read : Read,
  quantum : Int,
) -> Result[(Bool, Int64), ReadIssue] {
  if read.custody is InstalledBorrow(_) {
    return Err(BorrowedRun)
  }
  if !read_available(read) || !read.finished {
    return Err(Closed)
  }
  @rows.advance_row_capture(read.run, quantum).map_err(issue => Host(issue))
}

///|
pub fn capture_result_read(
  read : Read,
) -> Result[@rows.RowSourceCapture, ReadIssue] {
  if read.custody is InstalledBorrow(_) {
    return Err(BorrowedRun)
  }
  if !read_available(read) || !read.finished {
    return Err(Closed)
  }
  @rows.capture_row_run(read.run).map_err(issue => Host(issue))
}

///|
pub fn interrupt_result_read(read : Read) -> Unit {
  if !read.closed && !read.interrupted {
    read.interrupted = true
    @rows.abort_row_run(read.run)
  }
}

///|
/// Only the same physical stop observer may release the original reservation.
/// Failure retains the same job, Common run and pending retirement for retry.
pub fn close_result_read(read : Read) -> Result[Unit, ReadIssue] {
  guard read.custody is Original(verify_transport) else {
    return Err(BorrowedRun)
  }
  if read.closed {
    return Ok(())
  }
  read.interrupted = true
  if !read.transport_confirmed {
    if !verify_transport(@rows.row_run_attempt(read.run)) {
      return Err(TransportUnsettled)
    }
    read.transport_confirmed = true
  }
  match @rows.close_accounted_row_run(read.run) {
    Ok(_) => {
      read.closed = true
      Ok(())
    }
    Err(issue) => Err(Host(issue))
  }
}
