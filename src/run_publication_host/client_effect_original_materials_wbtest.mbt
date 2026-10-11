///|
fn original_effect_materials_fixture(
  parameters? : @decode.Cursor? = None,
  parameterized? : Bool = false,
  alternate? : Bool = false,
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
  let compilation = issue_prepared_client_effect_compilation(
    prepared,
    run_materials_manifests(),
    bounds.sequence,
    bounds.max_sequence_steps,
    bounds.max_sequence_work,
    bounds.max_evidence_bytes,
    bounds.max_evidence_nodes,
    bounds.max_evidence_depth,
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
