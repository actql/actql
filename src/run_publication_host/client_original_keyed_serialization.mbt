///|
// Core Local's closed synchronous receiver. No Node Ledger getter, Source
// observation reconstruction, Model permission or additional execution Owner.
pub fn borrow_client_original_keyed_serialization_inputs(
  scope : ClientModelReadScope,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  prepared : PreparedClientProgram,
  value : ClientOriginalKeyedPrefixLookup,
  task : Int,
  step : Int,
  generated : @execution.GeneratedSequence,
) -> Result[
  (@resources.Ledger, @execution.ProducerRead, @execution.SuppliedRelationRead),
  ClientKeyedRequestIssue,
] {
  guard value.scope is Some(original) &&
    physical_equal(original, scope) &&
    value.lookup is Some(lookup) &&
    value.prefix is Some(prefix) &&
    lookup.read is Some(_) &&
    lookup.holding is Some(_) &&
    client_original_keyed_capture_available(
      scope,
      compiled,
      definition,
      plan,
      prepared,
      lookup.left.acquisition,
    ) &&
    client_compiled_run_serialization(compiled) is Some(component) &&
    plan.serialization is Some(selected) &&
    physical_equal(component, selected) &&
    physical_equal(component.owner, prepared) &&
    component.task == task &&
    component.step == step &&
    client_keyed_acquisition_coordinates(lookup.left.acquisition)
    is Some((_, actual_task, join)) &&
    actual_task == task &&
    join < step &&
    @execution.generated_sequence_step_index_at(generated, 0) == Some(join) else {
    return Err(ForeignLeft)
  }
  let (_, left, right) = match
    prepare_client_keyed_lookup_join_inputs(lookup, generated) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // Binding and whole-input liveness may synchronously close/reenter. This
  // final actual census, not the earlier count/tuple, precedes Local reserve.
  guard client_original_keyed_capture_available(
      scope,
      compiled,
      definition,
      plan,
      prepared,
      lookup.left.acquisition,
    ) &&
    physical_equal(scope.ledger, lookup.ledger) &&
    @resources.original_keyed_serialization_preparation_available(
      scope.identity,
      scope.ledger,
      prefix,
      lookup.reservation,
      lookup.completed_responses,
    ) else {
    return Err(Assembly("original_serialization_custody_changed"))
  }
  Ok((scope.ledger, left, right))
}
