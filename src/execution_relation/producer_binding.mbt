///|
/// Exact completed producer selection and its checked input projection.
/// Binding does not discharge receiving input resource accounting.
struct BoundProducerInput {
  receiver : @lower.BoundPrepared
  input_index : Int
  output : CompletedOutput
  projection : @relation.CheckedOperation?
}

///|
pub(all) enum ProducerBindingIssue {
  NotProducedInput
  ProducerOwnerMismatch
  ProducerBindingMismatch
  ProducerTargetMismatch
  ProducerUnavailable
}

///|
/// The dependency environment supplies the expected *bound* producer explicitly:
/// ProducedInput retains a CheckedPipeline, which alone cannot distinguish two
/// invocations using different Parameter bindings. Never infer the invocation
/// from matching schema, rows, source text or the unbound pipeline identity.
pub fn bind_completed_input(
  receiver : @lower.BoundPrepared,
  input_index : Int,
  expected_producer : @lower.BoundPrepared,
  output : CompletedOutput,
) -> Result[BoundProducerInput, ProducerBindingIssue] {
  if !completion_is_live(output.completion) {
    return Err(ProducerUnavailable)
  }
  let pipeline = @lower.pipeline(@lower.bound_preparation(receiver))
  guard @pipeline.input_producer(pipeline, input_index) is Some(producer) else {
    return Err(NotProducedInput)
  }
  if !physical_equal(
      @pipeline.producer_pipeline(producer),
      @lower.pipeline(@lower.bound_preparation(expected_producer)),
    ) {
    return Err(ProducerOwnerMismatch)
  }
  if !physical_equal(
      @lower.sequence_owner(output.completion.sequence),
      expected_producer,
    ) {
    return Err(ProducerBindingMismatch)
  }
  if output.target != @pipeline.producer_target(producer) {
    return Err(ProducerTargetMismatch)
  }
  Ok({
    receiver,
    input_index,
    output,
    projection: @pipeline.producer_projection(producer),
  })
}
