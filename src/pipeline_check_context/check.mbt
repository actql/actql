///|
pub(all) struct Limits {
  max_steps : Int
  max_results : Int
  max_work : Int
  max_text_bytes : Int
}

///|
pub(all) enum Issue {
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
  let (order_work, order_text) = @results.checked_orders_usage(orders)
  let closure = @results.checked_producer_orders(orders)
  let expressions = match
    collect_expression_requirements(closure, limits.max_work - order_work) {
    Ok(v) => v
    Err(e) => return Err(Expressions(e))
  }
  let guards = match
    @pipeline.bind_contextual_guards(
      closure,
      bindings,
      max_work=limits.max_work - order_work - expressions.work,
      max_text_bytes=limits.max_text_bytes - order_text,
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
      max_work=limits.max_work - order_work - expressions.work - guard_work,
    ) {
    Ok(v) => v
    Err(e) => return Err(Capacity(e))
  }
  Ok({
    results,
    orders,
    guards,
    capacity,
    expressions,
    work: order_work +
    expressions.work +
    guard_work +
    @capacity.application_closure_work(capacity),
    text: order_text + guard_text,
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
