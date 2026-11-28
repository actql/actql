// Reuse the existing checked Salesforce-update fixture and compilation Owner.
// This fixture creates no allowed Run, publication, capture or Provider call.

///|
fn effect_static_computation_fixture(
  document? : String? = None,
) -> (PreparedClientEffectComputation, ClientEffectCompilation) {
  let (base, environment, limits) = local_update_normalization_fixture()
  let limits = if document is Some(_) {
    let checking = limits.program.checking
    {
      ..limits,
      program: {
        ..limits.program,
        max_tasks: 3,
        checking: {
          input: { ..checking.input, max_stages: 3, },
          compilation: {
            ..checking.compilation,
            structure: { ..checking.compilation.structure, stages: 3, },
          },
        },
      },
    }
  } else {
    limits
  }
  let original = prepare_client_effect_computation(
    document.unwrap_or(base),
    Json,
    environment,
    None,
    [],
    limits,
  ).unwrap()
  let bounds = run_materials_limits()
  let compiled = issue_prepared_client_effect_compilation(
    original,
    run_materials_manifests(),
    bounds.sequence,
    bounds.max_sequence_steps,
    bounds.max_sequence_work,
    bounds.max_evidence_bytes,
    bounds.max_evidence_nodes,
    bounds.max_evidence_depth,
  ).unwrap()
  (original, compiled)
}

///|
fn effect_static_computation_bound(
  original : PreparedClientEffectComputation,
  compiled : ClientEffectCompilation,
) -> PreparedClientEffectRun {
  let allowed = issue_client_effect_allowed_run(
    compiled,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2027-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = issue_client_effect_run_definition(
    allowed, "scope", "stage-work", "2026-11-20T00:00:00.000Z", "2027-01-01T00:00:00.000Z",
  ).unwrap()
  bind_client_effect_compiled_run(original, allowed, definition).unwrap()
}

///|
test "Effect computation static map uses the retained original compiler without a Run" {
  let (original, compiled) = effect_static_computation_fixture()
  assert_true(original.normalization is None)
  assert_true(original.normalization_custody is None)
  let first = client_effect_static_computation_plan_view(
    original, compiled, 65536, 4096, 64,
  ).unwrap()
  let second = client_effect_static_computation_plan_view(
    original, compiled, 65536, 4096, 64,
  ).unwrap()
  assert_eq(first, second)
  assert_true(original.normalization is None)
  assert_true(original.normalization_custody is None)
  let value = @publication.parse_interactive_run_control_shape(
    "plan_view", first, 65536, 4096, 64,
  ).unwrap()
  let definition = prepared_client_effect_identity(original).program_definition_cid
  guard @canonical.object_field(value, "compiled_plan_cid")
    is Some(@canonical.String(actual_plan_cid)) else {
    fail("static computation component lacks compiled Plan identity")
  }
  assert_eq(
    actual_plan_cid,
    @publication.publication_contract_identity(compiled.compiled.compiled_plan),
  )
  let map = @canonical.object_field(value, "logical_map").unwrap()
  guard @canonical.object_field(map, "program_definition_cid")
    is Some(@canonical.String(actual_definition)) else {
    fail("static computation component lacks original Program identity")
  }
  assert_eq(actual_definition, definition)
  let capabilities = @canonical.object_field(value, "capabilities").unwrap()
  assert_true(
    @canonical.object_field(capabilities, "inspect")
    is Some(@canonical.Bool(false)),
  )
  assert_true(
    @canonical.object_field(capabilities, "durable_control")
    is Some(@canonical.Bool(false)),
  )
  assert_true(first.contains("\"operator\":\"values\""))
  assert_true(first.contains("\"provider_io\":0"))
  assert_true(!first.contains("\"preview\""))
  assert_true(!first.contains("\"run_ref\""))
}

///|
test "Effect computation static map refuses an equal document from another prepared Owner" {
  let (original, compiled) = effect_static_computation_fixture()
  let (foreign, _) = effect_static_computation_fixture()
  assert_eq(
    prepared_client_effect_identity(original),
    prepared_client_effect_identity(foreign),
  )
  assert_eq(
    client_effect_static_computation_plan_view(
      foreign, compiled, 65536, 4096, 64,
    ),
    Err(ClientInteractivePlanIssue::ForeignCompilation),
  )
}

///|
test "Effect computation static map preserves finite read limits" {
  let (original, compiled) = effect_static_computation_fixture()
  assert_eq(
    client_effect_static_computation_plan_view(original, compiled, 0, 4096, 64),
    Err(InvalidReadLimits),
  )
  assert_eq(
    client_effect_static_computation_plan_view(
      original, compiled, 65536, 4096, 0,
    ),
    Err(InvalidReadLimits),
  )
  assert_eq(
    client_effect_static_computation_plan_view(
      original, compiled, 65536, -1, 64,
    ),
    Err(InvalidReadLimits),
  )
  assert_true(
    client_effect_static_computation_plan_view(original, compiled, 65536, 1, 64)
    is Err(_),
  )
  assert_true(
    client_effect_static_computation_plan_view(original, compiled, 64, 4096, 64)
    is Err(_),
  )
  assert_true(original.normalization is None)
}

///|
test "Effect preflight visits each original Stage once with a forward lookup" {
  let (base, _, _) = local_update_normalization_fixture()
  let values =
    #|{"values":{"schema":{"id":{"type":"string","nullable":false}},"rows":[{"id":"extra"}]},"as":"selected"}
  let stage = (id : String) => {
    "{\"id\":\"" +
    id +
    "\",\"inputs\":{},\"steps\":[" +
    values +
    "],\"results\":{\"out\":{\"from\":\"selected\",\"fields\":[\"id\"]}}}"
  }
  let exports =
    #|"results":{"left":{"from":{"stage":"left","result":"out"}},"right":{"from":{"stage":"right","result":"out"}},"published":
  let document = base
    .replace(
      old="\"stages\":[",
      new="\"stages\":[" + stage("left") + "," + stage("right") + ",",
    )
    .replace(old="\"results\":{\"published\":", new=exports)
  let (original, compiled) = effect_static_computation_fixture(
    document=Some(document),
  )
  let bound = effect_static_computation_bound(original, compiled)
  let graph = @strategy.checked_effect_run_graph(
    prepared_client_effect_run_graph(bound),
  )
  let computation_wire = Ref(None)
  let (explanation, _) = capture_client_static_effect_explanation_original(
    original,
    compiled,
    65536,
    4096,
    64,
    computation_wire=Some(computation_wire),
  ).unwrap()
  let map = explanation.map
  let cid = @publication.run_evidence_value_identity(map)
  // Inspect the separate emitted wire only as a test oracle. The preflight
  // below receives the issuing Common Map directly, with no readmission.
  let plan_value = parse_plan_identity_value(
    computation_wire.val.unwrap(),
    65536,
    4096,
    64,
  ).unwrap()
  let emitted_map = @canonical.object_field(plan_value, "logical_map").unwrap()
  assert_eq(explanation_original_text(emitted_map, "self_cid"), cid)
  let original_map = @publication.interactive_logical_map_original(map).unwrap()
  assert_eq(
    @canonical.stringify_value(original_map, 65536, 4096, 64),
    @canonical.stringify_value(emitted_map, 65536, 4096, 64),
  )
  guard @canonical.object_field(original_map, "steps")
    is Some(@canonical.Array(steps)) else {
    fail("the checked Map has original Steps")
  }
  assert_eq(@strategy.graph_task_count(graph), 3)
  assert_eq(@strategy.graph_data_count(graph), 0)
  assert_eq(@strategy.graph_control_count(graph), 2)
  let work = 39
  let coordinates = [(0, 0), (1, 0), (2, 0)]
  assert_eq(@canonical.array_count(steps), coordinates.length())
  let visited : Array[(Int, Int)] = []
  let find_task = (stage, ordinal) => {
    visited.push((stage, ordinal))
    @strategy.checked_task_control_operation_task(graph, stage, ordinal)
  }
  let entry_id = explanation_original_text(
    @canonical.array_at(steps, 0).unwrap(),
    "step_id",
  )
  let expected = Some(entry_id)
  assert_eq(scan_effect_compute_entry(steps, 3, find_task).unwrap(), expected)
  assert_eq(visited, coordinates)
  let ledger = @resources.create_ledger({
    planning_work: work,
    attempts: 1,
    holdings: 1,
    transfer_bytes: 0L,
    retained_bytes: 0L,
    execution_bytes: 0L,
  }).unwrap()
  assert_true(
    preflight_client_effect_compute_steps(bound, ledger, map, cid, work - 1)
    is Err(Resource(PlanningLimit)),
  )
  assert_eq(@resources.ledger_usage(ledger).planning_work, 0)
  assert_eq(
    preflight_client_effect_compute_steps(bound, ledger, map, cid, work).unwrap(),
    expected,
  )
  assert_eq(@resources.ledger_usage(ledger).planning_work, work)
  assert_eq(@resources.ledger_usage(ledger).attempts, 0)
  let first_step = @canonical.stringify_value(
    @canonical.array_at(steps, 0).unwrap(),
    8192,
    512,
    64,
  )
  guard parse_plan_identity_value(
      "[" + first_step + "," + first_step + "]",
      16384,
      1024,
      64,
    ).unwrap()
    is @canonical.Array(duplicate) else {
    fail("duplicate coordinate control must be a canonical array")
  }
  visited.clear()
  assert_true(
    scan_effect_compute_entry(duplicate, 3, find_task) is Err(ForeignOwner),
  )
  assert_eq(visited, [(0, 0)])
}

///|
test "Effect preflight withholds a fused Compute despite exact logical Steps" {
  let (base, _, _) = local_update_normalization_fixture()
  let fused = base.replace(
    old=(
      #|],"results":{"out":{"from":"selected"
    ),
    new=(
      #|,{"from":"selected","take":{"count":1},"as":"picked"}],"results":{"out":{"from":"picked"
    ),
  )
  let (original, compiled) = effect_static_computation_fixture(
    document=Some(fused),
  )
  let bound = effect_static_computation_bound(original, compiled)
  let graph = @strategy.checked_effect_run_graph(
    prepared_client_effect_run_graph(bound),
  )
  let wire = client_effect_static_computation_plan_view(
    original, compiled, 65536, 4096, 64,
  ).unwrap()
  let plan = parse_plan_identity_value(wire, 65536, 4096, 64).unwrap()
  let original_map = @canonical.object_field(plan, "logical_map").unwrap()
  let map = @publication.admit_interactive_run_evidence_value(
    "logical_map", original_map, 65536, 4096, 64,
  ).unwrap()
  guard @canonical.object_field(original_map, "steps")
    is Some(@canonical.Array(steps)) else {
    fail("the authored values and take both have a logical Step")
  }
  assert_eq(@canonical.array_count(steps), 2)
  assert_eq(@strategy.graph_task_count(graph), 1)
  assert_eq(@strategy.graph_stage_operation_task(graph, 0, 0), Some(0))
  assert_eq(@strategy.graph_stage_operation_task(graph, 0, 1), Some(0))
  let work = 25
  let ledger = @resources.create_ledger({
    planning_work: work,
    attempts: 1,
    holdings: 1,
    transfer_bytes: 0L,
    retained_bytes: 0L,
    execution_bytes: 0L,
  }).unwrap()
  assert_eq(
    preflight_client_effect_compute_steps(
      bound,
      ledger,
      map,
      @publication.run_evidence_value_identity(map),
      work,
    ).unwrap(),
    None,
  )
  assert_eq(@resources.ledger_usage(ledger).planning_work, work)
  assert_eq(@resources.ledger_usage(ledger).attempts, 0)
}
