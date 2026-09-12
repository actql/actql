///|
/// A retained order can carry historical key_order metadata. Only the exact
/// local take that establishes it may materialize that completion again.
/// Resolve through the owning pipeline, never through an unowned order token.
fn take_completion(
  owner : @pipeline.CheckedPipeline,
  index : Int,
) -> @evidence.KeyedRelation? {
  guard @pipeline.take_order(owner, index) is Some(order) else { return None }
  if @pipeline.order_origin(order) != @pipeline.Step(index) ||
    @pipeline.order_input_producer(order) is Some(_) {
    return None
  }
  guard @pipeline.order_producer(order) is Some(producer) else { return None }
  guard @pipeline.step_at(owner, index) is Some(step) else { return None }
  if !physical_equal(producer, step) {
    return None
  }
  @pipeline.order_key_completion(order)
}
