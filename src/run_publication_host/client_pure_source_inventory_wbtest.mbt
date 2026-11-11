///|
// Three checked occurrences; the first and third deliberately reuse one
// Catalog Source and equal row values while retaining different nominal owners.
let pure_three_source_document : String =
  #|{"version":"actql/0.1","id":"three-original-direct-sources","stages":[{"id":"first","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id >= 0","as":"filtered"},{"select":["id","amount"],"as":"captured"}],"results":{"rows":{"from":"captured","fields":["id","amount"]}}},{"id":"second","inputs":{"remote":{"connector":"crm/right","resource":"r"}},"steps":[{"filter":"id >= 0","as":"filtered"},{"select":["id","amount"],"as":"captured"}],"results":{"rows":{"from":"captured","fields":["id","amount"]}}},{"id":"third","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id >= 0","as":"filtered"},{"select":["id","amount"],"as":"captured"}],"results":{"rows":{"from":"captured","fields":["id","amount"]}}},{"id":"join_pair","inputs":{"left_rows":{"result":{"stage":"first","result":"rows"}},"right_rows":{"result":{"stage":"second","result":"rows"}}},"steps":[{"from":"left_rows","join":{"kind":"inner","with":"right_rows","max_output_rows":10,"on":[{"left":"id","right":"id"}],"select":{"id":"left.id","amount":"left.amount"}},"as":"joined"}],"results":{"rows":{"from":"joined","fields":["id","amount"]}}},{"id":"join_all","inputs":{"left_rows":{"result":{"stage":"join_pair","result":"rows"}},"right_rows":{"result":{"stage":"third","result":"rows"}}},"steps":[{"from":"left_rows","join":{"kind":"inner","with":"right_rows","max_output_rows":10,"on":[{"left":"id","right":"id"}],"select":{"id":"left.id","amount":"right.amount"}},"as":"joined"}],"results":{"rows":{"from":"joined","fields":["id","amount"]}}}],"results":{"answer":{"from":{"stage":"join_all","result":"rows"}}}}

///|
fn pure_three_source_capture(
  prepared : PreparedClientProgram,
  stage : Int,
  live : Ref[Bool],
) -> (
  @query.CapturedInputSource,
  @query.CapturedSourceRelationIdentity,
  @planning.QueryRequirement,
  @publication.RunEvidenceValue,
  @publication.RunEvidenceValue,
) raise {
  let fragment = Some(product_test_fragment_wire())
  let ordered = Some(compiler_registered_ordered_wire())
  let contracts = @local_query_time.prepare_installed_sequence_contracts(
    compiler_registered_body_wire(),
    compiler_registered_values_wire(),
    fragment,
    ordered,
  ).unwrap()
  let requirement = @local_query_time.prepare_local_query_requirement(
    prepared,
    stage,
    0,
    contracts,
    compiler_registered_values_wire(),
    fragment,
    ordered,
  ).unwrap()
  let sequence = @planning.query_material_owner(
    @planning.query_requirement_material(requirement),
  )
  let limits = string_try_number_execution_limits()
  let receipt = @query.admit_query_receipt(
    sequence,
    [scalar_profile_cursor("{\"amount\":7,\"id\":1}")],
    1,
    limits.rows.input_values,
  ).unwrap()
  let completed = @query.execute_query_receipt(sequence, receipt, limits).unwrap()
  let target = @acquisition.query_acquisition_capture(
    @query.query_sequence_requirement(sequence),
  )
  let output = @execution.completed_output(completed, target).unwrap()
  assert_eq(@execution.completed_row_count(output), 1)
  let port = @query.prepare_trusted_capture_port(
    sequence,
    @planning.query_requirement_program(requirement),
    fn(_ : Unit) { if live.val { Some((output, 21)) } else { None } },
  ).unwrap()
  let captured = @query.capture_verified_source(port, ()).unwrap()
  let wire : @execution.RowWireLimits = {
    max_columns: 10,
    max_order_work: 1000,
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 100,
  }
  let identity = @query.identify_captured_source_relation(
    captured,
    1,
    limits.rows.input_values,
    wire,
    wire,
    { max_fields: 10, max_bytes: 10000, max_nodes: 1000, max_depth: 100, },
    1000,
  ).unwrap()
  let logical = issue_captured_source_input_logical(
    prepared.graph,
    captured,
    identity,
    requirement,
    task=stage,
  ).unwrap()
  let facts = @planning.query_source_evidence_fact_values(
    @planning.query_requirement_source_evidence_facts(requirement).unwrap(),
  )
  let evidence = @publication.seal_completed_source_observation({
    input: logical,
    source_ref: facts[0],
    source_contract_cid: facts[1],
    schema_evidence_cid: facts[2],
    capability_evidence_cid: "sha256:" + "7".repeat(64),
    authority_scope_cid: "sha256:" + "a".repeat(64),
    source_data_policy_cid: facts[3],
    data_classification: facts[4],
    source_view_contract_cid: facts[5],
    observed_at: "2026-11-11T00:00:01.000Z",
    snapshot_ref: "original-" + stage.to_string(),
  }).unwrap()
  (captured, identity, requirement, evidence, logical)
}

///|
test "Pure three Source captured invocation retains every original occurrence and refuses substitutions" {
  let prepared = multi_source_prepared(pure_three_source_document)
  assert_eq(prepared_client_acquisition_count(prepared), 3)
  let compilation = issue_prepared_client_task_compilation(
    prepared,
    run_materials_manifests(),
    client_standard_values_sequence_limits(),
    1000,
    1000,
    1000000,
    100000,
    100,
  ).unwrap()
  let run = issue_client_task_compiled_run(
    prepared,
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = issue_client_compiled_run_definition(
    run, "pure-three", "original-run", "2026-11-11T00:00:00.000Z", "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let live = Ref(true)
  let tuples = [0, 1, 2].map(stage => {
    pure_three_source_capture(prepared, stage, live)
  })
  let captures = tuples.map(value => value.0)
  let identities = tuples.map(value => value.1)
  let requirements = tuples.map(value => value.2)
  let sources = tuples.map(value => value.3)
  let inputs = tuples.map(value => value.4)
  assert_eq(
    @query.captured_source_relation_logical_cid(identities[0]),
    @query.captured_source_relation_logical_cid(identities[2]),
  )
  assert_false(physical_equal(captures[0], captures[2]))
  let policy = prepared_client_publication_data_policy_cid(prepared).unwrap()
  let issue = (
    actual_captures,
    actual_identities,
    actual_requirements,
    actual_sources,
    actual_inputs,
    bytes,
  ) => {
    issue_client_compiled_captured_invocation(
      run,
      definition,
      actual_captures,
      actual_identities,
      actual_requirements,
      actual_sources,
      actual_inputs,
      None,
      "sha256:" + "a".repeat(64),
      policy,
      "2026-11-11T00:00:00.000Z",
      "2026-11-11T00:00:01.000Z",
      bytes,
      100000,
      100,
    )
  }
  let (observation, _) = match
    issue(captures, identities, requirements, sources, inputs, 1000000) {
    Ok(value) => value
    Err(@publication.RunEvidenceReferenceMismatch(name)) =>
      fail("complete original inventory refused: " + name)
    Err(_) => fail("complete original inventory refused")
  }
  let (wire_observation, _) = issue_client_compiled_multi_task_invocation(
    run,
    definition,
    captures,
    identities,
    requirements,
    sources.map(@publication.run_evidence_value_json),
    inputs.map(@publication.run_evidence_value_json),
    "sha256:" + "a".repeat(64),
    policy,
    "2026-11-11T00:00:00.000Z",
    "2026-11-11T00:00:01.000Z",
    1000000,
    100000,
    100,
  ).unwrap()
  assert_eq(
    @publication.run_evidence_value_identity(wire_observation),
    @publication.run_evidence_value_identity(observation),
  )
  let body = parse_plan_identity_value(
    @publication.run_evidence_value_json(observation),
    1000000,
    100000,
    100,
  ).unwrap()
  guard @canonical.object_field(body, "source_evidence_cids")
    is Some(@canonical.Array(values)) else {
    fail("missing ordered Source evidence")
  }
  let listed = @canonical.array_values(values)
  assert_eq(listed.length(), 3)
  for index in 0..<3 {
    guard listed[index] is @canonical.String(cid) else {
      fail("Source evidence identity must remain a String")
    }
    assert_eq(cid, @publication.run_evidence_value_identity(sources[index]))
  }
  assert_true(
    issue(
      [captures[0], captures[1]],
      identities,
      requirements,
      sources,
      inputs,
      1000000,
    )
    is Err(_),
  )
  assert_true(
    issue(
      [captures[0], captures[1], captures[0]],
      identities,
      requirements,
      sources,
      inputs,
      1000000,
    )
    is Err(_),
  )
  assert_true(
    issue(
      captures,
      [identities[2], identities[1], identities[0]],
      requirements,
      sources,
      inputs,
      1000000,
    )
    is Err(_),
  )
  assert_true(
    issue(
      captures,
      identities,
      [requirements[2], requirements[1], requirements[0]],
      sources,
      inputs,
      1000000,
    )
    is Err(_),
  )
  assert_true(
    issue(
      captures,
      identities,
      requirements,
      [sources[1], sources[0], sources[2]],
      inputs,
      1000000,
    )
    is Err(_),
  )
  assert_true(
    issue(captures, identities, requirements, sources, inputs, 1)
    is Err(@publication.RunEvidenceInvalidWire),
  )
  let foreign = multi_source_prepared(pure_three_source_document)
  let (foreign_capture, foreign_identity, foreign_requirement, _, _) = pure_three_source_capture(
    foreign, 0, live,
  )
  assert_true(
    issue(
      [foreign_capture, captures[1], captures[2]],
      [foreign_identity, identities[1], identities[2]],
      [foreign_requirement, requirements[1], requirements[2]],
      sources,
      inputs,
      1000000,
    )
    is Err(_),
  )
  live.val = false
  assert_true(
    issue(captures, identities, requirements, sources, inputs, 1000000)
    is Err(_),
  )
}

///|
test "Pure three Source policy refuses an uncovered checked response and equal foreign owners" {
  let prepared = multi_source_prepared(pure_three_source_document)
  let program = @strategy.graph_program(prepared.graph)
  let policy = @checked.publication_source_policy(
    @checked.unit_publication_at(program, 4, 0).unwrap(),
  ).unwrap()
  assert_eq(@checked.publication_policy_source_count(policy), 3)
  assert_true(
    client_publication_policy_covers_source_responses(program, policy),
  )
  assert_true(prepared_client_publication_data_policy_cid(prepared) is Some(_))
  let partial = multi_source_prepared(
    pure_three_source_document.replace(
      old="\"stage\":\"join_all\",\"result\":\"rows\"",
      new="\"stage\":\"join_pair\",\"result\":\"rows\"",
    ),
  )
  assert_eq(prepared_client_acquisition_count(partial), 3)
  assert_eq(prepared_client_publication_data_policy_cid(partial), None)
  let foreign = multi_source_prepared(pure_three_source_document)
  let foreign_program = @strategy.graph_program(foreign.graph)
  let foreign_policy = @checked.publication_source_policy(
    @checked.unit_publication_at(foreign_program, 4, 0).unwrap(),
  ).unwrap()
  assert_eq(policy.cid, foreign_policy.cid)
  assert_false(
    client_publication_policy_covers_source_responses(program, foreign_policy),
  )
}
