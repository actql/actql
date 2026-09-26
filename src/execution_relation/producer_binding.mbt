///|
/// Exact completed producer selection and its checked input projection.
/// Binding does not discharge receiving input resource accounting.
struct BoundProducerInput {
  // Process-local identity only; retaining it does not retain the producer data.
  identity : ProducerBindingIdentity
  receiver : @lower.BoundPrepared
  consumer_step : Int?
  input_index : Int
  output : CompletedOutput
  projection : @lower.PreparedProjection?
}

///|
/// Immutable process-local binding identity; no producer rows or live closure.
priv struct ProducerBindingIdentity {
  input_index : Int
  carrier : @managed_carrier.ProducerReadReference?
  supplied : CapturedRows?
}

///|
/// Host-owned occurrence of one checked root Result. The authored name is
/// diagnostic; identity is the exact checked Program owner and ResultPort.
/// Two aliases of the same port remain distinct publication occurrences.
struct ManagedResultOccurrence {
  identity : Ref[Unit]
  owner : @lower.BoundPrepared
  name : String
  port : @results.ResultPort
}

///|
pub(all) enum ManagedResultOccurrenceIssue {
  EmptyName
  ForeignOwner
} derive(Eq, Debug)

///|
/// Bind a root export already admitted by checked Result wiring. Possession of
/// a name alone cannot construct or recover an occurrence.
pub fn bind_managed_result_occurrence(
  owner : @lower.BoundPrepared,
  name : String,
  port : @results.ResultPort,
) -> Result[ManagedResultOccurrence, ManagedResultOccurrenceIssue] {
  if name.is_empty() {
    return Err(EmptyName)
  }
  if !physical_equal(
      @pipeline.producer_pipeline(@results.port_input(port)),
      @lower.pipeline(@lower.bound_preparation(owner)),
    ) {
    return Err(ForeignOwner)
  }
  Ok({ identity: Ref(()), owner, name, port, })
}

///|
pub fn managed_result_occurrence_owner(
  occurrence : ManagedResultOccurrence,
) -> @lower.BoundPrepared {
  occurrence.owner
}

///|
pub fn managed_result_occurrence_name(
  occurrence : ManagedResultOccurrence,
) -> String {
  occurrence.name
}

///|
pub fn managed_result_occurrence_same(
  left : ManagedResultOccurrence,
  right : ManagedResultOccurrence,
) -> Bool {
  physical_equal(left.identity, right.identity)
}

///|
pub fn managed_result_occurrence_port(
  occurrence : ManagedResultOccurrence,
) -> @results.ResultPort {
  occurrence.port
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
    identity: { input_index, carrier: None, supplied: None, },
    receiver,
    consumer_step: None,
    input_index,
    output,
    projection: @lower.preparation_input_projection(
      @lower.bound_preparation(receiver),
      input_index,
    ),
  })
}

///|
/// Retain an internal Relation edge as its original checked operation input.
/// Its position is not an author-visible pipeline input.
pub fn bind_completed_operation_input(
  receiver : @lower.BoundPrepared,
  consumer_step : Int,
  input_index : Int,
  expected_producer : @lower.BoundPrepared,
  output : CompletedOutput,
) -> Result[BoundProducerInput, ProducerBindingIssue] {
  if !completed_output_available(output) {
    return Err(ProducerUnavailable)
  }
  let prepared = @lower.bound_preparation(receiver)
  guard physical_equal(receiver, expected_producer) &&
    physical_equal(
      @lower.sequence_owner(output.completion.sequence),
      expected_producer,
    ) &&
    @lower.node_at(prepared, consumer_step) is Some(node) &&
    @lower.node_input_target(node, input_index) is Some(target) &&
    target is @pipeline.Step(_) &&
    target == output.target &&
    @lower.preparation_schema_at(prepared, target) is Some(_) else {
    return Err(ProducerBindingMismatch)
  }
  Ok({
    identity: { input_index, carrier: None, supplied: None, },
    receiver,
    consumer_step: Some(consumer_step),
    input_index,
    output,
    projection: None,
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
