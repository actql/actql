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
/// Provider page progress only. Run, transfer, capture and cleanup responsibility
/// remain in the original Common RowRun; no parallel Ledger is constructed.
pub struct Read {
  priv prepared : PreparedRead
  priv run : @rows.RowRun
  priv limits : @response.ResponseLimits
  priv max_contract_pairs : Int
  priv verify_transport : (@rows.RowAttempt) -> Bool
  priv mut transport_confirmed : Bool
  priv mut original : @response.ResultSet?
  priv mut pages : Int
  priv mut rows : Int64
  priv mut finished : Bool
  priv mut interrupted : Bool
  priv mut closed : Bool
  priv mut statement_bound : Bool
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
  if max_contract_pairs <= 0 ||
    limits.max_bytes <= 0 ||
    limits.max_nodes <= 0 ||
    limits.max_depth <= 0 ||
    limits.max_columns <= 0 ||
    limits.max_name_units <= 0 ||
    limits.max_handle_units <= 0 ||
    limits.max_partitions <= 0 ||
    limits.max_rows < 0 ||
    limits.max_total_rows < 0L ||
    limits.max_total_rows > 2147483647L {
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
    verify_transport,
    transport_confirmed: false,
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
  if read.closed || read.interrupted || read.finished {
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
  if read.closed || read.interrupted || read.finished {
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
  if read.closed || read.interrupted || read.finished {
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
  if read.closed || read.interrupted || read.finished {
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
  if read.closed || read.interrupted || read.finished {
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
  if read.closed {
    return Ok(())
  }
  read.interrupted = true
  // This is the same trusted physical-stop observation originally supplied to
  // Common's acquisition registration. It is not a caller-provided read grant
  // or a logical cancellation ACK. Do not release the holding before it.
  if !read.transport_confirmed {
    if !(read.verify_transport)(@rows.row_run_attempt(read.run)) {
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
  if read.closed || read.interrupted {
    None
  } else {
    read.original
  }
}

///|
/// Common checks original transport settlement, residual execution and issued
/// evidence. Page completion alone cannot manufacture a captured Source.
pub fn capture_result_read(
  read : Read,
) -> Result[@rows.RowSourceCapture, ReadIssue] {
  if read.closed || read.interrupted || !read.finished {
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
