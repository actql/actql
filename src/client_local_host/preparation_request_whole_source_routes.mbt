///|
// Internal first frontier of the Whole-domain entry. It leaves Selecting on
// success so the enclosing entry MUST still reserve the observed RowInput and
// evidence-member constructor before returning to its Host caller. No capacity
// or physical start token is returned by this Source-original selection.
fn[I] reserve_request_whole_source_routes(
  owner : ClientRequestPreparation[I],
  input : I,
  request : @publication_host.ClientRequestIdentity,
  select_query? : Bool = false,
) -> Result[
  (
    @publication_host.ClientDirectAcquisitionOccurrences,
    Array[@sourceviews.SourceAcquisition],
  ),
  ClientRequestProgramPlanIssue,
] {
  guard owner.phase == ProgramPlanReserved &&
    owner.input is Some(original) &&
    physical_equal(original, input) &&
    owner.program_capacity is Some(_) &&
    owner.compiled_program is Some(prepared) &&
    owner.program_domain_quote is None &&
    !owner.program_body_attempted else {
    return Err(Preparation(WrongPhase))
  }
  let identity = @publication_host.prepared_client_identity(prepared)
  if identity.program_definition_cid !=
    @publication_host.client_request_program_cid(request) ||
    identity.parameter_values_cid !=
    @publication_host.client_request_parameters_cid(request) {
    return Err(Preparation(ForeignOriginal))
  }
  let graph = @publication_host.prepared_client_graph(prepared)
  // Complete-input occurrences need not form a captured prefix or own
  // distinct compute tasks. The existing selector visits every checked Source
  // execution, so that original scalar count also bounds its output inventory.
  let bound = @checked.source_execution_count(@strategy.graph_program(graph))
  guard bound > 0 &&
    installed_direct_occurrences_layout(@strategy.graph_captured_prefix(graph))
    is Some((old_retained, old_execution)) &&
    installed_direct_occurrences_layout(bound)
    is Some((new_retained, new_execution)) &&
    request_whole_source_observer_bytes() is Some(observer) else {
    return Err(Preparation(Policy))
  }
  // Extend the SAME already-funded selector slot, rather than charge a second
  // selector or credit any completed scratch/GC/child return as free capacity.
  let selector = Int64::max(
    Int64::max(0L, new_retained - old_retained),
    Int64::max(0L, new_execution - old_execution),
  )
  guard @execution.checked_preparation_add_product(selector, observer, 1L)
    is Some(additional) else {
    return Err(Preparation(Policy))
  }
  owner.phase = Selecting
  match
    reserve_request_domain_graph_construction(
      owner, input, prepared, additional,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let direct = match installed_direct_occurrences_owned(Pure(prepared)) {
    Err(issue) => return Err(Installed(issue))
    Ok(value) => value
  }
  let count = @publication_host.client_direct_acquisition_occurrence_count(
    direct,
  )
  guard count > 0 &&
    count <= bound &&
    request_whole_source_route_scan_count(prepared, direct) is Some(scans) &&
    request_whole_source_route_frontier_bytes(count, scans, select_query~)
    is Some(bytes) else {
    return Err(Preparation(Policy))
  }
  match
    reserve_request_domain_graph_construction(owner, input, prepared, bytes) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let sources : Array[@sourceviews.SourceAcquisition] = []
  let mut query_selected = false
  for index in 0..<count {
    guard @publication_host.client_direct_acquisition_occurrence_at(
        direct, index,
      )
      is Some((stage, source_index, _)) else {
      return Err(Preparation(ForeignOriginal))
    }
    match
      select_installed_source_input(prepared, request, stage, source_index) {
      Err(issue) => return Err(Installed(issue))
      Ok(@sourceviews.WholeInputRoute(source)) if !query_selected =>
        sources.push(source)
      Ok(@sourceviews.QueryRoute(_)) if select_query && sources.is_empty() =>
        query_selected = true
      // These constructors have distinct ownership. Mixed routes are outside
      // the existing Native file profile, and cannot select either plan.
      Ok(_) => return Err(Installed(Unsupported))
    }
  }
  Ok((direct, sources))
}
