///|
/// Semantic bounds of the complete Source input, independent of Query Select.
/// The original parent funds actual construction before each phase; permitting
/// a larger future input does not preallocate that maximum.
pub(all) struct RowInputLimits {
  max_rows : Int
  page : RowPageLimits
  retention : @execution.ValueLimits
  wire : @execution.RowWireLimits
}

///|
priv struct RowInputPreparation {
  original : @sourcequery.SourceAcquisition
  program : @context.ProgramSourceIdentity
  sequence : @lower.PreparedSequence
  contracts : @execution.RegisteredRelationContracts
  owner : @lower.BoundPrepared
  input_index : Int
  schema : @schema.Schema
  columns : Array[String]
  view : RowDeclaredView
  limits : RowInputLimits
  facts : @planning.QuerySourceEvidenceFacts
  members : @environment.ConnectorSourceEvidenceMembers
  file_listing : @environment.FileListProfile?
  listing_rows : RowListingRows?
}

///|
/// General Source selection in the same RowRun owner, not a Query requirement.
struct RowInputAcquisition {
  preparation : RowInputPreparation
  choice : @planning.AcquisitionChoice[RowInputPreparation]
  candidate : @planning.PreparedAcquisition[
    RowInputPreparation,
    RowInputPreparation,
  ]
}

///|
priv struct RowInputIssuer {
  registration : @planning.QueryEvidenceRegistration[
    @sourcequery.SourceAcquisition,
    RowInputPreparation,
    RowAttempt,
  ]
}

///|
priv struct RowInputAuthority {
  issuer : RowInputIssuer
  token : @planning.QueryEvidenceAttemptAuthority[
    @sourcequery.SourceAcquisition,
    RowInputPreparation,
    RowAttempt,
  ]
}

///|
priv struct RowInputObservation {
  authority : RowInputAuthority
  read : @execution.SuppliedRelationRead
  input : @execution.AdmittedInput
  measured : @execution.RowWireIdentity
}

///|
fn row_input_limits_valid(limits : RowInputLimits) -> Bool {
  !(limits.max_rows < 0 ||
  limits.page.max_bytes <= 0 ||
  limits.page.max_nodes <= 0 ||
  limits.page.max_depth <= 0 ||
  limits.page.max_rows <= 0 ||
  limits.retention.max_nodes < 0 ||
  limits.retention.max_text_bytes < 0 ||
  limits.retention.max_depth < 0 ||
  limits.retention.max_work < 0 ||
  limits.wire.max_columns < 0 ||
  limits.wire.max_order_work < 0 ||
  limits.wire.max_bytes < 0 ||
  limits.wire.max_nodes < 0 ||
  limits.wire.max_depth < 0)
}

///|
pub fn prepare_row_input_acquisition(
  original : @sourcequery.SourceAcquisition,
  program : @context.ProgramSourceIdentity,
  sequence : @lower.PreparedSequence,
  contracts : @execution.RegisteredRelationContracts,
  declaration : RowDeclaration,
  limits : RowInputLimits,
  listing_policy? : @capacity.Policy? = None,
) -> Result[RowInputAcquisition, RowHostIssue] {
  if !row_input_limits_valid(limits) {
    return Err(InvalidSpecification)
  }
  if !@query.source_input_capture_preparation_matches(
      sequence, original, program,
    ) {
    return Err(Source(ForeignSource))
  }
  guard @planning.source_acquisition_evidence_facts(original) is Some(facts) &&
    row_declaration_view(declaration, facts.source_ref) is Some(view) &&
    view.view_cid == facts.source_contract_cid else {
    return Err(Source(UndeclaredSource))
  }
  let declared = @sourcequery.declaration(
    @sourcequery.mode_input(@sourcequery.source_acquisition_mode(original)),
  )
  if declared.connector != declaration.connector_id ||
    declared.resource != view.resource {
    return Err(Source(ForeignSource))
  }
  prepare_row_input_acquisition_original(
    original,
    program,
    sequence,
    contracts,
    Some(view),
    declaration.connector_registration,
    limits,
    listing_policy~,
  )
}

///|
/// An installed native source already has a checked Catalog SourceView. Keep
/// that same original and schema; no regenerated declaration or Query exists.
pub fn prepare_catalog_row_input_acquisition(
  original : @sourcequery.SourceAcquisition,
  program : @context.ProgramSourceIdentity,
  sequence : @lower.PreparedSequence,
  contracts : @execution.RegisteredRelationContracts,
  limits : RowInputLimits,
  listing_policy? : @capacity.Policy? = None,
) -> Result[RowInputAcquisition, RowHostIssue] {
  let source = @sourcequery.mode_input(
    @sourcequery.source_acquisition_mode(original),
  )
  let declared = @sourcequery.declaration(source)
  let catalog = @environment.reference_catalog(
    @environment.source_request_reference(
      @sourcequery.selected_contract(source),
    ),
  )
  let (connector_id, _, _) = @environment.catalog_identity(catalog)
  if declared.connector != connector_id {
    return Err(Source(ForeignSource))
  }
  // This entry is the known installed DuckDB implementation, never a caller's
  // proposed registration name. The Host separately retains its real entry.
  prepare_row_input_acquisition_original(
    original,
    program,
    sequence,
    contracts,
    None,
    "builtin_source",
    limits,
    listing_policy~,
  )
}

///|
fn prepare_row_input_acquisition_original(
  original : @sourcequery.SourceAcquisition,
  program : @context.ProgramSourceIdentity,
  sequence : @lower.PreparedSequence,
  contracts : @execution.RegisteredRelationContracts,
  declared_view : RowDeclaredView?,
  registration_name : String,
  limits : RowInputLimits,
  listing_policy? : @capacity.Policy? = None,
) -> Result[RowInputAcquisition, RowHostIssue] {
  if !row_input_limits_valid(limits) {
    return Err(InvalidSpecification)
  }
  if !@query.source_input_capture_preparation_matches(
      sequence, original, program,
    ) {
    return Err(Source(ForeignSource))
  }
  guard @planning.source_acquisition_evidence_facts(original) is Some(facts) else {
    return Err(Source(UndeclaredSource))
  }
  let mode = @sourcequery.source_acquisition_mode(original)
  let source = @sourcequery.mode_input(mode)
  let declared = @sourcequery.declaration(source)
  let file_listing = @environment.source_request_file_listing(
    @sourcequery.selected_contract(source),
  )
  let listing_rows = match file_listing {
    None => None
    Some(profile) => {
      // The same checked Source subject selects the original Catalog/Host
      // ceiling. max_rows is a capture bound, never a Host listing grant.
      let resolved = match
        @environment.resolve_file_listing_rows(
          profile,
          listing_policy,
          facts.source_ref,
        ) {
        Ok(value) => value
        Err(_) =>
          return Err(Source(ListingLimitUnresolved("max_listing_items")))
      }
      Some(ResolvedListingRows(resolved))
    }
  }
  let owner = @lower.sequence_owner(sequence)
  guard @sourcequery.source_acquisition_input(original)
    is @pipeline.Input(input_index) &&
    @lower.preparation_input_schema(
      @lower.bound_preparation(owner),
      input_index,
    )
    is Some(schema) else {
    return Err(Source(InvalidInputSchema))
  }
  let width = @schema.field_count(schema)
  if width == 0 ||
    (declared_view is Some(view) && width != view.fields.length()) ||
    width > limits.wire.max_columns {
    return Err(Source(InvalidInputSchema))
  }
  let columns = []
  for index in 0..<width {
    let name = @schema.field_reference_name(
      @schema.field_at(schema, index).unwrap(),
    )
    if (declared_view is Some(view) && !view.fields.contains(name)) ||
      columns.contains(name) {
      return Err(Source(InvalidInputSchema))
    }
    columns.push(name)
  }
  let view = declared_view.unwrap_or_else(() => {
    resource: declared.resource,
    source_ref: facts.source_ref,
    view_cid: facts.source_contract_cid,
    fields: columns.copy(),
    carrier_schema_cid: facts.carrier_schema_contract_cid,
    data_policy_cid: facts.source_data_policy_cid,
    classification: facts.data_classification,
  })
  let members = match @planning.source_acquisition_evidence_members(original) {
    Ok(value) => value
    Err(issue) => return Err(SourceEvidence(Member(issue)))
  }
  let preparation = {
    original,
    program,
    sequence,
    contracts,
    owner,
    input_index,
    schema,
    columns,
    view,
    limits,
    facts,
    members,
    file_listing,
    listing_rows,
  }
  guard @connector.prepare_capability_registry(
      [
        {
          name: registration_name,
          acquisition: true,
          fixed_compute: false,
          effect: false,
        },
      ],
      1,
      64,
    )
    is Ok(registry) &&
    @connector.capability_registration_at(registry, 0) is Some(registration) &&
    @planning.bind_acquisition_candidate(
      registration,
      preparation,
      preparation,
      @cost.Unknown,
      { transfer_bytes: None, retained_bytes: None, money_units: None, },
    )
    is Ok(candidate) &&
    @planning.choose_acquisition_candidate(
      registry,
      preparation,
      [@planning.prepared_acquisition_candidate(candidate)],
      Some([0]),
      10,
    )
    is Ok(@planning.Proposed(choice)) else {
    return Err(Selection)
  }
  Ok({ preparation, choice, candidate, })
}

///|
pub fn row_input_acquisition_columns(
  value : RowInputAcquisition,
) -> Array[String] {
  value.preparation.columns.copy()
}

///|
pub fn row_input_acquisition_is_listing(value : RowInputAcquisition) -> Bool {
  value.preparation.file_listing is Some(_)
}

///|
pub fn row_input_acquisition_max_rows(value : RowInputAcquisition) -> Int {
  value.preparation.limits.max_rows
}

///|
pub fn row_input_acquisition_matches_source(
  value : RowInputAcquisition,
  original : @sourcequery.SourceAcquisition,
) -> Bool {
  physical_equal(value.preparation.original, original)
}

///|
pub fn row_input_acquisition_target(
  value : RowInputAcquisition,
) -> (String, Array[String]) {
  (value.preparation.view.resource, value.preparation.columns.copy())
}

///|
/// Borrow the original declared resource without copying its column inventory.
/// This is immutable DATA; the caller still checks the original acquisition and
/// performs its Account/current observation at the actual read boundary.
pub fn row_input_acquisition_target_resource(
  value : RowInputAcquisition,
) -> String {
  value.preparation.view.resource
}

///|
pub fn row_input_acquisition_facts(
  value : RowInputAcquisition,
) -> @planning.QuerySourceEvidenceFacts {
  value.preparation.facts
}

///|
pub fn row_input_acquisition_request_wire(
  value : RowInputAcquisition,
) -> Result[String, RowHostIssue] {
  let limits = value.preparation.limits.wire
  @sourcequery.parameterized_request_wire(
    @sourcequery.source_acquisition_request(value.preparation.original),
    limits.max_bytes,
    limits.max_nodes,
    limits.max_depth,
  ).map_err(issue => Source(RequestEncoding(issue)))
}

///|
pub fn check_row_input_acquisition_original(
  value : RowInputAcquisition,
  declaration : RowDeclaration,
  original : @sourcequery.SourceAcquisition,
) -> Result[Unit, RowHostIssue] {
  guard physical_equal(value.preparation.original, original) &&
    row_declaration_view(declaration, value.preparation.facts.source_ref)
    is Some(view) &&
    physical_equal(value.preparation.view, view) else {
    return Err(ForeignDeclaration)
  }
  Ok(())
}

///|
/// Component entrance; ordinary callers use the same accounted Source parent.
pub fn start_row_input_acquisition(
  value : RowInputAcquisition,
  nonce : String,
  verify : (RowAttempt) -> Bool,
) -> Result[RowRun, RowHostIssue] {
  let preparation = value.preparation
  let issuer : RowInputIssuer = match
    @planning.register_query_evidence_issuer(
      preparation.original,
      preparation,
      nonce,
      128,
      "row-source-input-issuer",
      verify,
    ) {
    Ok(registration) => { registration, }
    Err(issue) => return Err(Evidence(custody_issue(issue)))
  }
  let (_, token) = match
    @planning.reserve_selected_query_evidence_attempt(
      issuer.registration,
      value.choice,
      value.candidate,
      original => original,
    ) {
    Ok(value) => value
    Err(issue) => {
      @planning.close_query_evidence_registration(issuer.registration)
      return Err(Evidence(custody_issue(issue)))
    }
  }
  Ok({
    configuration: InputConfiguration(value),
    issuer: InputIssuer(issuer),
    attempt: {
      preparation: InputPreparation(preparation),
      authority: InputAuthority({ issuer, token, }),
      state: Pending,
    },
    closed: false,
    physical: None,
    page_charge: None,
    response_borrowed: false,
    input_progress: Some({
      nodes: 0L,
      text: 0L,
      rows: 0L,
      tokens: 0L,
      working_frames: 0,
      preflight: None,
      parser: None,
    }),
    residual: None,
  })
}

///|
fn begin_input_row_run(
  run : RowRun,
  acquisition : RowInputAcquisition,
  page : RowPageLimits,
  max_rows : Int,
  reference_issuer : @admitted.ReferenceIssuer?,
) -> Result[Unit, RowHostIssue] {
  let preparation = acquisition.preparation
  let limits = preparation.limits
  guard !run.closed &&
    run.attempt.state is Pending &&
    run.attempt.preparation is InputPreparation(original) &&
    physical_equal(original, preparation) else {
    return Err(InvalidState)
  }
  if max_rows < 0 ||
    max_rows > limits.max_rows ||
    page.max_bytes > limits.page.max_bytes ||
    page.max_nodes > limits.page.max_nodes ||
    page.max_depth > limits.page.max_depth ||
    page.max_rows > limits.page.max_rows {
    return Err(Source(InvalidPage))
  }
  if run.physical is Some(physical) &&
    page.max_bytes.to_int64() > physical.execution_scratch {
    return Err(Physical(InvalidCharge))
  }
  let listing = match
    prepare_row_listing_progress(
      preparation.file_listing,
      @sourcequery.source_acquisition_request(preparation.original),
      page.max_bytes,
      reference_issuer,
      preparation.listing_rows,
      retention=if preparation.file_listing is Some(_) {
        Some({
          max_nodes: limits.retention.max_nodes,
          max_text: limits.retention.max_text_bytes,
          nodes: 0,
          text: 0,
        })
      } else {
        None
      },
    ) {
    Ok(value) => value
    Err(issue) => {
      abort_row_attempt(run.attempt)
      return Err(Source(issue))
    }
  }
  match
    new_row_source_read(
      preparation.owner,
      preparation.input_index,
      preparation.schema,
      preparation.columns,
      preparation.view.fields,
      page,
      max_rows,
      limits.retention,
      reference_issuer,
      listing,
      None,
    ) {
    Ok(read) => {
      run.attempt.state = Reading(read)
      Ok(())
    }
    Err(issue) => {
      abort_row_attempt(run.attempt)
      Err(Source(issue))
    }
  }
}

///|
fn input_row_capture_live(run : RowRun) -> Bool {
  guard !run.closed &&
    run.configuration is InputConfiguration(acquisition) &&
    run.issuer is InputIssuer(issuer) &&
    run.attempt.preparation is InputPreparation(preparation) &&
    physical_equal(preparation, acquisition.preparation) &&
    run.attempt.authority is InputAuthority(authority) &&
    physical_equal(authority.issuer, issuer) &&
    @planning.query_evidence_attempt_matches_registration(
      authority.token,
      issuer.registration,
    ) &&
    run.attempt.state
    is (InputAwaitingCleanup(_, _)
    | InputValidating(_)
    | InputValidated(_)
    | InputCaptured(_)) &&
    @planning.query_evidence_transport_matches(issuer.registration, run.attempt) else {
    return false
  }
  // The existing physical verifier may reenter cancellation. Recheck after it.
  !run.closed &&
  @planning.query_evidence_registration_live(issuer.registration) &&
  run.attempt.state
  is (InputAwaitingCleanup(_, _)
  | InputValidating(_)
  | InputValidated(_)
  | InputCaptured(_))
}

///|
fn capture_input_row_run(
  run : RowRun,
) -> Result[RowSourceCapture, RowHostIssue] {
  guard input_row_capture_live(run) &&
    run.configuration is InputConfiguration(acquisition) &&
    run.attempt.authority is InputAuthority(authority) &&
    run.attempt.state is InputValidated(validation) else {
    return Err(InvalidState)
  }
  let preparation = acquisition.preparation
  let read = validation.read
  let input = validation.input
  let measured = match
    @execution.supplied_relation_read_rows_identity(
      read,
      preparation.limits.wire,
    ) {
    Ok(value) => value
    Err(_) => {
      abort_row_run(run)
      return Err(Source(InvalidPage))
    }
  }
  let observation = { authority, read, input, measured, }
  run.attempt.state = InputCaptured(observation)
  let port = match
    @query.prepare_trusted_source_input_capture_port(
      preparation.contracts,
      preparation.sequence,
      preparation.original,
      preparation.program,
      preparation.limits.wire.max_columns,
      preparation.limits.wire.max_bytes,
      fn(proof : RowInputObservation) {
        if physical_equal(proof, observation) &&
          input_row_capture_live(run) &&
          run.attempt.state is InputCaptured(actual) &&
          physical_equal(actual, observation) {
          Some((proof.read, @execution.row_wire_usage(proof.measured).0))
        } else {
          None
        }
      },
    ) {
    Ok(value) => value
    Err(issue) => {
      abort_row_run(run)
      return Err(Consumer(issue))
    }
  }
  let source = match @query.capture_verified_source_input(port, observation) {
    Ok(value) => value
    Err(issue) => {
      abort_row_run(run)
      return Err(Consumer(issue))
    }
  }
  if run.physical is Some(physical) {
    guard row_input_capture_retained(run) is Some(retained) else {
      abort_row_run(run)
      return Err(Physical(InvalidLimits))
    }
    let holding = match
      @resources.retain_allocation(
        physical.ledger,
        physical.reservation,
        retained,
      ) {
      Ok(value) => value
      Err(issue) => {
        abort_row_run(run)
        return Err(Physical(issue))
      }
    }
    physical.holding = Some(holding)
    // The same holding, reservation and cleanup observer retain the original
    // input. Ordinary Host-backed input has completed its page construction
    // and both validation cursors here; later consumers cannot resume it.
    // Return ONLY that caller's construction scratch, not the retained input,
    // provider backing or the remaining receiver/evidence workspace. The
    // existing captured phase quote is an independent lower bound. Listing
    // and supplementary provider lifetimes keep their original full envelope.
    if physical.provider_capacity is None &&
      preparation.file_listing is None &&
      preparation.listing_rows is None {
      guard run.input_progress is Some(progress) &&
        progress.preflight is None &&
        progress.parser is None &&
        validation.phase == 6 &&
        validation.keys is None &&
        validation.scores is None &&
        !validation.constructing else {
        return Err(InvalidState)
      }
      if !input_row_capture_live(run) ||
        !(run.attempt.state is InputCaptured(actual) &&
        physical_equal(actual, observation)) {
        return Err(Evidence(UnverifiedTransport))
      }
      let (_, execution) = match
        @resources.reservation_capacity_amounts(
          physical.ledger,
          physical.reservation,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Physical(issue))
      }
      if execution < physical.execution_scratch ||
        execution - physical.execution_scratch < retained {
        return Err(Physical(InvalidLimits))
      }
      match
        @resources.reduce_execution_reservation(
          physical.ledger,
          physical.reservation,
          execution - physical.execution_scratch,
        ) {
        Ok(_) => ()
        Err(issue) => return Err(Physical(issue))
      }
      // A current observer may cancel/reenter. A returned byte allowance is
      // monotonic; keep this same captured original on every failed boundary.
      // This cut neither acknowledges physical stop nor permits recapture.
      if !input_row_capture_live(run) ||
        !(run.attempt.state is InputCaptured(actual) &&
        physical_equal(actual, observation)) {
        return Err(Evidence(UnverifiedTransport))
      }
    }
  }
  Ok({ run, observation: InputObservation(observation), source, })
}

///|
fn cleanup_input_row_capture(run : RowRun, quantum : Int) -> Bool {
  if !run.closed || quantum <= 0 {
    return false
  }
  let input = match run.attempt.state {
    InputStopping(validation) => {
      if !cleanup_input_validation(validation) {
        return false
      }
      validation.input
    }
    InputAwaitingCleanup(_, input) => input
    InputCaptured(observation) => observation.input
    InputFailed(input) => input
    _ => return true
  }
  if @execution.reclaim_admitted_input(input, quantum) {
    run.attempt.state = Failed
    true
  } else {
    false
  }
}

///|
/// Whole-input allocation remains with the Source RowRun alongside Compute.
/// It is not transferred into the root's output holding. The original managed
/// Run retains both and stops dependent Compute before retiring this input.
pub fn check_row_input_compute_binding(
  capture : RowSourceCapture,
  dag : @strategy.CapturedDAG,
  task : Int,
) -> Result[Unit, RowHostIssue] {
  guard task >= 0 &&
    row_capture_source(capture) is Ok(_) &&
    capture.observation is InputObservation(observation) &&
    capture.run.physical is Some(physical) &&
    physical_equal(physical.ledger, @strategy.captured_dag_ledger(dag)) &&
    @strategy.source_input_dag_matches_read_at(dag, observation.read, task) else {
    return Err(InvalidState)
  }
  Ok(())
}

///|
/// Same completed input occurrence, not another Run with equal rows or limits.
/// Liveness is checked by the existing capture getter at the consuming boundary.
pub fn check_row_input_capture_run(
  capture : RowSourceCapture,
  run : RowRun,
) -> Result[Unit, RowHostIssue] {
  if !physical_equal(capture.run, run) ||
    !(capture.observation is InputObservation(_)) {
    return Err(InvalidState)
  }
  Ok(())
}

///|
/// Initial original controls/selector and the actual provider recipe only.
/// Pages and validators grow this same reservation before construction; wire
/// and retention ceilings are semantic bounds rather than initial demand.
pub fn row_input_acquisition_capacity(
  value : RowInputAcquisition,
  provider : @execution.ExecutionCapacity?,
) -> @execution.ExecutionCapacity? {
  guard row_input_initial_capacity(value.preparation) is Some(initial) else {
    return None
  }
  let retained = @execution.execution_capacity_retained_bytes(initial)
  let execution = @execution.execution_capacity_execution_bytes(initial)
  // The existing provider describes its actual physical-reader construction.
  // A Host-backed original has no replacement/dummy provider declaration.
  if provider is None {
    return @execution.execution_capacity(retained, execution)
  }
  match row_provider_capacity_sum(retained, execution, 0L, provider) {
    Ok((retained, execution)) =>
      @execution.execution_capacity(retained, execution)
    Err(_) => None
  }
}

///|
/// Reserve on the supplied original Source/Request Ledger before constructing
/// its attempt. The caller must bind that Ledger and recipe to the same Plan.
pub fn start_accounted_row_input_acquisition(
  value : RowInputAcquisition,
  provider : @execution.ExecutionCapacity?,
  nonce : String,
  verify : (RowAttempt) -> Bool,
  ledger : @resources.Ledger,
  transfer_bytes : Int64,
  execution_scratch : Int64,
) -> Result[RowRun, RowHostIssue] {
  if transfer_bytes < 0L ||
    execution_scratch < value.preparation.limits.page.max_bytes.to_int64() {
    return Err(Physical(InvalidLimits))
  }
  guard row_input_acquisition_capacity(value, provider) is Some(capacity) else {
    return Err(Physical(InvalidLimits))
  }
  let retained = @execution.execution_capacity_retained_bytes(capacity)
  let execution = @execution.execution_capacity_execution_bytes(capacity)
  if execution_scratch > 9223372036854775807L - execution {
    return Err(Physical(InvalidLimits))
  }
  let reservation = match
    @resources.reserve_attempt(
      ledger,
      transfer_bytes,
      retained,
      execution + execution_scratch,
      quantities=@resources.quantity_neutral_amounts(ledger),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Physical(issue))
  }
  let run = match start_row_input_acquisition(value, nonce, verify) {
    Ok(value) => value
    Err(issue) =>
      match @resources.settle_reservation(ledger, reservation) {
        Ok(_) => return Err(issue)
        Err(issue) => return Err(Physical(issue))
      }
  }
  install_row_reservation(
    run,
    ledger,
    reservation,
    execution_scratch,
    provider_capacity=provider,
  )
  Ok(run)
}

///|
/// Borrow the exact checked input schema for the installed native value codec.
pub fn row_input_acquisition_schema(
  value : RowInputAcquisition,
) -> @schema.Schema {
  value.preparation.schema
}
