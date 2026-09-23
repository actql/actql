///|
pub(all) enum SalesforceBroadAttemptIssue {
  InvalidState
  Read(SalesforceBroadIssue)
  Residual(@query.QueryGuardIssue)
  MissingOutput
  Retention(@planning.QueryRetentionIssue)
}

///|
pub(all) enum SalesforceEvidenceIssue {
  InvalidLimits
  IdentifierLimit
  IdentifierExhausted
  IssuerClosed
  NotSelected
  UnauthorizedAttempt
  UnverifiedTransport
  NotRetained
  ForeignRecords
  AlreadyCaptured
  ForeignObservation
  Attempt(SalesforceBroadAttemptIssue)
  Artifact(@planning.QueryArtifactIssue)
  Consumer(@execution.ProducerBindingIssue)
}

///|
priv enum SalesforceBroadState {
  Pending
  Reading(SalesforceBroadQuery)
  AwaitingCleanup(@execution.CapturedRows)
  Ready(@execution.CapturedRows)
  Computed(SalesforceBroadCompletion)
  Retained(SalesforceBroadRetention)
  EvidenceIssued(SalesforceBroadRecords)
  Captured(SalesforceBroadObservation)
  Failed
}

///|
priv struct SalesforceBroadCompletion {
  scan : @execution.CapturedRows
  output : @execution.CompletedOutput
}

///|
priv struct SalesforceBroadRetention {
  completion : SalesforceBroadCompletion
  measured : @planning.MeasuredQueryRows
}

///|
struct SalesforceBroadIssuer {
  _contracts : @planning.QueryEvidenceContracts
  requirement : @planning.QueryRequirement
  name : String
  mut transport_matches : (SalesforceBroadAttempt) -> Bool
  attempts : @planning.IssuerCounter
  mut live : Bool
}

///|
let salesforce_issuer_serial : @planning.IssuerCounter = @planning.issuer_counter()

///|
priv struct SalesforceBroadAuthority {
  issuer : SalesforceBroadIssuer
  number : String
}

///|
struct SalesforceBroadAttempt {
  preparation : SalesforceBroadPreparation
  authority : SalesforceBroadAuthority
  mut state : SalesforceBroadState
}

///|
struct SalesforceBroadRecords {
  authority : SalesforceBroadAuthority
  retention : SalesforceBroadRetention
  artifacts : @planning.QueryRecordArtifacts
}

///|
struct SalesforceBroadObservation {
  records : SalesforceBroadRecords
  document : @encode.EncodedDocument
  cid : String
}

///|
pub(all) struct SalesforceBroadCompletionLimits {
  execution : @execution.SequenceExecutionLimits
  guards : @query.QueryGuardMeasureLimits
  retention : @planning.QueryRetentionLimits
  records : @planning.QueryMaterialLimits
  capture : @planning.QueryEvidenceLimits
}

///|
/// A trusted Host verifier checks the exact grant, Site, read view, and
/// physical settlement. A matching CID or a successful HTTP status is not
/// sufficient transport evidence.
pub fn prepare_salesforce_broad_issuer(
  contracts : @planning.QueryEvidenceContracts,
  requirement : @planning.QueryRequirement,
  process_nonce : String,
  max_nonce_chars : Int,
  transport_matches : (SalesforceBroadAttempt) -> Bool,
) -> Result[SalesforceBroadIssuer, SalesforceEvidenceIssue] {
  if max_nonce_chars < 0 {
    return Err(InvalidLimits)
  }
  if process_nonce.is_empty() || process_nonce.length() > max_nonce_chars {
    return Err(IdentifierLimit)
  }
  guard @planning.reserve_issuer_number(salesforce_issuer_serial)
    is Some(serial) else {
    return Err(IdentifierExhausted)
  }
  Ok({
    _contracts: contracts,
    requirement,
    name: process_nonce + "/salesforce-issuer/" + serial.to_string(),
    transport_matches,
    attempts: @planning.issuer_counter(),
    live: true,
  })
}

///|
pub fn prepare_issued_salesforce_broad_attempt(
  issuer : SalesforceBroadIssuer,
  choice : @planning.AcquisitionChoice,
  candidate : @planning.PreparedAcquisition[SalesforceBroadPreparation],
) -> Result[SalesforceBroadAttempt, SalesforceEvidenceIssue] {
  if !issuer.live {
    return Err(IssuerClosed)
  }
  guard @planning.acquisition_choice_payload(choice, candidate)
    is Some(preparation) else {
    return Err(NotSelected)
  }
  if !physical_equal(issuer.requirement, preparation.requirement) {
    return Err(UnauthorizedAttempt)
  }
  guard @planning.reserve_issuer_number(issuer.attempts) is Some(number) else {
    return Err(IdentifierExhausted)
  }
  Ok({
    preparation,
    authority: { issuer, number: number.to_string(), },
    state: Pending,
  })
}

///|
pub fn salesforce_broad_attempt_identity(
  attempt : SalesforceBroadAttempt,
) -> (String, String) {
  (attempt.authority.issuer.name, attempt.authority.number)
}

///|
pub fn close_salesforce_broad_issuer(issuer : SalesforceBroadIssuer) -> Unit {
  issuer.live = false
  issuer.transport_matches = _ => false
}

///|
pub fn abort_salesforce_broad_attempt(attempt : SalesforceBroadAttempt) -> Unit {
  if attempt.state is Captured(_) {
    return
  }
  if attempt.state is Reading(read) {
    cancel_salesforce_broad_query(read) |> ignore
  }
  attempt.state = Failed
}

///|
fn[T] fail_salesforce_broad_attempt(
  attempt : SalesforceBroadAttempt,
  issue : SalesforceBroadAttemptIssue,
) -> Result[T, SalesforceBroadAttemptIssue] {
  abort_salesforce_broad_attempt(attempt)
  Err(issue)
}

///|
pub fn begin_issued_salesforce_broad_read(
  attempt : SalesforceBroadAttempt,
  api_version : String,
  page_limits : @catalog.QueryPageLimits,
  max_pages : Int,
  max_total_rows : Int64,
  max_capture_rows : Int,
  retention : @execution.ValueLimits,
) -> Result[Unit, SalesforceBroadAttemptIssue] {
  guard attempt.state is Pending else { return Err(InvalidState) }
  match
    begin_salesforce_broad_query(
      attempt.preparation,
      api_version,
      page_limits,
      max_pages,
      max_total_rows,
      max_capture_rows,
      retention,
    ) {
    Ok(read) => {
      attempt.state = Reading(read)
      Ok(())
    }
    Err(issue) => fail_salesforce_broad_attempt(attempt, Read(issue))
  }
}

///|
pub fn salesforce_broad_attempt_next_path(
  attempt : SalesforceBroadAttempt,
) -> Result[String?, SalesforceBroadAttemptIssue] {
  match attempt.state {
    Reading(read) =>
      match salesforce_broad_next_path(read) {
        Ok(path) => Ok(path)
        Err(issue) => fail_salesforce_broad_attempt(attempt, Read(issue))
      }
    _ => Ok(None)
  }
}

///|
pub fn accept_issued_salesforce_broad_page(
  attempt : SalesforceBroadAttempt,
  path : String,
  bytes : Bytes,
) -> Result[@catalog.QueryPage, SalesforceBroadAttemptIssue] {
  guard attempt.state is Reading(read) else { return Err(InvalidState) }
  match accept_salesforce_broad_page(read, path, bytes) {
    Ok(page) => Ok(page)
    Err(issue) => fail_salesforce_broad_attempt(attempt, Read(issue))
  }
}

///|
pub fn finish_issued_salesforce_broad_read(
  attempt : SalesforceBroadAttempt,
) -> Result[Unit, SalesforceBroadAttemptIssue] {
  guard attempt.state is Reading(read) else { return Err(InvalidState) }
  match finish_salesforce_broad_query(read) {
    Ok(scan) => {
      attempt.state = AwaitingCleanup(scan)
      Ok(())
    }
    Err(issue) => fail_salesforce_broad_attempt(attempt, Read(issue))
  }
}

///|
/// This Host-only transition follows actual read settlement and cleanup.
/// The issuer verifier checks the same physical owner again at completion.
pub fn settle_salesforce_broad_transport(
  attempt : SalesforceBroadAttempt,
) -> Result[Unit, SalesforceBroadAttemptIssue] {
  guard attempt.state is AwaitingCleanup(scan) else { return Err(InvalidState) }
  attempt.state = Ready(scan)
  Ok(())
}

///|
pub fn execute_issued_salesforce_broad_residual(
  attempt : SalesforceBroadAttempt,
  limits : @execution.SequenceExecutionLimits,
  measurement : @query.QueryGuardMeasureLimits,
) -> Result[Unit, SalesforceBroadAttemptIssue] {
  guard attempt.state is Ready(scan) else { return Err(InvalidState) }
  let completed = match
    execute_salesforce_broad_residual(
      attempt.preparation,
      scan,
      limits,
      measurement,
    ) {
    Ok((value, _)) => value
    Err(issue) => return fail_salesforce_broad_attempt(attempt, Residual(issue))
  }
  let sequence = @planning.query_material_owner(
    @planning.query_requirement_material(attempt.preparation.requirement),
  )
  let query = @query.query_sequence_requirement(sequence)
  guard @execution.completed_output(
      completed,
      @sourcequery.query_acquisition_capture(query),
    )
    is Some(output) else {
    return fail_salesforce_broad_attempt(attempt, MissingOutput)
  }
  attempt.state = Computed({ scan, output, })
  Ok(())
}

///|
pub fn retain_salesforce_broad_attempt(
  attempt : SalesforceBroadAttempt,
  limits : @planning.QueryRetentionLimits,
) -> Result[Unit, SalesforceBroadAttemptIssue] {
  guard attempt.state is Computed(completion) else { return Err(InvalidState) }
  match
    @planning.measure_query_retention(
      completion.scan,
      completion.output,
      true,
      limits,
    ) {
    Ok(measured) => {
      attempt.state = Retained({ completion, measured, })
      Ok(())
    }
    Err(issue) => fail_salesforce_broad_attempt(attempt, Retention(issue))
  }
}

///|
fn salesforce_retention_matches(
  retained : SalesforceBroadRetention,
  attempt : SalesforceBroadAttempt,
) -> Bool {
  let current = match attempt.state {
    Retained(value) => value
    EvidenceIssued(value) => value.retention
    Captured(value) => value.records.retention
    _ => return false
  }
  physical_equal(current, retained) &&
  @execution.row_wire_matches_captured(
    retained.measured.scan,
    retained.completion.scan,
  ) &&
  @execution.row_wire_matches_output(
    retained.measured.output,
    retained.completion.output,
  )
}

///|
pub fn issue_salesforce_broad_records(
  attempt : SalesforceBroadAttempt,
  limits : @planning.QueryMaterialLimits,
) -> Result[SalesforceBroadRecords, SalesforceEvidenceIssue] {
  let authority = attempt.authority
  if !authority.issuer.live {
    return Err(IssuerClosed)
  }
  guard attempt.state is Retained(retained) else { return Err(NotRetained) }
  if !physical_equal(
      authority.issuer.requirement,
      attempt.preparation.requirement,
    ) ||
    !salesforce_retention_matches(retained, attempt) {
    abort_salesforce_broad_attempt(attempt)
    return Err(UnauthorizedAttempt)
  }
  if !(authority.issuer.transport_matches)(attempt) {
    abort_salesforce_broad_attempt(attempt)
    return Err(UnverifiedTransport)
  }
  guard @lower.preparation_input_schema(
      @lower.bound_preparation(attempt.preparation.owner),
      attempt.preparation.input_index,
    )
    is Some(schema) else {
    abort_salesforce_broad_attempt(attempt)
    return Err(Artifact(@planning.InvalidRetainedLayout))
  }
  match
    @planning.build_query_record_artifacts(
      attempt.preparation.requirement,
      retained.measured.scan,
      retained.measured.output,
      schema,
      authority.issuer.name,
      authority.number,
      limits,
    ) {
    Ok(artifacts) => {
      let records = { authority, retention: retained, artifacts, }
      attempt.state = EvidenceIssued(records)
      Ok(records)
    }
    Err(issue) => {
      abort_salesforce_broad_attempt(attempt)
      Err(Artifact(issue))
    }
  }
}

///|
pub fn verify_salesforce_broad_records(
  issuer : SalesforceBroadIssuer,
  attempt : SalesforceBroadAttempt,
  records : SalesforceBroadRecords,
) -> Result[Unit, SalesforceEvidenceIssue] {
  if !issuer.live {
    return Err(IssuerClosed)
  }
  if !physical_equal(issuer, attempt.authority.issuer) ||
    !physical_equal(records.authority, attempt.authority) {
    return Err(UnauthorizedAttempt)
  }
  let current = match attempt.state {
    EvidenceIssued(value) => Some(value)
    Captured(value) => Some(value.records)
    _ => None
  }
  guard current is Some(current) &&
    physical_equal(current, records) &&
    physical_equal(issuer.requirement, attempt.preparation.requirement) &&
    salesforce_retention_matches(records.retention, attempt) else {
    return Err(ForeignRecords)
  }
  if !(issuer.transport_matches)(attempt) {
    return Err(UnverifiedTransport)
  }
  Ok(())
}

///|
pub fn salesforce_broad_record_at(
  records : SalesforceBroadRecords,
  index : Int,
) -> (@encode.EncodedDocument, String)? {
  @planning.query_record_artifact_at(records.artifacts, index)
}

///|
pub fn capture_salesforce_broad_query(
  issuer : SalesforceBroadIssuer,
  attempt : SalesforceBroadAttempt,
  records : SalesforceBroadRecords,
  limits : @planning.QueryEvidenceLimits,
) -> Result[SalesforceBroadObservation, SalesforceEvidenceIssue] {
  match verify_salesforce_broad_records(issuer, attempt, records) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if attempt.state is Captured(_) {
    return Err(AlreadyCaptured)
  }
  match @planning.build_query_observation_artifact(records.artifacts, limits) {
    Ok((document, cid, _, _)) => {
      let observation = { records, document, cid, }
      attempt.state = Captured(observation)
      Ok(observation)
    }
    Err(issue) => {
      abort_salesforce_broad_attempt(attempt)
      Err(Artifact(issue))
    }
  }
}

///|
pub fn salesforce_broad_observation_cid(
  observation : SalesforceBroadObservation,
) -> String {
  observation.cid
}

///|
pub fn salesforce_broad_observation_document(
  observation : SalesforceBroadObservation,
) -> @encode.EncodedDocument {
  observation.document
}

///|
pub fn bind_captured_salesforce_broad_input(
  issuer : SalesforceBroadIssuer,
  attempt : SalesforceBroadAttempt,
  observation : SalesforceBroadObservation,
  receiver : @lower.BoundPrepared,
  input_index : Int,
  expected_producer : @lower.BoundPrepared,
) -> Result[@execution.BoundProducerInput, SalesforceEvidenceIssue] {
  match verify_salesforce_broad_records(issuer, attempt, observation.records) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  guard attempt.state is Captured(actual) && physical_equal(actual, observation) else {
    return Err(ForeignObservation)
  }
  @execution.bind_live_completed_input(
    receiver,
    input_index,
    expected_producer,
    observation.records.retention.completion.output,
    fn() {
      verify_salesforce_broad_records(issuer, attempt, observation.records)
      is Ok(_) &&
      attempt.state is Captured(actual) &&
      physical_equal(actual, observation)
    },
  ).map_err(issue => Consumer(issue))
}

///|
/// Success requires settlement, residual evaluation, retention, issued
/// records, and a captured observation. No step alone grants consumption.
pub fn complete_salesforce_broad_capture(
  issuer : SalesforceBroadIssuer,
  attempt : SalesforceBroadAttempt,
  limits : SalesforceBroadCompletionLimits,
) -> Result[SalesforceBroadObservation, SalesforceEvidenceIssue] {
  if !issuer.live {
    return Err(IssuerClosed)
  }
  if !physical_equal(issuer, attempt.authority.issuer) {
    return Err(UnauthorizedAttempt)
  }
  if !(issuer.transport_matches)(attempt) {
    abort_salesforce_broad_attempt(attempt)
    return Err(UnverifiedTransport)
  }
  match settle_salesforce_broad_transport(attempt) {
    Ok(_) => ()
    Err(issue) => return Err(Attempt(issue))
  }
  match
    execute_issued_salesforce_broad_residual(
      attempt,
      limits.execution,
      limits.guards,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Attempt(issue))
  }
  match retain_salesforce_broad_attempt(attempt, limits.retention) {
    Ok(_) => ()
    Err(issue) => return Err(Attempt(issue))
  }
  let records = match issue_salesforce_broad_records(attempt, limits.records) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  capture_salesforce_broad_query(issuer, attempt, records, limits.capture)
}
