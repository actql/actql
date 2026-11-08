///|
// Lifetime of the original captured-left dependency, not permission to acquire
// another Source. Unlike the preparation prerequisite, this remains valid
// after descriptor/read issuance while its original custody is still live.
// There is no user callback between these nominal checks and the final fence.
pub fn client_original_keyed_capture_available(
  scope : ClientModelReadScope,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  prepared : PreparedClientProgram,
  keyed : ClientKeyedAcquisition,
) -> Bool {
  client_model_origin_matches(scope.origin, compiled, definition, plan) &&
  client_compiled_run_matches(compiled, prepared) &&
  physical_equal(plan.owner, prepared) &&
  client_keyed_acquisition_matches_program(keyed, prepared) &&
  @resources.original_ledger_inventory_available(scope.identity)
}

///|
// Before the initial Direct read of a checked keyed pipeline, lend the original
// Ledger only to its existing Core Local accounted Row receiver. This checks
// Source inventory, not successful keyed acquisition, authority or Model send.
pub fn borrow_client_original_keyed_direct_ledger(
  scope : ClientModelReadScope,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  prepared : PreparedClientProgram,
  keyed : ClientKeyedAcquisition,
  requirement : @planning.QueryRequirement,
) -> Result[@resources.Ledger, ClientModelReadPreparationIssue] {
  if !client_model_origin_matches(scope.origin, compiled, definition, plan) ||
    !client_compiled_run_matches(compiled, prepared) ||
    !physical_equal(plan.owner, prepared) ||
    check_client_compiled_run_definition(compiled, definition) is Err(_) {
    return Err(ForeignRun)
  }
  guard client_compiled_run_serialization(compiled) is Some(component) &&
    plan.serialization is Some(selected) &&
    physical_equal(component, selected) &&
    physical_equal(component.owner, prepared) &&
    client_keyed_acquisition_matches_program(keyed, prepared) &&
    select_client_single_keyed_acquisition(prepared) is Ok(Some(original)) &&
    physical_equal(keyed.check, original.check) &&
    client_keyed_acquisition_coordinates(keyed) is Some((_, task, join)) &&
    task == component.task &&
    join < component.step &&
    client_serialization_single_capture_shape(prepared, component.task) &&
    client_keyed_observation_covers_sources(prepared, keyed, requirement) &&
    client_keyed_direct_acquisition_coordinates(keyed)
    is Some((stage, input, _)) &&
    @strategy.graph_task_owner(prepared.graph, 0) is Some(owner) &&
    @strategy.graph_task_unit_index(prepared.graph, 0) == Some(stage) else {
    return Err(ForeignRun)
  }
  let program = @checked.source_identity(
    @strategy.graph_program(prepared.graph),
  )
  let query = @planning.query_material_owner(
    @planning.query_requirement_material(requirement),
  )
  let acquisition = @query.query_sequence_requirement(query)
  guard physical_equal(
      @planning.query_requirement_program(requirement),
      program,
    ) &&
    physical_equal(@query.query_sequence_owner(query), owner) &&
    @context.program_identity_stage_requests(program, stage) is Some(requests) &&
    physical_equal(@acquisition.query_acquisition_owner(acquisition), requests) &&
    @acquisition.query_acquisition_source_index(acquisition) == input &&
    @acquisition.pipeline_request_at(requests, input)
    is Some(@acquisition.Direct(_, _)) else {
    return Err(ForeignRun)
  }
  if !@resources.original_ledger_prefix_available(scope.identity) {
    return Err(Resource(@resources.ChangedOriginalState))
  }
  Ok(scope.ledger)
}

///|
// The exact accounted Row capture is validated by the only receiver, Core
// Local, after this synchronous loan and after preparing the left producer.
// This does not issue a captured observation or bypass per-key Source duties.
pub fn borrow_client_original_keyed_captured_ledger(
  scope : ClientModelReadScope,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  prepared : PreparedClientProgram,
  keyed : ClientKeyedAcquisition,
  source : @query.CapturedInputSource,
  prefix? : @resources.Reservation? = None,
) -> Result[@resources.Ledger, ClientModelReadPreparationIssue] {
  if !client_model_origin_matches(scope.origin, compiled, definition, plan) ||
    !client_compiled_run_matches(compiled, prepared) ||
    !physical_equal(plan.owner, prepared) ||
    check_client_compiled_run_definition(compiled, definition) is Err(_) {
    return Err(ForeignRun)
  }
  guard client_compiled_run_serialization(compiled) is Some(component) &&
    plan.serialization is Some(selected) &&
    physical_equal(component, selected) &&
    physical_equal(component.owner, prepared) &&
    client_keyed_acquisition_matches_program(keyed, prepared) &&
    select_client_single_keyed_acquisition(prepared) is Ok(Some(original)) &&
    physical_equal(keyed.check, original.check) &&
    client_keyed_acquisition_coordinates(keyed) is Some((_, task, join)) &&
    task == component.task &&
    join < component.step &&
    client_serialization_single_capture_shape(prepared, component.task) &&
    @strategy.graph_task_owner(prepared.graph, 0) is Some(owner) &&
    @query.captured_source_matches(
      source,
      @checked.source_identity(@strategy.graph_program(prepared.graph)),
      owner,
    ) else {
    return Err(ForeignRun)
  }
  // Source liveness can synchronously stop/reenter; only the current census
  // AFTER that callback can authorize this Core borrow.
  if !@resources.original_ledger_captured_preparation_available(
      scope.identity,
      prefix~,
    ) {
    return Err(Resource(@resources.ChangedOriginalState))
  }
  Ok(scope.ledger)
}

///|
// Closed Core Local receiver only; the Node facade exposes no Ledger getter.
// Local retains the original capture and confirms its exact Row custody before
// calling this existing assembly constructor. Scope/control/input overlap is
// part of the trusted bootstrap, not a new numeric profile in this entry.
pub fn start_client_original_keyed_lookup_input(
  scope : ClientModelReadScope,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  prepared : PreparedClientProgram,
  keyed : ClientKeyedAcquisition,
  left : ClientKeyedLeftRead,
  max_bytes : Int,
  max_work : Int,
) -> Result[ClientKeyedLookupInput, ClientKeyedRequestIssue] {
  if !physical_equal(left.acquisition, keyed) {
    return Err(ForeignLeft)
  }
  guard left.composed is None && left.source is Some(source) else {
    return Err(ForeignLeft)
  }
  let ledger = match
    borrow_client_original_keyed_captured_ledger(
      scope, compiled, definition, plan, prepared, keyed, source,
    ) {
    Ok(value) => value
    Err(_) => return Err(Assembly("original_custody_changed"))
  }
  start_client_keyed_lookup_input_owned(
    left,
    ledger,
    max_bytes,
    max_work,
    Some(scope.identity),
  )
}

///|
// Loan only to Core Local's existing accounted keyed Row receiver. The cache
// count comes from actual completed responses, never preplanned key slots. Return
// its exact request so the receiver does not re-extract data after this check.
// No Node export/getter, another resource owner or durable grant is introduced.
pub fn borrow_client_original_keyed_child(
  scope : ClientModelReadScope,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  prepared : PreparedClientProgram,
  keyed : ClientKeyedAcquisition,
  lookup : ClientKeyedLookupInput,
  request : ClientKeyedRequest,
  prefix? : @resources.Reservation? = None,
) -> Result[
  (
    @resources.Ledger,
    @resources.OriginalLedgerIdentity,
    @resources.Reservation,
    Int,
    @acquisition.KeyedRowRequest,
  ),
  ClientKeyedRequestIssue,
] {
  // The producer callback may synchronously retire, park or reenter. Every
  // actual selected/phase/custody check below follows that callback.
  if !client_keyed_request_matches_acquisition(request, keyed) {
    return Err(ForeignLeft)
  }
  guard client_original_keyed_capture_available(
      scope, compiled, definition, plan, prepared, keyed,
    ) &&
    physical_equal(lookup.ledger, scope.ledger) &&
    physical_equal(lookup.left.acquisition, keyed) &&
    physical_equal(request.left, lookup.left) &&
    request.assembly_accounting is Some(accounting) &&
    physical_equal(accounting, lookup) &&
    !lookup.closed &&
    lookup.completed is None &&
    lookup.copying is None &&
    lookup.preparation is None &&
    lookup.left.lookup_issue is None &&
    lookup.selected_request is Some(selected) &&
    physical_equal(selected, request) &&
    lookup.selected_index == Some(-1) &&
    request.row == lookup.accepted &&
    request.attempts == 0L &&
    !request.io_complete &&
    @resources.original_keyed_child_preparation_available(
      scope.identity,
      scope.ledger,
      lookup.reservation,
      lookup.completed_responses,
      prefix~,
    ) else {
    return Err(Assembly("original_child_custody_changed"))
  }
  Ok(
    (
      scope.ledger,
      scope.identity,
      lookup.reservation,
      lookup.completed_responses,
      request.request,
    ),
  )
}

///|
// Retained children depend on the original left/Scope, not the mutable selected
// request slot (cleared after admission). Read/descriptor issuance is legal;
// original closing/park/retirement and assembly stop revoke new borrowed use.
pub fn client_original_keyed_lookup_available(
  scope : ClientModelReadScope,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  prepared : PreparedClientProgram,
  keyed : ClientKeyedAcquisition,
  lookup : ClientKeyedLookupInput,
) -> Bool {
  client_keyed_left_available(lookup.left) &&
  !lookup.closed &&
  lookup.left.lookup_issue is None &&
  physical_equal(lookup.ledger, scope.ledger) &&
  physical_equal(lookup.left.acquisition, keyed) &&
  client_original_keyed_capture_available(
    scope, compiled, definition, plan, prepared, keyed,
  )
}
