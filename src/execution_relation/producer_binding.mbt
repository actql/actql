///|
/// Exact completed producer selection for one receiving input. This is not yet
/// row adoption or permission to skip receiving input resource accounting.
priv struct BoundProducerInput {
  receiver : @lower.BoundPrepared
  input_index : Int
  output : CompletedOutput
}

///|
priv enum ProducerBindingIssue {
  NotProducedInput
  ProducerOwnerMismatch
  ProducerBindingMismatch
  ProducerTargetMismatch
  ProjectionExecutionPending
}

///|
/// The dependency environment supplies the expected *bound* producer explicitly:
/// ProducedInput retains a CheckedPipeline, which alone cannot distinguish two
/// invocations using different Parameter bindings. Never infer the invocation
/// from matching schema, rows, source text or the unbound pipeline identity.
fn bind_completed_input(
  receiver : @lower.BoundPrepared,
  input_index : Int,
  expected_producer : @lower.BoundPrepared,
  output : CompletedOutput,
) -> Result[BoundProducerInput, ProducerBindingIssue] {
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
  if @pipeline.producer_projection(producer) is Some(_) {
    return Err(ProjectionExecutionPending)
  }
  Ok({ receiver, input_index, output, })
}
