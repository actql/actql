// Custody of one row acquisition attempt: the same states and owners as
// every broad acquisition (issuer registration, selected attempt, settled
// transport, residual, retention, issued records, captured observation).
// Only the row admission differs; no step alone grants consumption.

///|
pub(all) enum RowAttemptIssue {
  InvalidState
  Read(RowSourceIssue)
  Residual(@query.QueryGuardIssue)
  MissingOutput
  Retention(@planning.QueryRetentionIssue)
}

///|
pub(all) enum RowEvidenceIssue {
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
  Attempt(RowAttemptIssue)
  Artifact(@planning.QueryArtifactIssue)
}

///|
priv enum RowAttemptState {
  Pending
  Reading(RowSourceRead)
  AwaitingCleanup(@execution.CapturedRows)
  EvidenceIssued(RowRecords)
  Captured(RowObservation)
  Failed
}

///|
priv struct RowCompletion {
  output : @execution.CompletedOutput
}

///|
priv struct RowRetention {
  completion : RowCompletion
  measured : @planning.MeasuredQueryRows
}

///|
priv struct RowIssuer {
  registration : @planning.QueryEvidenceRegistration[RowAttempt]
}

///|
priv struct RowAuthority {
  issuer : RowIssuer
  token : @planning.QueryEvidenceAttemptAuthority[RowAttempt]
}

///|
struct RowAttempt {
  preparation : RowSourcePreparation
  authority : RowAuthority
  mut state : RowAttemptState
}

///|
priv struct RowRecords {
  authority : RowAuthority
  retention : RowRetention
  issued : @planning.QueryEvidenceIssued[RowIssuer, RowAttempt, RowRetention]
}

///|
struct RowObservation {
  records : RowRecords
  captured : @planning.QueryEvidenceCaptured[
    RowIssuer,
    RowAttempt,
    RowRetention,
  ]
}

///|
pub(all) struct RowCompletionLimits {
  execution : @execution.SequenceExecutionLimits
  guards : @query.QueryGuardMeasureLimits
  retention : @planning.QueryRetentionLimits
  records : @planning.QueryMaterialLimits
  capture : @planning.QueryEvidenceLimits
}

///|
fn custody_issue(
  issue : @planning.QueryEvidenceCustodyIssue,
) -> RowEvidenceIssue {
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
fn abort_row_attempt(attempt : RowAttempt) -> Unit {
  if attempt.state is Captured(_) {
    return
  }
  if attempt.state is Reading(read) {
    cancel_row_source_read(read) |> ignore
  }
  attempt.state = Failed
}

///|
fn[T] fail_attempt(
  attempt : RowAttempt,
  issue : RowAttemptIssue,
) -> Result[T, RowAttemptIssue] {
  abort_row_attempt(attempt)
  Err(issue)
}

///|
fn verify_row_records(
  issuer : RowIssuer,
  attempt : RowAttempt,
  records : RowRecords,
) -> Result[Unit, RowEvidenceIssue] {
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
  @planning.verify_query_evidence_issued(
    records.issued,
    issuer.registration,
    records.authority.token,
    issuer,
    attempt,
    records.retention,
  ).map_err(custody_issue)
}

///|
/// Settle, compute the residual, retain, issue records and capture. Each
/// step requires the previous one; a failure aborts the attempt.
fn complete_row_capture(
  issuer : RowIssuer,
  attempt : RowAttempt,
  limits : RowCompletionLimits,
) -> Result[RowObservation, RowEvidenceIssue] {
  if !@planning.query_evidence_registration_live(issuer.registration) {
    return Err(IssuerClosed)
  }
  if !physical_equal(issuer, attempt.authority.issuer) {
    return Err(UnauthorizedAttempt)
  }
  if !@planning.query_evidence_transport_matches(issuer.registration, attempt) {
    abort_row_attempt(attempt)
    return Err(UnverifiedTransport)
  }
  guard attempt.state is AwaitingCleanup(scan) else {
    return Err(Attempt(InvalidState))
  }
  let completed = match
    execute_row_source_residual(
      attempt.preparation,
      scan,
      limits.execution,
      limits.guards,
    ) {
    Ok((value, _)) => value
    Err(issue) =>
      return fail_attempt(attempt, Residual(issue)).map_err(issue => {
        Attempt(issue)
      })
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
    return fail_attempt(attempt, MissingOutput).map_err(issue => Attempt(issue))
  }
  let completion = { output, }
  let measured = match
    @planning.measure_query_retention(scan, output, true, limits.retention) {
    Ok(value) => value
    Err(issue) =>
      return fail_attempt(attempt, Retention(issue)).map_err(issue => {
        Attempt(issue)
      })
  }
  let retained = { completion, measured, }
  let authority = attempt.authority
  if !physical_equal(
      @planning.query_evidence_registration_requirement(
        authority.issuer.registration,
      ),
      attempt.preparation.requirement,
    ) {
    abort_row_attempt(attempt)
    return Err(UnauthorizedAttempt)
  }
  guard @lower.preparation_input_schema(
      @lower.bound_preparation(attempt.preparation.owner),
      attempt.preparation.input_index,
    )
    is Some(schema) else {
    abort_row_attempt(attempt)
    return Err(Artifact(@planning.InvalidRetainedLayout))
  }
  let issued = match
    @planning.issue_query_evidence(
      authority.issuer.registration,
      authority.token,
      authority.issuer,
      attempt,
      retained,
      measured,
      scan,
      output,
      schema,
      limits.records,
    ) {
    Ok(value) => value
    Err(issue) => {
      abort_row_attempt(attempt)
      return Err(custody_issue(issue))
    }
  }
  let records = { authority, retention: retained, issued, }
  attempt.state = EvidenceIssued(records)
  match verify_row_records(issuer, attempt, records) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match
    @planning.capture_query_evidence(
      records.issued,
      issuer.registration,
      records.authority.token,
      issuer,
      attempt,
      records.retention,
      limits.capture,
    ) {
    Ok(captured) => {
      let observation = { records, captured, }
      attempt.state = Captured(observation)
      Ok(observation)
    }
    Err(issue) => {
      abort_row_attempt(attempt)
      Err(custody_issue(issue))
    }
  }
}

///|
/// Expose the exact retained observation to the common captured input
/// boundary, live only while issuer, attempt and observation still agree.
fn row_captured_source(
  issuer : RowIssuer,
  attempt : RowAttempt,
  observation : RowObservation,
) -> Result[@query.CapturedInputSource, @query.CapturedSourceIssue] {
  let live = fn() {
    verify_row_records(issuer, attempt, observation.records) is Ok(_) &&
    attempt.state is Captured(actual) &&
    physical_equal(actual, observation)
  }
  if !live() {
    return Err(Unavailable)
  }
  let requirement = attempt.preparation.requirement
  @query.prepare_trusted_capture_port(
    @planning.query_material_owner(
      @planning.query_requirement_material(requirement),
    ),
    @planning.query_requirement_program(requirement),
    fn(proof : RowObservation) {
      if physical_equal(proof, observation) && live() {
        Some(
          (
            observation.records.retention.completion.output,
            @execution.row_wire_usage(
              observation.records.retention.measured.output,
            ).0,
          ),
        )
      } else {
        None
      }
    },
  ).bind(port => @query.capture_verified_source(port, observation))
}

///|
pub fn row_observation_cid(observation : RowObservation) -> String {
  @planning.query_evidence_capture_cid(observation.captured)
}
