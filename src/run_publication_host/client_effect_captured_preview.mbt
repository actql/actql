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
  Run(@effect_binding.EffectProgramRunPreviewIssue)
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
  if !captured_client_effect_preview_original(materials, run, inputs, run_cid) {
    return Err(ForeignInput)
  }
  let preview = match
    admit_source_free_client_effect_preview_identities(
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
    Ok(value) => value
    Err(issue) => return Err(Identity(issue))
  }
  bind_checked_captured_client_effect_preview(
    run,
    inputs,
    invocation,
    stage,
    preview,
    limits.max_work,
    limits.plan,
  )
}

///|
/// Bind the nominal Preview already admitted by the caller's bounded issuer.
/// The issuer owns codec limits. This binding checks the actual Run, authoring,
/// captured members and static plan without rebuilding the admitted identity.
pub fn bind_admitted_captured_client_effect_preview(
  materials : ClientEffectRunMaterials,
  run : @strategy.CapturedEffectRunDAG,
  inputs : @strategy.CapturedEffectInputs,
  invocation : @publication.PublicationContract,
  stage : Int,
  preview : @publication.EffectPreviewIdentity,
  authoring_context_cid : String,
  identities : Array[ClientEffectLocalIdentity],
  max_work : Int,
  plan_limits : @stage_results.EffectPlanIdentityLimits,
) -> Result[
  @strategy.CapturedEffectPreviewInputs,
  ClientCapturedEffectPreviewIssue,
] {
  let run_cid = @publication.publication_contract_identity(
    materials.run_definition,
  )
  if !captured_client_effect_preview_original(materials, run, inputs, run_cid) {
    return Err(ForeignInput)
  }
  if @publication.effect_preview_run_identity(preview) != run_cid ||
    @publication.effect_preview_authoring_context_cid(preview) !=
    authoring_context_cid {
    return Err(Identity(ForeignPreview))
  }
  match
    check_admitted_source_free_client_effect_preview_identities(
      materials.prepared,
      inputs,
      preview,
      identities,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Identity(issue))
  }
  bind_checked_captured_client_effect_preview(
    run, inputs, invocation, stage, preview, max_work, plan_limits,
  )
}

///|
fn captured_client_effect_preview_original(
  materials : ClientEffectRunMaterials,
  run : @strategy.CapturedEffectRunDAG,
  inputs : @strategy.CapturedEffectInputs,
  run_cid : String,
) -> Bool {
  @strategy.captured_effect_inputs_match_run(inputs, run) &&
  @strategy.captured_effect_inputs_match_computation(
    inputs,
    materials.prepared.graph,
  ) &&
  @strategy.captured_effect_inputs_run_definition_cid(inputs) == Some(run_cid) &&
  physical_equal(materials.compilation, materials.allowed.compilation) &&
  physical_equal(materials.compilation.owner, materials.prepared)
}

///|
fn bind_checked_captured_client_effect_preview(
  run : @strategy.CapturedEffectRunDAG,
  inputs : @strategy.CapturedEffectInputs,
  invocation : @publication.PublicationContract,
  stage : Int,
  preview : @publication.EffectPreviewIdentity,
  max_work : Int,
  plan_limits : @stage_results.EffectPlanIdentityLimits,
) -> Result[
  @strategy.CapturedEffectPreviewInputs,
  ClientCapturedEffectPreviewIssue,
] {
  let checked = match
    @effect_binding.bind_effect_program_run_preview(
      @strategy.captured_effect_run_owner(run),
      invocation,
      stage,
      preview,
      max_work,
      plan_limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Run(issue))
  }
  @strategy.bind_captured_effect_preview_inputs(run, inputs, checked, max_work).map_err(issue => {
      Capture(issue)
    },
  )
}
