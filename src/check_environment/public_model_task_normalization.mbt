///|
/// Exact new public Task, installed configuration/profile and handling originals
/// retained alongside the existing canonical Task/prompt material. This neither
/// installs an Environment nor issues authority, funding or a new Run.
struct NormalizedPublicModelTask {
  declaration : PublicModelTaskDeclaration
  mock_profile : ModelMockProfile?
  defaults : ModelProviderDefaults
  resolved : ResolvedModelProviderDefaults
  handling : ModelProviderHandling
  provider : String
  task_wire : String
  task_cid : String
  prompt_wire : String
  prompt_cid : String
  work : Int
}

///|
fn public_task_emission_writer(
  budget : ModelTaskBudget,
  root : @decode.Cursor,
) -> @encode.Writer raise ModelTaskStop {
  // Reserve complete declared output/traversal work before allocating a writer.
  // Physical simultaneous originals/encoder/hash workspace remains Host funded.
  model_task_charge(budget, budget.limits.bodies.max_bytes, root)
  model_task_charge(budget, budget.limits.bodies.max_nodes, root)
  @encode.writer(
    budget.limits.bodies.max_bytes,
    budget.limits.bodies.max_nodes,
    budget.limits.bodies.max_depth,
  ) catch {
    _ => model_task_fail(BodyLimit, root)
  }
}

///|
fn emit_public_task_checked_contract(
  contract : PublicModelTaskContract,
  writer : @encode.Writer,
  budget : ModelTaskBudget,
  root : @decode.Cursor,
) -> Unit raise {
  let emission = @value_contract.start_checked_emission(
    public_model_task_contract(contract),
    writer,
    budget.limits.bodies.max_nodes,
  )
  errdefer @value_contract.cancel_checked_emission(emission)
  while true {
    model_task_charge(budget, 1, root)
    if @value_contract.advance_checked_emission(emission) {
      break
    }
  }
}

///|
fn emit_public_task_prompt(
  value : PublicModelTaskDeclaration,
  self_cid : String?,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "payload")
  @encode.begin_object(writer)
  @encode.key(writer, "format")
  @encode.string_value(writer, "actql.openai_chat_prompt/0.1")
  @encode.key(writer, "instructions")
  @encode.string_value(writer, value.instructions)
  @encode.end_object(writer)
  if self_cid is Some(cid) {
    @encode.key(writer, "self_cid")
    @encode.string_value(writer, cid)
  }
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-model-prompt/0.1")
  @encode.end_object(writer)
}

///|
fn emit_normalized_public_task(
  value : PublicModelTaskDeclaration,
  provider : String,
  resolved : ResolvedModelProviderDefaults,
  handling : ModelProviderHandling,
  prompt_cid : String,
  self_cid : String?,
  writer : @encode.Writer,
  budget : ModelTaskBudget,
) -> Unit raise {
  let generation = resolved.generation
  let root = value.original
  @encode.begin_object(writer)
  @encode.key(writer, "authored_model_selector")
  @encode.string_value(writer, resolved.model)
  @encode.key(writer, "connector_id")
  @encode.string_value(writer, provider)
  if self_cid is Some(cid) {
    @encode.key(writer, "contract_cid")
    @encode.string_value(writer, cid)
  }
  @encode.key(writer, "data_handling")
  emit_model_provider_handling(handling, writer)
  @encode.key(writer, "generation_config")
  @encode.begin_object(writer)
  @encode.key(writer, "max_output_tokens")
  @encode.decimal_number_value(writer, generation.max_output_tokens.to_string())
  if generation.seed_requested is Some(seed) {
    @encode.key(writer, "seed_requested")
    @encode.decimal_number_value(writer, seed.to_string())
  }
  @encode.key(writer, "temperature")
  @encode.number_value(writer, generation.temperature)
  @encode.key(writer, "top_p")
  @encode.number_value(writer, generation.top_p)
  @encode.end_object(writer)
  @encode.key(writer, "input_contract")
  emit_public_task_checked_contract(value.input, writer, budget, root)
  @encode.key(writer, "input_schema_cid")
  @encode.string_value(writer, value.input.cid)
  if value.max_items is Some(count) {
    @encode.key(writer, "max_items")
    @encode.decimal_number_value(writer, count.to_string())
  }
  @encode.key(writer, "output_contract")
  emit_public_task_checked_contract(value.output, writer, budget, root)
  @encode.key(writer, "output_schema_cid")
  @encode.string_value(writer, value.output.cid)
  @encode.key(writer, "prompt_template_cid")
  @encode.string_value(writer, prompt_cid)
  @encode.key(writer, "retrieval_policy")
  @encode.string_value(writer, "none")
  @encode.key(writer, "schema")
  @encode.string_value(writer, "actql.model_task/0.1")
  @encode.key(writer, "streaming")
  @encode.bool_value(writer, false)
  @encode.key(writer, "task_id")
  @encode.string_value(writer, value.task)
  @encode.key(writer, "task_kind")
  @encode.string_value(writer, "structured_generate")
  @encode.key(writer, "tool_policy")
  @encode.string_value(writer, "none")
  @encode.key(writer, "version")
  @encode.string_value(writer, value.task)
  @encode.end_object(writer)
}

///|
/// The Host has already selected the actual installed Provider original. Common
/// requires the same profile/selection and applicable handling before emitting
/// its existing Task/prompt contracts. No current default lookup occurs later.
fn normalize_public_model_task_selected(
  declaration : PublicModelTaskDeclaration,
  defaults : ModelProviderDefaults,
  resolved : ResolvedModelProviderDefaults,
  provider : String,
  limits : ModelTaskLimits,
  mock_profile : ModelMockProfile?,
) -> Result[NormalizedPublicModelTask, ModelTaskIssue] {
  let root = declaration.original
  if limits.max_work < 0 ||
    limits.bodies.max_bytes < 0 ||
    limits.bodies.max_nodes < 0 ||
    limits.bodies.max_depth < 0 ||
    limits.bodies.max_members < 0 ||
    limits.contracts.max_nodes < 0 ||
    limits.contracts.max_depth < 0 ||
    limits.contracts.max_text_bytes < 0 {
    return Err({ kind: InvalidLimits, source: Some(root), })
  }
  if provider.is_empty() || !physical_equal(resolved.original, defaults) {
    return Err({ kind: ReferenceMismatch, source: Some(root), })
  }
  let selected_model = if mock_profile is Some(profile) {
    if !model_mock_profile_current(profile) ||
      !(profile.defaults is Some(original) && physical_equal(original, defaults)) ||
      provider != "mock" {
      return Err({ kind: ReferenceMismatch, source: Some(root), })
    }
    None
  } else {
    declaration.model.map(pair => pair.1)
  }
  match (if mock_profile is Some(_) { None } else { declaration.model }) {
    Some((original_provider, model)) =>
      if original_provider != provider || model != resolved.model {
        return Err({ kind: ReferenceMismatch, source: Some(root), })
      }
    None =>
      if defaults.default_model != Some(resolved.model) {
        return Err({ kind: ReferenceMismatch, source: Some(root), })
      }
  }
  if declaration.max_output_tokens is Some(tokens) &&
    tokens != resolved.generation.max_output_tokens {
    return Err({ kind: ReferenceMismatch, source: Some(root), })
  }
  guard resolved.handling is Some(handling) else {
    return Err({ kind: ReferenceMismatch, source: Some(root), })
  }
  let budget : ModelTaskBudget = {
    limits,
    work: 0,
    contract_nodes: 0,
    contract_text: 0,
  }
  try {
    let expected = match
      resolve_model_provider_defaults(
        defaults,
        selected_model,
        declaration.max_output_tokens,
        limits.max_work,
      ) {
      Ok(value) => value
      Err(_) => model_task_fail(ReferenceMismatch, root)
    }
    model_task_charge(budget, expected.work, root)
    if expected.model != resolved.model ||
      expected.generation.temperature != resolved.generation.temperature ||
      expected.generation.top_p != resolved.generation.top_p ||
      expected.generation.max_output_tokens !=
      resolved.generation.max_output_tokens ||
      expected.generation.seed_requested != resolved.generation.seed_requested {
      model_task_fail(ReferenceMismatch, root)
    }
    let writer = public_task_emission_writer(budget, root)
    emit_public_task_prompt(declaration, None, writer)
    let prompt_preimage = @encode.finish(writer)
    model_task_charge(budget, limits.bodies.max_bytes, root)
    let prompt_cid = "sha256:" + @sha.hex(@utf8.encode(prompt_preimage))
    let writer = public_task_emission_writer(budget, root)
    emit_public_task_prompt(declaration, Some(prompt_cid), writer)
    let prompt_wire = @encode.finish(writer)
    let writer = public_task_emission_writer(budget, root)
    emit_normalized_public_task(
      declaration,
      provider,
      resolved,
      handling,
      prompt_cid,
      None,
      writer,
      budget,
    )
    let task_preimage = @encode.finish(writer)
    model_task_charge(budget, limits.bodies.max_bytes, root)
    let task_cid = "sha256:" + @sha.hex(@utf8.encode(task_preimage))
    let writer = public_task_emission_writer(budget, root)
    emit_normalized_public_task(
      declaration,
      provider,
      resolved,
      handling,
      prompt_cid,
      Some(task_cid),
      writer,
      budget,
    )
    let task_wire = @encode.finish(writer)
    Ok({
      declaration,
      mock_profile,
      defaults,
      resolved,
      handling,
      provider,
      task_wire,
      task_cid,
      prompt_wire,
      prompt_cid,
      work: budget.work,
    })
  } catch {
    ModelTaskStop(issue) => Err(issue)
    _ => Err({ kind: BodyLimit, source: Some(root), })
  }
}

///|
pub fn normalized_public_model_task_materials(
  value : NormalizedPublicModelTask,
) -> (String, String, String, String) {
  (value.task_wire, value.task_cid, value.prompt_wire, value.prompt_cid)
}

///|
pub fn normalized_public_model_task_original_for(
  value : NormalizedPublicModelTask,
  declaration : PublicModelTaskDeclaration,
  defaults : ModelProviderDefaults,
  resolved : ResolvedModelProviderDefaults,
) -> Bool {
  value.mock_profile is None &&
  physical_equal(value.declaration, declaration) &&
  physical_equal(value.defaults, defaults) &&
  physical_equal(value.resolved, resolved) &&
  resolved.handling is Some(handling) &&
  physical_equal(value.handling, handling)
}

///|
pub fn normalized_public_model_task_usage(
  value : NormalizedPublicModelTask,
) -> Int {
  value.work
}

///|
/// The ordinary installed Provider path retains its exact prior selection law.
pub fn normalize_public_model_task(
  declaration : PublicModelTaskDeclaration,
  defaults : ModelProviderDefaults,
  resolved : ResolvedModelProviderDefaults,
  provider : String,
  limits : ModelTaskLimits,
) -> Result[NormalizedPublicModelTask, ModelTaskIssue] {
  normalize_public_model_task_selected(
    declaration,
    defaults,
    resolved,
    provider,
    limits,
    None,
  )
}
