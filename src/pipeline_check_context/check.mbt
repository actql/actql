///|
pub(all) struct Limits {
  max_steps : Int
  max_results : Int
  max_work : Int
  max_text_bytes : Int
}

///|
pub(all) enum Issue {
  InvalidIntegrationLimits
  PriorOrderLimit
  Expressions(ExpressionRequirementIssue)
  Orders(@results.OrderCheckIssue)
  Guards(@pipeline.ProducerOrderIssue)
  Capacity(@capacity.ApplicationClosureIssue)
}

///|
/// An integrated order/binding/capacity context, not a complete CheckedProgram.
/// Other static obligations, semantic identities and execution remain separate.
struct PipelineContext {
  results : @results.CheckedResults
  orders : @results.CheckedOrders
  guards : @pipeline.BoundGuardClosure
  capacity : @capacity.ApplicationClosure
  expressions : ExpressionRequirements
  work : Int
  text : Int
}

///|
/// Exact resolved producer/publication orders and outstanding expression sites,
/// retained before guard or execution-value binding. This is not static closure.
struct PipelineOrderPreparation {
  results : @results.CheckedResults
  orders : @results.CheckedOrders
  expressions : ExpressionRequirements
  work : Int
  text : Int
}

///|
pub fn prepare_pipeline_orders(
  orders : @results.CheckedOrders,
  max_work~ : Int,
  max_text_bytes~ : Int,
) -> Result[PipelineOrderPreparation, Issue] {
  if max_work < 0 || max_text_bytes < 0 {
    return Err(InvalidIntegrationLimits)
  }
  let (order_work, order_text) = @results.checked_orders_usage(orders)
  if order_work > max_work || order_text > max_text_bytes {
    return Err(PriorOrderLimit)
  }
  let results = @results.publication_orders_results(
    @results.checked_publication_orders(orders),
  )
  let expressions = match
    collect_expression_requirements(
      @results.checked_producer_orders(orders),
      max_work - order_work,
    ) {
    Ok(v) => v
    Err(e) => return Err(Expressions(e))
  }
  Ok({
    results,
    orders,
    expressions,
    work: order_work + expressions.work,
    text: order_text,
  })
}

///|
pub fn prepared_pipeline_orders(
  value : PipelineOrderPreparation,
) -> @results.CheckedOrders {
  value.orders
}

///|
pub fn prepared_pipeline_results(
  value : PipelineOrderPreparation,
) -> @results.CheckedResults {
  value.results
}

///|
pub fn prepared_pipeline_order_usage(
  value : PipelineOrderPreparation,
) -> (Int, Int) {
  (value.work, value.text)
}

///|
pub fn prepared_expression_requirement_count(
  value : PipelineOrderPreparation,
) -> Int {
  value.expressions.entries.length()
}

///|
pub fn prepared_expression_requirement_at(
  value : PipelineOrderPreparation,
  index : Int,
) -> ExpressionRequirement? {
  value.expressions.entries.get(index)
}

///|
/// Resolve orders and guard bindings internally before checking all producer
/// capacity owners. No independent closure handles or partial success escape.
/// Bindings and capacity entries follow contextual producer occurrence order;
/// repeated and unused visits remain distinct and are checked individually.
pub fn check(
  results : @results.CheckedResults,
  bindings : Array[@parameter.BoundValues?],
  applications : Array[@capacity.ApplicationCoverage],
  selected_policy : @policy.Policy,
  limits : Limits,
  proof_owners? : Array[(Int, Int, Int)] = [],
  input_owners? : Array[(Int, Int, Int, Int)] = [],
) -> Result[PipelineContext, Issue] {
  let orders = match
    @results.resolve_all_orders(results, {
      max_steps: limits.max_steps,
      max_results: limits.max_results,
      max_work: limits.max_work,
      max_text_bytes: limits.max_text_bytes,
    }) {
    Ok(v) => v
    Err(e) => return Err(Orders(e))
  }
  check_resolved_orders(
    orders,
    bindings,
    applications,
    selected_policy,
    max_work=limits.max_work,
    max_text_bytes=limits.max_text_bytes,
    proof_owners~,
    input_owners~,
  )
}

///|
/// Reuse one opaque resolved-order owner for both prepared publication ports
/// and this context. Result and producer owners are derived from that object,
/// never supplied independently. Caps include its already consumed work/text;
/// step and Result admission limits belong to the earlier order resolution.
pub fn check_resolved_orders(
  orders : @results.CheckedOrders,
  bindings : Array[@parameter.BoundValues?],
  applications : Array[@capacity.ApplicationCoverage],
  selected_policy : @policy.Policy,
  max_work~ : Int,
  max_text_bytes~ : Int,
  proof_owners? : Array[(Int, Int, Int)] = [],
  input_owners? : Array[(Int, Int, Int, Int)] = [],
) -> Result[PipelineContext, Issue] {
  let prepared = match
    prepare_pipeline_orders(orders, max_work~, max_text_bytes~) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  bind_prepared_pipeline_orders(
    prepared,
    bindings,
    applications,
    selected_policy,
    max_work~,
    max_text_bytes~,
    proof_owners~,
    input_owners~,
  )
}

///|
/// Continue the exact retained order/expression owner through the existing
/// guard and capacity checks. Absence is not a fabricated Parameter value set.
pub fn bind_prepared_pipeline_orders(
  prepared : PipelineOrderPreparation,
  bindings : Array[@parameter.BoundValues?],
  applications : Array[@capacity.ApplicationCoverage],
  selected_policy : @policy.Policy,
  max_work~ : Int,
  max_text_bytes~ : Int,
  proof_owners? : Array[(Int, Int, Int)] = [],
  input_owners? : Array[(Int, Int, Int, Int)] = [],
) -> Result[PipelineContext, Issue] {
  if max_work < 0 || max_text_bytes < 0 {
    return Err(InvalidIntegrationLimits)
  }
  if prepared.work > max_work || prepared.text > max_text_bytes {
    return Err(PriorOrderLimit)
  }
  let closure = @results.checked_producer_orders(prepared.orders)
  let guards = match
    @pipeline.bind_contextual_guards(
      closure,
      bindings,
      max_work=max_work - prepared.work,
      max_text_bytes=max_text_bytes - prepared.text,
    ) {
    Ok(v) => v
    Err(e) => return Err(Guards(e))
  }
  let (guard_work, guard_text) = @pipeline.bound_guard_closure_usage(guards)
  let capacity = match
    @capacity.check_application_closure(
      closure,
      applications,
      selected_policy~,
      bound_guards=guards,
      proof_owners~,
      input_owners~,
      max_work=max_work - prepared.work - guard_work,
    ) {
    Ok(v) => v
    Err(e) => return Err(Capacity(e))
  }
  Ok({
    results: prepared.results,
    orders: prepared.orders,
    guards,
    capacity,
    expressions: prepared.expressions,
    work: prepared.work +
    guard_work +
    @capacity.application_closure_work(capacity),
    text: prepared.text + guard_text,
  })
}

///|
pub fn checked_results(v : PipelineContext) -> @results.CheckedResults {
  v.results
}

///|
pub fn checked_orders(v : PipelineContext) -> @results.CheckedOrders {
  v.orders
}

///|
pub fn bound_guards(v : PipelineContext) -> @pipeline.BoundGuardClosure {
  v.guards
}

///|
pub fn checked_capacity(v : PipelineContext) -> @capacity.ApplicationClosure {
  v.capacity
}

///|
/// Integration cost, including retained local capacity coverage costs; excludes
/// prior source/type admission and construction of the supplied local evidence.
pub fn usage(v : PipelineContext) -> (Int, Int) {
  (v.work, v.text)
}
