///|
pub enum PreparedStageIssue {
  InvalidLimits
  MissingStage
  BudgetExceeded
  Context(Issue)
  Parameters(ParameterIssue)
}

///|
/// Select order and Parameter owners from one prepared Local source. Capacity
/// applications and cross-producer ownership claims still undergo the existing
/// validation; this is not whole-Program closure or execution permission.
/// Work includes retained Stage orders and this integration, not source parsing
/// or the complete Local preparation prefix.
pub fn check_prepared_local_stage(
  prepared : @stage_results.PreparedLocalSource,
  index : Int,
  applications : Array[@capacity.ApplicationCoverage],
  selected_policy : @policy.Policy,
  max_work~ : Int,
  max_text_bytes~ : Int,
  proof_owners? : Array[(Int, Int, Int)] = [],
  input_owners? : Array[(Int, Int, Int, Int)] = [],
) -> Result[BoundParameters, PreparedStageIssue] {
  if max_work < 0 || max_text_bytes < 0 {
    return Err(InvalidLimits)
  }
  let port = match
    @stage_results.wiring_stage_at(
      @stage_results.local_source_wiring(prepared),
      index,
    ) {
    None => return Err(MissingStage)
    Some(v) => v
  }
  let orders = @results.ports_orders(
    @stage_results.stage_port_publications(port),
  )
  let count = @pipeline.contextual_closure_count(
    @results.checked_producer_orders(orders),
  )
  let (prior_work, prior_text) = @results.checked_orders_usage(orders)
  if prior_work > max_work ||
    count > max_work - prior_work ||
    prior_text > max_text_bytes {
    return Err(BudgetExceeded)
  }
  let bindings = Array::make(
    count,
    Some(@stage_results.local_source_values(prepared)),
  )
  let context = match
    check_resolved_orders(
      orders,
      bindings,
      applications,
      selected_policy,
      max_work=max_work - count,
      max_text_bytes~,
      proof_owners~,
      input_owners~,
    ) {
    Ok(v) => v
    Err(e) => return Err(Context(e))
  }
  match
    check_parameter_bindings(
      context,
      max_work=max_work - count,
      max_text_bytes~,
    ) {
    Ok(v) => Ok({ ..v, work: v.work + count, })
    Err(e) => Err(Parameters(e))
  }
}
