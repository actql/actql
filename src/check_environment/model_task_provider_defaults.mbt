///|
/// Checked configuration DATA only. Its private constructor does not prove an
/// installed Provider, current configuration, Task, physical funding or grant.
/// The Host must retain this with the same actual registration and original
/// configuration/revision before adopting a normalized public Task.
struct ModelProviderDefaults {
  default_model : String?
  models : Array[(String, ModelGeneration)]
  bytes : Int
  nodes : Int
  work : Int
}

///|
struct ResolvedModelProviderDefaults {
  original : ModelProviderDefaults
  model : String
  generation : ModelGeneration
  work : Int
}

///|
pub(all) enum ModelProviderDefaultsResolutionIssue {
  InvalidLimits
  WorkLimit
  DefaultUnavailable
  UnknownModel
  InvalidTaskOutputTokens
} derive(Eq, Debug)

///|
fn model_provider_defaults_read(
  root : @decode.Cursor,
  budget : ModelTaskBudget,
  bytes : Int,
  nodes : Int,
) -> ModelProviderDefaults raise ModelTaskStop {
  let object = model_task_object(root, ["default_model", "models"], budget)
  let default_model = match @decode.field(object, "default_model") {
    Missing => None
    Present(value) => Some(model_task_text(value, budget))
    ExplicitNull => model_task_fail(InvalidBody, root)
  }
  let values = model_task_required(object, "models", root)
  let count = match @decode.array_length(values) {
    Some(count) => count
    None => model_task_fail(InvalidBody, values)
  }
  if count > budget.limits.bodies.max_members {
    model_task_fail(TaskLimit, values)
  }
  // Charge the complete inventory before either collection grows. Unused
  // profiles are checked too; lookup does not excuse a malformed later entry.
  model_task_charge(budget, count, values)
  let models : Array[(String, ModelGeneration)] = []
  let names : Map[String, Bool] = Map([])
  for index in 0..<count {
    let value = @decode.element_at(values, index).unwrap()
    let profile = model_task_object(
      value,
      ["model", "generation_config"],
      budget,
    )
    let model = model_task_string(profile, "model", value, budget)
    if names.contains(model) {
      model_task_fail(DuplicateSelector(model), value)
    }
    names[model] = true
    let generation = model_task_generation(
      model_task_required(profile, "generation_config", value),
      budget,
    )
    models.push((model, generation))
  }
  if default_model is Some(model) && !names.contains(model) {
    model_task_fail(ReferenceMismatch, root)
  }
  { default_model, models, bytes, nodes, work: budget.work, }
}

///|
/// Read the model_defaults subrecord of the SAME nonsecret configuration
/// original. Other configuration fields remain with that Provider's contract.
/// Absence preserves legacy explicit-Task registrations; it supplies no default.
/// This parser neither validates that outer contract nor issues its binding.
pub fn read_model_provider_defaults_configuration(
  bytes : Bytes,
  limits : Limits,
  max_work : Int,
) -> Result[(ModelProviderDefaults?, Int, Int, Int), ModelTaskIssue] {
  if limits.max_bytes < 0 ||
    limits.max_nodes < 0 ||
    limits.max_depth < 0 ||
    limits.max_members < 0 ||
    max_work < 0 {
    return Err({ kind: InvalidLimits, source: None, })
  }
  if bytes.length() > limits.max_bytes {
    return Err({ kind: BodyLimit, source: None, })
  }
  if bytes.length() > max_work {
    return Err({ kind: WorkLimit, source: None, })
  }
  let parsed = match
    @source.parse_json_bytes_measured(bytes, {
      max_input_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(value) => value
    Err(issue) =>
      return Err({
        kind: match issue.issue {
          InputLimit | NodeLimit | DepthLimit => BodyLimit
          _ => InvalidBody
        },
        source: None,
      })
  }
  let root = match
    @decode.admit(parsed.node, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_bytes,
      max_total_string_bytes: limits.max_bytes,
    }) {
    Ok(value) => value
    Err(_) => return Err({ kind: InvalidBody, source: None, })
  }
  let budget : ModelTaskBudget = {
    limits: {
      bodies: limits,
      contracts: { max_nodes: 0, max_depth: 0, max_text_bytes: 0, },
      max_work,
    },
    work: bytes.length(),
    contract_nodes: 0,
    contract_text: 0,
  }
  try {
    // Parse and decoded-tree traversal are distinct work. The full original
    // remains retained while the selected profile is reconstructed.
    model_task_charge(budget, parsed.usage.nodes, root)
    guard @decode.object_length(root) is Some(count) else {
      return Ok((None, bytes.length(), parsed.usage.nodes, budget.work))
    }
    model_task_charge(budget, count, root)
    for index in 0..<count {
      let (name, value) = @decode.field_at(root, index).unwrap()
      model_task_charge(budget, name.length(), value)
      if name == "model_defaults" {
        let selected = model_provider_defaults_read(
          value,
          budget,
          bytes.length(),
          parsed.usage.nodes,
        )
        return Ok(
          (Some(selected), bytes.length(), parsed.usage.nodes, budget.work),
        )
      }
    }
    Ok((None, bytes.length(), parsed.usage.nodes, budget.work))
  } catch {
    ModelTaskStop(issue) => Err(issue)
  }
}

///|
/// Pure selection, not installed support/currentness or request admission.
/// An explicit Task value replaces a default; it is NOT capped by that default.
/// Separate Provider/Host/Program ceilings belong to bound execution/request
/// admission, which may lower but never raise the selected Task limit.
pub fn resolve_model_provider_defaults(
  original : ModelProviderDefaults,
  selected_model : String?,
  task_max_output_tokens : Int64?,
  max_work : Int,
) -> Result[ResolvedModelProviderDefaults, ModelProviderDefaultsResolutionIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  if task_max_output_tokens is Some(value) &&
    (value <= 0L || value > 9007199254740991L) {
    return Err(InvalidTaskOutputTokens)
  }
  let model = match selected_model {
    Some(value) => value
    None =>
      match original.default_model {
        Some(value) => value
        None => return Err(DefaultUnavailable)
      }
  }
  let mut work = 0
  for (name, generation) in original.models {
    // Reserve each string comparison before it happens, without Int overflow.
    for charge in [1, name.length(), model.length()] {
      if charge > max_work - work {
        return Err(WorkLimit)
      }
      work += charge
    }
    if name == model {
      if work == max_work {
        return Err(WorkLimit)
      }
      work += 1
      let selected = match task_max_output_tokens {
        None => generation
        Some(max_output_tokens) => { ..generation, max_output_tokens, }
      }
      return Ok({ original, model: name, generation: selected, work, })
    }
  }
  Err(UnknownModel)
}

///|
pub fn model_provider_defaults_usage(
  value : ModelProviderDefaults,
) -> (Int, Int, Int) {
  (value.bytes, value.nodes, value.work)
}

///|
pub fn resolved_model_provider_defaults_model(
  value : ResolvedModelProviderDefaults,
) -> String {
  value.model
}

///|
pub fn resolved_model_provider_defaults_generation(
  value : ResolvedModelProviderDefaults,
  original : ModelProviderDefaults,
) -> ModelGeneration? {
  if physical_equal(value.original, original) {
    Some(value.generation)
  } else {
    None
  }
}

///|
pub fn resolved_model_provider_defaults_work(
  value : ResolvedModelProviderDefaults,
) -> Int {
  value.work
}
