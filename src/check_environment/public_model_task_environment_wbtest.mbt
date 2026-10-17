///|
fn project_task_empty_environment() -> WireEnvironment {
  let body = "{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[],\"contract_registry\":[],\"host_policy_profile\":{},\"mapping_contracts\":[],\"model_task_contracts\":[],\"schema_snapshots\":[],\"source_views\":[],\"version\":\"actql-check-environment/0.1\"}"
  let identity = "sha256:" + @sha.hex(@utf8.encode(body))
  let wire = body.replace(
    old="\"host_policy_profile\"",
    new="\"evidence_bundle_cid\":\"" + identity + "\",\"host_policy_profile\"",
  )
  read(@utf8.encode(wire), identity, declaration_limits().bodies).unwrap()
}

///|
fn project_task_normalized(name : String) -> NormalizedPublicModelTask {
  let task = read_public_model_task_document(
    "{\"task\":\"" +
    name +
    "\",\"input\":{},\"output\":{},\"instructions\":\"\"}",
    "json",
    declaration_limits(),
  ).unwrap()
  let defaults = default_profile_read(
    handling_configuration(handling_policy_original()),
  )
  normalize_public_model_task(
    task,
    defaults,
    resolve_model_provider_defaults(defaults, None, None, 1000).unwrap(),
    "operator",
    declaration_limits(),
  ).unwrap()
}

///|
test "public Task Environment projection preserves exact original empty bytes and identity" {
  let environment = project_task_empty_environment()
  let (wire, identity, _) = project_public_model_task_environment(
    environment,
    [],
    declaration_limits(),
  ).unwrap()
  let writer = @encode.writer(10000, 1000, 32)
  emit(environment, writer)
  assert_eq(wire, @encode.finish(writer))
  assert_eq(identity, cid(environment))
}

///|
test "public Task Environment uses canonical original materials and ordinary Task admission" {
  let environment = project_task_empty_environment()
  let first = project_task_normalized("model-task:e\u{0301}")
  let second = project_task_normalized("model-task:second")
  let (wire, identity, _) = project_public_model_task_environment(
    environment,
    [first, second],
    declaration_limits(),
  ).unwrap()
  let admitted = read(@utf8.encode(wire), identity, declaration_limits().bodies).unwrap()
  let tasks = check_model_tasks(admitted, declaration_limits()).unwrap()
  assert_eq(
    model_task_identity(
      resolve_model_task(tasks, "model-task:e\u{0301}").unwrap(),
    ).2,
    first.task_cid,
  )
  assert_eq(
    model_task_model_selector(
      resolve_model_task(tasks, "model-task:second").unwrap(),
    ),
    second.resolved.model,
  )
  let reversed = project_public_model_task_environment(
    environment,
    [second, first],
    declaration_limits(),
  ).unwrap()
  assert_eq((wire, identity), (reversed.0, reversed.1))
}

///|
test "public Task Environment leaves duplicate selector refusal with the same Task Owner" {
  let environment = project_task_empty_environment()
  let first = project_task_normalized("model-task:duplicate")
  let (wire, identity, _) = project_public_model_task_environment(
    environment,
    [first, first],
    declaration_limits(),
  ).unwrap()
  let admitted = read(@utf8.encode(wire), identity, declaration_limits().bodies).unwrap()
  assert_true(
    check_model_tasks(admitted, declaration_limits()).unwrap_err().kind
    is DuplicateSelector("model-task:duplicate"),
  )
}

///|
test "public Task Environment enforces aggregate members output and work before adoption" {
  let environment = project_task_empty_environment()
  let task = project_task_normalized("model-task:limit")
  let limits = declaration_limits()
  let (_, _, work) = project_public_model_task_environment(
    environment,
    [task],
    limits,
  ).unwrap()
  assert_true(
    project_public_model_task_environment(environment, [task], {
      ..limits,
      max_work: work - 1,
    }).unwrap_err().kind
    is WorkLimit,
  )
  assert_true(
    project_public_model_task_environment(environment, [task], {
      ..limits,
      bodies: { ..limits.bodies, max_members: 0, },
    }).unwrap_err().kind
    is TaskLimit,
  )
  assert_true(
    project_public_model_task_environment(environment, [task], {
      ..limits,
      bodies: { ..limits.bodies, max_bytes: 1, },
    })
    is Err(_),
  )
}
