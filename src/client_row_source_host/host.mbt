// The common runtime's provider-neutral installed row source: what the
// standard Host calls for a connector that publishes a row declaration and
// pushes JSON pages. No provider type, name or package appears here.

///|
pub(all) enum RowHostIssue {
  InvalidSpecification
  Declaration(RowDeclarationIssue)
  ForeignDeclaration
  Source(RowSourceIssue)
  InvalidContracts
  Registration
  Candidate
  Selection
  Evidence(RowEvidenceIssue)
  Attempt(RowAttemptIssue)
  Consumer(@query.CapturedSourceIssue)
  SourceEvidence(RowSourceEvidenceIssue)
  Physical(@resources.LedgerIssue)
  InvalidState
}

///|
fn spec_text(value : Json, key : String) -> String? {
  match value {
    Object(entries) =>
      match entries.get(key) {
        Some(String(text)) => Some(text)
        _ => None
      }
    _ => None
  }
}

///|
/// Parse a connector's view specification:
/// `{"views":[{"resource","resource_kind","fields":[{"name","type","nullable"}]}]}`.
fn parse_row_views(text : String) -> Array[RowViewSpec]? {
  let parsed = @json.parse(text) catch { _ => return None }
  guard parsed is Object(root) &&
    root.length() == 1 &&
    root.get("views") is Some(Array(views)) else {
    return None
  }
  let specs = []
  for view in views {
    guard view is Object(entries) &&
      entries.length() == 3 &&
      spec_text(view, "resource") is Some(resource) &&
      spec_text(view, "resource_kind") is Some(resource_kind) &&
      entries.get("fields") is Some(Array(fields)) else {
      return None
    }
    let declared = []
    for field in fields {
      guard field is Object(members) &&
        members.length() == 3 &&
        spec_text(field, "name") is Some(name) &&
        spec_text(field, "type") is Some(value_type) &&
        members.get("nullable") is Some(nullable) else {
        return None
      }
      let flag = match nullable {
        True => true
        False => false
        _ => return None
      }
      declared.push({ name, value_type, nullable: flag, })
    }
    specs.push({ resource, resource_kind, fields: declared, })
  }
  Some(specs)
}

///|
let declaration_limits : RowDeclarationLimits = {
  max_bytes: 4000000,
  max_nodes: 400000,
  max_depth: 64,
  max_views: 64,
  max_fields: 200,
}

///|
/// Generate the declaration of an installed connector's views. With an
/// expected Catalog CID (a restore of a published generation), the runtime's
/// own generation must reproduce it exactly.
pub fn restore_row_declaration(
  connector_id : String,
  connector_registration : String,
  connector_version : String,
  views_json : String,
  expected_catalog_cid : String?,
) -> Result[RowDeclaration, RowHostIssue] {
  guard parse_row_views(views_json) is Some(views) else {
    return Err(InvalidSpecification)
  }
  let declaration = match
    generate_row_declaration(
      connector_id, connector_registration, connector_version, views, declaration_limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Declaration(issue))
  }
  if expected_catalog_cid is Some(expected) &&
    expected != declaration.catalog_cid {
    return Err(ForeignDeclaration)
  }
  Ok(declaration)
}

///|
pub fn row_declaration_catalog_cid(declaration : RowDeclaration) -> String {
  declaration.catalog_cid
}

///|
/// The declared Resource and fields a checked requirement reads, or an
/// undeclared-source refusal.
pub fn row_source_target(
  declaration : RowDeclaration,
  requirement : @planning.QueryRequirement,
) -> Result[(String, Array[String]), RowHostIssue] {
  let source_ref = @planning.query_requirement_source(requirement).0
  match row_declaration_view(declaration, source_ref) {
    Some(view) => Ok((view.resource, view.fields.copy()))
    None => Err(Source(UndeclaredSource))
  }
}

///|
priv struct RowHostConfiguration {
  contracts : @planning.QueryEvidenceContracts
  requirement : @planning.QueryRequirement
  choice : @planning.AcquisitionChoice
  candidate : @planning.PreparedAcquisition[RowSourcePreparation]
  limits : RowCompletionLimits
}

///|
/// One selected row acquisition for a checked source. Physical transport
/// starts only with `start_row_acquisition`.
struct RowAcquisition {
  preparation : RowSourcePreparation
  configuration : RowHostConfiguration
  context : RowSourceEvidenceContext
}

///|
fn admit_contract(body : String) -> @identity.CanonicalValue? {
  Some(@identity.from_json(@json.parse(body), 10000, 100, 100000)) catch {
    _ => None
  }
}

///|
pub fn prepare_row_acquisition(
  declaration : RowDeclaration,
  requirement : @planning.QueryRequirement,
  query_contract_body : String,
  evidence_contract_body : String,
) -> Result[RowAcquisition, RowHostIssue] {
  let preparation = match prepare_row_source(requirement, declaration) {
    Ok(value) => value
    Err(issue) => return Err(Source(issue))
  }
  prepare_declared_row_acquisition(
    preparation,
    declaration.connector_registration,
    query_contract_body,
    evidence_contract_body,
  )
}

///|
/// The common selection/custody owner for either a generated neutral view or
/// an existing provider declaration already bound to the checked requirement.
pub fn prepare_declared_row_acquisition(
  preparation : RowSourcePreparation,
  connector_registration : String,
  query_contract_body : String,
  evidence_contract_body : String,
) -> Result[RowAcquisition, RowHostIssue] {
  let requirement = preparation.requirement
  guard admit_contract(query_contract_body) is Some(query_contract) &&
    admit_contract(evidence_contract_body) is Some(evidence_contract) &&
    @planning.admit_query_evidence_contracts(
      query_contract,
      evidence_contract,
      { max_bytes: 100000, max_nodes: 10000, max_depth: 100, },
    )
    is Ok(contracts) else {
    return Err(InvalidContracts)
  }
  guard @connector.prepare_capability_registry(
      [
        {
          name: connector_registration,
          acquisition: true,
          fixed_compute: false,
          effect: false,
        },
      ],
      1,
      64,
    )
    is Ok(registry) &&
    @connector.capability_registration_at(registry, 0) is Some(registration) else {
    return Err(Registration)
  }
  guard @cost.assess_serial(
      8,
      [{ work_slots: [0, 1, 2, 3, 4, 5, 6, 7], milliseconds: Some(10L), }],
      100,
    )
    is Ok(duration) &&
    @planning.bind_acquisition_candidate(
      registration,
      requirement,
      preparation,
      duration,
      { transfer_bytes: None, retained_bytes: None, money_units: None, },
    )
    is Ok(candidate) else {
    return Err(Candidate)
  }
  guard @planning.choose_acquisition_candidate(
      registry,
      requirement,
      [@planning.prepared_acquisition_candidate(candidate)],
      None,
      100,
    )
    is Ok(@planning.Proposed(choice)) else {
    return Err(Selection)
  }
  let context = match prepare_row_source_evidence_context(requirement) {
    Ok(value) => value
    Err(issue) => return Err(SourceEvidence(issue))
  }
  // The residual filter and capture measure every captured value; the
  // capture holds at most 500 KB of text, what the standard Host's Local
  // fragments evaluate at once.
  let values : @execution.ValueLimits = {
    max_nodes: 100000,
    max_text_bytes: 500000,
    max_depth: 100,
    max_work: 20000000,
  }
  Ok({
    preparation,
    configuration: {
      contracts,
      requirement,
      choice,
      candidate,
      limits: {
        execution: {
          rows: {
            max_rows: 100,
            metadata_entries: 10000,
            retained_entries: 10000,
            operation_entries: 10000,
            input_values: values,
            output_values: values,
          },
          max_work: 50000000,
          max_frames: 100,
        },
        guards: {
          max_work: 50000000,
          max_bytes: 1000000,
          max_nodes: 100000,
          max_depth: 100,
        },
        retention: {
          received_wire_bytes: 4000000,
          retained_wire_bytes: 4000000,
          measurement: {
            max_columns: 100,
            max_order_work: 100000,
            max_bytes: 4000000,
            max_nodes: 100000,
            max_depth: 100,
          },
        },
        records: {
          max_work: 1000000,
          max_fields: 100,
          max_parameters: 100,
          max_bytes: 1000000,
          max_nodes: 100000,
          max_depth: 100,
        },
        capture: { max_bytes: 1000000, max_nodes: 100000, max_depth: 100, },
      },
    },
    context,
  })
}

///|
/// The declared Resource and the checked input's columns, in order: what the
/// Site driver must put in every row of every page.
pub fn row_acquisition_columns(value : RowAcquisition) -> Array[String] {
  value.preparation.columns.copy()
}

///|
/// The selected capture's canonical row-wire allowance. This is an upper
/// bound for the simultaneously retained scan and output, not a heap estimate.
pub fn row_acquisition_retained_capacity(value : RowAcquisition) -> Int64 {
  value.configuration.limits.retention.retained_wire_bytes.to_int64()
}

///|
/// The selected capture's bounded parse, residual and evidence allowance.
pub fn row_acquisition_execution_capacity(value : RowAcquisition) -> Int64 {
  let limits = value.configuration.limits
  (limits.retention.received_wire_bytes +
  limits.retention.retained_wire_bytes +
  limits.records.max_bytes +
  limits.capture.max_bytes).to_int64()
}

///|
pub fn row_acquisition_requirement(
  value : RowAcquisition,
) -> @planning.QueryRequirement {
  value.preparation.requirement
}

///|
struct RowRun {
  configuration : RowHostConfiguration
  issuer : RowIssuer
  attempt : RowAttempt
  mut closed : Bool
  mut physical : RowPhysical?
  mut page_charge : RowPageCharge?
}

///|
/// One page charged before provider decoding, owned by its exact live attempt.
/// Admission consumes this ticket once; it carries no parallel resource owner.
struct RowPageCharge {
  owner : RowAttempt
  mut consumed : Bool
}

///|
priv struct RowPhysical {
  ledger : @resources.Ledger
  reservation : @resources.Reservation
  execution_scratch : Int64
  mut holding : @resources.Holding?
  mut dag : (@strategy.CapturedDAG, Int)?
}

///|
/// Register the issuer and reserve the selected attempt. `verify` confirms
/// that the exact attempt's physical transport has settled.
pub fn start_row_acquisition(
  value : RowAcquisition,
  nonce : String,
  verify : (RowAttempt) -> Bool,
) -> Result[RowRun, RowHostIssue] {
  let configuration = value.configuration
  let issuer : RowIssuer = match
    @planning.register_query_evidence_issuer(
      configuration.contracts,
      configuration.requirement,
      nonce,
      128,
      "row-source-issuer",
      verify,
    ) {
    Ok(registration) => { registration, }
    Err(issue) => return Err(Evidence(custody_issue(issue)))
  }
  let (preparation, token) = match
    @planning.reserve_selected_query_evidence_attempt(
      issuer.registration,
      configuration.choice,
      configuration.candidate,
      preparation => preparation.requirement,
    ) {
    Ok(value) => value
    Err(issue) => {
      @planning.close_query_evidence_registration(issuer.registration)
      return Err(Evidence(custody_issue(issue)))
    }
  }
  Ok({
    configuration,
    issuer,
    attempt: { preparation, authority: { issuer, token, }, state: Pending, },
    closed: false,
    physical: None,
    page_charge: None,
  })
}

///|
/// Reserve the checked row capture before the Site starts its read. The
/// physical page bound is charged separately from the canonical row budget.
pub fn start_accounted_row_acquisition(
  value : RowAcquisition,
  nonce : String,
  verify : (RowAttempt) -> Bool,
  ledger : @resources.Ledger,
  transfer_bytes : Int64,
  execution_scratch : Int64,
) -> Result[RowRun, RowHostIssue] {
  if transfer_bytes < 0L ||
    execution_scratch < 0L ||
    execution_scratch >
    9223372036854775807L - row_acquisition_execution_capacity(value) {
    return Err(Physical(InvalidLimits))
  }
  let run = match start_row_acquisition(value, nonce, verify) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let reservation = match
    @resources.reserve_attempt(
      ledger,
      transfer_bytes,
      row_acquisition_retained_capacity(value),
      row_acquisition_execution_capacity(value) + execution_scratch,
    ) {
    Ok(value) => value
    Err(issue) => {
      close_row_run(run)
      return Err(Physical(issue))
    }
  }
  run.physical = Some({
    ledger,
    reservation,
    execution_scratch,
    holding: None,
    dag: None,
  })
  Ok(run)
}

///|
pub fn row_run_attempt(run : RowRun) -> RowAttempt {
  run.attempt
}

///|
/// Open admission for the attempt's pages.
pub fn begin_row_run(
  run : RowRun,
  max_page_bytes : Int,
  max_page_rows : Int,
  max_capture_rows : Int,
) -> Result[Unit, RowHostIssue] {
  if run.closed {
    return Err(InvalidState)
  }
  if run.physical is Some(physical) &&
    max_page_bytes.to_int64() > physical.execution_scratch {
    return Err(Physical(InvalidCharge))
  }
  let attempt = run.attempt
  guard attempt.state is Pending else { return Err(InvalidState) }
  match
    begin_row_source_read(
      attempt.preparation,
      {
        max_bytes: max_page_bytes,
        max_nodes: 400000,
        max_depth: 32,
        max_rows: max_page_rows,
      },
      max_capture_rows,
      {
        max_nodes: 100000,
        max_text_bytes: 500000,
        max_depth: 100,
        max_work: 20000000,
      },
    ) {
    Ok(read) => {
      attempt.state = Reading(read)
      Ok(())
    }
    Err(issue) => {
      abort_row_attempt(attempt)
      Err(Source(issue))
    }
  }
}

///|
/// Account for the actual received provider body before decoding it. A pending
/// ticket must be admitted before another body is charged or the read finishes.
/// Ordinary runs enforce the same page bound without a physical reservation.
pub fn charge_row_run_page(
  run : RowRun,
  body : Bytes,
) -> Result[RowPageCharge, RowHostIssue] {
  guard !run.closed && run.attempt.state is Reading(read) else {
    return Err(InvalidState)
  }
  if run.page_charge is Some(_) {
    abort_row_run(run)
    return Err(Physical(InvalidCharge))
  }
  if run.physical is Some(physical) {
    match
      @resources.charge_transfer(
        physical.ledger,
        physical.reservation,
        body.length().to_int64(),
      ) {
      Ok(_) => ()
      Err(issue) => {
        abort_row_run(run)
        return Err(Physical(issue))
      }
    }
  }
  if body.length() > read.page_limits.max_bytes {
    abort_row_run(run)
    return Err(Source(InvalidPage))
  }
  let charge = { owner: run.attempt, consumed: false, }
  run.page_charge = Some(charge)
  Ok(charge)
}

///|
fn consume_row_page_charge(
  run : RowRun,
  charge : RowPageCharge,
) -> Result[Unit, RowHostIssue] {
  guard !run.closed && run.attempt.state is Reading(_) else {
    return Err(InvalidState)
  }
  if !physical_equal(charge.owner, run.attempt) {
    abort_row_run(run)
    return Err(Physical(ForeignOwner))
  }
  guard !charge.consumed &&
    run.page_charge is Some(expected) &&
    physical_equal(expected, charge) else {
    abort_row_run(run)
    return Err(Physical(InvalidCharge))
  }
  charge.consumed = true
  run.page_charge = None
  Ok(())
}

///|
/// Admit one JSON page with exactly one charge of its actual received bytes.
/// A refused page aborts the attempt.
pub fn accept_row_run_page(
  run : RowRun,
  bytes : Bytes,
) -> Result[Int, RowHostIssue] {
  guard !run.closed && run.attempt.state is Reading(read) else {
    return Err(InvalidState)
  }
  let charge = match charge_row_run_page(run, bytes) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match consume_row_page_charge(run, charge) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match accept_row_source_page(read, bytes) {
    Ok(count) => Ok(count)
    Err(issue) => {
      abort_row_run(run)
      Err(Source(issue))
    }
  }
}

///|
/// The driver read every page the provider stated: close admission. The
/// attempt then awaits settlement of its physical transport.
pub fn finish_row_run(run : RowRun) -> Result[Unit, RowHostIssue] {
  guard !run.closed && run.attempt.state is Reading(read) else {
    return Err(InvalidState)
  }
  if run.page_charge is Some(_) {
    abort_row_run(run)
    return Err(Physical(InvalidCharge))
  }
  match finish_row_source_read(read) {
    Ok(scan) => {
      run.attempt.state = AwaitingCleanup(scan)
      Ok(())
    }
    Err(issue) => {
      abort_row_attempt(run.attempt)
      Err(Source(issue))
    }
  }
}

///|
pub fn abort_row_run(run : RowRun) -> Unit {
  if run.page_charge is Some(charge) {
    charge.consumed = true
    run.page_charge = None
  }
  abort_row_attempt(run.attempt)
}

///|
pub fn close_row_run(run : RowRun) -> Unit {
  if !run.closed {
    abort_row_run(run)
    @planning.close_query_evidence_registration(run.issuer.registration)
    run.closed = true
  }
}

///|
/// Stop the accounted source first, then release only the resources still
/// owned by this issuer. A transferred DAG allocation remains with its task.
pub fn close_accounted_row_run(run : RowRun) -> Result[Unit, RowHostIssue] {
  guard run.physical is Some(physical) else { return Err(InvalidState) }
  close_row_run(run)
  if physical.dag is Some((dag, task)) {
    @strategy.close_captured_task_output(dag, task)
    @strategy.refresh_captured_retention(dag)
  }
  if physical.holding is Some(holding) {
    match @resources.release_allocation(physical.ledger, holding) {
      Ok(_) => physical.holding = None
      Err(issue) => return Err(Physical(issue))
    }
  }
  if @resources.reservation_open(physical.reservation) {
    match @resources.settle_reservation(physical.ledger, physical.reservation) {
      Ok(_) => ()
      Err(issue) => return Err(Physical(issue))
    }
  }
  Ok(())
}

///|
/// One exact completed observation and its live captured source.
struct RowSourceCapture {
  run : RowRun
  observation : RowObservation
  source : @query.CapturedInputSource
}

///|
pub fn capture_row_run(run : RowRun) -> Result[RowSourceCapture, RowHostIssue] {
  if run.closed {
    return Err(InvalidState)
  }
  let observation = match
    complete_row_capture(run.issuer, run.attempt, run.configuration.limits) {
    Ok(value) => value
    Err(issue) => return Err(Evidence(issue))
  }
  let source = match row_captured_source(run.issuer, run.attempt, observation) {
    Ok(value) => value
    Err(issue) => return Err(Consumer(issue))
  }
  if run.physical is Some(physical) {
    let bytes = observation.records.retention.measured.retained_bytes.to_int64()
    let holding = match
      @resources.retain_allocation(physical.ledger, physical.reservation, bytes) {
      Ok(value) => value
      Err(issue) => return Err(Physical(issue))
    }
    physical.holding = Some(holding)
    match @resources.settle_reservation(physical.ledger, physical.reservation) {
      Ok(_) => ()
      Err(issue) => return Err(Physical(issue))
    }
  }
  Ok({ run, observation, source, })
}

///|
/// Transfer the exact captured input and allocation to its checked task.
pub fn retain_row_capture_task(
  capture : RowSourceCapture,
  dag : @strategy.CapturedDAG,
  task : Int,
) -> Result[Unit, RowHostIssue] {
  let run = capture.run
  guard !run.closed &&
    run.physical is Some(physical) &&
    physical.holding is Some(holding) &&
    physical.dag is None &&
    physical_equal(physical.ledger, @strategy.captured_dag_ledger(dag)) &&
    @strategy.captured_task_source_matches(dag, task, capture.source) else {
    return Err(Physical(ForeignOwner))
  }
  match
    @strategy.retain_captured_task_allocation(dag, task, holding, release_confirmed=fn() {
      run.closed
    }) {
    Ok(_) => ()
    Err(issue) => return Err(Physical(issue))
  }
  physical.dag = Some((dag, task))
  physical.holding = None
  Ok(())
}

///|
pub fn row_capture_source(
  capture : RowSourceCapture,
) -> Result[@query.CapturedInputSource, @query.CapturedSourceIssue] {
  if capture.run.closed || !@query.captured_source_available(capture.source) {
    return Err(Unavailable)
  }
  Ok(capture.source)
}

///|
/// Compatibility handoff for unaccounted typed rows. Accounted providers must
/// charge their actual response body before decoding and consume its ticket.
pub fn accept_row_run_values(
  run : RowRun,
  columns : Array[String],
  rows : Array[Array[@admitted.CheckedValue]],
) -> Result[Int, RowHostIssue] {
  guard !run.closed && run.attempt.state is Reading(read) else {
    return Err(InvalidState)
  }
  if run.physical is Some(_) || run.page_charge is Some(_) {
    abort_row_run(run)
    return Err(Physical(InvalidCharge))
  }
  match accept_row_source_values(read, columns, rows) {
    Ok(count) => Ok(count)
    Err(issue) => {
      abort_row_run(run)
      Err(Source(issue))
    }
  }
}

///|
/// Admit the typed values of one previously charged provider body. Ownership
/// and single consumption are checked before retaining any value.
pub fn accept_charged_row_run_values(
  run : RowRun,
  charge : RowPageCharge,
  columns : Array[String],
  rows : Array[Array[@admitted.CheckedValue]],
) -> Result[Int, RowHostIssue] {
  guard !run.closed && run.attempt.state is Reading(read) else {
    return Err(InvalidState)
  }
  match consume_row_page_charge(run, charge) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match accept_row_source_values(read, columns, rows) {
    Ok(count) => Ok(count)
    Err(issue) => {
      abort_row_run(run)
      Err(Source(issue))
    }
  }
}
