///|
pub enum PipelineAuthoringContextIssue {
  InvalidLimits
  BudgetExceeded
  ForeignOrders
  UnsupportedInputs
  Values(ValuesCapacityIssue)
  Capacity(@capacity.PreparationIssue)
  Context(Issue)
  Orders(OperationOrderIssue)
}

///|
priv struct AuthoringOrderLink {
  requirement : AuthoringOrderRequirement
  resolution : @pipeline.ContextualOrder
}

///|
/// Static capacity context for a fully closed, source-free authoring pipeline.
/// Actual Values proof preparation and guard/capacity application are shared
/// with bound checking. Publication closure and the complete Program remain
/// separate; this owner cannot grant execution or complete template checking.
struct PipelineAuthoringContext {
  authoring : PipelineAuthoringClosure
  orders : PipelineOrderPreparation
  material : ValuesCapacityMaterial
  context : PipelineContext
  order_links : Array[AuthoringOrderLink]
  work : Int
}

///|
pub fn prepare_pipeline_authoring_context(
  authoring : PipelineAuthoringClosure,
  orders : PipelineOrderPreparation,
  limits : CapacityStageLimits,
  metadata : @wire.Limits,
) -> Result[PipelineAuthoringContext, PipelineAuthoringContextIssue] {
  if limits.max_work < 0 ||
    limits.max_text_bytes < 0 ||
    limits.max_name_bytes < 0 ||
    limits.max_input_work < 0 ||
    limits.max_operand_work < 0 ||
    metadata.max_bytes < 0 ||
    metadata.max_nodes < 0 ||
    metadata.max_depth < 0 {
    return Err(InvalidLimits)
  }
  let pipeline = authoring.profiles.pipeline
  if !physical_equal(@results.pipeline(orders.results), pipeline) {
    return Err(ForeignOrders)
  }
  let producers = @results.checked_producer_orders(orders.orders)
  if @pipeline.input_count(pipeline) != 0 ||
    @pipeline.contextual_closure_count(producers) != 1 {
    return Err(UnsupportedInputs)
  }
  if !physical_equal(
      @pipeline.contextual_orders_pipeline(
        @pipeline.contextual_closure_at(producers, 0).unwrap(),
      ),
      pipeline,
    ) {
    return Err(ForeignOrders)
  }
  if authoring.work >= limits.max_work ||
    orders.work > limits.max_work - authoring.work - 1 ||
    orders.text > limits.max_text_bytes {
    return Err(BudgetExceeded)
  }
  let mut work = authoring.work + orders.work + 1
  // Use the already resolved producer orders for exactly this pipeline. Static
  // operation requirements are not runtime facts or independently re-inferred
  // ordering, and their original requirement owner remains retained.
  let producer = @pipeline.contextual_closure_at(producers, 0).unwrap()
  let order_links : Array[AuthoringOrderLink] = []
  let mut previous_step = -1
  let mut indexed = empty_operation_orders()
  for i in 0..<authoring.orders.length() {
    let requirement = authoring.orders[i]
    if work == limits.max_work {
      return Err(BudgetExceeded)
    }
    work += 1
    if requirement.step != previous_step {
      guard @pipeline.contextual_order_count(producer, requirement.step)
        is Some(count) else {
        return Err(Orders(ForeignOwner(i)))
      }
      if work == limits.max_work || count > limits.max_work - work - 1 {
        return Err(BudgetExceeded)
      }
      work += count + 1
      indexed = empty_operation_orders()
      for index in 0..<count {
        let resolution = @pipeline.contextual_order_at(
          producer,
          requirement.step,
          index,
        ).unwrap()
        if !retain_operation_order(indexed, resolution) {
          return Err(Orders(AmbiguousResolution(i)))
        }
      }
      previous_step = requirement.step
    }
    guard select_operation_order(indexed, requirement.demand)
      is Some(resolution) else {
      return Err(Orders(MissingResolution(i, requirement.demand)))
    }
    order_links.push({ requirement, resolution, })
  }
  let material = match
    derive_values_capacity_material(
      pipeline,
      { sources: empty_capacity_input_sources(), consumers: [], },
      limits.max_work - work,
      metadata,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Values(issue))
  }
  work += material.work
  let policy = @environment.capacity_policy(authoring.capacity)
  let coverage = match
    @capacity.prepare_application_coverage(
      pipeline,
      material.material.sources,
      policy,
      [],
      {
        max_work: limits.max_work - work,
        max_name_bytes: limits.max_name_bytes.min(
          limits.max_text_bytes - orders.text,
        ),
        max_input_work: limits.max_input_work,
        max_operand_work: limits.max_operand_work,
      },
    ) {
    Ok(value) => value
    Err(issue) => return Err(Capacity(issue))
  }
  work += @capacity.application_coverage_work(coverage)
  // The shared order prefix and coverage are already owned here. Continue the
  // same context path with only the remaining budget plus those exact prefixes.
  let context_prefix = orders.work +
    @capacity.application_coverage_work(coverage)
  let context = match
    bind_prepared_pipeline_orders(
      orders,
      [None],
      [coverage],
      policy,
      max_work=context_prefix + (limits.max_work - work),
      max_text_bytes=limits.max_text_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Context(issue))
  }
  work += context.work - context_prefix
  Ok({ authoring, orders, material, context, order_links, work, })
}

///|
pub fn pipeline_authoring_context_source(
  value : PipelineAuthoringContext,
) -> PipelineAuthoringClosure {
  value.authoring
}

///|
pub fn pipeline_authoring_context_orders(
  value : PipelineAuthoringContext,
) -> PipelineOrderPreparation {
  value.orders
}

///|
pub fn pipeline_authoring_context_pipeline(
  value : PipelineAuthoringContext,
) -> PipelineContext {
  value.context
}

///|
pub fn pipeline_authoring_context_usage(
  value : PipelineAuthoringContext,
) -> (Int, Int, Int) {
  (value.work, value.material.metadata_bytes, value.material.metadata_nodes)
}

///|
/// Static links retain the exact operation obligation and contextual producer
/// resolution. They confer no execution-value or authority facts.
pub fn pipeline_authoring_context_order_count(
  value : PipelineAuthoringContext,
) -> Int {
  value.order_links.length()
}

///|
pub fn pipeline_authoring_context_order_at(
  value : PipelineAuthoringContext,
  index : Int,
) -> (Int, @pipeline.OperationObligations, Int, @pipeline.ContextualOrder)? {
  value.order_links
  .get(index)
  .map(link => {
    (
      link.requirement.step,
      link.requirement.owner,
      link.requirement.index,
      link.resolution,
    )
  })
}
