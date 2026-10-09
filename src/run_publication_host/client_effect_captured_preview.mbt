///|
pub(all) struct ClientCapturedEffectPreviewLimits {
  max_work : Int
  max_wire_bytes : Int
  max_nodes : Int
  max_depth : Int
  plan : @stage_results.EffectPlanIdentityLimits
}

///|
pub(all) enum ClientCapturedEffectPreviewIssue {
  Unavailable
  ForeignInput
  Identity(ClientEffectLocalIdentityIssue)
  Preview(@publication.EffectPreviewIdentityIssue)
  Run(@checked.EffectProgramRunPreviewIssue)
  Capture(@strategy.RunIssue)
}

///|
/// Admit an authored Preview against this actual captured original Run and
/// every issued local Effect identity. This binds retained Preview inputs;
/// it neither persists a waiting transition nor authorizes physical writes.
pub fn bind_captured_client_effect_preview(
  materials : ClientEffectRunMaterials,
  run : @strategy.CapturedEffectRunDAG,
  inputs : @strategy.CapturedEffectInputs,
  invocation : @publication.PublicationContract,
  stage : Int,
  preview_wire : String,
  authoring_context_cid : String,
  identities : Array[ClientEffectLocalIdentity],
  limits : ClientCapturedEffectPreviewLimits,
) -> Result[
  @strategy.CapturedEffectPreviewInputs,
  ClientCapturedEffectPreviewIssue,
] {
  let owner = materials.prepared
  let run_cid = @publication.publication_contract_identity(
    materials.run_definition,
  )
  if !@strategy.captured_effect_inputs_match_run(inputs, run) ||
    !@strategy.captured_effect_inputs_match_computation(inputs, owner.graph) ||
    @strategy.captured_effect_inputs_run_definition_cid(inputs) != Some(run_cid) ||
    !physical_equal(materials.compilation, materials.allowed.compilation) ||
    !physical_equal(materials.compilation.owner, owner) {
    return Err(ForeignInput)
  }
  match
    check_source_free_client_effect_preview_identities(
      owner,
      inputs,
      preview_wire,
      run_cid,
      authoring_context_cid,
      identities,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Identity(issue))
  }
  let preview = match
    @publication.admit_effect_preview_identity(
      preview_wire,
      run_cid,
      authoring_context_cid,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Preview(issue))
  }
  let checked = match
    @checked.bind_effect_program_run_preview(
      @strategy.captured_effect_run_owner(run),
      invocation,
      stage,
      preview,
      limits.max_work,
      limits.plan,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Run(issue))
  }
  @strategy.bind_captured_effect_preview_inputs(
    run,
    inputs,
    checked,
    limits.max_work,
  ).map_err(issue => Capture(issue))
}
