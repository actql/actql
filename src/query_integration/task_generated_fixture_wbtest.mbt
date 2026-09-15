///|
/// Common completion setup without constructing Local fragments or evaluator
/// contexts. Registry validation and the typed semantic sequence are sufficient
/// for preparation, but never substitute for execution evidence.
fn task_test_completion(
  owner : @lower.BoundPrepared,
) -> @execution.CompletionPreparation raise {
  let sequence = prepared_sequence(owner)
  let last = @lower.node_at(
    @lower.bound_preparation(owner),
    @lower.sequence_count(sequence) - 1,
  ).unwrap()
  @execution.prepare_completion(
    registered_relation_contracts(),
    sequence,
    [@lower.node_id(last)],
    100000,
    10000,
  ).unwrap()
}

///|
/// Reuse the real Local sequence compiler and its exact expression contexts.
/// No assumption about a demonstration task's operation count or positions.
fn task_test_generated(
  owner : @lower.BoundPrepared,
) -> @execution.GeneratedSequence raise {
  let sequence = prepared_sequence(owner)
  let contexts = []
  for step in 0..<@lower.sequence_count(sequence) {
    if @lower.sequence_step(sequence, step) is Some(RowStep(kernel)) {
      match @lower.kernel_body(kernel) {
        SnapshotMap(_) | OrderedBindings(_) | Filter(_) =>
          contexts.push(sequence_fragment_context(sequence, step, 10L))
        _ => ()
      }
    }
  }
  let last = @lower.node_at(
    @lower.bound_preparation(owner),
    @lower.sequence_count(sequence) - 1,
  ).unwrap()
  @execution.prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    contexts,
    [@lower.node_id(last)],
    100000,
    10000,
  ).unwrap()
}
