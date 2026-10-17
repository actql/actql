///|
fn default_profile_limits() -> Limits {
  { max_bytes: 8192, max_nodes: 512, max_depth: 16, max_members: 8, }
}

///|
fn default_profile_configuration() -> String {
  (
    #|{"endpoint":"https://operator.invalid/","model_defaults":{"default_model":"operator-a","models":[{"model":"operator-a","generation_config":{"temperature":0.25,"top_p":0.875,"max_output_tokens":100}},{"model":"operator-b","generation_config":{"temperature":0,"top_p":1,"max_output_tokens":300,"seed_requested":-7}}]}}
  )
}

///|
fn default_profile_read(wire : String) -> ModelProviderDefaults {
  read_model_provider_defaults_configuration(
    @utf8.encode(wire),
    default_profile_limits(),
    100000,
  )
  .unwrap()
  .unwrap()
}

///|
test "provider default DATA selects only its explicit per-model generation" {
  let original = default_profile_read(default_profile_configuration())
  let resolved = resolve_model_provider_defaults(original, None, None, 1000).unwrap()
  assert_eq(resolved_model_provider_defaults_model(resolved), "operator-a")
  let generation = resolved_model_provider_defaults_generation(resolved)
  assert_eq(generation.temperature, 0.25)
  assert_eq(generation.top_p, 0.875)
  assert_eq(generation.max_output_tokens, 100L)
  assert_eq(generation.seed_requested, None)
  assert_true(physical_equal(resolved.original, original))
  // This is still configuration DATA, not a registered Provider or Task.
  assert_eq(original.models.length(), 2)
}

///|
test "explicit model and Task token limit override defaults without making defaults ceilings" {
  let original = default_profile_read(default_profile_configuration())
  let explicit = resolve_model_provider_defaults(
    original,
    Some("operator-b"),
    Some(200L),
    1000,
  ).unwrap()
  assert_eq(resolved_model_provider_defaults_model(explicit), "operator-b")
  let generation = resolved_model_provider_defaults_generation(explicit)
  assert_eq(generation.temperature, 0.0)
  assert_eq(generation.top_p, 1.0)
  assert_eq(generation.max_output_tokens, 200L)
  assert_eq(generation.seed_requested, Some(-7L))
  let above_default = resolve_model_provider_defaults(
    original,
    Some("operator-a"),
    Some(200L),
    1000,
  ).unwrap()
  assert_eq(above_default.generation.max_output_tokens, 200L)
  assert_eq(original.models[0].1.max_output_tokens, 100L)
}

///|
test "absent defaults preserve explicit legacy configuration without inventing a model" {
  for wire in ["{}", "null", "17", "{\"selector\":\"legacy-explicit\"}"] {
    assert_true(
      read_model_provider_defaults_configuration(
        @utf8.encode(wire),
        default_profile_limits(),
        100000,
      )
      is Ok(None),
    )
  }
  let original = default_profile_read(
    (
      #|{"model_defaults":{"models":[{"model":"operator-a","generation_config":{"temperature":0,"top_p":1,"max_output_tokens":100}}]}}
    ),
  )
  assert_true(
    resolve_model_provider_defaults(original, None, None, 1000)
    is Err(DefaultUnavailable),
  )
  assert_true(
    resolve_model_provider_defaults(original, Some("operator-a"), None, 1000)
    is Ok(_),
  )
  assert_true(
    resolve_model_provider_defaults(original, Some("other"), None, 1000)
    is Err(UnknownModel),
  )
}

///|
test "provider default admission checks unused models and rejects duplicate or unresolved originals" {
  for
    wire in [
      "{\"model_defaults\":{\"default_model\":\"absent\",\"models\":[]}}", "{\"model_defaults\":{\"default_model\":null,\"models\":[]}}",
      "{\"model_defaults\":{\"models\":[],\"temperature\":0}}", "{\"model_defaults\":{\"models\":[{\"model\":\"a\",\"generation_config\":{\"temperature\":0,\"top_p\":1,\"max_output_tokens\":1}},{\"model\":\"a\",\"generation_config\":{\"temperature\":0,\"top_p\":1,\"max_output_tokens\":2}}]}}",
      "{\"model_defaults\":{\"default_model\":\"a\",\"models\":[{\"model\":\"a\",\"generation_config\":{\"temperature\":0,\"top_p\":1,\"max_output_tokens\":1}},{\"model\":\"b\",\"generation_config\":{\"temperature\":0,\"top_p\":0,\"max_output_tokens\":1}}]}}",
      "{\"model_defaults\":{\"models\":[{\"model\":\"a\",\"generation_config\":{\"temperature\":0,\"top_p\":1,\"max_output_tokens\":1,\"seed_requested\":null}}]}}",
      "{\"model_defaults\":null}", "{\"model_defaults\":{\"models\":[]},\"model_defaults\":{\"models\":[]}}",
    ] {
    assert_true(
      read_model_provider_defaults_configuration(
        @utf8.encode(wire),
        default_profile_limits(),
        100000,
      )
      is Err(_),
    )
  }
}

///|
test "provider defaults keep exact model text and reject invalid Task token limits" {
  let original = default_profile_read(
    "{\"model_defaults\":{\"default_model\":\"e\u{0301}\",\"models\":[{\"model\":\"e\u{0301}\",\"generation_config\":{\"temperature\":0,\"top_p\":1,\"max_output_tokens\":100}}]}}",
  )
  assert_eq(
    resolved_model_provider_defaults_model(
      resolve_model_provider_defaults(original, None, None, 1000).unwrap(),
    ),
    "e\u{0301}",
  )
  assert_true(
    resolve_model_provider_defaults(original, Some("é"), None, 1000)
    is Err(UnknownModel),
  )
  for tokens in [0L, -1L, 9007199254740992L] {
    assert_true(
      resolve_model_provider_defaults(original, None, Some(tokens), 1000)
      is Err(InvalidTaskOutputTokens),
    )
  }
}

///|
test "provider default parsing and selection charge their exact independent work boundary" {
  let wire =
    #|{"model_defaults":{"models":[{"model":"m","generation_config":{"temperature":0,"top_p":1,"max_output_tokens":10}}]}}
  let original = default_profile_read(wire)
  let (bytes, nodes, work) = model_provider_defaults_usage(original)
  assert_eq(bytes, wire.length())
  assert_eq(nodes, 9)
  // 9 decoded nodes; 15 outer field work; 7 profile field work; 1 model;
  // 24 entry field work; 1 name unit; 36 generation fields and 3 values.
  assert_eq(work, bytes + 96)
  assert_true(
    read_model_provider_defaults_configuration(
      @utf8.encode(wire),
      default_profile_limits(),
      work,
    )
    is Ok(Some(_)),
  )
  assert_true(
    read_model_provider_defaults_configuration(
      @utf8.encode(wire),
      default_profile_limits(),
      work - 1,
    )
    is Err({ kind: WorkLimit, .. }),
  )
  let selected = resolve_model_provider_defaults(original, Some("m"), None, 4).unwrap()
  assert_eq(resolved_model_provider_defaults_work(selected), 4)
  assert_true(
    resolve_model_provider_defaults(original, Some("m"), None, 3)
    is Err(WorkLimit),
  )
}

///|
test "provider defaults enforce declared byte node depth and model cardinality bounds" {
  let wire = default_profile_configuration()
  let limits = default_profile_limits()
  for
    refused in [
      { ..limits, max_bytes: wire.length() - 1, },
      { ..limits, max_nodes: 1, },
      { ..limits, max_depth: 1, },
      { ..limits, max_members: 1, },
    ] {
    assert_true(
      read_model_provider_defaults_configuration(
        @utf8.encode(wire),
        refused,
        100000,
      )
      is Err(_),
    )
  }
  assert_true(
    read_model_provider_defaults_configuration(
      @utf8.encode(wire),
      { ..limits, max_members: -1, },
      100000,
    )
    is Err({ kind: InvalidLimits, .. }),
  )
}
