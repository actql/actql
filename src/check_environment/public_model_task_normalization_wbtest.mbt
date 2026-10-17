///|
fn normalization_declaration(extra : String) -> PublicModelTaskDeclaration {
  read_public_model_task_declaration(
    declaration_cursor(
      "{\"task\":\"model-task:public.opaque\",\"input\":{},\"output\":{},\"instructions\":\"\"" +
      extra +
      "}",
    ),
    declaration_limits(),
  ).unwrap()
}

///|
test "public Task normalization fixes independent original Task prompt and schema identities" {
  let task = normalization_declaration(
    ",\"limits\":{\"max_output_tokens\":200}",
  )
  let defaults = default_profile_read(
    handling_configuration(handling_policy_original()),
  )
  let resolved = resolve_model_provider_defaults(
    defaults,
    None,
    Some(200L),
    1000,
  ).unwrap()
  let normalized = normalize_public_model_task(
    task,
    defaults,
    resolved,
    "operator",
    declaration_limits(),
  ).unwrap()
  let (wire, cid, prompt, prompt_cid) = normalized_public_model_task_materials(
    normalized,
  )
  // Independent literals calculated with Node crypto, not product output.
  assert_eq(
    cid, "sha256:e672bc4e7bc042bf5fd95712095c32d902065a876e8bf775bf1741f795bba1bd",
  )
  assert_eq(
    prompt_cid, "sha256:569a0ace73cebaae33dc947794fdb88961739bf54f4b61257af9a07305e3c976",
  )
  assert_eq(
    prompt,
    (
      #|{"payload":{"format":"actql.openai_chat_prompt/0.1","instructions":""},"self_cid":"sha256:569a0ace73cebaae33dc947794fdb88961739bf54f4b61257af9a07305e3c976","version":"actql-model-prompt/0.1"}
    ),
  )
  let cursor = declaration_cursor(wire)
  let object = @decode.open_object(cursor).unwrap()
  assert_eq(
    @decode.text(@decode.lookup(object, "version").unwrap()),
    Ok("model-task:public.opaque"),
  )
  assert_eq(
    @decode.text(@decode.lookup(object, "input_schema_cid").unwrap()),
    Ok(
      "sha256:f89257995d800e6fda8e5c4ea89ec10e01702a86253b6ef701930d4be9aac7fb",
    ),
  )
  assert_true(
    normalized_public_model_task_original_for(
      normalized, task, defaults, resolved,
    ),
  )
  // Consume the actual emitted material with the existing Environment/Task
  // Owner, not only this new normalizer's getters or a JSON shape assertion.
  let prefix = "{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[],\"contract_registry\":[],"
  let suffix = "\"host_policy_profile\":{},\"mapping_contracts\":[],\"model_task_contracts\":[" +
    wire +
    "],\"schema_snapshots\":[],\"source_views\":[],\"version\":\"actql-check-environment/0.1\"}"
  let environment_cid = "sha256:" + @sha.hex(@utf8.encode(prefix + suffix))
  let environment = read(
    @utf8.encode(
      prefix + "\"evidence_bundle_cid\":\"" + environment_cid + "\"," + suffix,
    ),
    environment_cid,
    { max_bytes: 10000, max_nodes: 1000, max_depth: 32, max_members: 100, },
  ).unwrap()
  let tasks = check_model_tasks(environment, declaration_limits()).unwrap()
  let checked = resolve_model_task(tasks, "model-task:public.opaque").unwrap()
  assert_eq(
    model_task_identity(checked),
    ("model-task:public.opaque", "model-task:public.opaque", cid),
  )
  assert_eq(
    model_task_generation_config(checked).unwrap().max_output_tokens,
    200L,
  )
  assert_eq(
    model_task_data_handling_cid(checked),
    "sha256:4ae245d55eb9bcb462b0e709d9b7495429918caab5207eb27c3e359428ca3763",
  )
  assert_false(
    normalized_public_model_task_original_for(
      normalized,
      normalization_declaration(",\"limits\":{\"max_output_tokens\":200}"),
      defaults,
      resolved,
    ),
  )
}

///|
test "public Task normalization refuses missing policy foreign profiles and mismatched overrides" {
  let task = normalization_declaration("")
  let defaults = default_profile_read(
    handling_configuration(handling_policy_original()),
  )
  let resolved = resolve_model_provider_defaults(defaults, None, None, 1000).unwrap()
  let foreign = default_profile_read(
    handling_configuration(handling_policy_original()),
  )
  assert_true(
    normalize_public_model_task(
      task,
      foreign,
      resolved,
      "operator",
      declaration_limits(),
    )
    is Err(_),
  )
  let no_policy = default_profile_read(default_profile_configuration())
  let no_policy_selection = resolve_model_provider_defaults(
    no_policy,
    None,
    None,
    1000,
  ).unwrap()
  assert_true(
    normalize_public_model_task(
      task,
      no_policy,
      no_policy_selection,
      "operator",
      declaration_limits(),
    )
    is Err(_),
  )
  let altered = resolve_model_provider_defaults(
    defaults,
    None,
    Some(200L),
    1000,
  ).unwrap()
  assert_true(
    normalize_public_model_task(
      task,
      defaults,
      altered,
      "operator",
      declaration_limits(),
    )
    is Err(_),
  )
  let explicit = normalization_declaration(
    ",\"model\":{\"provider\":\"operator\",\"name\":\"first\"}",
  )
  assert_true(
    normalize_public_model_task(
      explicit,
      defaults,
      resolved,
      "foreign",
      declaration_limits(),
    )
    is Err(_),
  )
  let other = resolve_model_provider_defaults(
    defaults,
    Some("second"),
    None,
    1000,
  ).unwrap()
  assert_true(
    normalize_public_model_task(
      explicit,
      defaults,
      other,
      "operator",
      declaration_limits(),
    )
    is Err(_),
  )
}

///|
test "public Task normalization retains prior policy materials when another configuration is read" {
  let task = normalization_declaration("")
  let defaults = default_profile_read(
    handling_configuration(handling_policy_original()),
  )
  let resolved = resolve_model_provider_defaults(defaults, None, None, 1000).unwrap()
  let value = normalize_public_model_task(
    task,
    defaults,
    resolved,
    "operator",
    declaration_limits(),
  ).unwrap()
  let before = normalized_public_model_task_materials(value)
  let later = default_profile_read(default_profile_configuration())
  let later_resolved = resolve_model_provider_defaults(later, None, None, 1000).unwrap()
  assert_false(
    normalized_public_model_task_original_for(
      value, task, later, later_resolved,
    ),
  )
  assert_eq(normalized_public_model_task_materials(value), before)
  let work = normalized_public_model_task_usage(value)
  assert_true(
    normalize_public_model_task(task, defaults, resolved, "operator", {
      ..declaration_limits(),
      max_work: work,
    })
    is Ok(_),
  )
  assert_true(
    normalize_public_model_task(task, defaults, resolved, "operator", {
      ..declaration_limits(),
      max_work: work - 1,
    })
    is Err({ kind: WorkLimit, .. }),
  )
}

///|
test "public Task normalization rejects negative unused limits instead of treating them as free" {
  let task = normalization_declaration("")
  let defaults = default_profile_read(
    handling_configuration(handling_policy_original()),
  )
  let resolved = resolve_model_provider_defaults(defaults, None, None, 1000).unwrap()
  let limits = declaration_limits()
  for
    invalid in [
      { ..limits, bodies: { ..limits.bodies, max_members: -1, }, },
      { ..limits, contracts: { ..limits.contracts, max_nodes: -1, }, },
      { ..limits, contracts: { ..limits.contracts, max_depth: -1, }, },
      { ..limits, contracts: { ..limits.contracts, max_text_bytes: -1, }, },
    ] {
    assert_true(
      normalize_public_model_task(task, defaults, resolved, "operator", invalid)
      is Err({ kind: InvalidLimits, .. }),
    )
  }
}
