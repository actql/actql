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
  Residual(@connector.FixedComputeIssue)
  ResidualWork(@local.ManagedProviderWorkIssue)
  InputValidationWork(@bounded.Issue)
  InputKeys(@execution.InputKeyIssue)
  InputScores(@execution.InputScoreIssue)
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
  choice : @planning.AcquisitionChoice[@planning.QueryRequirement]
  candidate : @planning.PreparedAcquisition[
    @planning.QueryRequirement,
    RowSourcePreparation,
  ]
  limits : RowCompletionLimits
  listing_rows : RowListingRows?
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
  Some(
    @identity.from_json(
      @json.parse(body),
      row_contract_nodes,
      row_contract_depth,
      row_contract_input_utf16,
    ),
  ) catch {
    _ => None
  }
}

///|
/// Admit the same protocol bodies once under the installing Source's original
/// constructor reservation. This immutable DATA is neither an acquisition nor
/// a read grant; the Source material retains its actual backing across Requests.
pub fn admit_row_acquisition_contracts(
  query_contract_body : String,
  evidence_contract_body : String,
) -> Result[@planning.QueryEvidenceContracts, RowHostIssue] {
  guard admit_contract(query_contract_body) is Some(query_contract) &&
    admit_contract(evidence_contract_body) is Some(evidence_contract) &&
    @planning.admit_query_evidence_contracts(
      query_contract, evidence_contract, row_contract_emit_limits,
    )
    is Ok(contracts) else {
    return Err(InvalidContracts)
  }
  Ok(contracts)
}

///|
pub fn prepare_row_acquisition(
  declaration : RowDeclaration,
  requirement : @planning.QueryRequirement,
  query_contract_body : String,
  evidence_contract_body : String,
  listing_policy? : @capacity.Policy? = None,
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
    listing_policy~,
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
  listing_policy? : @capacity.Policy? = None,
) -> Result[RowAcquisition, RowHostIssue] {
  let listing_rows = match
    resolve_row_listing_rows(preparation, listing_policy) {
    Ok(value) => value
    Err(issue) => return Err(Source(issue))
  }
  let contracts = match
    admit_row_acquisition_contracts(query_contract_body, evidence_contract_body) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  prepare_row_acquisition_owned(
    preparation, connector_registration, contracts, listing_rows,
  )
}

///|
/// Consume the retained admitted protocol original. Selection, listing policy,
/// candidate, Source evidence and later physical/current checks are unchanged.
pub fn prepare_declared_row_acquisition_with_contracts(
  preparation : RowSourcePreparation,
  connector_registration : String,
  contracts : @planning.QueryEvidenceContracts,
  listing_policy? : @capacity.Policy? = None,
) -> Result[RowAcquisition, RowHostIssue] {
  let listing_rows = match
    resolve_row_listing_rows(preparation, listing_policy) {
    Ok(value) => value
    Err(issue) => return Err(Source(issue))
  }
  prepare_row_acquisition_owned(
    preparation, connector_registration, contracts, listing_rows,
  )
}

///|
fn prepare_row_acquisition_owned(
  preparation : RowSourcePreparation,
  connector_registration : String,
  contracts : @planning.QueryEvidenceContracts,
  listing_rows : RowListingRows?,
) -> Result[RowAcquisition, RowHostIssue] {
  let requirement = preparation.requirement
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
      listing_rows,
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
/// The selected Source's actual parameter-bound Request. It is not a separate
/// selector interpretation, new authority or proof of acquisition completion.
pub fn row_acquisition_request_wire(
  value : RowAcquisition,
) -> Result[String, RowHostIssue] {
  let limits = value.configuration.limits.records
  @sourcequery.parameterized_request_wire(
    value.preparation.request,
    limits.max_bytes,
    limits.max_nodes,
    limits.max_depth,
  ).map_err(issue => Source(RequestEncoding(issue)))
}

///|
/// The selected capture's canonical row-wire allowance. This is an upper
/// bound for the simultaneously retained scan and output, not a heap estimate.
pub fn row_acquisition_retained_capacity(value : RowAcquisition) -> Int64 {
  let (original, _) = row_original_input_capacity()
  value.configuration.limits.retention.retained_wire_bytes.to_int64() + original
}

///|
/// The selected capture's bounded parse, residual and evidence allowance.
pub fn row_acquisition_execution_capacity(value : RowAcquisition) -> Int64 {
  let limits = value.configuration.limits
  let (_, original) = row_original_input_capacity()
  (limits.retention.received_wire_bytes +
  limits.retention.retained_wire_bytes +
  // The parameter-bound driver Request stays live through transport and may
  // overlap the completion/evidence record writer. Reserve both before I/O.
  limits.records.max_bytes +
  limits.records.max_bytes +
  limits.capture.max_bytes).to_int64() +
  (if value.configuration.listing_rows is Some(rows) {
    // The immutable witness/limit records, parsed claims and admission writer
    // can overlap. Reserve their bounded representations before transport.
    @environment.file_listing_rows_record_capacity(
      listing_rows_resolution(rows),
    )
  } else {
    0L
  }) +
  original
}

///|
pub fn row_acquisition_requirement(
  value : RowAcquisition,
) -> @planning.QueryRequirement {
  value.preparation.requirement
}

///|
/// The selected Catalog declaration, not a driver-supplied listing flag.
pub fn row_acquisition_is_listing(value : RowAcquisition) -> Bool {
  value.preparation.file_listing is Some(_)
}

///|
/// Includes the typed empty exact-path selection before any Site request.
pub fn row_run_listing_complete(run : RowRun) -> Bool {
  !run.closed &&
  run.attempt.state is Reading(read) &&
  read.listing is Some(progress) &&
  progress.complete
}

///|
struct RowRun {
  configuration : RowRunConfiguration
  issuer : RowRunIssuer
  attempt : RowAttempt
  mut closed : Bool
  mut physical : RowPhysical?
  mut page_charge : RowPageCharge?
  mut response_borrowed : Bool
  input_progress : RowInputProgress?
  mut residual : RowCaptureResidual?
}

///|
priv enum RowRunConfiguration {
  DirectConfiguration(RowHostConfiguration)
  InputConfiguration(RowInputAcquisition)
  KeyedConfiguration(RowKeyedAcquisition)
  // Same Row owner and payload shape; only this checked receiver installs
  // original Scope liveness that must be detached after actual physical close.
  OriginalKeyedConfiguration(RowKeyedAcquisition)
}

///|
priv enum RowRunIssuer {
  DirectIssuer(RowIssuer)
  InputIssuer(RowInputIssuer)
  KeyedIssuer(RowKeyedIssuer)
}

///|
/// One page charged before provider decoding, owned by its exact live attempt.
/// Admission consumes this ticket once; it carries no parallel resource owner.
struct RowPageCharge {
  owner : RowAttempt
  mut received_bytes : Int64
  mut consumed : Bool
}

///|
priv struct RowPhysical {
  ledger : @resources.Ledger
  reservation : @resources.Reservation
  execution_scratch : Int64
  // Supplementary provider backing stays in this original reservation through
  // capture and the reader's real cleanup, never in a separately issued loan.
  mut provider_capacity : @execution.ExecutionCapacity?
  mut holding : @resources.Holding?
  mut dag : (@strategy.CapturedDAG, Int)?
  // Keep keyed transport cleanup authority after invalidating issuer access.
  mut cleanup_confirmed : (() -> Bool)?
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
    configuration: DirectConfiguration(configuration),
    issuer: DirectIssuer(issuer),
    attempt: {
      preparation: DirectPreparation(preparation),
      authority: DirectAuthority({ issuer, token, }),
      state: Pending,
    },
    closed: false,
    physical: None,
    page_charge: None,
    response_borrowed: false,
    input_progress: None,
    residual: None,
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
  // Preserve the ordinary resolved listing profile and its existing allowance.
  // The additional report profile is selected only by the dedicated accounted
  // entry. An ordinary caller cannot infer that envelope or adopt its payload.
  if value.configuration.listing_rows is Some(ReportListingRows(_, _)) {
    return Err(Physical(InvalidLimits))
  }
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
  attach_row_reservation(
    run,
    ledger,
    transfer_bytes,
    row_acquisition_retained_capacity(value),
    row_acquisition_execution_capacity(value),
    execution_scratch,
  )
}

///|
/// Both checked acquisition profiles attach to this same reservation and
/// cleanup owner. No profile has a second transfer/retention ledger.
fn attach_row_reservation(
  run : RowRun,
  ledger : @resources.Ledger,
  transfer_bytes : Int64,
  retained_bytes : Int64,
  execution_bytes : Int64,
  execution_scratch : Int64,
) -> Result[RowRun, RowHostIssue] {
  if transfer_bytes < 0L ||
    retained_bytes < 0L ||
    execution_bytes < 0L ||
    execution_scratch < 0L ||
    execution_scratch > 9223372036854775807L - execution_bytes {
    close_row_run(run)
    return Err(Physical(InvalidLimits))
  }
  let reservation = match
    @resources.reserve_attempt(
      ledger,
      transfer_bytes,
      retained_bytes,
      execution_bytes + execution_scratch,
      quantities=@resources.quantity_neutral_amounts(ledger),
    ) {
    Ok(value) => value
    Err(issue) => {
      close_row_run(run)
      return Err(Physical(issue))
    }
  }
  install_row_reservation(run, ledger, reservation, execution_scratch)
  Ok(run)
}

///|
// Install only a reservation issued by the same caller's Source Ledger.
// The listing entry has already reserved before allocating its attempt.
fn install_row_reservation(
  run : RowRun,
  ledger : @resources.Ledger,
  reservation : @resources.Reservation,
  execution_scratch : Int64,
  provider_capacity? : @execution.ExecutionCapacity? = None,
) -> Unit {
  run.physical = Some({
    ledger,
    reservation,
    execution_scratch,
    provider_capacity,
    holding: None,
    dag: None,
    cleanup_confirmed: None,
  })
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
  reference_issuer? : @admitted.ReferenceIssuer? = None,
) -> Result[Unit, RowHostIssue] {
  begin_row_run_with_page_limits(
    run,
    {
      max_bytes: max_page_bytes,
      max_nodes: 400000,
      max_depth: 32,
      max_rows: max_page_rows,
    },
    max_capture_rows,
    reference_issuer~,
  )
}

///|
/// Narrow the standard page envelope for this same original RowRun. The
/// installed Host must bind these DATA limits to its actual Source original;
/// neither the limits nor this admission supplies capacity or permission.
pub fn begin_row_run_with_page_limits(
  run : RowRun,
  page_limits : RowPageLimits,
  max_capture_rows : Int,
  reference_issuer? : @admitted.ReferenceIssuer? = None,
) -> Result[Unit, RowHostIssue] {
  if run.closed {
    return Err(InvalidState)
  }
  if run.configuration is InputConfiguration(acquisition) {
    return begin_input_row_run(
      run, acquisition, page_limits, max_capture_rows, reference_issuer,
    )
  }
  if run.physical is Some(physical) &&
    page_limits.max_bytes.to_int64() > physical.execution_scratch {
    return Err(Physical(InvalidCharge))
  }
  let attempt = run.attempt
  guard attempt.state is Pending &&
    attempt.preparation is DirectPreparation(preparation) &&
    run.configuration is DirectConfiguration(configuration) else {
    return Err(InvalidState)
  }
  if page_limits.max_nodes > 400000 || page_limits.max_depth > 32 {
    abort_row_attempt(attempt)
    return Err(Source(InvalidPage))
  }
  match
    begin_row_source_read(
      preparation,
      page_limits,
      max_capture_rows,
      {
        max_nodes: 100000,
        max_text_bytes: 500000,
        max_depth: 100,
        max_work: 20000000,
      },
      reference_issuer~,
      listing_rows=configuration.listing_rows,
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
  if !row_provider_cleanup_bound(run) {
    return Err(Evidence(UnverifiedTransport))
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
  let charge = {
    owner: run.attempt,
    received_bytes: body.length().to_int64(),
    consumed: false,
  }
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
/// Consume one original physical-response charge without inventing a data
/// page. The installer still owns the operation's authorization, request count
/// and observation semantics. No row, Source completion, permission or cleanup
/// ACK is issued here; actual transfer stays charged to this same RowRun Ledger.
pub fn consume_row_run_observation_charge(
  run : RowRun,
  charge : RowPageCharge,
) -> Result[Unit, RowHostIssue] {
  if run.physical is None {
    return Err(InvalidState)
  }
  consume_row_page_charge(run, charge)
}

///|
/// Admit one JSON page with exactly one charge of its actual received bytes.
/// A refused page aborts the attempt.
pub fn accept_row_run_page(
  run : RowRun,
  bytes : Bytes,
) -> Result[Int, RowHostIssue] {
  let charge = match charge_row_run_page(run, bytes) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  accept_charged_row_run_page(run, charge, bytes)
}

///|
/// Admit completed projected JSON rows with this attempt's final response ticket.
/// A dependent multi-response reader must consume earlier tickets as observations
/// before the next exchange, while its original owner retains and validates the
/// complete request/response/row prefix. The ticket supplies accounting only,
/// never that correspondence, current authority or physical retirement.
/// Consume it once without charging projected output as another network body.
pub fn accept_charged_row_run_page(
  run : RowRun,
  charge : RowPageCharge,
  bytes : Bytes,
) -> Result[Int, RowHostIssue] {
  guard !run.closed && run.attempt.state is Reading(read) else {
    return Err(InvalidState)
  }
  match consume_row_page_charge(run, charge) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let parsed = if run.configuration is InputConfiguration(_) &&
    run.physical is Some(_) {
    match prepare_row_input_page(run, read, bytes) {
      Ok(value) => Some(value)
      Err(issue) => {
        abort_row_run(run)
        return Err(issue)
      }
    }
  } else {
    None
  }
  match accept_row_source_page(read, bytes, parsed~) {
    Ok(count) => Ok(count)
    Err(issue) => {
      abort_row_run(run)
      Err(Source(issue))
    }
  }
}

///|
/// Record an actual listing request before dispatch. A retry is another attempt
/// on the same read and cannot reset its cumulative counters or cursor.
pub fn begin_row_run_listing_request(
  run : RowRun,
  token : String?,
  elapsed_ms : Int64,
) -> Result[Unit, RowHostIssue] {
  guard !run.closed && run.attempt.state is Reading(read) else {
    return Err(InvalidState)
  }
  match begin_row_listing_request(read, token, elapsed_ms) {
    Ok(_) => Ok(())
    Err(issue) => {
      abort_row_run(run)
      Err(Source(issue))
    }
  }
}

///|
/// Receive the listing protocol envelope, charging its actual physical body
/// once through the existing ledger before bounded decoding and row admission.
pub fn begin_row_run_listing_page(
  run : RowRun,
  body : Bytes,
  elapsed_ms : Int64,
) -> Result[Unit, RowHostIssue] {
  let charge = match charge_row_run_page(run, body) {
    Ok(charge) => charge
    Err(issue) => return Err(issue)
  }
  begin_charged_row_run_listing_page(run, charge, body, elapsed_ms)
}

///|
/// Consume this exact attempt's physical-body ticket once. The envelope is
/// the full listing envelope, never a connector's successful/selected prefix.
/// A provider decoder may translate the envelope, but physical accounting uses
/// the original received byte count owned by this ticket.
pub fn begin_charged_row_run_listing_page(
  run : RowRun,
  charge : RowPageCharge,
  body : Bytes,
  elapsed_ms : Int64,
) -> Result[Unit, RowHostIssue] {
  match consume_row_page_charge(run, charge) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  guard run.attempt.state is Reading(read) else { return Err(InvalidState) }
  let parsed = match run.configuration {
    InputConfiguration(acquisition) =>
      match prepare_row_input_listing_page(run, read, acquisition, body) {
        Ok(value) => Some(value)
        Err(issue) => {
          abort_row_run(run)
          return Err(issue)
        }
      }
    _ => None
  }
  match
    begin_row_source_listing_page(
      read,
      body,
      elapsed_ms,
      received_bytes=charge.received_bytes,
      parsed~,
    ) {
    Ok(_) => Ok(())
    Err(issue) => {
      abort_row_run(run)
      Err(Source(issue))
    }
  }
}

///|
/// Resume common selection and admission without charging the page again.
pub fn advance_row_run_listing_page(
  run : RowRun,
  quantum : Int,
  elapsed_ms : Int64,
) -> Result[RowListingPagePoll, RowHostIssue] {
  guard !run.closed && run.attempt.state is Reading(read) else {
    return Err(InvalidState)
  }
  match advance_row_source_listing_page(read, quantum, elapsed_ms) {
    Ok(value) => Ok(value)
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
  if !row_provider_cleanup_bound(run) {
    return Err(Evidence(UnverifiedTransport))
  }
  if run.page_charge is Some(_) {
    abort_row_run(run)
    return Err(Physical(InvalidCharge))
  }
  let finished = if read.keyed is Some(_) {
    complete_keyed_row_read(read)
  } else {
    finish_row_source_read(read)
  }
  match finished {
    Ok(scan) => {
      run.attempt.state = if run.configuration is InputConfiguration(_) {
        InputAwaitingCleanup(scan, read.input)
      } else {
        AwaitingCleanup(scan)
      }
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
  cancel_row_input_progress(run)
  if run.residual is Some(residual) {
    @local.cancel_managed_provider(
      @local.guarded_relation_execution(residual.execution),
    )
    |> ignore
  }
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
    match run.issuer {
      DirectIssuer(issuer) =>
        @planning.close_query_evidence_registration(issuer.registration)
      InputIssuer(issuer) =>
        @planning.close_query_evidence_registration(issuer.registration)
      KeyedIssuer(issuer) =>
        @planning.close_query_evidence_registration(issuer.registration)
    }
    run.closed = true
  }
  if run.physical is None && run.residual is None {
    // A synchronous unaccounted run has no child left to acknowledge. This
    // Unit API still means revocation; rejected custody remains reachable.
    retire_closed_row_evidence(run.attempt) |> ignore
  }
}

///|
/// Stop the accounted source first, then release only the resources still
/// owned by this issuer. A transferred DAG allocation remains with its task.
pub fn close_accounted_row_run(run : RowRun) -> Result[Unit, RowHostIssue] {
  guard run.physical is Some(physical) else { return Err(InvalidState) }
  close_row_run(run)
  match cleanup_row_capture(run) {
    Ok(true) => ()
    Ok(false) => {
      if @resources.reservation_open(physical.reservation) {
        match
          @resources.mark_cleanup_pending(physical.ledger, physical.reservation) {
          Ok(_) => ()
          Err(issue) => return Err(Physical(issue))
        }
      }
      return Err(InvalidState)
    }
    Err(issue) => return Err(issue)
  }
  if (
      physical.provider_capacity is Some(_) &&
      run.response_borrowed &&
      physical.cleanup_confirmed is None
    ) ||
    (physical.cleanup_confirmed is Some(confirm) && !confirm()) {
    if @resources.reservation_open(physical.reservation) {
      match
        @resources.mark_cleanup_pending(physical.ledger, physical.reservation) {
        Ok(_) => ()
        Err(issue) => return Err(Physical(issue))
      }
    }
    return Err(Evidence(UnverifiedTransport))
  }
  if run.configuration is DirectConfiguration(configuration) &&
    configuration.listing_rows is Some(ReportListingRows(_, reports)) &&
    !reclaim_row_listing_reports(reports, 1) {
    if @resources.reservation_open(physical.reservation) {
      match
        @resources.mark_cleanup_pending(physical.ledger, physical.reservation) {
        Ok(_) => ()
        Err(issue) => return Err(Physical(issue))
      }
    }
    return Err(InvalidState)
  }
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
  if physical.provider_capacity is Some(_) {
    // The same reader confirmed retirement and this reservation really
    // settled above. Do not retain its observer/installation aliases forever
    // on an escaped closed RowRun, or re-observe it on an idempotent close.
    physical.cleanup_confirmed = None
    physical.provider_capacity = None
  }
  if run.configuration is OriginalKeyedConfiguration(acquisition) {
    // A failed close/holding/reservation settlement returns above. Only actual
    // same-Owner completion may sever the new original Scope/lookup borrow.
    // The escaped acquisition stays unavailable, never silently permissive.
    acquisition.input_available = Some(() => false)
    physical.cleanup_confirmed = None
  }
  if !retire_closed_row_evidence(run.attempt) {
    return Err(InvalidState)
  }
  Ok(())
}

///|
/// One exact completed observation and its live captured source.
struct RowSourceCapture {
  run : RowRun
  observation : RowCaptureObservation
  source : @query.CapturedInputSource
}

///|
priv enum RowCaptureObservation {
  QueryObservation(RowObservation)
  InputObservation(RowInputObservation)
}

///|
pub fn capture_row_run(run : RowRun) -> Result[RowSourceCapture, RowHostIssue] {
  if run.configuration is InputConfiguration(_) {
    return capture_input_row_run(run)
  }
  guard !run.closed &&
    run.issuer is DirectIssuer(issuer) &&
    run.configuration is DirectConfiguration(configuration) else {
    return Err(InvalidState)
  }
  let observation = match
    (match run.residual {
      Some(residual) => {
        guard row_capture_input_live(run, residual.receipt) &&
          @local.guarded_relation_completed_output(residual.execution)
          is Some(output) else {
          return Err(InvalidState)
        }
        let query = @planning.query_material_owner(
          @planning.query_requirement_material(configuration.requirement),
        )
        let scan = @query.query_receipt_rows(residual.receipt)
        if !(@execution.completed_output_matches_captured_inputs(output, [scan]) ||
          @execution.completed_acquisition_matches_captured_input(
            output,
            @query.query_generated_sequence(query),
            scan,
          )) {
          return Err(InvalidState)
        }
        complete_row_capture_output(
          issuer,
          run.attempt,
          output,
          configuration.limits,
        )
      }
      None => complete_row_capture(issuer, run.attempt, configuration.limits)
    }) {
    Ok(value) => value
    Err(issue) => return Err(Evidence(issue))
  }
  let source = match row_captured_source(issuer, run.attempt, observation) {
    Ok(value) => value
    Err(issue) => return Err(Consumer(issue))
  }
  if run.physical is Some(physical) {
    let measured = observation.records.retention.measured.retained_bytes.to_int64()
    let (original, _) = row_original_input_capacity()
    if measured < 0L ||
      original < 0L ||
      original > 9223372036854775807L - measured {
      return Err(Physical(InvalidLimits))
    }
    // The same RowRun still owns its original read/export backing. Move its
    // already reserved allowance beside the measured scan/output wire into
    // the same holding; only confirmed Row/DAG cleanup may release it.
    let bytes = measured + original
    let holding = match
      @resources.retain_allocation(physical.ledger, physical.reservation, bytes) {
      Ok(value) => value
      Err(issue) => return Err(Physical(issue))
    }
    physical.holding = Some(holding)
    match
      settle_row_capture_capacity(
        configuration.listing_rows is Some(ReportListingRows(_, _)) ||
        physical.provider_capacity is Some(_),
        physical,
      ) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  Ok({ run, observation: QueryObservation(observation), source, })
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
/// Borrow the original admitted scan, not the acquisition's filtered/projected
/// output. Both remain in this RowRun's custody until its normal cleanup. This
/// port cannot issue Source evidence or substitute another captured input.
pub fn row_capture_original_read(
  capture : RowSourceCapture,
) -> @execution.SuppliedRelationRead? {
  if capture.observation is InputObservation(original) {
    return if row_capture_source(capture) is Ok(_) {
      Some(original.read)
    } else {
      None
    }
  }
  guard row_capture_source(capture) is Ok(_) &&
    capture.run.residual is Some(residual) &&
    capture.run.configuration is DirectConfiguration(configuration) else {
    return None
  }
  let query = @planning.query_material_owner(
    @planning.query_requirement_material(configuration.requirement),
  )
  match
    @execution.prepare_supplied_relation_read(
      @query.query_sequence_owner(query),
      @query.query_receipt_input_index(query),
      @query.query_receipt_rows(residual.receipt),
      fn() { row_capture_source(capture) is Ok(_) },
    ) {
    Ok(read) => Some(read)
    Err(_) => None
  }
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
/// Admit completed typed values with this attempt's final response ticket.
/// Earlier dependent responses follow the same original-prefix observation law
/// as JSON pages; a ticket alone proves neither that prefix nor permission.
/// Ownership and single consumption are checked before retaining any value.
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
  if run.configuration is InputConfiguration(_) &&
    run.physical is Some(_) &&
    columns.length() == read.columns.length() &&
    rows.length() <= read.page_limits.max_rows {
    let width = read.columns.length().to_int64()
    match
      fund_row_input_page(
        run,
        read,
        rows.length().to_int64() * (2L * width + 1L),
        0L,
        rows.length().to_int64(),
        0,
        None,
      ) {
      Ok(_) => ()
      Err(issue) => {
        abort_row_run(run)
        return Err(issue)
      }
    }
  }
  if run.configuration is InputConfiguration(_) && run.physical is Some(_) {
    match fund_row_input_values(run, read, rows) {
      Ok(_) => ()
      Err(issue) => {
        abort_row_run(run)
        return Err(issue)
      }
    }
  }
  match accept_row_source_values(read, columns, rows) {
    Ok(count) => Ok(count)
    Err(issue) => {
      abort_row_run(run)
      Err(Source(issue))
    }
  }
}
