///|
pub enum SortStrategy {
  CandidateKey(SortCompletion)
  ExistingTotal(LogicalOrder)
}

///|
/// Owned resolution for a nonempty sort, not an execution certificate.
struct SortOrder {
  pipeline : CheckedPipeline
  index : Int
  order : LogicalOrder
  strategy : SortStrategy
}

///|
/// None for a non-sort, empty sort, invalid index, or unresolved nonempty sort.
/// Empty sorts retain input evidence through logical_order without generating it.
pub fn sort_order(p : CheckedPipeline, index : Int) -> SortOrder? {
  guard p.steps.get(index) is Some({ operation: Unary(op), .. }) &&
    @relation.operation(op) == @relation.Sort &&
    @relation.sort_term_count(op) > 0 else {
    return None
  }
  guard logical_order(p, Step(index)) is Some(order) else { return None }
  let strategy : SortStrategy = match (order.completion, order.tie_order) {
    (Some(c), _) => CandidateKey(c)
    (None, Some(prior)) => ExistingTotal(prior)
    _ => return None
  }
  Some({ pipeline: p, index, order, strategy, })
}

///|
pub fn sort_order_pipeline(v : SortOrder) -> CheckedPipeline {
  v.pipeline
}

///|
pub fn sort_order_step(v : SortOrder) -> Int {
  v.index
}

///|
/// Retains authored keys, direction, null placement and original source.
pub fn sort_order_consumer(v : SortOrder) -> CheckedStep {
  v.pipeline.steps[v.index]
}

///|
pub fn sort_order_input(v : SortOrder) -> Target {
  v.pipeline.steps[v.index].input.unwrap()
}

///|
pub fn sort_order_strategy(v : SortOrder) -> SortStrategy {
  v.strategy
}

///|
pub fn sort_order_evidence(v : SortOrder) -> LogicalOrder {
  v.order
}

///|
/// Tie-only dependency, never a claim that the entire prior order is preserved.
/// Coordinates belong to the originating pipeline; imported owners remain explicit.
pub fn order_tie_break(order : LogicalOrder) -> LogicalOrder? {
  order.tie_order
}
