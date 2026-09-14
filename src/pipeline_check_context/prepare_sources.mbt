///|
pub enum PrepareSourcesIssue {
  InvalidLimits
  BudgetExceeded
  Declarations(@binding_declarations.Issue)
  Slots(@request_slots.Issue)
  Requests(SourceRequestIssue)
  Rows(SourceRowsIssue)
  Policy(SourcePolicyIssue)
  Capacity(SourceCapacityIssue)
  Producers(SourceProducerIssue)
}

///|
/// Prepare the request branch from the selected context's Program. Row bounds
/// and producer coordinates remain explicit checked evidence, not inferred
/// empty collections or caller-assembled request successes.
pub fn prepare_program_sources(
  selected : SelectedPolicyContext,
  bounds : Array[Array[@step_bounds.TargetRows]],
  locations : Array[Array[(Int, Int)]],
  limits : @sourceviews.RequestLimits,
  max_bindings~ : Int,
  max_slots~ : Int,
) -> Result[SourceProducerContext, PrepareSourcesIssue] {
  prepare_program_sources_internal(
    selected,
    Some(bounds),
    Some(locations),
    limits,
    max_bindings~,
    max_slots~,
  )
}

///|
/// Construct acquisition bounds from the selected Program's own capacity
/// applications. Coordinates select candidates; all target, policy and producer
/// checks remain mandatory. This does not admit rows or authorize acquisition.
pub fn prepare_program_source_acquisitions(
  selected : SelectedPolicyContext,
  locations : Array[Array[(Int, Int)]],
  limits : @sourceviews.RequestLimits,
  max_bindings~ : Int,
  max_slots~ : Int,
) -> Result[SourceProducerContext, PrepareSourcesIssue] {
  prepare_program_sources_internal(
    selected,
    None,
    Some(locations),
    limits,
    max_bindings~,
    max_slots~,
  )
}

///|
/// Select applicable positive row bounds from the owned capacity closures.
/// No proof coordinates or independently reconstructed TargetRows are required.
pub fn prepare_program_source_acquisitions_auto(
  selected : SelectedPolicyContext,
  limits : @sourceviews.RequestLimits,
  max_bindings~ : Int,
  max_slots~ : Int,
) -> Result[SourceProducerContext, PrepareSourcesIssue] {
  prepare_program_sources_internal(
    selected,
    None,
    None,
    limits,
    max_bindings~,
    max_slots~,
  )
}

///|
fn prepare_program_sources_internal(
  selected : SelectedPolicyContext,
  bounds : Array[Array[@step_bounds.TargetRows]]?,
  locations : Array[Array[(Int, Int)]]?,
  limits : @sourceviews.RequestLimits,
  max_bindings~ : Int,
  max_slots~ : Int,
) -> Result[SourceProducerContext, PrepareSourcesIssue] {
  if limits.max_work < 0 ||
    limits.max_pairs < 0 ||
    limits.values.max_nodes < 0 ||
    limits.values.max_depth < 0 ||
    limits.values.max_text_bytes < 0 ||
    max_bindings < 0 ||
    max_slots < 0 {
    return Err(InvalidLimits)
  }
  if selected.usage.work >= limits.max_work {
    return Err(BudgetExceeded)
  }
  let inputs = selected.context
  let source = @stages.operations_source(
    @stages.bound_operations(inputs.wired.stages.operations),
  )
  // Declaration work is included by slot collection, which is in turn included
  // by request checking. Reserve the nonshared policy work and owner join.
  let remaining = limits.max_work - selected.usage.work - 1
  let declarations = match
    @binding_declarations.prepare(@stages.program(source), {
      max_work: remaining,
      max_bindings,
    }) {
    Ok(v) => v
    Err(e) => return Err(Declarations(e))
  }
  let slots = match
    @request_slots.collect(source, declarations, {
      max_work: remaining,
      max_slots,
    }) {
    Ok(v) => v
    Err(e) => return Err(Slots(e))
  }
  let request_work = inputs.usage.work + remaining
  let requests = match
    check_source_requests(inputs, slots, { ..limits, max_work: request_work, }) {
    Ok(v) => v
    Err(e) => return Err(Requests(e))
  }
  let automatic = match locations {
    None =>
      match select_source_acquisition_rows(requests, request_work) {
        Ok(value) => Some(value)
        Err(error) => return Err(error)
      }
    Some(_) => None
  }
  let row_result = match (automatic, bounds) {
    (Some((rows, _)), _) => Ok(rows)
    (None, Some(values)) =>
      check_source_row_bounds(requests, values, request_work)
    (None, None) =>
      prepare_source_row_bounds(requests, locations.unwrap(), request_work)
  }
  let rows = match row_result {
    Ok(v) => v
    Err(e) => return Err(Rows(e))
  }
  let policy = match bind_source_policy(rows, selected, limits.max_work) {
    Ok(v) => v
    Err(e) => return Err(Policy(e))
  }
  let capacity = match check_source_capacity(policy, limits.max_work) {
    Ok(v) => v
    Err(e) => return Err(Capacity(e))
  }
  if automatic is Some((_, memberships)) {
    // Selection validated these memberships against the same immutable closure
    // and the exact TargetRows retained by capacity. Do not reconstruct them.
    return Ok({ capacity, memberships, work: capacity.work, })
  }
  match bind_source_producers(capacity, locations.unwrap(), limits.max_work) {
    Ok(v) => Ok(v)
    Err(e) => Err(Producers(e))
  }
}
