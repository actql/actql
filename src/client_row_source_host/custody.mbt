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
  InputAwaitingCleanup(@execution.CapturedRows, @execution.AdmittedInput)
  InputValidating(RowInputValidation)
  InputValidated(RowInputValidation)
  InputStopping(RowInputValidation)
  InputCaptured(RowInputObservation)
  InputFailed(@execution.AdmittedInput)
  KeyedRetained(RowKeyedRetention)
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
  registration : @planning.QueryEvidenceRegistration[
    @planning.QueryEvidenceContracts,
    @planning.QueryRequirement,
    RowAttempt,
  ]
}

///|
priv struct RowAuthority {
  issuer : RowIssuer
  token : @planning.QueryEvidenceAttemptAuthority[
    @planning.QueryEvidenceContracts,
    @planning.QueryRequirement,
    RowAttempt,
  ]
}

///|
struct RowAttempt {
  preparation : RowAttemptPreparation
  authority : RowAttemptAuthority
  mut state : RowAttemptState
}

///|
priv enum RowAttemptPreparation {
  DirectPreparation(RowSourcePreparation)
  InputPreparation(RowInputPreparation)
  KeyedPreparation(RowKeyedAcquisition)
}

///|
priv enum RowAttemptAuthority {
  DirectAuthority(RowAuthority)
  InputAuthority(RowInputAuthority)
  KeyedAuthority(RowKeyedAuthority)
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
  match attempt.state {
    InputValidating(validation) | InputValidated(validation) => {
      @bounded.request_cancel(validation.control) |> ignore
      attempt.state = InputStopping(validation)
      return
    }
    InputStopping(_) => return
    InputAwaitingCleanup(_, input) => {
      attempt.state = InputFailed(input)
      return
    }
    InputCaptured(observation) => {
      attempt.state = InputFailed(observation.input)
      return
    }
    InputFailed(_) => return
    _ => ()
  }
  if attempt.state is (Captured(_) | InputCaptured(_) | KeyedRetained(_)) {
    return
  }
  if attempt.state is Reading(read) {
    cancel_row_source_read(read) |> ignore
  }
  if attempt.state is EvidenceIssued(records) &&
    !@planning.retire_query_evidence_custody(records.issued) {
    // Never lose an original holder when its custody refuses retirement.
    return
  }
  attempt.state = Failed
}

///|
/// Called only after the same RowRun has completed its required cleanup. Keep
/// successful cancellation distinct from retirement of closed evidence, and
/// leave Input/Keyed cleanup ownership to their existing state machines.
fn retire_closed_row_evidence(attempt : RowAttempt) -> Bool {
  let records = match attempt.state {
    EvidenceIssued(records) => records
    Captured(observation) => observation.records
    _ => return true
  }
  if @planning.query_evidence_registration_live(
      records.authority.issuer.registration,
    ) ||
    !@planning.retire_query_evidence_custody(records.issued) {
    return false
  }
  attempt.state = Failed
  true
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
  guard attempt.preparation is DirectPreparation(preparation) &&
    attempt.authority is DirectAuthority(authority) else {
    return Err(UnauthorizedAttempt)
  }
  if !@planning.query_evidence_registration_live(issuer.registration) {
    return Err(IssuerClosed)
  }
  if !physical_equal(issuer, authority.issuer) ||
    !physical_equal(records.authority, authority) {
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
      preparation.requirement,
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
  guard attempt.preparation is DirectPreparation(preparation) &&
    attempt.authority is DirectAuthority(authority) else {
    return Err(UnauthorizedAttempt)
  }
  if !@planning.query_evidence_registration_live(issuer.registration) {
    return Err(IssuerClosed)
  }
  if !physical_equal(issuer, authority.issuer) {
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
      preparation,
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
    @planning.query_requirement_material(preparation.requirement),
  )
  let query = @query.query_sequence_requirement(sequence)
  guard @execution.completed_output(
      completed,
      @sourcequery.query_acquisition_capture(query),
    )
    is Some(output) else {
    return fail_attempt(attempt, MissingOutput).map_err(issue => Attempt(issue))
  }
  complete_row_capture_output(issuer, attempt, output, limits)
}

///|
/// Both residuals finish through the same custody. The synchronous caller
/// executes the exact scan here; the bounded caller separately verifies its
/// sealed supplied-input occurrence before passing the guarded completion.
fn complete_row_capture_output(
  issuer : RowIssuer,
  attempt : RowAttempt,
  output : @execution.CompletedOutput,
  limits : RowCompletionLimits,
) -> Result[RowObservation, RowEvidenceIssue] {
  guard attempt.preparation is DirectPreparation(preparation) &&
    attempt.authority is DirectAuthority(authority) &&
    physical_equal(issuer, authority.issuer) &&
    @planning.query_evidence_registration_live(issuer.registration) &&
    @planning.query_evidence_transport_matches(issuer.registration, attempt) &&
    attempt.state is AwaitingCleanup(scan) else {
    return Err(UnverifiedTransport)
  }
  let sequence = @planning.query_material_owner(
    @planning.query_requirement_material(preparation.requirement),
  )
  guard @execution.completed_output_matches_port(
    output,
    preparation.owner,
    @sourcequery.query_acquisition_capture(
      @query.query_sequence_requirement(sequence),
    ),
  ) else {
    return Err(Attempt(MissingOutput))
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
  if !physical_equal(
      @planning.query_evidence_registration_requirement(
        authority.issuer.registration,
      ),
      preparation.requirement,
    ) {
    abort_row_attempt(attempt)
    return Err(UnauthorizedAttempt)
  }
  guard @lower.preparation_input_schema(
      @lower.bound_preparation(preparation.owner),
      preparation.input_index,
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
    Err(issue) => {
      abort_row_attempt(attempt)
      return Err(issue)
    }
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
  guard attempt.preparation is DirectPreparation(preparation) else {
    return Err(Unavailable)
  }
  let live = fn() {
    verify_row_records(issuer, attempt, observation.records) is Ok(_) &&
    attempt.state is Captured(actual) &&
    physical_equal(actual, observation)
  }
  if !live() {
    return Err(Unavailable)
  }
  let requirement = preparation.requirement
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
