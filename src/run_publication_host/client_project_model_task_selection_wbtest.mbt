///|
fn selection_task(extra : String) -> @environment.PublicModelTaskDeclaration {
  let wire = "{\"task\":\"model-task:t\",\"input\":{},\"output\":{},\"instructions\":\"original\"" +
    extra +
    "}"
  let node = @source.parse_json_bytes_preserving(@utf8.encode(wire), {
    max_input_bytes: 10000,
    max_nodes: 1000,
    max_depth: 16,
  }).unwrap()
  let cursor = @decode.admit(node, {
    max_nodes: 1000,
    max_depth: 16,
    max_string_bytes: 10000,
    max_total_string_bytes: 10000,
  }).unwrap()
  @environment.read_public_model_task_declaration(cursor, {
    bodies: {
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 16,
      max_members: 100,
    },
    contracts: { max_nodes: 100, max_depth: 16, max_text_bytes: 1000, },
    max_work: 100000,
  }).unwrap()
}

///|
fn selection_registry() -> ClientProjectModelRegistry {
  admit_client_project_model_registry(
    (
      #|{"version":"actql-model-tasks/0.1","tasks":{"model-task:t":"original.yaml"},"providers":{"first":{"type":"openai"},"second":{"type":"fixture"}},"default_provider":"first"}
    ),
  ).unwrap()
}

///|
test "project Task selects explicit pair instead of registry default and retains original pair" {
  let registry = selection_registry()
  let task = selection_task(
    ",\"model\":{\"provider\":\"second\",\"name\":\"explicit\"}",
  )
  let selected = select_client_project_model_task(registry, task, 10000).unwrap()
  assert_eq(
    client_project_model_task_selection_for(selected, registry, task),
    Some(("second", Some("explicit"), "original.yaml")),
  )
  assert_eq(
    client_project_model_task_selection_for(
      selected,
      selection_registry(),
      task,
    ),
    None,
  )
  assert_eq(
    client_project_model_task_selection_for(
      selected,
      registry,
      selection_task(
        ",\"model\":{\"provider\":\"second\",\"name\":\"explicit\"}",
      ),
    ),
    None,
  )
}

///|
test "project Task omission selects only the original registered default" {
  let registry = selection_registry()
  let task = selection_task("")
  let selected = select_client_project_model_task(registry, task, 10000).unwrap()
  assert_eq(
    client_project_model_task_selection_for(selected, registry, task),
    Some(("first", None, "original.yaml")),
  )
  let absent = admit_client_project_model_registry(
    (
      #|{"version":"actql-model-tasks/0.1","tasks":{"model-task:t":"original.yaml"},"providers":{"first":{"type":"openai"}}}
    ),
  ).unwrap()
  assert_true(
    select_client_project_model_task(absent, task, 10000)
    is Err(ProviderUnavailable),
  )
  assert_true(
    select_client_project_model_task(
      registry,
      selection_task(
        ",\"model\":{\"provider\":\"foreign\",\"name\":\"explicit\"}",
      ),
      10000,
    )
    is Err(ProviderUnavailable),
  )
}

///|
test "project Task selection work has an exact boundary before matching originals" {
  let registry = selection_registry()
  let task = selection_task("")
  let selected = select_client_project_model_task(registry, task, 10000).unwrap()
  let work = client_project_model_task_selection_usage(selected)
  assert_true(select_client_project_model_task(registry, task, work) is Ok(_))
  assert_true(
    select_client_project_model_task(registry, task, work - 1) is Err(WorkLimit),
  )
  assert_true(
    select_client_project_model_task(registry, task, -1) is Err(InvalidLimits),
  )
}

///|
test "project Task generation uses its original pair provider and explicit token override" {
  let registry = selection_registry()
  let task = selection_task(",\"limits\":{\"max_output_tokens\":200}")
  let selected = select_client_project_model_task(registry, task, 10000).unwrap()
  let defaults = read_client_model_provider_defaults(
    "first",
    "{}",
    "{}",
    installed_defaults_wire(),
    installed_defaults_limits(),
    100000,
  ).unwrap()
  let resolved = resolve_client_project_model_task_defaults(
    selected, registry, task, defaults, 1000,
  ).unwrap()
  assert_eq(
    client_model_provider_defaults_generation(defaults, resolved).unwrap().max_output_tokens,
    200L,
  )
  assert_true(
    resolve_client_project_model_task_defaults(
      selected,
      selection_registry(),
      task,
      defaults,
      1000,
    )
    is Err(ForeignOriginal),
  )
  assert_true(
    resolve_client_project_model_task_defaults(
      selected,
      registry,
      selection_task(",\"limits\":{\"max_output_tokens\":200}"),
      defaults,
      1000,
    )
    is Err(ForeignOriginal),
  )
  let foreign = read_client_model_provider_defaults(
    "second",
    "{}",
    "{}",
    installed_defaults_wire(),
    installed_defaults_limits(),
    100000,
  ).unwrap()
  assert_true(
    resolve_client_project_model_task_defaults(
      selected, registry, task, foreign, 1000,
    )
    is Err(ForeignOriginal),
  )
}
