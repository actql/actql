///|
/// Conditional position completion within authored peer groups, not peer order
/// or publication order. Inspect obligations in the originating pipeline.
struct AnalyticPositionOrder {
  consumer : CheckedStep
  input : Target
  completion : SortCompletion?
  retained : LogicalOrder?
}

///|
pub fn analytic_position_order(
  p : CheckedPipeline,
  index : Int,
) -> AnalyticPositionOrder? {
  p.analytic_orders.get(index).bind(v => v)
}

///|
pub fn analytic_order_consumer(order : AnalyticPositionOrder) -> CheckedStep {
  order.consumer
}

///|
pub fn analytic_order_input(order : AnalyticPositionOrder) -> Target {
  order.input
}

///|
pub fn analytic_order_completion(
  order : AnalyticPositionOrder,
) -> SortCompletion? {
  order.completion
}

///|
/// Stable position within equal authored peer keys, not a replacement for them.
pub fn analytic_order_retained(order : AnalyticPositionOrder) -> LogicalOrder? {
  order.retained
}
