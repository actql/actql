///|
fn client_effect_serialized_infer_fixture(
  keep? : Bool = false,
) -> PreparedClientEffectComputation raise {
  let (_, _, limits) = client_composed_effect_base_fixture()
  let base = admit_client_check_environment(
    local_normalization_environment_wire,
    "sha256:e3da0e91ef758728bdf6e58957c09fe044d97d1fa2a21c9c19e3bdf5109bf45b",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  // This is an authored three-Unit Effect Program, not an Effect-free copy.
  // The Model contract here consumes the generated name; public media tests
  // additionally require the actual generated ContentRef and physical bytes.
  let document =
    #|{"version":"actql/0.1","id":"original-content-model-effect","stages":[{"id":"capture","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id >= 0"},{"select":["id","amount"],"as":"captured"}],"results":{"rows":{"from":"captured","fields":["id","amount"]}}},{"id":"classify","inputs":{"rows":{"result":{"stage":"capture","result":"rows"}}},"steps":[{"assert_rows":{"unique_by":["id"]}},{"serialize":{"format":"jsonl","fields":["id","amount"],"order_by":[{"id":"asc"}],"name":"out.jsonl","bounds":{"max_rows":2,"max_bytes":128}},"as":"attachment"},{"assert_rows":{"unique_by":["name"]}},{"infer":{"contract":"model-task:risk-score.v1","key":"name","input":{"text":{"field":"name"}}},"as":"classified"}],"results":{"rows":{"from":"classified","fields":["name","outcome","value"]}}},{"id":"apply","inputs":{"classified":{"result":{"stage":"classify","result":"rows"}}},"steps":[{"derive":{"value":{"literal":1}},"as":"selected"}],"results":{"out":{"from":"selected","fields":["value"]}},"effects":{"save":{"create":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"out"}}}}}],"results":{"published":{"from":{"stage":"apply","result":"out"}}}}
  let document = if keep {
    document
    .replace(
      old="\"as\":\"classified\"}],\"results\"",
      new="\"as\":\"classified\"},{\"join\":{\"with\":\"attachment\",\"kind\":\"inner\",\"cardinality\":\"one_to_one\",\"on\":\"name\",\"select\":{\"name\":\"left.name\",\"outcome\":\"left.outcome\",\"value\":\"left.value\",\"content\":\"right.content\"}},\"as\":\"kept\"}],\"results\"",
    )
    .replace(
      old="\"from\":\"classified\",\"fields\":[\"name\",\"outcome\",\"value\"]",
      new="\"from\":\"kept\",\"fields\":[\"name\",\"outcome\",\"value\",\"content\"]",
    )
  } else {
    document
  }
  match
    prepare_client_effect_computation(
      document.replace(
        old="\"steps\":[{\"derive\":{\"value\":{\"literal\":1}}",
        new="\"steps\":[{\"select\":[\"name\"]},{\"derive\":{\"value\":{\"literal\":1}}",
      ),
      Json,
      client_composed_effect_test_environment(base),
      None,
      [],
      { ..limits, program: client_standard_program_preparation_limits(), },
    ) {
    Ok(value) => value
    Err(Candidate(Computation(Source(issue)))) =>
      match issue {
        Requests(_) => fail("Fixture Source requests")
        Checks(_) => fail("Fixture Source checks")
        Identity(_) => fail("Fixture Source identity")
        Declarations(_) => fail("Fixture Source declarations")
        Registration(_) => fail("Fixture Source registration")
        SourceView(Program(Program(Pipeline(stage, issue)))) =>
          fail(
            "Fixture pipeline stage " +
            stage.to_string() +
            ": " +
            @debug.to_string(issue.kind),
          )
        SourceView(Program(Program(_))) =>
          fail("Fixture Source view local Program")
        SourceView(Program(_)) => fail("Fixture Source view Program")
        SourceView(Context(_)) => fail("Fixture Source view context")
        SourceView(_) => fail("Fixture Source view binding")
        _ => fail("Fixture Source audit budget")
      }
    Err(Candidate(Computation(issue))) => raise issue
    Err(_) => fail("Original serialized Model Effect preparation failed")
  }
}

///|
test "read-only restriction sees the complete Source Model and Effect preparation before any execution" {
  let owner = client_effect_serialized_infer_fixture()
  assert_true(prepared_client_effect_infer_occurrence(owner) is Some(_))
  assert_true(
    @strategy.graph_captured_prefix(
      @strategy.checked_effect_computation_graph(
        prepared_client_effect_computation_graph(owner),
      ),
    ) >
    0,
  )
  let intent = prepare_client_submitted_intent(
    "{\"kind\":\"program\",\"input\":{},\"parameters\":null,\"readOnly\":true}",
    4096, 128, 16,
  ).unwrap()
  // The original static candidate owns all three stages. No Source reader,
  // Model port, Preview or dispatch is acquired to enforce this choice.
  assert_false(client_submitted_intent_effect_compatible(intent, owner))
}

///|
test "original Effect Infer KEEP retains the authentic Content producer edge" {
  let owner = client_effect_serialized_infer_fixture(keep=true)
  let occurrence = prepared_client_effect_infer_occurrence(owner).unwrap()
  let execution = client_infer_graph_test_execution(
    occurrence.owner,
    occurrence=Some(occurrence),
  )
  let component = issue_installed_client_composed_infer_plan_graph(
    occurrence,
    execution,
    run_materials_limits().sequence,
    1000000,
    100000,
    100,
  ).unwrap()
  let graph = parse_plan_identity_value(
    component.graph.wire,
    1000000,
    100000,
    100,
  ).unwrap()
  guard @canonical.object_field(graph, "data_edges")
    is Some(@canonical.Array(edges)) else {
    fail("Missing Content/Model KEEP edges")
  }
  let mut kept = 0
  for edge in @canonical.array_values(edges) {
    let from = @canonical.object_field(edge, "from").unwrap()
    let to = @canonical.object_field(edge, "to").unwrap()
    if @canonical.object_field(to, "node_id")
      is Some(@canonical.String("task_1_after_infer_4")) {
      kept += 1
      if @canonical.object_field(to, "port")
        is Some(@canonical.String("input_1")) {
        assert_true(
          @canonical.object_field(from, "node_id")
          is Some(@canonical.String("task_1_serialize_1")),
        )
      }
    }
  }
  assert_eq(kept, 2)
  let compiled = issue_prepared_client_effect_compilation(
    owner,
    run_materials_manifests(),
    run_materials_limits().sequence,
    1000,
    10000,
    1000000,
    100000,
    100,
    infer=Some(component),
  ).unwrap()
  assert_true(
    physical_equal(
      compiled.compiled.serialization.unwrap(),
      component.serialization.unwrap(),
    ),
  )
}

///|
test "original Effect compilation retains Content and Model components and their input edge" {
  let owner = client_effect_serialized_infer_fixture()
  let occurrence = prepared_client_effect_infer_occurrence(owner).unwrap()
  assert_eq(client_infer_occurrence_coordinates(occurrence), (1, 1, 3))
  let execution = client_infer_graph_test_execution(
    occurrence.owner,
    occurrence=Some(occurrence),
  )
  let component = issue_installed_client_composed_infer_plan_graph(
    occurrence,
    execution,
    run_materials_limits().sequence,
    1000000,
    100000,
    100,
  ).unwrap()
  let content = component.serialization.unwrap()
  assert_eq((content.task, content.step), (1, 1))
  assert_true(physical_equal(content.owner, occurrence.owner))
  assert_true(
    physical_equal(
      @lower.serialization_owner(content.barrier),
      occurrence.preparation,
    ),
  )
  assert_false(component.input.node_id == content.input.node_id)
  assert_true(component.graph.transformations.is_empty())
  let compilation = issue_prepared_client_effect_compilation(
    owner,
    run_materials_manifests(),
    run_materials_limits().sequence,
    1000,
    10000,
    1000000,
    100000,
    100,
    infer=Some(component),
  ).unwrap()
  assert_true(physical_equal(compilation.owner, owner))
  assert_true(physical_equal(compilation.compiled.infer.unwrap(), component))
  assert_true(
    physical_equal(compilation.compiled.serialization.unwrap(), content),
  )
  let task_graph = issue_client_task_plan_graph(
    occurrence.owner,
    run_materials_limits().sequence,
    1000000,
    100000,
    100,
    true,
    [("save", 2)],
    infer=Some(component),
  ).unwrap()
  let graph = parse_plan_identity_value(task_graph.wire, 1000000, 100000, 100).unwrap()
  guard @canonical.object_field(graph, "data_edges")
    is Some(@canonical.Array(edges)) else {
    fail("Combined checked graph edges")
  }
  let mut external = 0
  for edge in @canonical.array_values(edges) {
    let from = @canonical.object_field(edge, "from").unwrap()
    let to = @canonical.object_field(edge, "to").unwrap()
    if @canonical.object_field(from, "node_id")
      is Some(@canonical.String("task_0")) {
      external += 1
      assert_true(
        @canonical.object_field(to, "node_id") is Some(@canonical.String(id)) &&
        id == content.input.node_id,
      )
      assert_true(
        @canonical.object_field(to, "port") is Some(@canonical.String("rows")),
      )
    }
  }
  assert_eq(external, 1)
  let plan = parse_plan_identity_value(
    client_task_executable_plan_wire(compilation.compiled.plan),
    1000000,
    100000,
    100,
  ).unwrap()
  let expected_profiles = "[{\"contract_cid\":\"" +
    @environment.compiler_inference_barrier_contract_cid() +
    "\",\"profile_id\":\"actql-infer/0.1\"},{\"contract_cid\":\"" +
    @environment.compiler_content_barrier_contract_cid() +
    "\",\"profile_id\":\"actql-content/0.1\"}]"
  assert_eq(
    @canonical.stringify_value(
      @canonical.object_field(plan, "required_profiles").unwrap(),
      10000,
      1000,
      20,
    ),
    expected_profiles,
  )
  let allowed = issue_client_effect_allowed_run(
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let model_run = client_effect_allowed_infer_run(allowed).unwrap()
  let content_run = client_effect_allowed_serialization_run(allowed).unwrap()
  assert_true(physical_equal(model_run.admission, content_run.admission))
  assert_true(physical_equal(model_run.owner, content_run.owner))
  assert_true(
    physical_equal(
      client_compiled_run_serialization(content_run).unwrap(),
      content,
    ),
  )
}

///|
test "mixed Effect components reject equal Programs with foreign checked owners" {
  let owner = client_effect_serialized_infer_fixture()
  let foreign = client_effect_serialized_infer_fixture()
  let occurrence = prepared_client_effect_infer_occurrence(owner).unwrap()
  let component = issue_installed_client_composed_infer_plan_graph(
    occurrence,
    client_infer_graph_test_execution(
      occurrence.owner,
      occurrence=Some(occurrence),
    ),
    run_materials_limits().sequence,
    1000000,
    100000,
    100,
  ).unwrap()
  assert_true(
    issue_prepared_client_effect_compilation(
      foreign,
      run_materials_manifests(),
      run_materials_limits().sequence,
      1000,
      10000,
      1000000,
      100000,
      100,
      infer=Some(component),
    )
    is Err(ForeignInferOwner),
  )
  let content = issue_client_serialization_effect_plan(
      client_effect_program_view(foreign),
      run_materials_limits().sequence,
      1000000,
      100000,
      100,
    )
    .unwrap()
    .unwrap()
  assert_true(
    issue_prepared_client_serialized_infer_plan_graph(
      occurrence,
      content,
      component.execution,
      run_materials_limits().sequence,
      1000000,
      100000,
      100,
      include_results=false,
    )
    is Err(UnsupportedProgram),
  )
}
