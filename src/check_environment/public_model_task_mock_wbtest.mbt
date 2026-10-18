///|
test "mock installs its explicit originals and ignores authored physical model selection" {
  let profile = install_model_mock_profile(declaration_limits()).unwrap()
  let originals = model_mock_profile_originals(profile).unwrap()
  // Independently hashed canonical source literals, not normalized output.
  assert_eq(
    originals.5,
    "sha256:1506a8d602619c0e320f8dc21232fd7bad021295802d7a60d3b054a03da3acf8",
  )
  let absent = normalization_declaration("")
  let physical = normalization_declaration(
    ",\"model\":{\"provider\":\"uninstalled-live\",\"name\":\"not-a-mock-default\"}",
  )
  let a = normalize_public_mock_model_task(
    absent,
    profile,
    declaration_limits(),
  ).unwrap()
  let b = normalize_public_mock_model_task(
    physical,
    profile,
    declaration_limits(),
  ).unwrap()
  assert_eq(
    normalized_public_model_task_materials(a),
    normalized_public_model_task_materials(b),
  )
  assert_true(
    normalized_public_mock_model_task_original_for(a, absent, profile),
  )
  assert_false(
    normalized_public_mock_model_task_original_for(a, physical, profile),
  )
  assert_false(
    normalized_public_mock_model_task_original_for(
      a,
      absent,
      install_model_mock_profile(declaration_limits()).unwrap(),
    ),
  )
}

///|
test "mock profile copy and retirement cannot normalize another original" {
  let profile = install_model_mock_profile(declaration_limits()).unwrap()
  let copied = { ..profile, }
  let task = normalization_declaration("")
  assert_false(model_mock_profile_current(copied))
  assert_false(retire_model_mock_profile(copied))
  assert_true(
    normalize_public_mock_model_task(task, copied, declaration_limits())
    is Err(_),
  )
  assert_true(retire_model_mock_profile(profile))
  assert_true(
    normalize_public_mock_model_task(task, profile, declaration_limits())
    is Err(_),
  )
}

///|
test "mock profile admission retains source byte and work ceilings" {
  let limits = declaration_limits()
  assert_true(
    install_model_mock_profile({
      ..limits,
      contracts: { ..limits.contracts, max_nodes: -1, },
    })
    is Err({ kind: InvalidLimits, .. }),
  )
  assert_true(
    install_model_mock_profile({
      ..limits,
      bodies: { ..limits.bodies, max_bytes: 1, },
    })
    is Err({ kind: BodyLimit, .. }),
  )
  assert_true(
    install_model_mock_profile({ ..limits, max_work: 1, })
    is Err({ kind: WorkLimit, .. }),
  )
}

///|
test "mock execution originals are bounded no-retry and admitted by the same Task owner" {
  let limits = declaration_limits()
  let profile = install_model_mock_profile(limits).unwrap()
  let declaration = normalization_declaration("")
  let normalized = normalize_public_mock_model_task(
    declaration, profile, limits,
  ).unwrap()
  let (task_wire, _, prompt, prompt_cid) = normalized_public_model_task_materials(
    normalized,
  )
  let prefix = "{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[],\"contract_registry\":[],"
  let suffix = "\"host_policy_profile\":{},\"mapping_contracts\":[],\"model_task_contracts\":[" +
    task_wire +
    "],\"schema_snapshots\":[],\"source_views\":[],\"version\":\"actql-check-environment/0.1\"}"
  let cid = "sha256:" + @sha.hex(@utf8.encode(prefix + suffix))
  let environment = read(
    @utf8.encode(prefix + "\"evidence_bundle_cid\":\"" + cid + "\"," + suffix),
    cid,
    limits.bodies,
  ).unwrap()
  let task = resolve_model_task(
    check_model_tasks(environment, limits).unwrap(),
    "model-task:public.opaque",
  ).unwrap()
  let materials = model_mock_execution_materials(profile, normalized, limits).unwrap()
  let execution = read_model_execution_contract(
    task,
    @utf8.encode(materials.0),
    materials.1,
    limits.bodies,
    limits.max_work,
  ).unwrap()
  assert_true(model_mock_execution_matches(profile, normalized, execution))
  assert_eq(model_execution_ceiling(execution, AttemptsPerSlot), 1L)
  assert_eq(model_execution_ceiling(execution, TotalAttempts), 1000L)
  assert_eq(model_execution_ceiling(execution, TotalCostUnits), 0L)
  assert_eq(model_execution_ceiling(execution, TotalDurationMs), 60000L)
  assert_eq(model_execution_ceiling(execution, TotalWireBytes), 67108864L)
  assert_eq(model_execution_ceiling(execution, TotalTokenReservation), 1000000L)
  assert_eq(
    materials.3,
    "sha256:0c53e62a9c01afcf23a2036a06dd0b5e47653e943cae76d48bee1c84c11efb90",
  )
  assert_eq(
    materials.5,
    "sha256:739f886f72a9d0393470b92ccc3eb6a3a00f0616ed2d6f61df714f429de99d56",
  )
  let dependencies = read_single_attempt_model_dependencies(
    execution,
    Some(@utf8.encode(prompt)),
    Some(@utf8.encode(materials.2)),
    Some(@utf8.encode(materials.4)),
    limits.bodies,
    limits.max_work,
  ).unwrap()
  assert_eq(
    model_dependency_identity(single_attempt_model_prompt(dependencies)),
    prompt_cid,
  )
  let original_prompt = single_attempt_model_prompt(dependencies)
  assert_true(
    normalized_public_mock_model_task_matches_prompt(
      normalized, declaration, profile, task, original_prompt,
    ),
  )
  assert_false(
    normalized_public_mock_model_task_matches_prompt(
      normalized,
      declaration,
      profile,
      task,
      { ..original_prompt, kind: ModelRetryPolicy, },
    ),
  )
  assert_false(
    normalized_public_mock_model_task_matches_prompt(
      normalized,
      declaration,
      profile,
      task,
      { ..original_prompt, payload: None, },
    ),
  )
  assert_false(
    normalized_public_mock_model_task_matches_prompt(
      normalized,
      declaration,
      profile,
      task,
      { ..original_prompt, cid: materials.3, },
    ),
  )
  let changed = { ..execution, ceilings: execution.ceilings.copy(), }
  changed.ceilings[0] = 2L
  assert_false(model_mock_execution_matches(profile, normalized, changed))
  assert_eq(
    "sha256:" + @sha.hex(@utf8.encode(model_mock_execution_profile_wire())),
    "sha256:edadf04e63295c8f8212755301ed48e1ee7b060ec91b4d2519dbc512d5905ff7",
  )
  assert_eq(
    model_mock_profile_originals(profile).unwrap().1,
    "sha256:7e3143a485c71bac05f5fd819e047bbfa9cb9480f3b7b31358551e127dd23a71",
  )
  assert_true(
    model_mock_execution_materials(
      install_model_mock_profile(limits).unwrap(),
      normalized,
      limits,
    )
    is Err({ kind: ReferenceMismatch, .. }),
  )
}
