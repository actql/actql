///|
/// Mock ignores the authored physical provider/model pair. Its generation and
/// handling fields come only from this source-pinned fixture profile; the
/// original declaration, contracts and token ceiling remain unchanged.
pub fn normalize_public_mock_model_task(
  declaration : PublicModelTaskDeclaration,
  profile : ModelMockProfile,
  limits : ModelTaskLimits,
) -> Result[NormalizedPublicModelTask, ModelTaskIssue] {
  if !model_mock_profile_current(profile) {
    return Err({ kind: ReferenceMismatch, source: Some(declaration.original), })
  }
  let defaults = profile.defaults.unwrap()
  let resolved = match
    resolve_model_provider_defaults(
      defaults,
      None,
      declaration.max_output_tokens,
      limits.max_work,
    ) {
    Err(_) =>
      return Err({
        kind: ReferenceMismatch,
        source: Some(declaration.original),
      })
    Ok(value) => value
  }
  normalize_public_model_task_selected(
    declaration,
    defaults,
    resolved,
    "mock",
    limits,
    Some(profile),
  )
}

///|
pub fn normalized_public_mock_model_task_original_for(
  normalized : NormalizedPublicModelTask,
  declaration : PublicModelTaskDeclaration,
  profile : ModelMockProfile,
) -> Bool {
  model_mock_profile_current(profile) &&
  physical_equal(normalized.declaration, declaration) &&
  normalized.mock_profile is Some(original) &&
  physical_equal(original, profile) &&
  profile.defaults is Some(defaults) &&
  physical_equal(normalized.defaults, defaults) &&
  physical_equal(normalized.resolved.original, defaults)
}

///|
/// Bind the checked Environment Task to the original normalization before
/// retaining that exact Task in the Model installation. This is DATA admission,
/// not a dispatch, Account, current-Host or capacity proof.
pub fn normalized_public_mock_model_task_matches_task(
  normalized : NormalizedPublicModelTask,
  declaration : PublicModelTaskDeclaration,
  profile : ModelMockProfile,
  task : ModelTaskContract,
) -> Bool {
  normalized_public_mock_model_task_original_for(
    normalized, declaration, profile,
  ) &&
  task.cid == normalized.task_cid &&
  task.task_id == declaration.task &&
  task.connector == "mock" &&
  task.prompt == normalized.prompt_cid
}

///|
/// The fixture implementation consumes this original normalized prompt, rather
/// than delegating its interpretation to a Host's physical-provider callback.
/// The dependency reader has already checked its complete canonical body/CID;
/// keep its kind and payload present and bind that identity to this same Task.
pub fn normalized_public_mock_model_task_matches_prompt(
  normalized : NormalizedPublicModelTask,
  declaration : PublicModelTaskDeclaration,
  profile : ModelMockProfile,
  task : ModelTaskContract,
  prompt : ModelDependency,
) -> Bool {
  normalized_public_mock_model_task_matches_task(
    normalized, declaration, profile, task,
  ) &&
  prompt.kind == ModelPrompt &&
  prompt.cid == normalized.prompt_cid &&
  prompt.payload is Some(_)
}
