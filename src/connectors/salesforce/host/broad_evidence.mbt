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
  registration : @planning.QueryEvidenceRegistration[SalesforceBroadAttempt]
}

///|
priv struct SalesforceBroadAuthority {
  issuer : SalesforceBroadIssuer
  token : @planning.QueryEvidenceAttemptAuthority[SalesforceBroadAttempt]
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
  issued : @planning.QueryEvidenceIssued[
    SalesforceBroadIssuer,
    SalesforceBroadAttempt,
    SalesforceBroadRetention,
  ]
}

///|
struct SalesforceBroadObservation {
  records : SalesforceBroadRecords
  captured : @planning.QueryEvidenceCaptured[
    SalesforceBroadIssuer,
    SalesforceBroadAttempt,
    SalesforceBroadRetention,
  ]
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
  @planning.register_query_evidence_issuer(
    contracts, requirement, process_nonce, max_nonce_chars, "salesforce-issuer",
    transport_matches,
  )
  .map(registration => { registration, })
  .map_err(salesforce_custody_issue)
}

///|
pub fn prepare_issued_salesforce_broad_attempt(
  issuer : SalesforceBroadIssuer,
  choice : @planning.AcquisitionChoice,
  candidate : @planning.PreparedAcquisition[SalesforceBroadPreparation],
) -> Result[SalesforceBroadAttempt, SalesforceEvidenceIssue] {
  let (preparation, token) = match
    @planning.reserve_selected_query_evidence_attempt(
      issuer.registration,
      choice,
      candidate,
      preparation => preparation.requirement,
    ) {
    Ok(value) => value
    Err(issue) => return Err(salesforce_custody_issue(issue))
  }
  Ok({ preparation, authority: { issuer, token, }, state: Pending, })
}

///|
pub fn salesforce_broad_attempt_identity(
  attempt : SalesforceBroadAttempt,
) -> (String, String) {
  (
    @planning.query_evidence_registration_name(
      attempt.authority.issuer.registration,
    ),
    @planning.query_evidence_attempt_number(attempt.authority.token),
  )
}

///|
pub fn salesforce_broad_attempt_plan(
  attempt : SalesforceBroadAttempt,
) -> @catalog.ReadProjection {
  attempt.preparation.plan
}

///|
pub fn salesforce_broad_attempt_read_complete(
  attempt : SalesforceBroadAttempt,
) -> Bool {
  match attempt.state {
    Reading(read) => salesforce_broad_complete(read)
    _ => false
  }
}

///|
pub fn salesforce_broad_attempt_read_row_count(
  attempt : SalesforceBroadAttempt,
) -> Result[Int64, SalesforceBroadAttemptIssue] {
  match attempt.state {
    Reading(read) => Ok(salesforce_broad_row_count(read))
    _ => Err(InvalidState)
  }
}

///|
pub fn close_salesforce_broad_issuer(issuer : SalesforceBroadIssuer) -> Unit {
  @planning.close_query_evidence_registration(issuer.registration)
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
fn salesforce_custody_issue(
  issue : @planning.QueryEvidenceCustodyIssue,
) -> SalesforceEvidenceIssue {
  match issue {
    InvalidLimits => InvalidLimits
    InvalidIdentity => IdentifierLimit
    IdentifierExhausted => IdentifierExhausted
    IssuerClosed => IssuerClosed
    NotSelected => NotSelected
    ForeignRequirement => UnauthorizedAttempt
    ForeignOwner => UnauthorizedAttempt
    ForeignRetention | ForeignRecords => ForeignRecords
    UnverifiedTransport => UnverifiedTransport
    AlreadyCaptured => AlreadyCaptured
    Artifact(issue) => Artifact(issue)
  }
}

///|
pub fn issue_salesforce_broad_records(
  attempt : SalesforceBroadAttempt,
  limits : @planning.QueryMaterialLimits,
) -> Result[SalesforceBroadRecords, SalesforceEvidenceIssue] {
  let authority = attempt.authority
  if !@planning.query_evidence_registration_live(authority.issuer.registration) {
    return Err(IssuerClosed)
  }
  guard attempt.state is Retained(retained) else { return Err(NotRetained) }
  if !physical_equal(
      @planning.query_evidence_registration_requirement(
        authority.issuer.registration,
      ),
      attempt.preparation.requirement,
    ) {
    abort_salesforce_broad_attempt(attempt)
    return Err(UnauthorizedAttempt)
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
    @planning.issue_query_evidence(
      authority.issuer.registration,
      authority.token,
      authority.issuer,
      attempt,
      retained,
      retained.measured,
      retained.completion.scan,
      retained.completion.output,
      schema,
      limits,
    ) {
    Ok(issued) => {
      let records = { authority, retention: retained, issued, }
      attempt.state = EvidenceIssued(records)
      Ok(records)
    }
    Err(issue) => {
      abort_salesforce_broad_attempt(attempt)
      Err(salesforce_custody_issue(issue))
    }
  }
}

///|
pub fn verify_salesforce_broad_records(
  issuer : SalesforceBroadIssuer,
  attempt : SalesforceBroadAttempt,
  records : SalesforceBroadRecords,
) -> Result[Unit, SalesforceEvidenceIssue] {
  if !@planning.query_evidence_registration_live(issuer.registration) {
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
    physical_equal(
      @planning.query_evidence_registration_requirement(issuer.registration),
      attempt.preparation.requirement,
    ) else {
    return Err(ForeignRecords)
  }
  match
    @planning.verify_query_evidence_issued(
      records.issued,
      issuer.registration,
      records.authority.token,
      issuer,
      attempt,
      records.retention,
    ) {
    Ok(_) => Ok(())
    Err(issue) => Err(salesforce_custody_issue(issue))
  }
}

///|
pub fn salesforce_broad_record_at(
  records : SalesforceBroadRecords,
  index : Int,
) -> (@encode.EncodedDocument, String)? {
  @planning.query_evidence_record_at(records.issued, index)
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
  match
    @planning.capture_query_evidence(
      records.issued,
      issuer.registration,
      records.authority.token,
      issuer,
      attempt,
      records.retention,
      limits,
    ) {
    Ok(captured) => {
      let observation = { records, captured, }
      attempt.state = Captured(observation)
      Ok(observation)
    }
    Err(issue) => {
      abort_salesforce_broad_attempt(attempt)
      Err(salesforce_custody_issue(issue))
    }
  }
}

///|
pub fn salesforce_broad_observation_cid(
  observation : SalesforceBroadObservation,
) -> String {
  @planning.query_evidence_capture_cid(observation.captured)
}

///|
pub fn salesforce_broad_observation_document(
  observation : SalesforceBroadObservation,
) -> @encode.EncodedDocument {
  @planning.query_evidence_capture_document(observation.captured)
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
  @planning.bind_captured_query_evidence_input(
    observation.captured,
    observation.records.issued,
    issuer.registration,
    observation.records.authority.token,
    issuer,
    attempt,
    observation.records.retention,
    receiver,
    input_index,
    expected_producer,
    fn() {
      verify_salesforce_broad_records(issuer, attempt, observation.records)
      is Ok(_) &&
      attempt.state is Captured(actual) &&
      physical_equal(actual, observation)
    },
  ).map_err(issue => {
    match issue {
      @planning.Evidence(issue) => salesforce_custody_issue(issue)
      @planning.ForeignObservation => ForeignObservation
      @planning.Consumer(issue) => Consumer(issue)
    }
  })
}

///|
/// Success requires settlement, residual evaluation, retention, issued
/// records, and a captured observation. No step alone grants consumption.
pub fn complete_salesforce_broad_capture(
  issuer : SalesforceBroadIssuer,
  attempt : SalesforceBroadAttempt,
  limits : SalesforceBroadCompletionLimits,
) -> Result[SalesforceBroadObservation, SalesforceEvidenceIssue] {
  if !@planning.query_evidence_registration_live(issuer.registration) {
    return Err(IssuerClosed)
  }
  if !physical_equal(issuer, attempt.authority.issuer) {
    return Err(UnauthorizedAttempt)
  }
  if !@planning.query_evidence_transport_matches(issuer.registration, attempt) {
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
