///|
// Original completion/Run/Plan identity shared by live and restored consumers.
// This part only reads private local state; generation/custody currentness is
// checked by each actual input Owner and fenced again after that callback.
fn original_host_output_matches(
  held : OutputUse,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
) -> Bool {
  let active = held.owner
  !held.released &&
  !active.reclaimed &&
  !active.cancelled &&
  !active.advancing &&
  active.phase is Terminal &&
  active.completed is Some(completed) &&
  physical_equal(held.output, completed) &&
  active.original_preparation is Some(original) &&
  original.read is Claimed(_) &&
  active.run_binding is Some(binding) &&
  physical_equal(binding.compiled, compiled) &&
  physical_equal(binding.definition, definition) &&
  active.plan is Some(selected) &&
  physical_equal(selected, plan) &&
  active.model is Some(_)
}

///|
/// Borrow the real restored execution's completion for its enclosing Host.
/// The caller already retains its actual OutputUse before any callback.
/// Neither caller rows nor a Saved scope alone can issue this completion. The
/// same execution still owns its Model work, input, output and cleanup.
pub fn borrow_original_restored_host_output(
  held : OutputUse,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
) -> (@relation.CompletedOutput, @model.ModelExecution)? {
  let active = held.owner
  guard original_host_output_matches(held, compiled, definition, plan) &&
    active.saved_call_scope is Some(saved) &&
    active.call_scope is Some(scope) &&
    active.model is Some(model) &&
    @input.client_infer_completed_input(active.input) is Some(input) &&
    @publication_host.client_infer_call_scope_matches(
      scope,
      active.occurrence.owner,
      input,
    ) &&
    @publication_host.client_infer_saved_call_scope_matches_originals(
      saved,
      compiled,
      definition,
      active.occurrence,
      plan,
    ) else {
    return None
  }
  // Saved custody can call out and reenter cleanup or another handoff. Check
  // the original local phase again before publishing this borrowed output.
  if held.released ||
    active.reclaimed ||
    active.cancelled ||
    active.advancing ||
    !(active.phase is Terminal) {
    return None
  }
  Some(
    (
      @relation.restrict_completed_output(held.output, () => {
        !held.released &&
        !active.reclaimed &&
        !active.cancelled &&
        @publication_host.client_infer_saved_call_scope_matches_originals(
          saved,
          compiled,
          definition,
          active.occurrence,
          plan,
        ) &&
        !held.released &&
        !active.reclaimed &&
        !active.cancelled
      }),
      model,
    ),
  )
}
