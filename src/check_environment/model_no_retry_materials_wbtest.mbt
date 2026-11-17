///|
fn normal_execution_task(
  original : NormalizedPublicModelTask,
) -> ModelTaskContract {
  let prefix = "{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[],\"contract_registry\":[],"
  let suffix = "\"host_policy_profile\":{},\"mapping_contracts\":[],\"model_task_contracts\":[" +
    original.task_wire +
    "],\"schema_snapshots\":[],\"source_views\":[],\"version\":\"actql-check-environment/0.1\"}"
  let cid = "sha256:" + @sha.hex(@utf8.encode(prefix + suffix))
  let environment = read(
    @utf8.encode(prefix + "\"evidence_bundle_cid\":\"" + cid + "\"," + suffix),
    cid,
    declaration_limits().bodies,
  ).unwrap()
  resolve_model_task(
    check_model_tasks(environment, declaration_limits()).unwrap(),
    "model-task:public.opaque",
  ).unwrap()
}

///|
test "normal no-retry materials preserve explicit positive cost and enter the actual execution dependency readers" {
  let original = profile_projection_original()
  let before = normalized_public_model_task_materials(original)
  let materials = normalized_public_model_task_no_retry_materials(
    original, 2L, 123456L, 30000L, 65536L, 8192L, 10000, 1000, 32, 22000,
  ).unwrap()
  assert_eq(
    materials.1,
    "sha256:87287f2d4eb0a6675fd193f0de9b2fef2756e7df517f7fa7837bc7ccec2ed5b3",
  )
  assert_eq(
    materials.0,
    (
      #|{"backoff_contract_cid":"sha256:739f886f72a9d0393470b92ccc3eb6a3a00f0616ed2d6f61df714f429de99d56","default_publication":"outcomes","max_attempts_per_slot":1,"max_total_attempts":2,"max_total_cost_units":123456,"max_total_duration_ms":30000,"max_total_token_reservation":8192,"max_total_wire_bytes":65536,"media_input_contracts":{},"model_task_contract_cid":"sha256:e672bc4e7bc042bf5fd95712095c32d902065a876e8bf775bf1741f795bba1bd","retry_classification_contract_cid":"sha256:0c53e62a9c01afcf23a2036a06dd0b5e47653e943cae76d48bee1c84c11efb90","self_cid":"sha256:87287f2d4eb0a6675fd193f0de9b2fef2756e7df517f7fa7837bc7ccec2ed5b3","version":"actql-model-execution-contract/0.1"}
    ),
  )
  let task = normal_execution_task(original)
  let execution = read_model_execution_contract(
    task,
    @utf8.encode(materials.0),
    materials.1,
    declaration_limits().bodies,
    100000,
  ).unwrap()
  assert_eq(model_execution_ceiling(execution, AttemptsPerSlot), 1L)
  assert_eq(model_execution_ceiling(execution, TotalAttempts), 2L)
  assert_eq(model_execution_ceiling(execution, TotalCostUnits), 123456L)
  assert_eq(model_execution_ceiling(execution, TotalDurationMs), 30000L)
  assert_eq(model_execution_ceiling(execution, TotalWireBytes), 65536L)
  assert_eq(model_execution_ceiling(execution, TotalTokenReservation), 8192L)
  let dependencies = read_single_attempt_model_dependencies(
    execution,
    Some(@utf8.encode(original.prompt_wire)),
    Some(@utf8.encode(materials.2)),
    Some(@utf8.encode(materials.4)),
    declaration_limits().bodies,
    100000,
  ).unwrap()
  assert_eq(
    model_dependency_identity(single_attempt_model_prompt(dependencies)),
    original.prompt_cid,
  )
  assert_eq(normalized_public_model_task_materials(original), before)
}

///|
test "normal no-retry materials refuse invalid ceilings and construction bounds before replacing originals" {
  let original = profile_projection_original()
  let before = normalized_public_model_task_materials(original)
  for
    (attempts, cost, duration, bytes, tokens) in [
      (0L, 1L, 1L, 1L, 1L),
      (1L, -1L, 1L, 1L, 1L),
      (1L, 1L, 0L, 1L, 1L),
      (1L, 1L, 1L, 0L, 1L),
      (1L, 1L, 1L, 1L, 0L),
      (1L, 9007199254740992L, 1L, 1L, 1L),
    ] {
    assert_true(
      normalized_public_model_task_no_retry_materials(
        original, attempts, cost, duration, bytes, tokens, 10000, 1000, 32, 22000,
      )
      is Err({ kind: InvalidLimits, .. }),
    )
  }
  assert_true(
    normalized_public_model_task_no_retry_materials(
      original, 2L, 123456L, 30000L, 65536L, 8192L, 10000, 1000, 32, 21999,
    )
    is Err({ kind: WorkLimit, .. }),
  )
  for (bytes, nodes, depth) in [(1, 1000, 32), (10000, 1, 32), (10000, 1000, 0)] {
    assert_true(
      normalized_public_model_task_no_retry_materials(
        original, 2L, 123456L, 30000L, 65536L, 8192L, bytes, nodes, depth, 22000,
      )
      is Err({ kind: BodyLimit, .. }),
    )
  }
  assert_eq(normalized_public_model_task_materials(original), before)
}

///|
test "normal no-retry originals cannot adopt a Mock owner or bind another Task" {
  let original = profile_projection_original()
  let materials = normalized_public_model_task_no_retry_materials(
    original, 2L, 123456L, 30000L, 65536L, 8192L, 10000, 1000, 32, 22000,
  ).unwrap()
  let profile = install_model_mock_profile(declaration_limits()).unwrap()
  let mock = normalize_public_mock_model_task(
    normalization_declaration(""),
    profile,
    declaration_limits(),
  ).unwrap()
  assert_true(
    normalized_public_model_task_no_retry_materials(
      mock, 2L, 123456L, 30000L, 65536L, 8192L, 10000, 1000, 32, 22000,
    )
    is Err({ kind: ReferenceMismatch, .. }),
  )
  assert_true(
    read_model_execution_contract(
      normal_execution_task(mock),
      @utf8.encode(materials.0),
      materials.1,
      declaration_limits().bodies,
      100000,
    )
    is Err({ kind: ReferenceMismatch, .. }),
  )
}
