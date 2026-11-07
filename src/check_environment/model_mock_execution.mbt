///|
/// An explicit bounded implementation profile, not a physical byte/quantity
/// supplier. Its full body is pinned by the original installation revision.
fn model_mock_execution_profile_wire() -> String {
  (
    #|{"max_attempts_per_slot":1,"max_total_attempts":1000,"max_total_cost_units":0,"max_total_duration_ms":60000,"max_total_token_reservation":1000000,"max_total_wire_bytes":67108864,"version":"actql-mock-model-execution-profile/0.1"}
  )
}

///|
fn model_mock_retry_wire() -> String {
  (
    #|{"retryable_failures":[],"self_cid":"sha256:0c53e62a9c01afcf23a2036a06dd0b5e47653e943cae76d48bee1c84c11efb90","version":"actql-model-retry-policy/0.1"}
  )
}

///|
fn model_mock_backoff_wire() -> String {
  (
    #|{"delays_ms":[],"self_cid":"sha256:739f886f72a9d0393470b92ccc3eb6a3a00f0616ed2d6f61df714f429de99d56","version":"actql-model-backoff/0.1"}
  )
}

///|
fn model_mock_execution_bounds(
  budget : ModelTaskBudget,
) -> Array[(String, Int64)] raise ModelTaskStop {
  let wire = model_mock_execution_profile_wire()
  if @scalar.admit_utf8_length(wire, budget.limits.bodies.max_bytes) is Err(_) {
    raise ModelTaskStop({ kind: BodyLimit, source: None, })
  }
  // Reserve encoding and bounded source/decode traversal before allocating.
  for
    amount in [
      wire.length(),
      wire.length(),
      budget.limits.bodies.max_nodes,
      budget.limits.bodies.max_nodes,
    ] {
    if amount > budget.limits.max_work - budget.work {
      raise ModelTaskStop({ kind: WorkLimit, source: None, })
    }
    budget.work += amount
  }
  let limits = budget.limits.bodies
  let source = match
    @source.parse_json_bytes(@utf8.encode(wire), {
      max_input_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(value) => value
    Err(_) => raise ModelTaskStop({ kind: InvalidBody, source: None, })
  }
  let root = match
    @decode.admit(source, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_bytes,
      max_total_string_bytes: limits.max_bytes,
    }) {
    Ok(value) => value
    Err(_) => raise ModelTaskStop({ kind: BodyLimit, source: None, })
  }
  let names = [
    "max_attempts_per_slot", "max_total_attempts", "max_total_cost_units", "max_total_duration_ms",
    "max_total_token_reservation", "max_total_wire_bytes",
  ]
  let closed_names = names.copy()
  closed_names.push("version")
  let object = model_task_object(root, closed_names, budget)
  if model_task_string(object, "version", root, budget) !=
    "actql-mock-model-execution-profile/0.1" {
    model_task_fail(InvalidBody, root)
  }
  let bounds = []
  for name in names {
    let value = model_task_integer(
      model_task_required(object, name, root),
      name != "max_total_cost_units",
      budget,
    )
    bounds.push((name, value))
  }
  bounds
}

///|
fn emit_mock_execution(
  writer : @encode.Writer,
  normalized : NormalizedPublicModelTask,
  bounds : Array[(String, Int64)],
  self_cid : String?,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "backoff_contract_cid")
  @encode.string_value(
    writer, "sha256:739f886f72a9d0393470b92ccc3eb6a3a00f0616ed2d6f61df714f429de99d56",
  )
  @encode.key(writer, "default_publication")
  @encode.string_value(writer, "outcomes")
  for (name, value) in bounds {
    @encode.key(writer, name)
    @encode.number_value(writer, value.to_double())
  }
  @encode.key(writer, "media_input_contracts")
  @encode.begin_object(writer)
  @encode.end_object(writer)
  @encode.key(writer, "model_task_contract_cid")
  @encode.string_value(writer, normalized.task_cid)
  @encode.key(writer, "retry_classification_contract_cid")
  @encode.string_value(
    writer, "sha256:0c53e62a9c01afcf23a2036a06dd0b5e47653e943cae76d48bee1c84c11efb90",
  )
  if self_cid is Some(cid) {
    @encode.key(writer, "self_cid")
    @encode.string_value(writer, cid)
  }
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-model-execution-contract/0.1")
  @encode.end_object(writer)
}

///|
/// Actual Mock execution/retry/backoff originals for the existing ordinary
/// Host readers. Prompt originals remain the normalization's exact materials.
/// These finite ceilings and no-retry policies issue no reservation or grant.
pub fn model_mock_execution_materials(
  profile : ModelMockProfile,
  normalized : NormalizedPublicModelTask,
  limits : ModelTaskLimits,
) -> Result[(String, String, String, String, String, String), ModelTaskIssue] {
  if !normalized_public_mock_model_task_original_for(
      normalized,
      normalized.declaration,
      profile,
    ) {
    return Err({ kind: ReferenceMismatch, source: None, })
  }
  if limits.max_work < 0 ||
    limits.bodies.max_bytes < 0 ||
    limits.bodies.max_nodes < 0 ||
    limits.bodies.max_depth < 0 ||
    limits.bodies.max_members < 0 {
    return Err({ kind: InvalidLimits, source: None, })
  }
  let budget : ModelTaskBudget = {
    limits,
    work: 0,
    contract_nodes: 0,
    contract_text: 0,
  }
  try {
    let bounds = profile.execution_bounds
    let hash_writer = public_task_emission_writer(
      budget,
      normalized.declaration.original,
    )
    emit_mock_execution(hash_writer, normalized, bounds, None) catch {
      _ => model_task_fail(BodyLimit, normalized.declaration.original)
    }
    let preimage = @encode.finish(hash_writer) catch {
      _ => model_task_fail(BodyLimit, normalized.declaration.original)
    }
    model_task_charge(
      budget,
      limits.bodies.max_bytes,
      normalized.declaration.original,
    )
    let cid = "sha256:" + @sha.hex(@utf8.encode(preimage))
    let writer = public_task_emission_writer(
      budget,
      normalized.declaration.original,
    )
    emit_mock_execution(writer, normalized, bounds, Some(cid)) catch {
      _ => model_task_fail(BodyLimit, normalized.declaration.original)
    }
    let wire = @encode.finish(writer) catch {
      _ => model_task_fail(BodyLimit, normalized.declaration.original)
    }
    Ok(
      (
        wire,
        cid,
        model_mock_retry_wire(),
        "sha256:0c53e62a9c01afcf23a2036a06dd0b5e47653e943cae76d48bee1c84c11efb90",
        model_mock_backoff_wire(),
        "sha256:739f886f72a9d0393470b92ccc3eb6a3a00f0616ed2d6f61df714f429de99d56",
      ),
    )
  } catch {
    ModelTaskStop(issue) => Err(issue)
  }
}

///|
/// Structural correspondence to the same admitted scope's execution contract.
/// The caller separately proves its nominal Run/rows/current/resource binding.
pub fn model_mock_execution_matches(
  profile : ModelMockProfile,
  normalized : NormalizedPublicModelTask,
  execution : ModelExecutionContract,
) -> Bool {
  if !normalized_public_mock_model_task_matches_task(
      normalized,
      normalized.declaration,
      profile,
      execution.task,
    ) ||
    execution.media.length() != 0 ||
    execution.retry_classification_cid !=
    "sha256:0c53e62a9c01afcf23a2036a06dd0b5e47653e943cae76d48bee1c84c11efb90" ||
    execution.backoff_cid !=
    "sha256:739f886f72a9d0393470b92ccc3eb6a3a00f0616ed2d6f61df714f429de99d56" {
    return false
  }
  for (name, value) in profile.execution_bounds {
    let ceiling = match name {
      "max_attempts_per_slot" => AttemptsPerSlot
      "max_total_attempts" => TotalAttempts
      "max_total_cost_units" => TotalCostUnits
      "max_total_duration_ms" => TotalDurationMs
      "max_total_token_reservation" => TotalTokenReservation
      "max_total_wire_bytes" => TotalWireBytes
      _ => return false
    }
    if model_execution_ceiling(execution, ceiling) != value {
      return false
    }
  }
  true
}

///|
/// The same no-I/O typed-answer profile consumes checked references as opaque
/// input values. It never transfers their bytes and cannot issue a physical
/// media dependency. All canonical scalar bodies and execution limits retain
/// the ordinary reader; only physical media-role validation is inapplicable.
pub fn read_original_mock_model_dependencies(
  profile : ModelMockProfile,
  normalized : NormalizedPublicModelTask,
  execution : ModelExecutionContract,
  prompt : Bytes?,
  retry : Bytes?,
  backoff : Bytes?,
  limits : Limits,
  max_work : Int,
) -> Result[SingleAttemptModelDependencies, ModelDependencyIssue] {
  read_model_dependencies_selected(
    execution,
    prompt,
    retry,
    backoff,
    limits,
    max_work,
    [],
    Some((profile, normalized)),
  )
}
