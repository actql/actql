///|
fn funded_materials_large_environment() -> @checked.CheckEnvironment raise {
  let (_, original, _) = client_composed_effect_base_fixture()
  let original_wire = @checked.checking_environment_wire(original)
  let (bytes, nodes, depth) = @environment.emission_geometry(original_wire)
  let writer = @encode.writer(bytes, nodes, depth)
  @environment.emit(original_wire, writer)
  guard @json.parse(@encode.finish(writer)) is Object(body) else {
    abort("original environment fixture")
  }
  let (extra_wire, _) = source_extent_environment(false, count=129)
  guard @json.parse(extra_wire) is Object(extra) else {
    abort("source environment fixture")
  }
  body.remove("evidence_bundle_cid")
  for
    name in [
      "connector_catalogs", "connector_capabilities", "contract_registry", "schema_snapshots",
      "source_views",
    ] {
    guard (body.get(name), extra.get(name))
      is (Some(Array(left)), Some(Array(right))) else {
      abort("original member inventory")
    }
    let merged = left.map(value => value.stringify())
    for value in right {
      merged.push(value.stringify())
    }
    body[name] = source_extent_members(merged).to_json()
  }
  guard (body.get("connector_manifest"), extra.get("connector_manifest"))
    is (Some(Object(left)), Some(Object(right))) &&
    (left.get("connectors"), right.get("connectors"))
    is (Some(Array(connectors)), Some(Array(additional))) else {
    abort("original manifest inventory")
  }
  for value in additional {
    connectors.push(value)
  }
  left["connectors"] = connectors.to_json()
  body["connector_manifest"] = Json::object(left)
  let (_, cid) = source_extent_json(Json::object(body))
  body["evidence_bundle_cid"] = cid.to_json()
  let (wire, _) = source_extent_json(Json::object(body))
  assert_true(@utf8.encode(wire).length() > 262144)
  admit_client_check_environment(
    wire,
    cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
}

///|
test "funded prepared original preserves complete bytes and refuses before each projection" {
  let (_, allowed, _, _) = target_selection_fixture()
  let ordinary = issue_client_effect_prepared_original(allowed.compilation).unwrap()
  let seen : Array[String] = []
  let funded = issue_client_effect_prepared_original(
    allowed.compilation,
    before_body=Some(fn(purpose, bytes, nodes, depth) {
      seen.push(purpose)
      bytes > 0 && nodes > 0 && depth > 0
    }),
  ).unwrap()
  assert_eq(funded, ordinary)
  assert_eq(seen, ["program", "environment", "run_materials"])
  for refused in ["program", "environment", "run_materials"] {
    seen.clear()
    assert_true(
      issue_client_effect_prepared_original(
        allowed.compilation,
        before_body=Some(fn(purpose, _, _, _) {
          seen.push(purpose)
          purpose != refused
        }),
      )
      is Err(Input(MaterialsConstructionRefused(reason))) &&
      reason == refused,
    )
    assert_eq(seen[seen.length() - 1], refused)
  }
}

///|
test "funded material projection preserves exact small bytes and refuses before the next writer" {
  let (prepared, allowed, definition) = original_effect_materials_fixture()
  assert_true(
    physical_equal(client_effect_allowed_run_owner(allowed), prepared),
  )
  let ordinary = issue_prepared_client_effect_run_materials(allowed, definition).unwrap()
  let seen : Array[String] = []
  let funded = issue_prepared_client_effect_run_materials(
    allowed,
    definition,
    before_body=Some(fn(purpose, bytes, nodes, depth) {
      seen.push(purpose)
      bytes > 0 && nodes > 0 && depth > 0
    }),
  ).unwrap()
  assert_eq(funded, ordinary)
  assert_eq(seen, [
    "program", "environment", "run_definition_read", "run_materials",
  ])
  seen.clear()
  assert_true(
    issue_prepared_client_effect_run_materials(
      allowed,
      definition,
      before_body=Some(fn(purpose, _, _, _) {
        seen.push(purpose)
        purpose != "environment"
      }),
    )
    is Err(Input(MaterialsConstructionRefused("environment"))),
  )
  assert_eq(seen, ["program", "environment"])
  let (_, _, foreign) = original_effect_materials_fixture(alternate=true)
  seen.clear()
  assert_true(
    issue_prepared_client_effect_run_materials(
      allowed,
      foreign,
      before_body=Some(fn(purpose, _, _, _) {
        seen.push(purpose)
        true
      }),
    )
    is Err(Binding(_)),
  )
  assert_eq(seen.length(), 0)
}

///|
test "funded material projection and inverse retain the complete large original environment" {
  let environment = funded_materials_large_environment()
  let (prepared, allowed, definition) = original_effect_materials_fixture(
    selected_environment=Some(environment),
  )
  let request = prepare_client_effect_request_identity(
    prepared,
    "sha256:" + "c".repeat(64),
    "funded-original",
    source_free_caller_input_intent_cid(),
  ).unwrap()
  assert_true(
    issue_prepared_client_effect_run_materials(
      allowed,
      definition,
      request=Some(request),
    )
    is Err(Input(MaterialsMalformed)),
  )
  let geometry = @environment.emission_geometry(
    @checked.checking_environment_wire(environment),
  )
  assert_true(geometry.0 > 65536 && geometry.1 > 4096)
  let emitted : Array[(Int, Int, Int)] = []
  let wire = issue_prepared_client_effect_run_materials(
    allowed,
    definition,
    request=Some(request),
    before_body=Some(fn(purpose, bytes, nodes, depth) {
      if purpose == "environment" {
        emitted.push((bytes, nodes, depth))
      }
      true
    }),
  ).unwrap()
  assert_eq(emitted, [geometry])
  assert_true(
    @utf8.encode(wire).length() > @remote.REMOTE_RUN_MATERIALS_MAX_BYTES,
  )
  assert_true(
    read_client_run_materials_body(wire, { text_time: false, veca: false, }, {
      rela: true,
      sga: false,
      tea: false,
      calendar: false,
      text_rank: false,
    })
    is Err(MaterialsMalformed),
  )
  let read_purposes : Array[String] = []
  let (_, _, effect_limits) = client_composed_effect_base_fixture()
  let restored = admit_client_effect_run_materials(
    wire,
    @publication.publication_contract_identity(definition),
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    run_materials_manifests(),
    run_materials_limits(),
    effect_limits,
    original_compilation=Some(allowed.compilation),
    expected_request=Some(request),
    before_body=Some(fn(purpose, _, _, _) {
      read_purposes.push(purpose)
      true
    }),
  ).unwrap()
  assert_true(physical_equal(restored.prepared, prepared))
  assert_true(physical_equal(restored.compilation, allowed.compilation))
  assert_eq(read_purposes, [
    "run_materials_read", "environment_read", "prepared_invocation_read", "run_authorization_read",
    "request_read", "program", "environment", "run_definition_read", "run_materials",
  ])
  read_purposes.clear()
  assert_true(
    admit_client_effect_run_materials(
      wire,
      @publication.publication_contract_identity(definition),
      { text_time: false, veca: false, },
      { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
      run_materials_manifests(),
      run_materials_limits(),
      effect_limits,
      original_compilation=Some(allowed.compilation),
      expected_request=Some(request),
      before_body=Some(fn(purpose, _, _, _) {
        read_purposes.push(purpose)
        purpose != "environment_read"
      }),
    )
    is Err(Input(MaterialsConstructionRefused("environment_read"))),
  )
  assert_eq(read_purposes, ["run_materials_read", "environment_read"])
}

///|
test "funded source geometry covers original Unicode escaping numbers and supplied values" {
  let source = @source.parse_json_bytes(
    @utf8.encode(
      "{\"note\":\"e\\u0301\\r\\n😀\",\"numbers\":[-1.2345678901234567e-200,1e+200]}",
    ),
    { max_input_bytes: 1024, max_nodes: 32, max_depth: 4, },
  ).unwrap()
  let root = @decode.admit(source, {
    max_nodes: 32,
    max_depth: 4,
    max_string_bytes: 1024,
    max_total_string_bytes: 1024,
  }).unwrap()
  let geometry = client_effect_material_source_geometry(root, 0).unwrap()
  let writer = @encode.writer(geometry.0, geometry.1, geometry.2)
  @syntax.emit_admitted_source_value(root, writer)
  let wire = @encode.finish(writer)
  assert_true(@utf8.encode(wire).length() <= geometry.0)
  let reparsed = @source.parse_json_bytes(@utf8.encode(wire), {
    max_input_bytes: geometry.0,
    max_nodes: geometry.1,
    max_depth: geometry.2,
  }).unwrap()
  assert_eq(
    @json.parse(wire),
    @json.parse(
      "{\"note\":\"e\\u0301\\r\\n😀\",\"numbers\":[-1.2345678901234567e-200,1e+200]}",
    ),
  )
  assert_true(
    @decode.admit(reparsed, {
      max_nodes: 32,
      max_depth: 4,
      max_string_bytes: 1024,
      max_total_string_bytes: 1024,
    })
    is Ok(_),
  )
}

///|
test "funded materials preserve original supplied Unicode and reject before its nested parser" {
  let parsed = @source.parse_json_bytes(
    @utf8.encode("{\"note\":\"e\\u0301\\r\\n😀\"}"),
    { max_input_bytes: 1024, max_nodes: 10, max_depth: 3, },
  ).unwrap()
  let parameters = @decode.admit(parsed, {
    max_nodes: 10,
    max_depth: 3,
    max_string_bytes: 1024,
    max_total_string_bytes: 1024,
  }).unwrap()
  let (_, allowed, definition) = original_effect_materials_fixture(
    parameters=Some(parameters),
    parameterized=true,
  )
  let purposes : Array[String] = []
  let wire = issue_prepared_client_effect_run_materials(
    allowed,
    definition,
    before_body=Some(fn(purpose, _, _, _) {
      purposes.push(purpose)
      true
    }),
  ).unwrap()
  assert_eq(purposes, [
    "program", "parameters", "environment", "run_definition_read", "run_materials",
  ])
  purposes.clear()
  let body = read_client_run_materials_body(
    wire,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    before_body=Some(fn(purpose, _, _, _) {
      purposes.push(purpose)
      true
    }),
  ).unwrap()
  assert_eq(purposes, [
    "run_materials_read", "parameters_read", "environment_read",
  ])
  let object = @decode.open_object(body.parameters.unwrap()).unwrap()
  assert_eq(
    @decode.text(@decode.lookup(object, "note").unwrap()).unwrap(),
    "e\u0301\r\n😀",
  )
  purposes.clear()
  assert_true(
    read_client_run_materials_body(
      wire,
      { text_time: false, veca: false, },
      { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
      before_body=Some(fn(purpose, _, _, _) {
        purposes.push(purpose)
        purpose != "parameters_read"
      }),
    )
    is Err(MaterialsConstructionRefused("parameters_read")),
  )
  assert_eq(purposes, ["run_materials_read", "parameters_read"])
}

///|
test "nominal material inverse compares full original Environment before borrowing its configured owner" {
  let (_, environment, effect_limits) = client_composed_effect_base_fixture()
  let (prepared, allowed, definition) = original_effect_materials_fixture(
    selected_environment=Some(environment),
  )
  let request = prepare_client_effect_request_identity(
    prepared,
    "sha256:" + "c".repeat(64),
    "nominal-env",
    source_free_caller_input_intent_cid(),
  ).unwrap()
  let wire = issue_prepared_client_effect_run_materials(
    allowed,
    definition,
    request=Some(request),
    before_body=Some((_, _, _, _) => true),
  ).unwrap()
  let seen : Array[String] = []
  let restore = (material, selected) => {
    admit_client_effect_run_materials(
      material,
      @publication.publication_contract_identity(definition),
      { text_time: false, veca: false, },
      { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
      run_materials_manifests(),
      run_materials_limits(),
      effect_limits,
      original_compilation=Some(allowed.compilation),
      expected_request=Some(request),
      original_environment=Some(selected),
      before_body=Some(fn(purpose, _, _, _) {
        seen.push(purpose)
        true
      }),
    )
  }
  let restored = restore(wire, environment).unwrap()
  assert_true(physical_equal(restored.prepared, prepared))
  assert_false(seen.contains("environment_read"))
  assert_eq(seen.filter(value => value == "environment"), [
    "environment", "environment",
  ])
  let wrong = target_projection_replace_raw_field(
    wire,
    "check_environment",
    Some("\"changed original\""),
  )
  seen.clear()
  assert_true(restore(wrong, environment) is Err(Input(MaterialsEnvironment)))
  assert_eq(seen, ["run_materials_read", "environment"])
  let raw = read_client_run_materials_body(
    wire,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let foreign = admit_client_check_environment(
    raw.environment_wire,
    @checked.checking_environment_cid(environment),
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  seen.clear()
  assert_true(restore(wire, foreign) is Err(Input(MaterialsEnvironment)))
  assert_eq(seen.length(), 0)
  let changed_profiles = @checked.checking_environment(
    @checked.checking_environment_wire(environment),
    { text_time: false, veca: false, },
    { rela: true, sga: true, tea: false, calendar: false, text_rank: false, },
  )
  assert_true(
    restore(wire, changed_profiles) is Err(Input(MaterialsEnvironment)),
  )
  assert_eq(seen.length(), 0)
}

///|
test "nominal material inverse rejects equal ModelTask bodies from another admitted original" {
  let (_, allowed, definition, request) = selected_infer_original_fixture()
  let checked = @strategy.graph_program(
    allowed.compilation.compiled.owner.graph,
  )
  let wire_original = @checked.checked_environment(checked)
  assert_true(@checked.checked_model_tasks(checked) is Some(_))
  let foreign = admit_client_check_environment_from_wire(
    wire_original,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  assert_true(
    physical_equal(@checked.checking_environment_wire(foreign), wire_original),
  )
  let wire = issue_prepared_client_effect_run_materials(
    allowed,
    definition,
    request=Some(request),
    before_body=Some((_, _, _, _) => true),
  ).unwrap()
  let calls = Ref(0)
  assert_true(
    admit_client_effect_run_materials(
      wire,
      @publication.publication_contract_identity(definition),
      { text_time: false, veca: false, },
      { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
      run_materials_manifests(),
      run_materials_limits(),
      client_standard_effect_computation_limits(),
      original_compilation=Some(allowed.compilation),
      expected_request=Some(request),
      original_environment=Some(foreign),
      before_body=Some(fn(_, _, _, _) {
        calls.val += 1
        true
      }),
    )
    is Err(Input(MaterialsEnvironment)),
  )
  assert_eq(calls.val, 0)
}
