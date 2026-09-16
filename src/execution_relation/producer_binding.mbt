///|
/// Exact completed producer selection and its checked input projection.
/// Binding does not discharge receiving input resource accounting.
struct BoundProducerInput {
  // Process-local identity only; retaining it does not retain the producer data.
  identity : ProducerBindingIdentity
  receiver : @lower.BoundPrepared
  input_index : Int
  output : CompletedOutput
  projection : @lower.PreparedProjection?
}

///|
/// Immutable process-local binding identity; no producer rows or live closure.
priv struct ProducerBindingIdentity {
  input_index : Int
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
  if !completed_output_available(output) {
    return Err(ProducerUnavailable)
  }
  match
    validate_producer_binding_owner(
      receiver,
      input_index,
      expected_producer,
      @lower.sequence_owner(output.completion.sequence),
      output.target,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  Ok({
    identity: { input_index, },
    receiver,
    input_index,
    output,
    projection: @lower.preparation_input_projection(
      @lower.bound_preparation(receiver),
      input_index,
    ),
  })
}

///|
/// Shared ownership-only check for legacy and managed completion. Keep frontend
/// identity traversal at this boundary, not in physical readers or evaluators.
fn validate_producer_binding_owner(
  receiver : @lower.BoundPrepared,
  input_index : Int,
  expected_producer : @lower.BoundPrepared,
  actual_producer : @lower.BoundPrepared,
  target : @pipeline.Target,
) -> Result[Unit, ProducerBindingIssue] {
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
  if !physical_equal(actual_producer, expected_producer) {
    return Err(ProducerBindingMismatch)
  }
  if target != @pipeline.producer_target(producer) {
    return Err(ProducerTargetMismatch)
  }
  Ok(())
}

///|
/// Add a live admission condition to an existing successful output. This only
/// narrows authority: the original completion must remain live as well. The
/// predicate is synchronous and side-effect-free, installed by the owning
/// integration (never inferred from a serialized claim). No data is copied or
/// re-admitted. Already completed consumers keep their independent results.
pub fn bind_live_completed_input(
  receiver : @lower.BoundPrepared,
  input_index : Int,
  expected_producer : @lower.BoundPrepared,
  output : CompletedOutput,
  live : () -> Bool,
) -> Result[BoundProducerInput, ProducerBindingIssue] {
  bind_completed_input(
    receiver,
    input_index,
    expected_producer,
    restrict_completed_output(output, live),
  )
}
