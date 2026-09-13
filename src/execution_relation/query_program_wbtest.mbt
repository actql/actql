///|
// Public main construction APIs; not a fabricated CheckedProgram or private
// main test constructor. This fixture assembles source identity through public
// components; it does not invoke the final CheckedProgram entry.
fn query_program_fixture(
  id? : String = "p",
  supplied? : String = "{\"minimum\":1}",
) -> (@context.ProgramSourceIdentity, QuerySequence) raise {
  let text = "{\"version\":\"actql/0.1\",\"id\":\"" +
    id +
    "\",\"params\":{\"minimum\":{\"type\":\"number\",\"nullable\":false}},\"stages\":[{\"id\":\"a\",\"inputs\":{\"remote\":{\"connector\":\"crm/main\",\"resource\":\"r\"}},\"steps\":[{\"filter\":\"id > $minimum\",\"as\":\"filtered\"},{\"select\":[\"id\"],\"as\":\"captured\"}],\"results\":{\"r\":{\"from\":\"captured\",\"fields\":[\"id\"]}}}],\"results\":{\"out\":{\"from\":{\"stage\":\"a\",\"result\":\"r\"}}}}"
  let program = @syntax.parse(
    text,
    {
      source: { max_input_bytes: 1000000, max_nodes: 100000, max_depth: 100, },
      tree: {
        max_nodes: 100000,
        max_depth: 100,
        max_string_bytes: 1000000,
        max_total_string_bytes: 1000000,
      },
      max_stages: 10,
    },
    format=Json,
  ).unwrap()
  let source = @stages.prepare(program, {
    max_parameters: 100,
    max_nodes: 10000,
    max_depth: 100,
    max_text_bytes: 100000,
  }).unwrap()
  let (views, locals) = @context.prepare_source_registrations(
    source,
    query_program_catalog_fixture(),
    {
      max_work: 1000000,
      max_nodes: 100000,
      max_depth: 100,
      max_text_bytes: 1000000,
    },
    max_inputs=100,
    max_views=100,
    max_order_keys=100,
  ).unwrap()
  let mixed = @wire.check_mixed_claims([], [], {
    max_entities: 0,
    max_references: 0,
    max_bytes: 0,
    max_nodes: 0,
    max_depth: 0,
  }).unwrap()
  let claims = @wire.check_mixed_program_claims(mixed, [], {
    max_witnesses: 0,
    max_references: 0,
  }).unwrap()
  let sources = @host.bind_claim_sources(claims, [], {
    max_entries: 0,
    max_bytes: 0,
    max_nodes: 0,
    max_depth: 0,
  }).unwrap()
  let selected = @context.prepare_sourceview_context(
    views,
    locals,
    Some(input_cursor(supplied)),
    [[{ sources, consumers: [], }]],
    {
      max_stages: 10,
      max_steps: 10,
      max_results: 10,
      max_work: 1000000,
      max_nodes: 100000,
      max_tokens: 10000,
      max_text_bytes: 1000000,
      max_depth: 100,
    },
    {
      stages: {
        max_work: 10000000,
        max_text_bytes: 10000000,
        max_name_bytes: 1000000,
        max_input_work: 1000000,
        max_operand_work: 1000000,
      },
      max_policy_bytes: 10000,
      max_policy_nodes: 100,
      max_policy_depth: 10,
      max_local_input_nodes: 100000,
    },
  ).unwrap()
  let producer = @context.prepare_program_source_acquisitions(
    selected,
    [[]],
    {
      max_work: 10000000,
      max_pairs: 1000,
      values: { max_nodes: 10000, max_depth: 100, max_text_bytes: 100000, },
    },
    max_bindings=100,
    max_slots=1000,
  ).unwrap()
  let operations = @context.prepare_program_checks(
    producer,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    {
      work: 10000000,
      text_bytes: 10000000,
      source_value_nodes: 1000000,
      source_comparison_pairs: 1000000,
      policy_nodes: 1000000,
      local_input_nodes: 1000000,
      pattern_ast_bytes: 1000000,
      pattern_ast_nodes: 1000000,
    },
    max_policy_depth=100,
    max_requirements=1000,
    max_regex_depth=100,
  ).unwrap()
  let identity = @context.prepare_program_source_identity(operations, {
    body: {
      max_work: 1000000,
      selectors: {
        max_nodes: 10000,
        max_depth: 100,
        max_text_bytes: 100000,
        max_tokens: 1000,
        tree: {
          max_nodes: 10000,
          max_depth: 100,
          max_string_bytes: 100000,
          max_total_string_bytes: 100000,
        },
      },
    },
    uses: {
      max_work: 1000000,
      max_slots: 1000,
      max_references: 1000,
      max_pointer_units: 100000,
      max_direct_text_bytes: 100000,
    },
    references: {
      max_work: 4000000,
      max_slots: 1000,
      max_references: 1000,
      max_pointer_units: 1000000,
      max_request_text_bytes: 100000,
    },
    identity: {
      max_work: 10000000,
      max_stages: 10,
      max_hash_bytes: 1000000,
      max_hash_nodes: 100000,
      max_depth: 100,
    },
    max_bindings: 100,
  }).unwrap()
  let requests = @context.source_request_stage(
    @context.source_rows_requests(
      @context.source_policy_rows(
        @context.source_capacity_context(
          @context.source_producer_capacity(producer),
        ),
      ),
    ),
    0,
  ).unwrap()
  let query = @acquisition.derive_query_acquisition(requests, 0, 1000000).unwrap()
  let prepared = @lower.prepare(
    @acquisition.query_acquisition_pipeline(query),
    {
      max_nodes: 100,
      max_references: 100,
      max_work: 100000,
      max_identifier_bytes: 10000,
    },
  ).unwrap()
  let values = @acquisition.request_parameter_values(
    @acquisition.pipeline_requests_parameters(requests),
  )
  let bound = @lower.bind_parameters(
    prepared,
    Some(values),
    max_parameters=100,
    max_name_bytes=10000,
  ).unwrap()
  (
    identity,
    prepare_query_sequence(query, query_generated(bound), 10000).unwrap(),
  )
}

///|
test "Program-owned canonical query requirement refuses a separately constructed equal owner" {
  let (program, sequence) = query_program_fixture()
  let material = @planning.prepare_query_material(
    sequence,
    query_material_limits(),
  ).unwrap()
  let guards : @planning.QueryLogicalGuards = {
    max_rows: 10,
    max_value_bytes: 10000,
  }
  let requirement = @planning.prepare_query_requirement(
    material,
    program,
    guards,
    query_material_limits(),
  ).unwrap()
  assert_true(
    physical_equal(@planning.query_requirement_program(requirement), program),
  )
  assert_true(
    physical_equal(@planning.query_requirement_material(requirement), material),
  )
  assert_eq(@planning.query_requirement_site(requirement), ("a", "remote"))
  let (other, _) = query_program_fixture()
  assert_eq(
    @context.program_identity_definition_cid(program),
    @context.program_identity_definition_cid(other),
  )
  assert_true(
    @planning.prepare_query_requirement(
      material,
      other,
      guards,
      query_material_limits(),
    )
    is Err(ForeignProgram),
  )
}

///|
test "query requirement emits the shared exact preimage and cumulative budget frontiers" {
  let (program, sequence) = query_program_fixture()
  let material = @planning.prepare_query_material(
    sequence,
    query_material_limits(),
  ).unwrap()
  let limits = query_material_limits()
  let guards : @planning.QueryLogicalGuards = {
    max_rows: 10,
    max_value_bytes: 10000,
  }
  let value = @planning.prepare_query_requirement(
    material, program, guards, limits,
  ).unwrap()
  let schema = query_material_expected(
    "{\"id\":{\"nullable\":false,\"type\":\"number\"}}",
  )
  let filter = query_material_expected(
    "{\"gt\":[{\"field\":\"id\"},{\"$param\":\"minimum\"}]}",
  )
  let parameters = query_material_expected(
    "{\"values\":{\"minimum\":1},\"version\":\"actql-parameter-values/0.1\"}",
  )
  let definition = @context.program_identity_definition_cid(program)
  // Main-owned identity is the input to this assembly; expected structure and
  // all other hashes come from explicit preimages, not the emitted requirement.
  let expected = "{\"filter\":{\"expression_cid\":\"" +
    filter +
    "\",\"occurrence\":\"/steps/0/filter\"},\"input_contract_cid\":\"" +
    schema +
    "\",\"logical_guards\":{\"max_rows\":10,\"max_value_bytes\":10000},\"output_contract_cid\":\"" +
    schema +
    "\",\"owner\":{\"input\":\"remote\",\"program_source_cid\":\"" +
    definition +
    "\",\"stage\":\"a\"},\"parameter_values_cid\":\"" +
    parameters +
    "\",\"request\":{},\"select\":{\"fields\":[{\"input\":\"id\",\"output\":\"id\"}],\"occurrence\":\"/steps/1/select\"},\"source_contract_cid\":\"sha256:1f5ce9a50072a24f9cf0673d174f4f0639a216cc5537277e15299fef59db921f\",\"source_order_cid\":null,\"source_ref\":\"connector://crm/main/r#v\",\"source_validation\":{\"fields\":[\"id\"],\"scope\":\"selected_scan\"},\"version\":\"actql-query-acquisition/0.1\"}"
  assert_eq(
    @encode.document_text(@planning.query_requirement_document(value)),
    expected,
  )
  assert_eq(
    @planning.query_requirement_cid(value),
    query_material_expected(expected),
  )
  assert_eq(@planning.query_requirement_contracts(value), (schema, schema))
  assert_eq(
    @planning.query_requirement_source(value),
    (
      "connector://crm/main/r#v", "sha256:1f5ce9a50072a24f9cf0673d174f4f0639a216cc5537277e15299fef59db921f",
    ),
  )
  assert_eq(@planning.query_requirement_guards(value).max_rows, 10)
  let (work, bytes, nodes) = @planning.query_requirement_usage(value)
  assert_true(
    @planning.prepare_query_requirement(material, program, guards, {
      ..limits,
      max_work: work,
      max_bytes: bytes,
      max_nodes: nodes,
      max_fields: 2,
    })
    is Ok(_),
  )
  assert_true(
    @planning.prepare_query_requirement(material, program, guards, {
      ..limits,
      max_work: work - 1,
    })
    is Err(WorkLimit),
  )
  assert_true(
    @planning.prepare_query_requirement(material, program, guards, {
      ..limits,
      max_bytes: bytes - 1,
    })
    is Err(Encoding(_)),
  )
  assert_true(
    @planning.prepare_query_requirement(material, program, guards, {
      ..limits,
      max_nodes: nodes - 1,
    })
    is Err(Encoding(_)),
  )
  assert_true(
    @planning.prepare_query_requirement(material, program, guards, {
      ..limits,
      max_fields: 1,
    })
    is Err(FieldLimit),
  )
  assert_true(
    @planning.prepare_query_requirement(
      material,
      program,
      { ..guards, max_rows: -1, },
      limits,
    )
    is Err(InvalidLimits),
  )
  let changed = @planning.prepare_query_requirement(
    material,
    program,
    { ..guards, max_rows: 9, },
    limits,
  ).unwrap()
  assert_true(
    @planning.query_requirement_cid(changed) !=
    @planning.query_requirement_cid(value),
  )
}

///|
test "query owner uses Program Definition rather than semantics or Parameter value identity" {
  let (program, sequence) = query_program_fixture()
  let (renamed, other_sequence) = query_program_fixture(id="other")
  let (rebound, rebound_sequence) = query_program_fixture(
    supplied="{\"minimum\":2}",
  )
  let semantics = @program_refs.program_definition_semantics_cid(
    @context.program_identity_definition(program),
  )
  assert_eq(
    semantics,
    @program_refs.program_definition_semantics_cid(
      @context.program_identity_definition(renamed),
    ),
  )
  assert_true(
    @context.program_identity_definition_cid(program) !=
    @context.program_identity_definition_cid(renamed),
  )
  assert_true(@context.program_identity_definition_cid(program) != semantics)
  assert_eq(
    @context.program_identity_definition_cid(program),
    @context.program_identity_definition_cid(rebound),
  )
  let limits = query_material_limits()
  let guards : @planning.QueryLogicalGuards = {
    max_rows: 10,
    max_value_bytes: 10000,
  }
  let material = @planning.prepare_query_material(sequence, limits).unwrap()
  let first = @planning.prepare_query_requirement(
    material, program, guards, limits,
  ).unwrap()
  for (owner, seq) in [(renamed, other_sequence), (rebound, rebound_sequence)] {
    assert_true(
      @planning.prepare_query_requirement(material, owner, guards, limits)
      is Err(ForeignProgram),
    )
    let other_material = @planning.prepare_query_material(seq, limits).unwrap()
    let other = @planning.prepare_query_requirement(
      other_material, owner, guards, limits,
    ).unwrap()
    assert_true(
      @planning.query_requirement_cid(other) !=
      @planning.query_requirement_cid(first),
    )
  }
}
