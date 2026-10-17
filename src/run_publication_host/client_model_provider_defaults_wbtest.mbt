///|
fn installed_defaults_limits() -> @environment.Limits {
  { max_bytes: 4096, max_nodes: 256, max_depth: 16, max_members: 8, }
}

///|
fn installed_defaults_wire() -> String {
  (
    #|{"model_defaults":{"default_model":"m","models":[{"generation_config":{"max_output_tokens":100,"temperature":0.25,"top_p":0.875},"model":"m"}]}}
  )
}

///|
fn installed_defaults_read(wire : String) -> ClientModelProviderDefaults {
  read_client_model_provider_defaults(
    "models/independent",
    "{}",
    "{}",
    wire,
    installed_defaults_limits(),
    100000,
  ).unwrap()
}

///|
test "installed defaults retain the original canonical provider binding and profile pair" {
  let wire = installed_defaults_wire()
  let original = installed_defaults_read(wire)
  let binding = client_model_provider_defaults_binding(original)
  let previous = issue_client_model_provider_binding(
    "models/independent", "{}", "{}", wire,
  ).unwrap()
  assert_eq(
    @publication.run_evidence_value_json(binding),
    @publication.run_evidence_value_json(previous),
  )
  assert_eq(
    @publication.run_evidence_value_identity(binding),
    @publication.run_evidence_value_identity(previous),
  )
  let selected = resolve_client_model_provider_defaults(
    original,
    None,
    Some(200L),
    1000,
  ).unwrap()
  let generation = client_model_provider_defaults_generation(original, selected).unwrap()
  assert_eq(generation.max_output_tokens, 200L)
  assert_eq(generation.temperature, 0.25)
  assert_eq(generation.top_p, 0.875)
  assert_eq(generation.seed_requested, None)
}

///|
test "installed defaults refuse an equal separately admitted profile for the selected generation" {
  let original = installed_defaults_read(installed_defaults_wire())
  let foreign = installed_defaults_read(installed_defaults_wire())
  let selected = resolve_client_model_provider_defaults(
    original,
    None,
    None,
    1000,
  ).unwrap()
  assert_true(
    client_model_provider_defaults_generation(foreign, selected) is None,
  )
  assert_true(
    client_model_provider_defaults_generation(original, selected) is Some(_),
  )
}

///|
test "changed default configuration cannot rewrite a retained original profile or binding" {
  let original = installed_defaults_read(installed_defaults_wire())
  let changed = installed_defaults_read(
    installed_defaults_wire().replace(old="100", new="300"),
  )
  assert_true(
    @publication.run_evidence_value_identity(original.binding) !=
    @publication.run_evidence_value_identity(changed.binding),
  )
  let old_selection = resolve_client_model_provider_defaults(
    original,
    None,
    None,
    1000,
  ).unwrap()
  let new_selection = resolve_client_model_provider_defaults(
    changed,
    None,
    None,
    1000,
  ).unwrap()
  assert_eq(
    client_model_provider_defaults_generation(original, old_selection).unwrap().max_output_tokens,
    100L,
  )
  assert_eq(
    client_model_provider_defaults_generation(changed, new_selection).unwrap().max_output_tokens,
    300L,
  )
  assert_true(
    client_model_provider_defaults_generation(changed, old_selection) is None,
  )
}

///|
test "legacy no-default binding remains exact and reports profile read work without a selector" {
  let original = installed_defaults_read("{}")
  assert_true(
    resolve_client_model_provider_defaults(original, None, None, 1000)
    is Err(@environment.DefaultUnavailable),
  )
  let (bytes, nodes, work) = client_model_provider_defaults_usage(original)
  assert_eq(bytes, 2)
  assert_eq(nodes, 1)
  assert_true(work > bytes)
}

///|
test "installed defaults refuse noncanonical originals and malformed unused profiles" {
  assert_true(
    read_client_model_provider_defaults(
      "models/independent",
      " {}",
      "{}",
      installed_defaults_wire(),
      installed_defaults_limits(),
      100000,
    )
    is Err(InvalidBinding(_)),
  )
  assert_true(
    read_client_model_provider_defaults(
      "models/independent",
      "{}",
      "{}",
      "{\"model_defaults\":{\"models\":[{\"generation_config\":{\"max_output_tokens\":1,\"temperature\":0,\"top_p\":0},\"model\":\"unused\"}]}}",
      installed_defaults_limits(),
      100000,
    )
    is Err(InvalidDefaults(_)),
  )
}

///|
test "installed defaults preserve declared work limits and unknown model refusal" {
  assert_true(
    read_client_model_provider_defaults(
      "models/independent",
      "{}",
      "{}",
      installed_defaults_wire(),
      installed_defaults_limits(),
      1,
    )
    is Err(InvalidDefaults(@environment.WorkLimit)),
  )
  let original = installed_defaults_read(installed_defaults_wire())
  assert_true(
    resolve_client_model_provider_defaults(original, Some("other"), None, 1000)
    is Err(@environment.UnknownModel),
  )
}
