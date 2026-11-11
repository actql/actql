///|
fn original_effect_materials_fixture(
  parameters? : @decode.Cursor? = None,
  parameterized? : Bool = false,
  alternate? : Bool = false,
  normalized? : Bool = false,
) -> (
  PreparedClientEffectComputation,
  ClientEffectAllowedRun,
  @publication.PublicationContract,
) {
  let (base, environment, limits) = client_composed_effect_base_fixture()
  let base = if alternate {
    base.replace(old="\"value\":1", new="\"value\":2")
  } else {
    base
  }
  let document = if parameterized {
    base
    .replace(
      old="\"stages\":[",
      new="\"params\":{\"note\":{\"type\":\"string\"}},\"stages\":[",
    )
    .replace(
      old="\"as\":\"selected\"}],",
      new="\"as\":\"selected\"},{\"filter\":{\"eq\":[{\"$param\":\"note\"},{\"$param\":\"note\"}]}}],",
    )
  } else {
    base
  }
  let prepared = prepare_client_effect_computation(
    document,
    Json,
    environment,
    parameters,
    [],
    limits,
  ).unwrap()
  let bounds = run_materials_limits()
  let normalization = if normalized {
    Some(issue_prepared_client_effect_normalization(prepared).unwrap())
  } else {
    None
  }
  let compilation = issue_prepared_client_effect_compilation(
    prepared,
    run_materials_manifests(),
    bounds.sequence,
    bounds.max_sequence_steps,
    bounds.max_sequence_work,
    bounds.max_evidence_bytes,
    bounds.max_evidence_nodes,
    bounds.max_evidence_depth,
    normalization~,
  ).unwrap()
  let allowed = issue_client_effect_allowed_run(
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2026-10-10T00:00:00.000Z",
  ).unwrap()
  let definition = issue_client_effect_run_definition(
    allowed, "original-scope", "original-effect-run", "2026-10-09T00:00:00.000Z",
    "2026-10-10T00:00:00.000Z",
  ).unwrap()
  (prepared, allowed, definition)
}

///|
fn retained_static_effect_fixture(
  document : String,
  environment : @checked.CheckEnvironment,
  supplied : @decode.Cursor?,
  limits : ClientEffectComputationLimits,
) -> @checked.EffectProgramStaticCandidate {
  let parsed = @syntax.parse(
    document,
    limits.program.checking.input,
    format=Json,
  ).unwrap()
  let computation = @checked.prepare_effect_computation_candidate(
    parsed,
    environment,
    supplied,
    [],
    limits.program.checking,
    limits.max_members,
    limits.max_header_work,
  ).unwrap()
  let mappings = @environment.check_mapping_contract_shapes(
    @checked.effect_computation_environment(computation),
    limits.mapping,
    limits.max_mapping_work,
  ).unwrap()
  @checked.close_effect_computation_static(
    computation,
    mappings,
    limits.effects,
  ).unwrap()
}

///|
test "retained static Effect compilation preserves original supplied input without rechecking" {
  let (base, environment, limits) = client_composed_effect_base_fixture()
  let document = base
    .replace(
      old="\"stages\":[",
      new="\"params\":{\"note\":{\"type\":\"string\"}},\"stages\":[",
    )
    .replace(
      old="\"as\":\"selected\"}],",
      new="\"as\":\"selected\"},{\"filter\":{\"eq\":[{\"$param\":\"note\"},{\"$param\":\"note\"}]}}],",
    )
  let source = @source.parse_json_bytes(
    @utf8.encode("{\"note\":\"e\\u0301\\r\\n\\n\\r\"}"),
    { max_input_bytes: 1024, max_nodes: 10, max_depth: 3, },
  ).unwrap()
  let supplied = @decode.admit(source, {
    max_nodes: 10,
    max_depth: 3,
    max_string_bytes: 1024,
    max_total_string_bytes: 1024,
  }).unwrap()
  let candidate = retained_static_effect_fixture(
    document,
    environment,
    Some(supplied),
    limits,
  )
  let (parsed, original_supplied) = @checked.effect_program_static_original_input(
    candidate,
  )
  assert_true(
    original_supplied is Some(original) && physical_equal(original, supplied),
  )
  // These unused checking bounds cannot parse or check this Program again.
  // The actual lowering and graph bounds are unchanged.
  let compilation_limits = {
    ..limits.program,
    checking: {
      input: {
        ..limits.program.checking.input,
        source: { ..limits.program.checking.input.source, max_input_bytes: 0, },
      },
      compilation: { ..limits.program.checking.compilation, work: 0, },
    },
  }
  let prepared = prepare_static_client_effect_computation(
    candidate,
    compilation_limits,
    limits.max_mapping_work,
  ).unwrap()
  assert_true(physical_equal(prepared.candidate, candidate))
  assert_true(physical_equal(prepared.source, parsed))
  assert_true(
    prepared.supplied is Some(original) && physical_equal(original, supplied),
  )
  assert_eq(
    prepared_client_effect_computation_environment_cid(prepared),
    @checked.checking_environment_cid(environment),
  )
  let (_, parameters, _) = client_effect_original_input_wires(prepared).unwrap()
  let actual = decode_client_run_materials_parameters(parameters)
    .unwrap()
    .unwrap()
  let object = @decode.open_object(actual).unwrap()
  assert_eq(
    @decode.text(@decode.lookup(object, "note").unwrap()).unwrap(),
    "e\u0301\r\n\n\r",
  )
}

///|
test "retained static Effect compilation keeps actual task and graph bounds" {
  let (document, environment, limits) = client_composed_effect_base_fixture()
  let candidate = retained_static_effect_fixture(
    document,
    environment,
    None,
    limits,
  )
  assert_true(
    prepare_static_client_effect_computation(
      candidate,
      { ..limits.program, max_tasks: 0, },
      limits.max_mapping_work,
    )
    is Err(Graph(@strategy.GraphIssue::TaskLimit)),
  )
  assert_true(
    prepare_static_client_effect_computation(
      candidate,
      { ..limits.program, max_graph_work: 0, },
      limits.max_mapping_work,
    )
    is Err(Graph(@strategy.GraphIssue::WorkLimit)),
  )
}

///|
test "original Effect materials project original Program environment request and lifetime" {
  let (prepared, allowed, definition) = original_effect_materials_fixture()
  let normalization = issue_prepared_client_effect_normalization(prepared).unwrap()
  let request = prepare_client_effect_request_identity(
    prepared,
    "sha256:" + "c".repeat(64),
    "original-caller",
    source_free_caller_input_intent_cid(),
  ).unwrap()
  let wire = issue_prepared_client_effect_run_materials(
    allowed,
    definition,
    request=Some(request),
  ).unwrap()
  let body = read_client_run_materials_body(
    wire,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let writer = @encode.writer(65536, 8192, 64)
  @syntax.emit_program_source(prepared.source, writer)
  assert_eq(body.program, @encode.finish(writer))
  assert_eq(body.scope_id, "original-scope")
  assert_eq(body.run_id, "original-effect-run")
  assert_eq(body.created_at, "2026-10-09T00:00:00.000Z")
  assert_eq(body.valid_until, "2026-10-10T00:00:00.000Z")
  assert_eq(
    body.prepared_wire,
    @publication.run_evidence_value_json(
      @publication.run_publication_prepared(allowed.admission),
    ),
  )
  assert_eq(
    body.authorization_wire,
    @publication.run_evidence_value_json(
      @publication.run_publication_authorization(allowed.admission),
    ),
  )
  assert_true(
    physical_equal(
      normalization,
      issue_prepared_client_effect_normalization(prepared).unwrap(),
    ),
  )
  assert_eq(
    admit_client_request_identity_record_wire(body.request_wire.unwrap()).unwrap(),
    request,
  )
}

///|
test "original Effect materials preserve supplied Unicode and line ending values" {
  let values = "{\"note\":\"e\\u0301\\r\\n\\n\\r\"}"
  let source = @source.parse_json_bytes(@utf8.encode(values), {
    max_input_bytes: 1024,
    max_nodes: 10,
    max_depth: 3,
  }).unwrap()
  let parameters = @decode.admit(source, {
    max_nodes: 10,
    max_depth: 3,
    max_string_bytes: 1024,
    max_total_string_bytes: 1024,
  }).unwrap()
  let (_, allowed, definition) = original_effect_materials_fixture(
    parameters=Some(parameters),
    parameterized=true,
  )
  let wire = issue_prepared_client_effect_run_materials(allowed, definition).unwrap()
  let body = read_client_run_materials_body(
    wire,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let actual = body.parameters.unwrap()
  let object = @decode.open_object(actual).unwrap()
  assert_eq(
    @decode.text(@decode.lookup(object, "note").unwrap()).unwrap(),
    "e\u0301\r\n\n\r",
  )
}

///|
test "original Effect materials reject a foreign Run and request before encoding" {
  let (_, allowed, definition) = original_effect_materials_fixture()
  let (other, _, foreign) = original_effect_materials_fixture(alternate=true)
  // A definition for another checked Program does not bind this original Owner.
  assert_true(
    issue_prepared_client_effect_run_materials(allowed, foreign)
    is Err(Binding(_)),
  )
  let foreign_request = prepare_client_effect_request_identity(
    other,
    "sha256:" + "d".repeat(64),
    "foreign-caller",
    source_free_caller_input_intent_cid(),
  ).unwrap()
  // A request from another Program cannot replace the original request scope.
  let projection = issue_prepared_client_effect_run_materials(
    allowed,
    definition,
    request=Some(foreign_request),
  )
  assert_true(projection is Err(Request(_)))
}

///|
// The compiler is an explicit original here, not a Resource admission. The
// eventual Request caller must retain and fund it before entering this codec.
test "Effect material binding uses the supplied original compilation without rechecking its Program" {
  let (prepared, allowed, definition) = original_effect_materials_fixture()
  let request = prepare_client_effect_request_identity(
    prepared,
    "sha256:" + "c".repeat(64),
    "original-compiled-materials",
    source_free_caller_input_intent_cid(),
  ).unwrap()
  let wire = issue_prepared_client_effect_run_materials(
    allowed,
    definition,
    request=Some(request),
  ).unwrap()
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
  ).unwrap()
  assert_true(physical_equal(restored.prepared, prepared))
  assert_true(physical_equal(restored.compilation, allowed.compilation))
  assert_eq(restored.request, Some(request))
  assert_eq(
    @publication.publication_contract_identity(restored.run_definition),
    @publication.publication_contract_identity(definition),
  )
}

///|
test "Effect material binding rejects changed authored input without a second Program parser" {
  let (prepared, allowed, definition) = original_effect_materials_fixture()
  let request = prepare_client_effect_request_identity(
    prepared,
    "sha256:" + "c".repeat(64),
    "original-compiled-materials",
    source_free_caller_input_intent_cid(),
  ).unwrap()
  let wire = issue_prepared_client_effect_run_materials(
    allowed,
    definition,
    request=Some(request),
  ).unwrap()
  let body = parse_plan_identity_value(wire, 100000, 10000, 100).unwrap()
  let body = @canonical.object_without_field(body, "program").unwrap()
  let changed = @canonical.object_with_string_field(
    body, "program", "this is deliberately not a Program",
  ).unwrap()
  let changed = @canonical.stringify_value(changed, 100000, 10000, 100)
  let (_, _, effect_limits) = client_composed_effect_base_fixture()
  assert_true(
    admit_client_effect_run_materials(
      changed,
      @publication.publication_contract_identity(definition),
      { text_time: false, veca: false, },
      { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
      run_materials_manifests(),
      run_materials_limits(),
      effect_limits,
      original_compilation=Some(allowed.compilation),
      expected_request=Some(request),
    )
    is Err(RunMismatch),
  )
}

///|
test "Effect material binding requires the independently selected original Request" {
  let (prepared, allowed, definition) = original_effect_materials_fixture()
  let request = prepare_client_effect_request_identity(
    prepared,
    "sha256:" + "c".repeat(64),
    "original-compiled-materials",
    source_free_caller_input_intent_cid(),
  ).unwrap()
  let foreign = prepare_client_effect_request_identity(
    prepared,
    "sha256:" + "c".repeat(64),
    "foreign-compiled-materials",
    source_free_caller_input_intent_cid(),
  ).unwrap()
  let wire = issue_prepared_client_effect_run_materials(
    allowed,
    definition,
    request=Some(request),
  ).unwrap()
  let (_, _, effect_limits) = client_composed_effect_base_fixture()
  for expected in [None, Some(foreign)] {
    assert_true(
      admit_client_effect_run_materials(
        wire,
        @publication.publication_contract_identity(definition),
        { text_time: false, veca: false, },
        {
          rela: true,
          sga: false,
          tea: false,
          calendar: false,
          text_rank: false,
        },
        run_materials_manifests(),
        run_materials_limits(),
        effect_limits,
        original_compilation=Some(allowed.compilation),
        expected_request=expected,
      )
      is Err(Request(IdentityMismatch)),
    )
  }
}

///|
test "Effect material binding rejects a different original compiler without rebuilding it" {
  let (prepared, allowed, definition) = original_effect_materials_fixture()
  let (_, foreign, _) = original_effect_materials_fixture(alternate=true)
  let request = prepare_client_effect_request_identity(
    prepared,
    "sha256:" + "c".repeat(64),
    "original-compiled-materials",
    source_free_caller_input_intent_cid(),
  ).unwrap()
  let wire = issue_prepared_client_effect_run_materials(
    allowed,
    definition,
    request=Some(request),
  ).unwrap()
  let (_, _, effect_limits) = client_composed_effect_base_fixture()
  assert_true(
    admit_client_effect_run_materials(
      wire,
      @publication.publication_contract_identity(definition),
      { text_time: false, veca: false, },
      { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
      run_materials_manifests(),
      run_materials_limits(),
      effect_limits,
      original_compilation=Some(foreign.compilation),
      expected_request=Some(request),
    )
    is Err(Binding(_)),
  )
}

///|
test "Effect material binding reuses live custody and never displaces it with another Request" {
  let (prepared, allowed, definition) = original_effect_materials_fixture(
    normalized=true,
  )
  let request = prepare_client_effect_request_identity(
    prepared,
    "sha256:" + "c".repeat(64),
    "bound-original",
    source_free_caller_input_intent_cid(),
  ).unwrap()
  let foreign = prepare_client_effect_request_identity(
    prepared,
    "sha256:" + "c".repeat(64),
    "other-original",
    source_free_caller_input_intent_cid(),
  ).unwrap()
  let normalization = issue_prepared_client_effect_normalization(prepared).unwrap()
  let issued = issue_prepared_client_effect_normalization_materials(
    allowed,
    definition,
    normalization,
    request=Some(request),
  ).unwrap()
  let bound = bind_prepared_client_effect_original_materials(
    allowed,
    definition,
    issued,
    request=Some(request),
  ).unwrap()
  let wire = client_effect_issued_normalization_materials_wire(issued)
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
    original_materials=Some(issued),
    expected_request=Some(request),
  ).unwrap()
  assert_true(
    physical_equal(
      restored.normalization.unwrap(),
      bound.normalization.unwrap(),
    ),
  )
  let foreign_wire = issue_prepared_client_effect_run_materials(
    allowed,
    definition,
    normalization=Some(normalization),
    request=Some(foreign),
  ).unwrap()
  assert_true(
    admit_client_effect_run_materials(
      foreign_wire,
      @publication.publication_contract_identity(definition),
      { text_time: false, veca: false, },
      { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
      run_materials_manifests(),
      run_materials_limits(),
      effect_limits,
      original_compilation=Some(allowed.compilation),
      expected_request=Some(foreign),
    )
    is Err(Normalization(ForeignMaterials)),
  )
  assert_true(
    physical_equal(
      prepared.normalization_custody.unwrap(),
      bound.normalization.unwrap(),
    ),
  )
}
