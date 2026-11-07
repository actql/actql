///|
pub(all) enum ReadIssue {
  InvalidLimits
  ForeignDeclaration
  Description(@description.DescriptionIssue)
  Host(@rows.RowHostIssue)
  Response(@response.ResponseIssue)
  SchemaMismatch(String)
  WrongPartition
  WrongStatement
  Incomplete
  Closed
  TransportUnsettled
  BorrowedRun
}

///|
/// The checked Source requirement and original declaration stay in the existing
/// Common acquisition. This wrapper selects provider spelling, not authority.
pub struct PreparedRead {
  priv acquisition : @rows.RowAcquisition
  priv projection : @description.ReadProjection
}

///|
pub fn prepare_declared_read(
  description : @description.TableDescription,
  declaration : @rows.RowDeclaration,
  requirement : @planning.QueryRequirement,
  query_contract : String,
  evidence_contract : String,
  limits : @description.DescriptionLimits,
  declaration_limits : @rows.RowDeclarationLimits,
) -> Result[PreparedRead, ReadIssue] {
  if declaration.connector_registration != "snowflake" {
    return Err(ForeignDeclaration)
  }
  let source_ref = @planning.query_requirement_source(requirement).0
  guard @rows.row_declaration_view(declaration, source_ref) is Some(view) else {
    return Err(ForeignDeclaration)
  }
  let full = match
    @description.prepare_read_projection(description, view.fields, limits) {
    Ok(value) => value
    Err(issue) => return Err(Description(issue))
  }
  // A field-map CID is not a carrier-schema envelope CID. Reuse Common's
  // declaration issuer with the original resource/version before comparing
  // the original carrier reference in that same identity domain.
  let observed = match
    @description.generate_read_declaration(
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
    @description.prepare_read_projection(
      description,
      @rows.row_acquisition_columns(acquisition),
      limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Description(issue))
  }
  Ok({ acquisition, projection, })
}

///|
pub fn prepared_read_acquisition(read : PreparedRead) -> @rows.RowAcquisition {
  read.acquisition
}

///|
pub fn prepared_read_projection(
  read : PreparedRead,
) -> @description.ReadProjection {
  read.projection
}

///|
/// A failed begin retains the same already-reserved Common run for its caller's
/// cleanup. There is no automatic close whose unconfirmed outcome can be lost.
pub struct ReadStartFailure {
  priv issue : ReadIssue
  priv cleanup : Read?
}

///|
pub fn read_start_failure_issue(failure : ReadStartFailure) -> ReadIssue {
  failure.issue
}

///|
pub fn read_start_failure_cleanup(failure : ReadStartFailure) -> Read? {
  failure.cleanup
}

///|
priv enum ReadCustody {
  Original((@rows.RowAttempt) -> Bool)
  InstalledBorrow(@rows.RowRunResponseBorrow)
}

///|
/// Provider page progress only. Run, transfer, capture and cleanup responsibility
/// remain in the original Common RowRun; no parallel Ledger is constructed.
pub struct Read {
  priv prepared : PreparedRead
  priv run : @rows.RowRun
  priv limits : @response.ResponseLimits
  priv max_contract_pairs : Int
  priv custody : ReadCustody
  priv mut transport_confirmed : Bool
  priv mut transport_bound : Bool
  priv mut retire_transport : (() -> Bool)?
  priv mut original : @response.ResultSet?
  priv mut pages : Int
  priv mut rows : Int64
  priv mut finished : Bool
  priv mut interrupted : Bool
  priv mut closed : Bool
  priv mut statement_bound : Bool
}

///|
fn valid_read_limits(
  limits : @response.ResponseLimits,
  max_contract_pairs : Int,
) -> Bool {
  !(max_contract_pairs <= 0 ||
  limits.max_bytes <= 0 ||
  limits.max_nodes <= 0 ||
  limits.max_depth <= 0 ||
  limits.max_columns <= 0 ||
  limits.max_name_units <= 0 ||
  limits.max_handle_units <= 0 ||
  limits.max_partitions <= 0 ||
  limits.max_rows < 0 ||
  limits.max_total_rows < 0L ||
  limits.max_total_rows > 2147483647L)
}

///|
pub fn start_accounted_read(
  prepared : PreparedRead,
  nonce : String,
  verify_transport : (@rows.RowAttempt) -> Bool,
  ledger : @resources.Ledger,
  transfer_bytes : Int64,
  execution_scratch : Int64,
  limits : @response.ResponseLimits,
  max_contract_pairs : Int,
) -> Result[Read, ReadStartFailure] {
  // The existing response Owner still validates every received envelope. These
  // are pre-start bounds for its exact page and Common's Int-indexed capture.
  if !valid_read_limits(limits, max_contract_pairs) {
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
  let read = {
    prepared,
    run,
    limits,
    max_contract_pairs,
    custody: Original(verify_transport),
    transport_confirmed: false,
    transport_bound: false,
    retire_transport: None,
    original: None,
    pages: 0,
    rows: 0L,
    finished: false,
    interrupted: false,
    closed: false,
    statement_bound: false,
  }
  match
    @rows.begin_row_run(
      run,
      limits.max_bytes,
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
/// Borrow exactly the Host's already-begun accounted run. The Host remains the
/// sole finish/capture/close owner; this port reserves and begins nothing.
pub fn borrow_accounted_read(
  prepared : PreparedRead,
  run : @rows.RowRun,
  limits : @response.ResponseLimits,
  max_contract_pairs : Int,
) -> Result[Read, ReadIssue] {
  if !valid_read_limits(limits, max_contract_pairs) {
    return Err(InvalidLimits)
  }
  let borrow = match @rows.borrow_row_run_responses(run, prepared.acquisition) {
    Ok(value) => value
    Err(issue) => return Err(Host(issue))
  }
  Ok({
    prepared,
    run,
    limits,
    max_contract_pairs,
    custody: InstalledBorrow(borrow),
    transport_confirmed: false,
    transport_bound: false,
    retire_transport: None,
    original: None,
    pages: 0,
    rows: 0L,
    finished: false,
    interrupted: false,
    closed: false,
    statement_bound: false,
  })
}

///|
/// The existing physical transport Owner supplies this exact reader's stop
/// observation. It is not Source/publish authority, completion or a caller
/// cancellation acknowledgement. Unknown leaves this same root funded.
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
    read.original = None
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
/// Retire only this provider alias after its same physical scope stops. The
/// Common root remains with the original Host until that owner closes it.
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
    // No statement candidate/admission is available before transport binding.
    read.closed = true
    read.original = None
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
fn first_values(
  result : @response.ResultSet,
) -> Array[Array[@admitted.CheckedValue]] {
  let values = []
  for row in 0..<@response.result_set_row_count(result) {
    let cells = []
    for column in 0..<@response.result_set_column_count(result) {
      cells.push(@response.result_set_cell(result, row, column).unwrap())
    }
    values.push(cells)
  }
  values
}

///|
/// Charge the exact provider envelope before parsing. The response's contracts
/// must equal the selected original metadata contracts, not just its names.
pub fn accept_first_result(read : Read, body : Bytes) -> Result[Int, ReadIssue] {
  if read.statement_bound {
    return Err(WrongStatement)
  }
  if !read_available(read) || read.finished {
    return Err(Closed)
  }
  if read.original is Some(_) {
    return fail_read(read, WrongPartition)
  }
  let charge = match @rows.charge_row_run_page(read.run, body) {
    Ok(value) => value
    Err(issue) => return fail_read(read, Host(issue))
  }
  accept_charged_first_result(read, charge, body, None)
}

///|
fn accept_charged_first_result(
  read : Read,
  charge : @rows.RowPageCharge,
  body : Bytes,
  expected_handle : String?,
) -> Result[Int, ReadIssue] {
  if !read_available(read) || read.finished {
    return Err(Closed)
  }
  if read.original is Some(_) {
    return fail_read(read, WrongPartition)
  }
  let acquisition = read.prepared.acquisition
  let contracts = []
  for index, name in @rows.row_acquisition_columns(acquisition) {
    guard @rows.row_acquisition_column_contract(acquisition, index)
      is Some(contract) else {
      return fail_read(read, ForeignDeclaration)
    }
    contracts.push((name, contract))
  }
  let result = match
    @response.project_result_set_with_contracts(
      body,
      read.limits,
      contracts,
      read.max_contract_pairs,
    ) {
    Ok(value) => value
    Err(@response.ContractMismatch(name)) =>
      return fail_read(read, SchemaMismatch(name))
    Err(issue) => return fail_read(read, Response(issue))
  }
  if expected_handle is Some(expected) &&
    @response.result_set_handle(result) != expected {
    return fail_read(read, WrongStatement)
  }
  let accepted = match
    @rows.accept_charged_row_run_values(
      read.run,
      charge,
      @description.read_projection_fields(read.prepared.projection),
      first_values(result),
    ) {
    Ok(value) => value
    Err(issue) => return fail_read(read, Host(issue))
  }
  read.original = Some(result)
  read.pages = 1
  read.rows = accepted.to_int64()
  Ok(accepted)
}

///|
/// The physical driver must associate this exact ordinal with its original
/// statement handle. A partition cannot substitute metadata or a new handle.
pub fn accept_result_partition(
  read : Read,
  ordinal : Int,
  body : Bytes,
) -> Result[Int, ReadIssue] {
  if read.statement_bound {
    return Err(WrongStatement)
  }
  if !read_available(read) || read.finished {
    return Err(Closed)
  }
  guard read.original is Some(original) &&
    ordinal == read.pages &&
    ordinal < @response.result_set_partition_count(original) else {
    return fail_read(read, WrongPartition)
  }
  let charge = match @rows.charge_row_run_page(read.run, body) {
    Ok(value) => value
    Err(issue) => return fail_read(read, Host(issue))
  }
  accept_charged_result_partition(read, charge, ordinal, body)
}

///|
fn accept_charged_result_partition(
  read : Read,
  charge : @rows.RowPageCharge,
  ordinal : Int,
  body : Bytes,
) -> Result[Int, ReadIssue] {
  if !read_available(read) || read.finished {
    return Err(Closed)
  }
  guard read.original is Some(original) &&
    ordinal == read.pages &&
    ordinal < @response.result_set_partition_count(original) else {
    return fail_read(read, WrongPartition)
  }
  let page = match
    @response.project_partition(body, original, ordinal, read.limits) {
    Ok(value) => value
    Err(issue) => return fail_read(read, Response(issue))
  }
  let values = []
  for row in 0..<@response.partition_row_count(page) {
    let cells = []
    for column in 0..<@response.result_set_column_count(original) {
      cells.push(@response.partition_cell(page, row, column).unwrap())
    }
    values.push(cells)
  }
  let accepted = match
    @rows.accept_charged_row_run_values(
      read.run,
      charge,
      @description.read_projection_fields(read.prepared.projection),
      values,
    ) {
    Ok(value) => value
    Err(issue) => return fail_read(read, Host(issue))
  }
  read.pages += 1
  read.rows += accepted.to_int64()
  Ok(accepted)
}

///|
/// Finishing page admission only enters Common's AwaitingCleanup state. It is
/// neither a transport-stop ACK nor a captured Source or durable publication.
pub fn finish_result_read(read : Read) -> Result[Unit, ReadIssue] {
  if read.custody is InstalledBorrow(_) {
    return Err(BorrowedRun)
  }
  if !read_available(read) || read.finished {
    return Err(Closed)
  }
  guard read.original is Some(original) &&
    read.pages == @response.result_set_partition_count(original) &&
    read.rows == @response.result_set_total_rows(original) else {
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
pub fn interrupt_result_read(read : Read) -> Unit {
  if !read.closed && !read.interrupted {
    read.interrupted = true
    @rows.abort_row_run(read.run)
  }
}

///|
/// Preserve the original run, response and metadata on a failed cleanup. A retry
/// uses that same Common responsibility; it never constructs another attempt.
pub fn close_result_read(read : Read) -> Result[Unit, ReadIssue] {
  guard read.custody is Original(verify_transport) else {
    return Err(BorrowedRun)
  }
  if read.closed {
    return Ok(())
  }
  read.interrupted = true
  // This is the same trusted physical-stop observation originally supplied to
  // Common's acquisition registration. It is not a caller-provided read grant
  // or a logical cancellation ACK. Do not release the holding before it.
  if !read.transport_confirmed {
    if !verify_transport(@rows.row_run_attempt(read.run)) {
      return Err(TransportUnsettled)
    }
    read.transport_confirmed = true
  }
  match @rows.close_accounted_row_run(read.run) {
    Ok(_) => {
      read.closed = true
      read.original = None
      Ok(())
    }
    Err(issue) => Err(Host(issue))
  }
}

///|
pub fn result_read_usage(read : Read) -> (Int, Int64) {
  (read.pages, read.rows)
}

///|
pub fn result_read_original(read : Read) -> @response.ResultSet? {
  if !read_available(read) {
    None
  } else {
    read.original
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
/// Common checks original transport settlement, residual execution and issued
/// evidence. Page completion alone cannot manufacture a captured Source.
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
/// Retain the original lookup handle while cleanup is pending. This material
/// grants no permission to submit, retry, read or cancel a provider statement.
pub fn result_read_statement_handle(read : Read) -> String? {
  if read.closed {
    None
  } else {
    read.original.map(@response.result_set_handle)
  }
}
