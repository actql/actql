///|
// Actual checked three-Direct Effect graph with one Whole and two Query
// captures. Observation DATA is synthetic; this does not read a provider,
// publish an Effect, execute a Host or establish a physical cleanup ACK.
let mixed_three_effect_document : String =
  #|{"version":"actql/0.1","id":"mixed-three-original-effect","stages":[{"id":"first","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id >= 0","as":"filtered"},{"select":["id","amount"],"as":"captured"}],"results":{"rows":{"from":"captured","fields":["id","amount"]}}},{"id":"second","inputs":{"remote":{"connector":"crm/right","resource":"r"}},"steps":[{"filter":"id >= 0","as":"filtered"},{"select":["id","amount"],"as":"captured"}],"results":{"rows":{"from":"captured","fields":["id","amount"]}}},{"id":"third","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id >= 0","as":"filtered"},{"select":["id","amount"],"as":"captured"}],"results":{"rows":{"from":"captured","fields":["id","amount"]}}},{"id":"join_pair","inputs":{"left_rows":{"result":{"stage":"first","result":"rows"}},"right_rows":{"result":{"stage":"second","result":"rows"}}},"steps":[{"from":"left_rows","join":{"kind":"inner","with":"right_rows","max_output_rows":10,"on":[{"left":"id","right":"id"}],"select":{"id":"left.id","amount":"left.amount"}},"as":"joined"}],"results":{"rows":{"from":"joined","fields":["id","amount"]}}},{"id":"join_all","inputs":{"left_rows":{"result":{"stage":"join_pair","result":"rows"}},"right_rows":{"result":{"stage":"third","result":"rows"}}},"steps":[{"from":"left_rows","join":{"kind":"inner","with":"right_rows","max_output_rows":10,"on":[{"left":"id","right":"id"}],"select":{"id":"left.id","amount":"right.amount"}},"as":"joined"}],"results":{"rows":{"from":"joined","fields":["id","amount"]}}},{"id":"apply","inputs":{"input":{"result":{"stage":"join_all","result":"rows"}}},"steps":[{"select":[{"value":"id"}],"as":"selected"}],"results":{"out":{"from":"selected","fields":["value"]}},"effects":{"save":{"create":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"out"}}}}}],"results":{"published":{"from":{"stage":"apply","result":"out"}}}}

///|
fn effect_mixed_three_fixture() -> (
  ClientEffectCompilation,
  ClientEffectAllowedRun,
  @publication.PublicationContract,
) raise {
  let environment = admit_client_check_environment(
    bound_effect_source_environment,
    "sha256:e3da0e91ef758728bdf6e58957c09fe044d97d1fa2a21c9c19e3bdf5109bf45b",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let prepared = match
    prepare_client_effect_computation(
      mixed_three_effect_document,
      Json,
      environment,
      None,
      [],
      client_standard_effect_computation_limits(),
    ) {
    Ok(value) => value
    Err(Syntax(issue)) =>
      fail("mixed fixture syntax: " + @debug.to_string(issue))
    Err(Candidate(Computation(issue))) => raise issue
    Err(Candidate(_)) => fail("mixed fixture candidate")
    Err(Graph(issue)) => fail("mixed fixture graph: " + @debug.to_string(issue))
    Err(Static(_)) => fail("mixed fixture static Effect")
    Err(Mapping(_)) => fail("mixed fixture Mapping")
    Err(_) => fail("mixed fixture preparation")
  }
  let limits = run_materials_limits()
  // This graph is outside the finite one-root MappedCreate normalization
  // profile. Preserve its actual refusal; this component exercises the existing
  // optional-normalization compiler, not ordinary normalized publication.
  assert_true(
    issue_prepared_client_effect_normalization(prepared)
    is Err(Inventory(@checked.ProfileNotInstalled)),
  )
  let compilation = issue_prepared_client_effect_compilation(
    prepared,
    run_materials_manifests(),
    limits.sequence,
    limits.max_sequence_steps,
    limits.max_sequence_work,
    limits.max_evidence_bytes,
    limits.max_evidence_nodes,
    limits.max_evidence_depth,
  ).unwrap()
  let allowed = issue_client_effect_allowed_run(
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2027-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = issue_client_effect_run_definition(
    allowed, "mixed-three", "original-run", "2026-11-11T00:00:00.000Z", "2027-01-01T00:00:00.000Z",
  ).unwrap()
  (compilation, allowed, definition)
}

///|
fn effect_mixed_whole_capture(
  prepared : PreparedClientEffectComputation,
  live : Ref[Bool],
) -> (
  @query.CapturedInputSource,
  @query.CapturedSourceRelationIdentity,
  @acquisition.SourceAcquisition,
  @publication.RunEvidenceValue,
  @publication.RunEvidenceValue,
) {
  let graph = @strategy.checked_effect_computation_graph(prepared.graph)
  let acquisition = prepare_client_effect_source_acquisition(prepared, 0, 0).unwrap()
  let owner = @strategy.graph_task_owner(graph, 0).unwrap()
  let sequence = @lower.prepare_sequence(owner, run_materials_limits().sequence).unwrap()
  let rows = @execution.capture_input(
    owner,
    0,
    [scalar_profile_cursor("{\"amount\":7,\"id\":1}")],
    max_rows=1,
    string_try_number_execution_limits().rows.input_values,
  ).unwrap()
  let original = @execution.prepare_supplied_relation_read(owner, 0, rows, () => {
    live.val
  }).unwrap()
  let proof = Ref(original)
  let port = @query.prepare_trusted_source_input_capture_port(
    whole_source_capture_contracts(),
    sequence,
    acquisition,
    @checked.source_identity(@strategy.graph_program(graph)),
    2,
    8,
    fn(actual : Ref[@execution.SuppliedRelationRead]) {
      if physical_equal(actual, proof) && live.val {
        Some((actual.val, 41))
      } else {
        None
      }
    },
  ).unwrap()
  let captured = @query.capture_verified_source_input(port, proof).unwrap()
  let wire : @execution.RowWireLimits = {
    max_columns: 2,
    max_order_work: 10000,
    max_bytes: 20000,
    max_nodes: 10000,
    max_depth: 20,
  }
  let identity = @query.identify_captured_source_relation(
    captured,
    1,
    {
      max_nodes: 10000,
      max_text_bytes: 10000,
      max_depth: 20,
      max_work: 1000000,
    },
    wire,
    wire,
    { max_fields: 2, max_bytes: 10000, max_nodes: 1000, max_depth: 20, },
    20000,
  ).unwrap()
  let input = issue_captured_whole_source_input_logical(
    graph, captured, identity, acquisition,
  ).unwrap()
  let facts = @planning.source_acquisition_evidence_facts(acquisition).unwrap()
  let authority = "sha256:" + "a".repeat(64)
  let observation = @publication.seal_completed_source_observation({
    input,
    source_ref: facts.source_ref,
    source_contract_cid: facts.source_contract_cid,
    schema_evidence_cid: facts.carrier_schema_contract_cid,
    capability_evidence_cid: "sha256:" + "b".repeat(64),
    authority_scope_cid: authority,
    source_data_policy_cid: facts.source_data_policy_cid,
    data_classification: facts.data_classification,
    source_view_contract_cid: facts.source_view_contract_cid,
    observed_at: "2026-11-11T00:00:01.000Z",
    snapshot_ref: "fixture-snapshot",
  }).unwrap()
  (captured, identity, acquisition, observation, input)
}

///|
fn effect_mixed_query_capture(
  prepared : PreparedClientEffectComputation,
  stage : Int,
  live : Ref[Bool],
) -> (
  @query.CapturedInputSource,
  @query.CapturedSourceRelationIdentity,
  @planning.QueryRequirement,
  @publication.RunEvidenceValue,
  @publication.RunEvidenceValue,
) raise {
  let graph = @strategy.checked_effect_computation_graph(prepared.graph)
  let fragment = Some(product_test_fragment_wire())
  let ordered = Some(compiler_registered_ordered_wire())
  let contracts = @local_query_time.prepare_installed_sequence_contracts(
    compiler_registered_body_wire(),
    compiler_registered_values_wire(),
    fragment,
    ordered,
  ).unwrap()
  let requirement = @local_query_time.prepare_effect_local_query_requirement(
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
    graph,
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
test "mixed three Source Effect invocation preserves ordered originals and rejects substitution" {
  let (compilation, allowed, definition) = effect_mixed_three_fixture()
  let prepared = client_effect_compilation_owner(compilation)
  let graph = @strategy.checked_effect_computation_graph(prepared.graph)
  assert_eq(@strategy.graph_captured_prefix(graph), 3)
  let direct = select_client_effect_direct_acquisition_occurrences(
    prepared, 100000,
  ).unwrap()
  assert_eq(client_direct_acquisition_occurrence_count(direct), 3)
  let live = Ref(true)
  let whole = effect_mixed_whole_capture(prepared, live)
  let second = effect_mixed_query_capture(prepared, 1, live)
  let third = effect_mixed_query_capture(prepared, 2, live)
  let captures = [whole.0, second.0, third.0]
  let identities = [whole.1, second.1, third.1]
  let originals = [
    WholeSourceOriginal(whole.2),
    QuerySourceOriginal(second.2),
    QuerySourceOriginal(third.2),
  ]
  let sources = [whole.3, second.3, third.3]
  let inputs = [whole.4, second.4, third.4]
  // Repeated Catalog identity is not permission to coalesce nominal occurrences.
  assert_eq(
    @planning.source_acquisition_evidence_facts(whole.2).unwrap().source_ref,
    @planning.query_requirement_source(third.2).0,
  )
  assert_false(physical_equal(captures[0], captures[2]))
  let policy = prepared_client_effect_publication_data_policy_cid(prepared).unwrap()
  let invoke = (actual_captures, actual_originals, actual_sources) => {
    issue_client_effect_direct_sources_invocation(
      prepared,
      compilation,
      client_effect_allowed_run_admission(allowed),
      definition,
      direct,
      actual_captures,
      identities,
      actual_originals,
      actual_sources,
      inputs,
      "sha256:" + "a".repeat(64),
      policy,
      "2026-11-11T00:00:00.000Z",
      "2026-11-11T00:00:01.000Z",
      1000000,
      100000,
      100,
    )
  }
  let (observations, invocation) = invoke(captures, originals, sources).unwrap()
  let body = parse_plan_identity_value(
    @publication.run_evidence_value_json(observations),
    1000000,
    100000,
    100,
  ).unwrap()
  guard @canonical.object_field(body, "source_evidence_cids")
    is Some(@canonical.Array(values)) else {
    fail("missing original ordered Source evidence")
  }
  let listed = @canonical.array_values(values)
  assert_eq(listed.length(), 3)
  for index in 0..<3 {
    guard listed[index] is @canonical.String(cid) else {
      fail("Source identity must remain String")
    }
    assert_eq(cid, @publication.run_evidence_value_identity(sources[index]))
  }
  assert_true(
    @publication.publication_contract_json(invocation).contains(
      @publication.run_evidence_value_identity(observations),
    ),
  )
  assert_true(invoke(captures, originals, [sources[0], sources[1]]) is Err(_))
  assert_true(
    invoke([captures[2], captures[1], captures[0]], originals, sources)
    is Err(_),
  )
  assert_true(
    invoke(
      captures,
      [
        QuerySourceOriginal(third.2),
        QuerySourceOriginal(second.2),
        QuerySourceOriginal(third.2),
      ],
      sources,
    )
    is Err(_),
  )
  assert_true(
    invoke(
      captures,
      [
        WholeSourceOriginal(whole.2),
        QuerySourceOriginal(third.2),
        QuerySourceOriginal(second.2),
      ],
      sources,
    )
    is Err(_),
  )
  live.val = false
  assert_true(invoke(captures, originals, sources) is Err(_))
}
