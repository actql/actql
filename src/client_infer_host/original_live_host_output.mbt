///|
/// Borrow the actual completed physical Model under its original output use.
/// This is not Saved restoration, another invocation, a provider entrance or
/// publication authority. The same Work/Scope retains execution and cleanup.
pub fn borrow_original_live_host_output(
  held : OutputUse,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
) -> (@relation.CompletedOutput, @model.ModelExecution)? {
  let active = held.owner
  guard original_host_output_matches(held, compiled, definition, plan) &&
    active.source is Physical(_) &&
    active.saved_call_scope is None &&
    active.call_scope is Some(scope) &&
    @input.client_infer_completed_input(active.input) is Some(input) &&
    @publication_host.client_infer_call_scope_matches(
      scope,
      active.occurrence.owner,
      input,
    ) else {
    return None
  }
  // The original input's availability may call out. Never return a borrow
  // whose exact output use/Model was retired during that observation.
  guard original_host_output_matches(held, compiled, definition, plan) &&
    active.model is Some(model) else {
    return None
  }
  Some(
    (
      @relation.restrict_completed_output(held.output, () => {
        original_host_output_matches(held, compiled, definition, plan) &&
        @publication_host.client_infer_call_scope_matches(
          scope,
          active.occurrence.owner,
          input,
        ) &&
        original_host_output_matches(held, compiled, definition, plan)
      }),
      model,
    ),
  )
}
