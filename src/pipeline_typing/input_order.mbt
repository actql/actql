///|
/// Conditional resolution of an existing-input-order obligation, not execution.
struct InputOrderResolution {
  consumer : CheckedStep
  requirement : @relation.ValidationKind
  input : Target
  order : LogicalOrder
}

///|
/// Only prefix watermark and pivot(first) require this exact input sequence.
/// None means unsupported/not applicable, invalid index, or unresolved order.
/// Does not complete a key, reorder input, or use the consumer's output order.
pub fn resolve_existing_input_order(
  p : CheckedPipeline,
  index : Int,
) -> InputOrderResolution? {
  guard p.steps.get(index) is Some(consumer) else { return None }
  guard consumer.operation is Unary(op) else { return None }
  guard @relation.existing_order_requirement(op) is Some(requirement) else {
    return None
  }
  guard consumer.input is Some(input) else { return None }
  guard logical_order(p, input) is Some(order) else { return None }
  Some({ consumer, requirement, input, order, })
}

///|
pub fn input_order_consumer(r : InputOrderResolution) -> CheckedStep {
  r.consumer
}

///|
pub fn input_order_requirement(
  r : InputOrderResolution,
) -> @relation.ValidationKind {
  r.requirement
}

///|
pub fn input_order_target(r : InputOrderResolution) -> Target {
  r.input
}

///|
pub fn input_order_evidence(r : InputOrderResolution) -> LogicalOrder {
  r.order
}
