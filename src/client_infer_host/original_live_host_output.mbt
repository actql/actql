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

///|
/// Project the actual physical execution's own retained admission. A
/// separately issued admission for the same checked Plan cannot supply the
/// producer classification.
pub fn original_live_whole_model_egress(
  held : OutputUse,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
  artifact : @publication_host.ClientWholeLocalResultArtifact,
  manifest : @publication_host.ClientWholeLocalResultManifest,
) -> Result[
  @publication_host.ClientWholeModelEgressOriginal,
  @publication_host.ClientInferEgressIssue,
] {
  let active = held.owner
  guard original_host_output_matches(held, compiled, definition, plan) &&
    active.source is Physical(_) &&
    active.saved_call_scope is None &&
    active.call_scope is Some(call) &&
    active.egress_admission is Some(admission) else {
    return Err(ForeignOwner)
  }
  @publication_host.verify_client_whole_model_egress_original(
    admission,
    call,
    held.output,
    artifact,
    manifest,
  ).bind(original => {
    if original_host_output_matches(held, compiled, definition, plan) &&
      active.call_scope is Some(current) &&
      physical_equal(current, call) &&
      active.egress_admission is Some(admitted) &&
      physical_equal(admitted, admission) {
      Ok(original)
    } else {
      Err(ForeignOwner)
    }
  })
}
