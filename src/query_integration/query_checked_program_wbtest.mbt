///|
fn query_checked_program_fixture(
  nullable? : Bool = false,
  catalog? : @environment.SourceRequestContracts? = None,
  dag? : Bool = false,
) -> @program_check.CheckedProgram raise {
  let text =
    #|{"version":"actql/0.1","id":"p","params":{"minimum":{"type":"number","nullable":false}},"stages":[{"id":"a","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id > $minimum","as":"filtered"},{"select":["id"],"as":"captured"}],"results":{"r":{"from":"captured","fields":["id"]}}}],"results":{"out":{"from":{"stage":"a","result":"r"}}}}
  let text = if dag {
    text.replace(
      old="}],\"results\":{\"out\":{\"from\":{\"stage\":\"a\",\"result\":\"r\"}}}}",
      new="},{\"id\":\"compute_a\",\"inputs\":{\"x\":{\"result\":{\"stage\":\"a\",\"result\":\"r\"}}},\"steps\":[{\"filter\":\"id > 2\"},{\"select\":[\"id\"],\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":[\"id\"]}}},{\"id\":\"compute_b\",\"inputs\":{\"x\":{\"result\":{\"stage\":\"a\",\"result\":\"r\"}}},\"steps\":[{\"filter\":\"id > 0\"},{\"select\":[\"id\"],\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":[\"id\"]}}},{\"id\":\"compute_c\",\"inputs\":{\"x\":{\"result\":{\"stage\":\"compute_a\",\"result\":\"r\"}}},\"steps\":[{\"filter\":\"id < 9\"},{\"select\":[\"id\"],\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":[\"id\"]}}}],\"results\":{\"b\":{\"from\":{\"stage\":\"compute_b\",\"result\":\"r\"}},\"c\":{\"from\":{\"stage\":\"compute_c\",\"result\":\"r\"}}}}",
    )
  } else {
    text
  }
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
  let policies = @environment.value_contract_policies(
    @environment.source_view_shape_values(
      @environment.read_mode_shapes(
        @environment.carrier_schema_modes(
          @environment.source_request_carriers(
            if catalog is Some(catalog) {
              catalog
            } else if nullable {
              query_nullable_catalog_fixture()
            } else {
              query_program_catalog_fixture()
            },
          ),
        ),
      ),
    ),
  )
  let environment = @environment.contract_registry_environment(
    @environment.catalog_registry(
      @environment.reference_contents(
        @environment.data_policy_references(policies),
      ),
    ),
  )
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
  @program_check.check(
    program,
    environment,
    Some(input_cursor("{\"minimum\":1}")),
    if dag {
      [1, 2, 2, 3].map(visits => {
        Array::makei(visits, _ => { sources, consumers: [], })
      })
    } else {
      [[{ sources, consumers: [], }]]
    },
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    query_checked_limits(10),
    max_work=100000000,
    max_bytes=10000000,
    max_nodes=1000000,
    max_depth=100,
  )
}

///|
test "query Program reaches the public main checked entry" {
  let checked = query_checked_program_fixture()
  assert_eq(@program_check.unit_count(checked), 1)
  assert_eq(@program_check.source_execution_count(checked), 5)
  for i in 0..<5 {
    let execution = @program_check.source_execution_at(checked, i).unwrap()
    assert_true(
      physical_equal(
        @program_check.source_execution_subject(execution).owner,
        @program_check.source_identity(checked),
      ),
    )
  }
}

///|
fn query_checked_sequence(
  checked : @program_check.CheckedProgram,
) -> @query.QuerySequence raise {
  let identity = @program_check.source_identity(checked)
  let requests = @context.program_identity_stage_requests(identity, 0).unwrap()
  let query = @acquisition.derive_query_acquisition(requests, 0, 1000000).unwrap()
  assert_true(
    physical_equal(
      @program_check.unit_pipeline(checked, 0).unwrap(),
      @acquisition.query_acquisition_pipeline(query),
    ),
  )
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
  @query.prepare_query_sequence(query, query_generated(bound), 10000).unwrap()
}

///|
test "public CheckedProgram feeds both query strategies capture and checked consumer" {
  let checked = query_checked_program_fixture()
  let identity = @program_check.source_identity(checked)
  let sequence = query_checked_sequence(checked)
  let material = @planning.prepare_query_material(
    sequence,
    query_material_limits(),
  ).unwrap()
  let requirement = @planning.prepare_query_requirement(
    material,
    identity,
    { max_rows: 10, max_value_bytes: 100, },
    query_material_limits(),
  ).unwrap()
  let unit_cid = @program_check.unit_definition_cid(checked, 0).unwrap()
  let requirement_cid = @planning.query_requirement_cid(requirement)
  let (query_body, evidence_body) = query_evidence_test_bodies()
  let contracts = @planning.admit_query_evidence_contracts(
    query_body,
    evidence_body,
    query_capture_limits(),
  ).unwrap()
  let issuer = @planning.prepare_mock_query_issuer(
    contracts, requirement, "checked-program-test", 100,
  ).unwrap()
  let owner = @query.query_sequence_owner(sequence)
  let receiver = typed_receiver(owner, "[{\"select\":[\"id\"]}]")
  for route in [@planning.NativeQuery, @planning.BroadWithResidual] {
    let attempt = query_issuer_attempt(issuer, sequence, route)
    query_issuer_run(attempt)
    let records = @planning.issue_mock_query_records(
      attempt,
      query_material_limits(),
    ).unwrap()
    let observation = @planning.capture_mock_query(
      issuer,
      attempt,
      records,
      query_capture_limits(),
    ).unwrap()
    let input = @planning.bind_captured_query_input(
      issuer, attempt, observation, receiver, 0, owner,
    ).unwrap()
    let consumer = @execution.prepare_local_compute_attempt(
      compute_test_sequence(receiver),
      [input],
      3,
    ).unwrap()
    let complete = @execution.execute_local_compute_attempt(
      consumer,
      compute_test_limits(),
    ).unwrap()
    let output = @execution.completed_output(complete, Step(0)).unwrap()
    assert_eq(@execution.completed_row_count(output), 2)
    assert_true(@execution.completed_cell(output, 0, 0) is Some(Number(3)))
    assert_true(@execution.completed_cell(output, 1, 0) is Some(Number(2)))
    assert_eq(@program_check.unit_definition_cid(checked, 0).unwrap(), unit_cid)
    assert_eq(@planning.query_requirement_cid(requirement), requirement_cid)
  }
  let foreign = query_checked_program_fixture()
  assert_eq(
    @context.program_identity_definition_cid(
      @program_check.source_identity(foreign),
    ),
    @context.program_identity_definition_cid(identity),
  )
  assert_true(
    @planning.prepare_query_requirement(
      material,
      @program_check.source_identity(foreign),
      { max_rows: 10, max_value_bytes: 100, },
      query_material_limits(),
    )
    is Err(ForeignProgram),
  )
}
