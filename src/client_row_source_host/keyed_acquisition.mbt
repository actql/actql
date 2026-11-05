///|
/// One original keyed occurrence and actual admitted request. This is not a
/// Direct query, a transport grant, or a successful response observation.
priv struct RowKeyedRequirement {
  owner : @lower.BoundPrepared
  facts : @sourcequery.KeyedSourceFacts
  request : @sourcequery.KeyedRowRequest
}

///|
pub(all) struct RowKeyedLimits {
  page : RowPageLimits
  retention : @execution.ValueLimits
  request : @sourcequery.RequestLimits
  wire : @execution.RowWireLimits
}

///|
struct RowKeyedAcquisition {
  requirement : RowKeyedRequirement
  view : RowDeclaredView
  connector_id : String
  choice : @planning.AcquisitionChoice[RowKeyedRequirement]
  candidate : @planning.PreparedAcquisition[
    RowKeyedRequirement,
    RowKeyedRequirement,
  ]
  limits : RowKeyedLimits
  max_rows : Int
  mut input_available : (() -> Bool)?
}

///|
priv struct RowKeyedIssuer {
  registration : @planning.QueryEvidenceRegistration[
    @sourcequery.KeyedSourceFacts,
    RowKeyedRequirement,
    RowAttempt,
  ]
}

///|
priv struct RowKeyedAuthority {
  issuer : RowKeyedIssuer
  token : @planning.QueryEvidenceAttemptAuthority[
    @sourcequery.KeyedSourceFacts,
    RowKeyedRequirement,
    RowAttempt,
  ]
}

///|
priv struct RowKeyedRetention {
  authority : RowKeyedAuthority
  requirement : RowKeyedRequirement
  rows : @execution.CapturedRows
  measured : @execution.RowWireIdentity
}

///|
/// Exact retained supplied input under the existing RowRun. It has no Direct
/// receipt or completed-output representation. Whole-lookup completion and
/// Source evidence still belong to the caller's original checked barrier.
struct RowKeyedSourceCapture {
  run : RowRun
  retention : RowKeyedRetention
}

///|
pub fn prepare_keyed_row_acquisition(
  owner : @lower.BoundPrepared,
  facts : @sourcequery.KeyedSourceFacts,
  request : @sourcequery.KeyedRowRequest,
  declaration : RowDeclaration,
  limits : RowKeyedLimits,
  input_available? : (() -> Bool)? = None,
) -> Result[RowKeyedAcquisition, RowHostIssue] {
  if !valid_keyed_row_limits(limits) {
    return Err(InvalidSpecification)
  }
  guard @planning.keyed_source_evidence_facts(facts) is Some(source) &&
    row_declaration_view(declaration, source.source_ref) is Some(view) else {
    return Err(Source(UndeclaredSource))
  }
  let join = @sourcequery.keyed_source_join(facts)
  match @query.keyed_response_input_schema(owner, join, request) {
    Ok(_) => ()
    Err(issue) => return Err(Source(KeyedOwner(issue)))
  }
  let selected = match
    selected_keyed_row_capacity(owner, facts, declaration, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let registry = match
    @connector.prepare_capability_registry(
      [
        {
          name: declaration.connector_registration,
          acquisition: true,
          fixed_compute: false,
          effect: false,
        },
      ],
      1,
      64,
    ) {
    Ok(value) => value
    Err(_) => return Err(Registration)
  }
  let registration = @connector.capability_registration_at(registry, 0).unwrap()
  let requirement = { owner, facts, request, }
  let candidate = match
    @planning.bind_acquisition_candidate(
      registration,
      requirement,
      requirement,
      @cost.Unknown,
      { transfer_bytes: None, retained_bytes: None, money_units: None, },
    ) {
    Ok(value) => value
    Err(_) => return Err(Candidate)
  }
  // A single installed path is Host-selected, not an invented duration.
  guard @planning.choose_acquisition_candidate(
      registry,
      requirement,
      [@planning.prepared_acquisition_candidate(candidate)],
      Some([0]),
      10,
    )
    is Ok(@planning.Proposed(choice)) else {
    return Err(Selection)
  }
  Ok({
    requirement,
    view,
    connector_id: declaration.connector_id,
    choice,
    candidate,
    limits,
    max_rows: selected.max_rows,
    input_available,
  })
}

///|
pub fn start_keyed_row_acquisition(
  acquisition : RowKeyedAcquisition,
  nonce : String,
  verify : (RowAttempt) -> Bool,
) -> Result[RowRun, RowHostIssue] {
  start_keyed_row_acquisition_owned(acquisition, nonce, verify, None)
}

///|
fn start_keyed_row_acquisition_owned(
  acquisition : RowKeyedAcquisition,
  nonce : String,
  verify : (RowAttempt) -> Bool,
  original : (
    @resources.Ledger,
    @resources.OriginalLedgerIdentity,
    @resources.Reservation,
    Int,
    @resources.Reservation?,
  )?,
) -> Result[RowRun, RowHostIssue] {
  if !keyed_acquisition_input_live(acquisition) {
    return Err(InvalidState)
  }
  // The existing liveness callback can alter original custody synchronously.
  // Reject that change before registration/RowRun allocation, not after I/O.
  if original is Some((ledger, identity, assembly, children, prefix)) &&
    !@resources.original_keyed_child_preparation_available(
      identity,
      ledger,
      assembly,
      children,
      prefix~,
    ) {
    return Err(Physical(ForeignOwner))
  }
  let issuer : RowKeyedIssuer = match
    @planning.register_query_evidence_issuer(
      acquisition.requirement.facts,
      acquisition.requirement,
      nonce,
      128,
      "keyed-row-source-issuer",
      verify,
    ) {
    Ok(registration) => { registration, }
    Err(issue) => return Err(Evidence(custody_issue(issue)))
  }
  let (_, token) = match
    @planning.reserve_selected_query_evidence_attempt(
      issuer.registration,
      acquisition.choice,
      acquisition.candidate,
      value => value,
    ) {
    Ok(value) => value
    Err(issue) => {
      @planning.close_query_evidence_registration(issuer.registration)
      return Err(Evidence(custody_issue(issue)))
    }
  }
  Ok({
    configuration: if original is Some(_) {
      OriginalKeyedConfiguration(acquisition)
    } else {
      KeyedConfiguration(acquisition)
    },
    issuer: KeyedIssuer(issuer),
    attempt: {
      preparation: KeyedPreparation(acquisition),
      authority: KeyedAuthority({ issuer, token, }),
      state: Pending,
    },
    closed: false,
    physical: None,
    page_charge: None,
    response_borrowed: false,
    residual: None,
  })
}

///|
pub fn start_accounted_keyed_row_acquisition(
  acquisition : RowKeyedAcquisition,
  nonce : String,
  verify : (RowAttempt) -> Bool,
  ledger : @resources.Ledger,
  transfer_bytes : Int64,
  execution_scratch : Int64,
  cleanup_confirmed : (RowAttempt) -> Bool,
) -> Result[RowRun, RowHostIssue] {
  start_accounted_keyed_row_acquisition_owned(
    acquisition,
    nonce,
    verify,
    ledger,
    transfer_bytes,
    execution_scratch,
    cleanup_confirmed,
    None,
  )
}

///|
// Core Local is the original Host's closed receiver; this is no public Node
// Ledger getter or caller-issued permission. Ordinary acquisition is unchanged.
pub fn start_original_accounted_keyed_row_acquisition(
  acquisition : RowKeyedAcquisition,
  nonce : String,
  verify : (RowAttempt) -> Bool,
  ledger : @resources.Ledger,
  identity : @resources.OriginalLedgerIdentity,
  assembly : @resources.Reservation,
  accepted_children : Int,
  transfer_bytes : Int64,
  execution_scratch : Int64,
  cleanup_confirmed : (RowAttempt) -> Bool,
  prefix? : @resources.Reservation? = None,
) -> Result[RowRun, RowHostIssue] {
  start_accounted_keyed_row_acquisition_owned(
    acquisition,
    nonce,
    verify,
    ledger,
    transfer_bytes,
    execution_scratch,
    cleanup_confirmed,
    Some((ledger, identity, assembly, accepted_children, prefix)),
  )
}

///|
fn start_accounted_keyed_row_acquisition_owned(
  acquisition : RowKeyedAcquisition,
  nonce : String,
  verify : (RowAttempt) -> Bool,
  ledger : @resources.Ledger,
  transfer_bytes : Int64,
  execution_scratch : Int64,
  cleanup_confirmed : (RowAttempt) -> Bool,
  original : (
    @resources.Ledger,
    @resources.OriginalLedgerIdentity,
    @resources.Reservation,
    Int,
    @resources.Reservation?,
  )?,
) -> Result[RowRun, RowHostIssue] {
  if transfer_bytes < 0L || execution_scratch < 0L {
    return Err(Physical(InvalidLimits))
  }
  let run = match
    start_keyed_row_acquisition_owned(acquisition, nonce, verify, original) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // Canonical-wire/workspace budgets, as in ordinary row acquisition, not
  // an allocator/RSS claim. Request, page and identity encoding may overlap.
  let (wire, workspace) = keyed_row_reservation_capacity(acquisition.limits)
  attach_row_reservation(
    run, ledger, transfer_bytes, wire, workspace, execution_scratch,
  ).map(attached => {
    // Successful response evidence and physical stop are different facts.
    // Failure may stop the transport without issuing successful Source evidence.
    attached.physical.unwrap().cleanup_confirmed = Some(() => {
      cleanup_confirmed(attached.attempt)
    })
    attached
  })
}

///|
pub fn begin_keyed_row_run(
  run : RowRun,
  reference_issuer? : @admitted.ReferenceIssuer? = None,
) -> Result[Unit, RowHostIssue] {
  guard !run.closed &&
    run.attempt.state is Pending &&
    run.configuration
    is (KeyedConfiguration(acquisition)
    | OriginalKeyedConfiguration(acquisition)) &&
    run.attempt.preparation is KeyedPreparation(original) &&
    physical_equal(original, acquisition) else {
    return Err(InvalidState)
  }
  if !keyed_acquisition_input_live(acquisition) {
    abort_row_run(run)
    return Err(InvalidState)
  }
  if run.physical is Some(physical) &&
    acquisition.limits.page.max_bytes.to_int64() > physical.execution_scratch {
    return Err(Physical(InvalidCharge))
  }
  let requirement = acquisition.requirement
  match
    begin_declared_keyed_row_read(
      requirement.owner,
      requirement.facts,
      requirement.request,
      acquisition.connector_id,
      acquisition.view,
      acquisition.limits.page,
      acquisition.max_rows,
      acquisition.limits.retention,
      acquisition.limits.request,
      reference_issuer~,
    ) {
    Ok(read) => {
      run.attempt.state = Reading(read)
      Ok(())
    }
    Err(issue) => {
      abort_row_run(run)
      Err(Source(issue))
    }
  }
}

///|
pub fn begin_row_run_keyed_page(
  run : RowRun,
  body : Bytes,
) -> Result[Unit, RowHostIssue] {
  let charge = match charge_row_run_page(run, body) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  begin_charged_row_run_keyed_page(run, charge, body)
}

///|
/// Consume the ticket for this actual provider body once. A driver charging
/// before decoding must not charge it again when bounded admission begins.
pub fn begin_charged_row_run_keyed_page(
  run : RowRun,
  charge : RowPageCharge,
  body : Bytes,
) -> Result[Unit, RowHostIssue] {
  guard run.configuration
    is (KeyedConfiguration(acquisition)
    | OriginalKeyedConfiguration(acquisition)) &&
    keyed_acquisition_input_live(acquisition) else {
    abort_row_run(run)
    return Err(InvalidState)
  }
  match consume_row_page_charge(run, charge) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  guard run.attempt.state is Reading(read) else { return Err(InvalidState) }
  match begin_keyed_row_page(read, body) {
    Ok(_) => Ok(())
    Err(issue) => {
      abort_row_run(run)
      Err(Source(issue))
    }
  }
}

///|
/// The selected declaration's target and exact checked response columns.
/// Provider wire cannot replace either with a self-declared schema.
pub fn keyed_row_acquisition_target(
  acquisition : RowKeyedAcquisition,
) -> Result[(String, Array[String]), RowHostIssue] {
  if !keyed_acquisition_input_live(acquisition) {
    return Err(InvalidState)
  }
  let requirement = acquisition.requirement
  let schema = match
    @query.keyed_response_input_schema(
      requirement.owner,
      @sourcequery.keyed_source_join(requirement.facts),
      requirement.request,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Source(KeyedOwner(issue)))
  }
  Ok(
    (
      acquisition.view.resource,
      Array::makei(@schema.field_count(schema), i => {
        @schema.field_reference_name(@schema.field_at(schema, i).unwrap())
      }),
    ),
  )
}

///|
pub fn advance_row_run_keyed_page(
  run : RowRun,
  quantum : Int,
) -> Result[RowKeyedPagePoll, RowHostIssue] {
  guard !run.closed && run.attempt.state is Reading(read) else {
    return Err(InvalidState)
  }
  guard run.configuration
    is (KeyedConfiguration(acquisition)
    | OriginalKeyedConfiguration(acquisition)) &&
    keyed_acquisition_input_live(acquisition) else {
    abort_row_run(run)
    return Err(InvalidState)
  }
  match advance_keyed_row_page(read, quantum) {
    Ok(value) => Ok(value)
    Err(issue) => {
      abort_row_run(run)
      Err(Source(issue))
    }
  }
}

///|
fn keyed_retention_live(run : RowRun, retained : RowKeyedRetention) -> Bool {
  !run.closed &&
  run.configuration
  is (KeyedConfiguration(acquisition) | OriginalKeyedConfiguration(acquisition)) &&
  keyed_acquisition_input_live(acquisition) &&
  run.issuer is KeyedIssuer(issuer) &&
  run.attempt.authority is KeyedAuthority(authority) &&
  run.attempt.state is KeyedRetained(current) &&
  physical_equal(current, retained) &&
  physical_equal(authority, retained.authority) &&
  physical_equal(authority.issuer, issuer) &&
  @planning.query_evidence_attempt_matches_registration(
    authority.token,
    issuer.registration,
  ) &&
  physical_equal(
    @planning.query_evidence_registration_requirement(issuer.registration),
    retained.requirement,
  ) &&
  @planning.query_evidence_transport_matches(issuer.registration, run.attempt) &&
  @execution.row_wire_matches_captured(retained.measured, retained.rows)
}

///|
pub fn retain_keyed_row_run(
  run : RowRun,
) -> Result[RowKeyedSourceCapture, RowHostIssue] {
  if run.attempt.state is KeyedRetained(retention) {
    if !keyed_retention_live(run, retention) {
      return Err(InvalidState)
    }
    if run.physical is Some(physical) &&
      @resources.reservation_open(physical.reservation) {
      match
        @resources.settle_reservation(physical.ledger, physical.reservation) {
        Ok(_) => ()
        Err(issue) => return Err(Physical(issue))
      }
    }
    return Ok({ run, retention, })
  }
  guard !run.closed &&
    run.configuration
    is (KeyedConfiguration(acquisition)
    | OriginalKeyedConfiguration(acquisition)) &&
    keyed_acquisition_input_live(acquisition) &&
    run.issuer is KeyedIssuer(issuer) &&
    run.attempt.authority is KeyedAuthority(authority) &&
    physical_equal(authority.issuer, issuer) &&
    @planning.query_evidence_attempt_matches_registration(
      authority.token,
      issuer.registration,
    ) &&
    physical_equal(
      @planning.query_evidence_registration_requirement(issuer.registration),
      acquisition.requirement,
    ) &&
    run.attempt.state is AwaitingCleanup(rows) else {
    return Err(InvalidState)
  }
  if !@planning.query_evidence_transport_matches(
      issuer.registration,
      run.attempt,
    ) {
    return Err(Evidence(UnverifiedTransport))
  }
  let measured = match
    @execution.identify_captured_rows(rows, acquisition.limits.wire) {
    Ok(value) => value
    Err(issue) => {
      abort_row_run(run)
      return Err(Evidence(Attempt(Retention(@planning.ScanIdentity(issue)))))
    }
  }
  let retained = {
    authority,
    requirement: acquisition.requirement,
    rows,
    measured,
  }
  if run.physical is Some(physical) {
    let bytes = @execution.row_wire_usage(measured).0.to_int64()
    let holding = match
      @resources.retain_allocation(physical.ledger, physical.reservation, bytes) {
      Ok(value) => value
      Err(issue) => return Err(Physical(issue))
    }
    // Retain the handle before settlement: a failed settle cannot lose custody
    // or allow a retry to reserve the same response a second time.
    physical.holding = Some(holding)
    run.attempt.state = KeyedRetained(retained)
    match @resources.settle_reservation(physical.ledger, physical.reservation) {
      Ok(_) => ()
      Err(issue) => return Err(Physical(issue))
    }
  } else {
    run.attempt.state = KeyedRetained(retained)
  }
  Ok({ run, retention: retained, })
}

///|
fn keyed_acquisition_input_live(acquisition : RowKeyedAcquisition) -> Bool {
  match acquisition.input_available {
    None => true
    Some(available) => available()
  }
}

///|
/// Borrow the exact retained right port through the existing supplied-input
/// reader. Its liveness checks issuer, original request, physical settlement
/// and retained rows on every access; no raw captured-row getter is exposed.
pub fn keyed_row_capture_read(
  capture : RowKeyedSourceCapture,
) -> Result[@execution.SuppliedRelationRead, RowHostIssue] {
  let retained = capture.retention
  let run = capture.run
  if !keyed_retention_live(run, retained) {
    return Err(InvalidState)
  }
  let index = match
    @query.keyed_response_input_index(
      retained.requirement.owner,
      @sourcequery.keyed_source_join(retained.requirement.facts),
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidState)
  }
  @execution.prepare_supplied_relation_read(
    retained.requirement.owner,
    index,
    retained.rows,
    () => keyed_retention_live(run, retained),
  ).map_err(_ => InvalidState)
}

///|
/// Return the existing measured ordered-row identity only while its original
/// request, transport evidence and holding remain live. This is not whole-set
/// Source evidence, a physical byte digest or a replacement input owner.
pub fn keyed_row_capture_identity(
  capture : RowKeyedSourceCapture,
) -> Result[@execution.RowWireIdentity, RowHostIssue] {
  if !keyed_retention_live(capture.run, capture.retention) {
    return Err(InvalidState)
  }
  Ok(capture.retention.measured)
}

///|
/// The assembly accepts only a successful capture of this exact opaque
/// Request, not another key with the same declared response schema.
pub fn keyed_row_capture_matches_request(
  capture : RowKeyedSourceCapture,
  request : @sourcequery.KeyedRowRequest,
) -> Bool {
  keyed_retention_live(capture.run, capture.retention) &&
  physical_equal(capture.retention.requirement.request, request)
}
