///|
#external
priv type TaskCompletionFixtureRequire

///|
#module("node:module")
extern "js" fn task_completion_fixture_require(
  url : String,
) -> TaskCompletionFixtureRequire = "createRequire"

///|
extern "js" fn task_completion_fixture_url() -> String =
  #|() => import.meta.url

///|
extern "js" fn task_completion_fixture_original(
  load : TaskCompletionFixtureRequire,
  graph : @graph.CheckedDAG,
  capacity : Int64,
  current : () -> Unit,
) -> @resources.OriginalNodeManagedRunReference =
  #|(load, graph, capacity, current) =>
  #|  load('../../../../../adapters/host-node/ordinary-node-resource-runtime.cjs')
  #|    .retainOrdinaryManagedRun(graph, {
  #|      planningWork: 10000, attempts: 4, holdings: 4,
  #|      transferBytes: 0n, retainedBytes: capacity, executionBytes: capacity,
  #|    }, current, () => false)

///|
extern "js" fn task_completion_fixture_contract(
  load : TaskCompletionFixtureRequire,
  values : Bool,
) -> String =
  #|(load, values) => {
  #|  const contract = load('../../../../../spec/contracts/actql-aoa.json');
  #|  return JSON.stringify(values ? contract.execution_contracts['REL.values'] :
  #|    load('../../../../../' + contract.pipeline_registry_file));
  #|}

///|
let task_completion_fixture_program : String =
  #|{"version":"actql/0.1","id":"boundary.single-operation","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"n":{"type":"number","nullable":false}},"rows":[{"n":1}]},"as":"data"}],"results":{"rows":{"from":"data","fields":["n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}

///|
fn task_completion_fixture_graph(
  program? : String = task_completion_fixture_program,
  stages? : Int = 1,
) -> @graph.CheckedDAG raise {
  let wire =
    #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[],"contract_registry":[],"evidence_bundle_cid":"sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
  let admitted = @environment.read(
    @utf8.encode(wire),
    "sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904",
    { max_bytes: 4096, max_nodes: 4096, max_depth: 32, max_members: 32, },
  ).unwrap()
  let environment = @checked.checking_environment(
    admitted,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  )
  let outcome = @checked.check_document(
    program,
    environment,
    None,
    {
      input: {
        source: { max_input_bytes: 4096, max_nodes: 4096, max_depth: 32, },
        tree: {
          max_nodes: 4096,
          max_depth: 32,
          max_string_bytes: 4096,
          max_total_string_bytes: 4096,
        },
        max_stages: stages,
      },
      compilation: {
        work: 100000 * stages,
        artifacts: { bytes: 65536 * stages, nodes: 8192 * stages, depth: 32, },
        structure: {
          stages,
          steps: 4 * stages,
          results: 4 * stages,
          parameters: 4,
          bindings: 128 * stages,
          slots: 128 * stages,
          references: 128 * stages,
          requirements: 128 * stages,
          tokens: 128 * stages,
        },
        traversal: {
          nodes: 8192,
          depth: 32,
          text_bytes: 65536,
          string_bytes: 8192,
          name_bytes: 8192,
          pointer_units: 8192,
          comparison_pairs: 8192 * stages,
        },
        values: { nodes: 8192, depth: 32, text_bytes: 65536, },
        policy: { bytes: 65536, nodes: 8192, depth: 32, },
        patterns: { bytes: 65536, nodes: 8192, depth: 32, },
      },
    },
    format=Json,
  )
  let checked = match outcome {
    @checked.Checked(value) => value
    @checked.Rejected(issue) =>
      fail(
        "Checked task fixture: " +
        @debug.to_string(@checked.diagnostic_category(issue)) +
        " " +
        @checked.diagnostic_location(issue)
        .map(@checked.diagnostic_location_source_path)
        .unwrap_or(""),
      )
    @checked.NeedsInputs(_) =>
      fail("Checked task fixture needs an original input")
  }
  let owners = Array::makei(stages, stage => {
    let lowered = @lower.prepare(
      @checked.unit_pipeline(checked, stage).unwrap(),
      {
        max_nodes: 1000,
        max_references: 1000,
        max_work: 10000,
        max_identifier_bytes: 4096,
      },
    ).unwrap()
    @lower.bind_parameters(lowered, None, max_parameters=4, max_name_bytes=4096).unwrap()
  })
  prepare_checked_dag(checked, owners, stages, 10000, source_free_root=true).unwrap()
}

///|
fn task_completion_fixture_output(
  load : TaskCompletionFixtureRequire,
  graph : @graph.CheckedDAG,
) -> @execution.CompletedOutput raise {
  let completed = task_completion_fixture_sequence(load, graph, 0, [], [
    @pipeline.Step(0),
  ])
  @execution.completed_output(completed, @pipeline.Step(0)).unwrap()
}

///|
fn task_completion_fixture_sequence(
  load : TaskCompletionFixtureRequire,
  graph : @graph.CheckedDAG,
  task : Int,
  inputs : Array[@execution.ProducerRead],
  targets : Array[@pipeline.Target],
) -> @execution.CompletedSequence raise {
  let contract = fn(values) raise {
    let original = @source.parse_json_bytes_preserving(
      @utf8.encode(task_completion_fixture_contract(load, values)),
      { max_input_bytes: 1000000, max_nodes: 100000, max_depth: 100, },
    ).unwrap()
    @identity.from_source(original, 100000, 100, 1000000, data_keys=true)
  }
  let contracts = @execution.admit_relation_registry(
    contract(false),
    contract(true),
    { max_body_bytes: 1000000, max_body_nodes: 100000, max_body_depth: 100, },
  ).unwrap()
  let owner = graph_task_owner(graph, task).unwrap()
  let prepared = @lower.prepare_sequence(owner, {
    max_steps: 4,
    max_rows: 10,
    max_cells: 100,
    max_bindings: 16,
    max_name_bytes: 4096,
    expressions: {
      max_nodes: 1000,
      max_work: 10000,
      max_depth: 32,
      max_literal_nodes: 1000,
      max_literal_text_bytes: 4096,
    },
  }).unwrap()
  let prepared_owner = @lower.bound_preparation(owner)
  let retained_ids = targets.map(target => {
    match target {
      @pipeline.Input(index) => @lower.input_id(prepared_owner, index).unwrap()
      @pipeline.Step(index) =>
        @lower.node_id(@lower.node_at(prepared_owner, index).unwrap())
    }
  })
  let sequence = match
    @execution.prepare_generated_sequence(
      contracts,
      prepared,
      [],
      retained_ids,
      10000,
      10000,
    ) {
    Ok(value) => value
    Err(MissingFragmentContext(step)) =>
      fail("Fixture sequence requires a Fragment at step " + step.to_string())
    Err(Wiring(_)) => fail("Fixture sequence refused its retained wiring")
    Err(_) => fail("Fixture sequence preparation refused")
  }
  let limits : @execution.ValueLimits = {
    max_nodes: 10000,
    max_text_bytes: 10000,
    max_depth: 100,
    max_work: 100000,
  }
  @execution.execute_fixed_producer_inputs(sequence, inputs, {
    rows: {
      max_rows: 10,
      metadata_entries: 10000,
      retained_entries: 10000,
      operation_entries: 10000,
      input_values: limits,
      output_values: limits,
    },
    max_work: 100000,
    max_frames: 100,
  }).unwrap()
}

///|
test "Debug task commit preserves the first identical settlement reentered by the original Ledger current callback" {
  let graph = task_completion_fixture_graph()
  let load = task_completion_fixture_require(task_completion_fixture_url())
  let visit : Ref[(() -> Unit)?] = Ref(None)
  // The fixture funds the new overlapping codec owners. The Sample controls
  // below consume the remaining space to exercise the actual exact limit.
  let fixture_capacity = 262144L
  let original = task_completion_fixture_original(
    load,
    graph,
    fixture_capacity,
    () => {
      if visit.val is Some(callback) {
        visit.val = None
        callback()
      }
    },
  )
  let admission = @resources.prepare_node_managed_run_admission(original, graph).unwrap()
  let ledger = @resources.start_node_managed_run_admission(admission).unwrap()
  let run = open_source_free_dag(graph, ledger).unwrap()
  let hooks = prepare_captured_task_boundary_hooks(
    run,
    graph,
    captured_dag_strategy_revision(run),
  ).unwrap()
  let current = @authorization.admit_account_configuration({
    account_id: "local",
    entries: [
      {
        entry_id: "debug",
        outcome: Allow,
        scope: {
          principal: All,
          connection: All,
          resource: All,
          operation: AnyOf(["pause", "resume"]),
        },
        exclusions: [],
      },
    ],
    bootstrap: None,
  }).unwrap()
  let subject = "sha256:" + "a".repeat(64)
  let context = "sha256:" + "b".repeat(64)
  let pause : @authorization.AccessTuple = {
    principal: "user",
    connection: "local",
    resource: "runs",
    operation: "pause",
  }
  let permit = fn(tuple) {
    @authorization.bind_dispatch_authorization(
      current,
      tuple,
      Activation,
      subject,
      context,
    ).unwrap()
  }
  prepare_captured_task_control(
    run,
    hooks,
    permit(pause),
    current,
    pause,
    subject,
    context,
  ).unwrap()
  let other = open_source_free_dag(graph, ledger).unwrap()
  assert_eq(
    acknowledge_captured_relation_sample_start(
      other, hooks, subject, context, 2,
    ),
    Err(ForeignOwner),
  )
  assert_eq(
    acknowledge_captured_relation_sample_start(run, hooks, context, subject, 2),
    Err(AuthorizationMismatch),
  )
  assert_eq(
    acknowledge_captured_relation_sample_start(run, hooks, subject, context, 0),
    Err(StaleRevision),
  )
  acknowledge_captured_relation_sample_start(run, hooks, subject, context, 2).unwrap()
  assert_eq(
    acknowledge_captured_relation_sample_start(run, hooks, subject, context, 3),
    Err(AlreadyStarted),
  )
  let resume_tuple = { ..pause, operation: "resume", }
  command_captured_task_control(
    run,
    hooks,
    0,
    ResumeStep,
    permit(resume_tuple),
    current,
    resume_tuple,
    subject,
    context,
  ).unwrap()
  let control = hooks.control.unwrap()
  assert_eq(control.remaining, 1)
  assert_eq(captured_task_control_state(run, hooks), Ok((1, Stepping(0))))
  let output = task_completion_fixture_output(load, graph)
  assert_eq(@execution.completed_row_count(output), 1)
  // An abandoned reservation consumes its issued serial, never an attempt.
  let abandoned = @resources.reserve_attempt(ledger, 0L, 0L, 0L).unwrap()
  @resources.settle_reservation(ledger, abandoned).unwrap()
  let reservation = @resources.reserve_attempt(ledger, 0L, 64L, 32L).unwrap()
  let holding = @resources.retain_allocation(ledger, reservation, 64L).unwrap()
  @resources.consume_reserved_attempt(ledger, reservation).unwrap()
  @resources.consume_reserved_attempt(ledger, reservation).unwrap()
  assert_eq(
    @resources.completed_output_attempt_sequence(ledger, reservation),
    0,
  )
  let commit = fn() {
    commit_materialized_task_output(
      run,
      0,
      output,
      holding,
      ForeignCandidate,
      reservation,
      64L,
      0L,
    )
  }
  let generation = captured_dag_generation(run)
  let nested = Ref(None)
  // The holding probe is callback-free. Arm last so only settlement observes
  // this callback, and both invocations present the identical notification.
  visit.val = Some(() => {
    let result = commit()
    nested.val = Some((result, @resources.ledger_usage(ledger)))
  })
  let outer = commit()
  let (inner, usage) = nested.val.unwrap()
  assert_true(inner is Ok(_))
  assert_true(visit.val is None)
  assert_true(physical_equal(materialized_task_output(run, 0).unwrap(), output))
  assert_true(captured_task_allocation_matches(run, 0, holding))
  assert_true(@resources.holding_available(ledger, holding))
  assert_false(@resources.reservation_open(reservation))
  assert_eq(@resources.ledger_usage(ledger), usage)
  assert_eq(usage.attempts, 1)
  assert_eq(usage.holdings, 1)
  assert_eq(usage.held_bytes, 64L)
  assert_eq(
    (captured_dag_generation(run), control.remaining),
    (generation + 1, 0),
  )
  assert_true(outer is Err(ForeignCandidate))
  assert_eq(captured_task_control_state(run, hooks), Ok((2, Completed)))
  let boundary = read_captured_task_boundary(run, hooks, Settled)
    .unwrap()
    .unwrap()
  assert_eq(captured_task_boundary_task(boundary), 0)
  assert_eq(captured_task_boundary_generation(boundary), generation + 1)
  let pin = pin_captured_task_output(run, 0, @pipeline.Step(0), 1).unwrap()
  assert_true(
    captured_task_output_pin_matches_committed_relation(run, boundary, pin),
  )
  let schema : @execution.RelationSchemaIdentityLimits = {
    max_fields: 1,
    max_bytes: 64,
    max_nodes: 8,
    max_depth: 4,
  }
  let capacity = captured_sample_prefix_bytes(schema, 512, 32, 8).unwrap()
  let before = @resources.ledger_usage(ledger)
  let interrupted_pin = pin_captured_task_output(run, 0, @pipeline.Step(0), 2).unwrap()
  let released = Ref(false)
  visit.val = Some(() => {
    released.val = release_captured_output_pin(interrupted_pin)
  })
  assert_true(
    capture_captured_relation_sample_prefix(
      run, boundary, interrupted_pin, 1, schema, 512, 32, 8,
    )
    is Err(StaleOriginal),
  )
  assert_true(released.val)
  let after_interruption = @resources.ledger_usage(ledger)
  assert_eq(after_interruption.live_reservations, before.live_reservations)
  assert_eq(
    after_interruption.reserved_retention_bytes,
    before.reserved_retention_bytes,
  )
  assert_eq(
    after_interruption.reserved_execution_bytes,
    before.reserved_execution_bytes,
  )
  let fill = fixture_capacity -
    before.reserved_retention_bytes -
    before.held_bytes -
    capacity
  assert_true(fill >= 0L)
  let pressure = @resources.reserve_capacity(ledger, fill + 1L, 0L).unwrap()
  let full = @resources.ledger_usage(ledger)
  assert_true(
    capture_captured_relation_sample_prefix(
      run, boundary, pin, 1, schema, 512, 32, 8,
    )
    is Err(Boundary(Resource(RetentionLimit))),
  )
  assert_eq(@resources.ledger_usage(ledger), full)
  @resources.settle_capacity(ledger, pressure).unwrap()
  let fit = @resources.reserve_capacity(ledger, fill, 0L).unwrap()
  let exact = @resources.ledger_usage(ledger)
  let sample = capture_captured_relation_sample_prefix(
    run, boundary, pin, 1, schema, 512, 32, 8,
  ).unwrap()
  let charged = @resources.ledger_usage(ledger)
  assert_eq(
    charged.reserved_retention_bytes - exact.reserved_retention_bytes,
    capacity,
  )
  assert_eq(
    charged.reserved_execution_bytes - exact.reserved_execution_bytes,
    capacity,
  )
  fn inspect_sample() raise {
    let (document, count, total, committed, attempt, start) = captured_relation_sample_prefix_current(
      run, sample, pin,
    ).unwrap()
    assert_true(@encode.document_bytes(document) <= 512)
    assert_eq((count, total, committed), (1, 1, generation + 1))
    assert_eq((attempt, start), (1L, 2))
  }
  inspect_sample()
  @resources.settle_capacity(ledger, fit).unwrap()
  // A separate Run over the same compiler graph cannot reuse a real pin or
  // its committed generation, even while the original loan remains live.
  assert_false(
    captured_task_output_pin_matches_committed_relation(other, boundary, pin),
  )
  stop_captured_dag(other)
  return_captured_task_boundary(boundary).unwrap()
  // The original commit remains current and the independent Sample lease
  // still owns the encoded payload after the temporary observation returns.
  inspect_sample()
  return_captured_relation_sample_prefix(sample).unwrap()
  assert_true(captured_relation_sample_prefix_current(run, sample, pin) is None)
  let current_boundary = read_captured_task_boundary(run, hooks, Settled)
    .unwrap()
    .unwrap()
  // One Work unit short with the exact same schema, output pin and byte
  // limits. The committed output must survive, and this path yields no prefix.
  let work = charged.planning_work - exact.planning_work
  assert_true(work > 0)
  let budget = @resources.ledger_limits(ledger).planning_work
  let spent = @resources.ledger_usage(ledger).planning_work
  @resources.charge_planning(ledger, budget - spent - work + 1).unwrap()
  let before_work_refusal = @resources.ledger_usage(ledger)
  assert_true(
    capture_captured_relation_sample_prefix(
      run, current_boundary, pin, 1, schema, 512, 32, 8,
    )
    is Err(Work(@resources.PlanningLimit)),
  )
  let after_work_refusal = @resources.ledger_usage(ledger)
  assert_eq(
    after_work_refusal.live_reservations,
    before_work_refusal.live_reservations,
  )
  assert_eq(
    after_work_refusal.reserved_retention_bytes,
    before_work_refusal.reserved_retention_bytes,
  )
  assert_eq(
    after_work_refusal.reserved_execution_bytes,
    before_work_refusal.reserved_execution_bytes,
  )
  assert_true(
    captured_task_output_pin_matches_committed_relation(
      run, current_boundary, pin,
    ),
  )
  assert_false(
    captured_task_output_pin_matches_committed_relation(run, boundary, pin),
  )
  assert_true(release_captured_output_pin(pin))
  assert_false(
    captured_task_output_pin_matches_committed_relation(
      run, current_boundary, pin,
    ),
  )
  return_captured_task_boundary(current_boundary).unwrap()
  close_captured_task_output(run, 0)
  stop_captured_dag(run)
  refresh_captured_retention(run)
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
  assert_false(@resources.holding_available(ledger, holding))
  @resources.cleanup_node_managed_run_admission(admission).unwrap()
}

///|
test "paused dependency rejects the different raw Input of its computed producer" {
  let producer_stages =
    #|{"version":"actql/0.1","id":"boundary.original-dependency","stages":[{"id":"seed","inputs":{},"steps":[{"values":{"schema":{"n":{"type":"number","nullable":false}},"rows":[{"n":0},{"n":2}]},"as":"data"}],"results":{"rows":{"from":"data","fields":["n"]}}},{"id":"mixed","inputs":{"source":{"result":{"stage":"seed","result":"rows"}}},"steps":[{"from":"source","take":{"count":1,"offset":1},"as":"subset"}],"results":{"raw":{"from":"source","fields":["n"]},"computed":{"from":"subset","fields":["n"]}}}
  let raw_stage =
    #|,{"id":"raw_reader","inputs":{"source":{"result":{"stage":"mixed","result":"raw"}}},"steps":[{"from":"source","select":["n"],"as":"out"}],"results":{"rows":{"from":"out","fields":["n"]}}}
  let computed_stage =
    #|,{"id":"computed_reader","inputs":{"source":{"result":{"stage":"mixed","result":"computed"}}},"steps":[{"from":"source","select":["n"],"as":"out"}],"results":{"rows":{"from":"out","fields":["n"]}}}
  let computed_result =
    #|],"results":{"computed":{"from":{"stage":"computed_reader","result":"rows"}}
  let raw_result =
    #|,"raw":{"from":{"stage":"raw_reader","result":"rows"}}
  let mixed_graph = task_completion_fixture_graph(
    program=producer_stages +
      raw_stage +
      computed_stage +
      computed_result +
      raw_result +
      "}}",
    stages=4,
  )
  assert_eq(graph_data_count(mixed_graph), 3)
  let raw_edge = graph_data_at(mixed_graph, 1).unwrap()
  let good_edge = graph_data_at(mixed_graph, 2).unwrap()
  assert_eq(
    (raw_edge.producer, raw_edge.consumer, raw_edge.input, raw_edge.target),
    (1, 2, 0, @pipeline.Input(0)),
  )
  assert_eq(
    (good_edge.producer, good_edge.consumer, good_edge.input, good_edge.target),
    (1, 3, 0, @pipeline.Step(0)),
  )
  let load = task_completion_fixture_require(task_completion_fixture_url())
  let mixed_seed = task_completion_fixture_output(load, mixed_graph)
  let binding = @execution.bind_completed_input(
    graph_task_owner(mixed_graph, 1).unwrap(),
    0,
    graph_task_owner(mixed_graph, 0).unwrap(),
    mixed_seed,
  ).unwrap()
  let raw_producer = @execution.prepare_producer_read(
    graph_task_owner(mixed_graph, 1).unwrap(),
    binding,
    10000,
    4096,
  ).unwrap()
  let mixed = task_completion_fixture_sequence(
    load,
    mixed_graph,
    1,
    [raw_producer],
    [@pipeline.Input(0), @pipeline.Step(0)],
  )
  let raw = @execution.completed_output(mixed, @pipeline.Input(0)).unwrap()
  let computed = @execution.completed_output(mixed, @pipeline.Step(0)).unwrap()
  assert_eq(@execution.completed_column_name(raw, 0), Some("n"))
  assert_eq(@execution.completed_column_name(computed, 0), Some("n"))
  assert_eq(@execution.completed_row_count(raw), 2)
  assert_eq(@execution.completed_row_count(computed), 1)
  assert_true(@execution.completed_cell(raw, 0, 0) is Some(Number(0.0)))
  assert_true(@execution.completed_cell(computed, 0, 0) is Some(Number(2.0)))
  assert_false(@execution.completed_output_same_occurrence(raw, computed))
  assert_true(
    paused_dependency_target(mixed_graph, raw_edge)
    is Err(DependencyUnavailable(UnsupportedGraph)),
  )
  assert_eq(
    paused_dependency_target(mixed_graph, good_edge).unwrap().target,
    good_edge.target,
  )
  // A separately checked graph has two independent producers for Join and
  // another unfinished consumer of the earlier output. Both sources have the
  // same type and value; their own commits still have different coordinates.
  let joined =
    #|{"version":"actql/0.1","id":"boundary.join-dependencies","stages":[{"id":"first","inputs":{},"steps":[{"values":{"schema":{"n":{"type":"number","nullable":false}},"rows":[{"n":2}]},"as":"out"}],"results":{"rows":{"from":"out","fields":["n"]}}},{"id":"second","inputs":{},"steps":[{"values":{"schema":{"n":{"type":"number","nullable":false}},"rows":[{"n":2}]},"as":"out"}],"results":{"rows":{"from":"out","fields":["n"]}}},{"id":"joined","inputs":{"a":{"result":{"stage":"first","result":"rows"}},"b":{"result":{"stage":"second","result":"rows"}}},"steps":[{"from":"a","join":{"kind":"inner","with":"b","on":[{"left":"n","right":"n"}],"select":{"n":"left.n"},"max_output_rows":1},"as":"out"}],"results":{"rows":{"from":"out","fields":["n"]}}},{"id":"other","inputs":{"a":{"result":{"stage":"first","result":"rows"}}},"steps":[{"from":"a","select":["n"],"as":"out"}],"results":{"rows":{"from":"out","fields":["n"]}}}],"results":{"joined":{"from":{"stage":"joined","result":"rows"}},"other":{"from":{"stage":"other","result":"rows"}}}}
  let graph = task_completion_fixture_graph(program=joined, stages=4)
  let original = task_completion_fixture_original(load, graph, 262144L, () => ())
  let admission = @resources.prepare_node_managed_run_admission(original, graph).unwrap()
  let ledger = @resources.start_node_managed_run_admission(admission).unwrap()
  let run = open_source_free_dag(graph, ledger).unwrap()
  let hooks = prepare_captured_task_boundary_hooks(
    run,
    graph,
    captured_dag_strategy_revision(run),
  ).unwrap()
  let account = @authorization.admit_account_configuration({
    account_id: "local",
    entries: [
      {
        entry_id: "debug",
        outcome: Allow,
        scope: {
          principal: All,
          connection: All,
          resource: All,
          operation: AnyOf(["pause", "resume"]),
        },
        exclusions: [],
      },
    ],
    bootstrap: None,
  }).unwrap()
  let subject = "sha256:" + "c".repeat(64)
  let context = "sha256:" + "d".repeat(64)
  let pause : @authorization.AccessTuple = {
    principal: "user",
    connection: "local",
    resource: "runs",
    operation: "pause",
  }
  let permit = tuple => {
    @authorization.bind_dispatch_authorization(
      account,
      tuple,
      Activation,
      subject,
      context,
    ).unwrap()
  }
  prepare_captured_task_control(
    run,
    hooks,
    permit(pause),
    account,
    pause,
    subject,
    context,
  ).unwrap()
  let resume_tuple = { ..pause, operation: "resume", }
  let step = revision => {
    command_captured_task_control(
      run,
      hooks,
      revision,
      ResumeStep,
      permit(resume_tuple),
      account,
      resume_tuple,
      subject,
      context,
    ).unwrap()
  }
  let commit = (task, output) => {
    let reservation = @resources.reserve_attempt(ledger, 0L, 64L, 32L).unwrap()
    let holding = @resources.retain_allocation(ledger, reservation, 64L).unwrap()
    @resources.consume_reserved_attempt(ledger, reservation).unwrap()
    commit_materialized_task_output(
      run,
      task,
      output,
      holding,
      ForeignCandidate,
      reservation,
      64L,
      0L,
    ).unwrap()
  }
  acknowledge_captured_relation_sample_start(run, hooks, subject, context, 3).unwrap()
  let unused = @resources.reserve_attempt(ledger, 0L, 0L, 0L).unwrap()
  @resources.consume_reserved_attempt(ledger, unused).unwrap()
  @resources.settle_reservation(ledger, unused).unwrap()
  step(0)
  let first = task_completion_fixture_output(load, graph)
  commit(0, first)
  step(2)
  let second = task_completion_fixture_sequence(load, graph, 1, [], [
    @pipeline.Step(0),
  ])
  commit(1, @execution.completed_output(second, @pipeline.Step(0)).unwrap())
  assert_eq(captured_task_control_state(run, hooks), Ok((4, Paused)))
  let source = read_captured_task_boundary(run, hooks, Settled)
    .unwrap()
    .unwrap()
  let visits = Ref(0)
  let received = Ref(None)
  let shape = Ref(None)
  let saved : Ref[CapturedPausedMaterializedDependency?] = Ref(None)
  let visit = (_, scope) => {
    visits.val += 1
    shape.val = captured_paused_materialized_dependency_shape(scope)
    received.val = Some(
      read_captured_paused_materialized_dependency_cell(scope, 0, 0),
    )
    saved.val = Some(scope)
  }
  let generation = captured_task_boundary_generation(source)
  assert_eq(
    captured_task_control_paused_task(run, hooks),
    Ok((4, 1, Some(2), generation)),
  )
  let first_edge = graph_data_at(graph, 0).unwrap()
  let next_edge = graph_data_at(graph, 1).unwrap()
  let other_edge = graph_data_at(graph, 2).unwrap()
  assert_eq((first_edge.producer, first_edge.consumer), (0, 2))
  assert_eq((next_edge.producer, next_edge.consumer), (1, 2))
  assert_eq((other_edge.producer, other_edge.consumer), (0, 3))
  assert_true(!captured_task_completed(run, other_edge.consumer))
  let (left, left_start, left_generation, left_attempt) = captured_paused_next_sample_dependency(
    run, hooks, 4, generation, 0,
  ).unwrap()
  let (right, right_start, right_generation, right_attempt) = captured_paused_next_sample_dependency(
    run, hooks, 4, generation, 1,
  ).unwrap()
  assert_eq(
    (left.producer, left_start, left_generation, left_attempt),
    (0, 3, generation - 1, 2),
  )
  assert_eq(
    (right.producer, right_start, right_generation, right_attempt),
    (1, 3, generation, 3),
  )
  // The two checked logical input ordinals resolve distinct Stage inputs.
  for index in 0..<2 {
    let (selected, selected_start, producer_generation, producer_attempt) = captured_paused_next_sample_input(
      run, hooks, 4, generation, index, 256,
    ).unwrap()
    assert_eq((selected.producer, selected.consumer), (index, 2))
    assert_eq(
      (selected_start, producer_generation, producer_attempt),
      (3, generation - 1 + index, 2 + index),
    )
  }
  assert_true(
    captured_paused_next_sample_input(run, hooks, 4, generation, 2, 256)
    is Err(InvalidDependency),
  )
  assert_true(
    captured_paused_next_sample_input(run, hooks, 4, generation, 0, 1)
    is Err(InputWorkLimit),
  )
  assert_true(
    captured_paused_next_sample_dependency(run, hooks, 4, generation, 2)
    is Err(InvalidDependency),
  )
  assert_true(
    captured_paused_next_sample_dependency(run, hooks, 4, generation - 1, 0)
    is Err(Boundary(StaleBoundary)),
  )
  assert_true(
    with_captured_paused_materialized_dependency(run, source, 4, 2, 1, visit)
    is Err(InvalidDependency),
  )
  assert_eq(visits.val, 0)
  let before = @resources.ledger_usage(ledger)
  // One full original read fork plus the fixed scoped cell reader.
  let quote = 10L * 16L + 13L * 8L + 19L * 8L + 24L * 16L + 60L * 8L + 32L * 8L
  let blocker = @resources.reserve_capacity(
    ledger,
    @resources.ledger_limits(ledger).retained_bytes -
    before.held_bytes -
    before.reserved_retention_bytes -
    quote +
    1L,
    0L,
  ).unwrap()
  assert_true(
    with_captured_paused_materialized_dependency(run, source, 4, 1, 1, visit)
    is Err(Boundary(Resource(RetentionLimit))),
  )
  @resources.settle_capacity(ledger, blocker).unwrap()
  assert_eq(visits.val, 0)
  assert_true(
    with_captured_paused_materialized_dependency(run, source, 3, 1, 1, visit)
    is Err(Boundary(StaleBoundary)),
  )
  with_captured_paused_materialized_dependency(run, source, 4, 1, 1, visit).unwrap()
  assert_eq(visits.val, 1)
  assert_eq(shape.val, Some((1, 1)))
  assert_true(received.val is Some(Ok(Some(Number(2.0)))))
  assert_eq(
    captured_paused_materialized_dependency_shape(saved.val.unwrap()),
    None,
  )
  assert_true(
    read_captured_paused_materialized_dependency_cell(saved.val.unwrap(), 0, 0)
    is Err(Boundary(StaleBoundary)),
  )
  let after = @resources.ledger_usage(ledger)
  assert_eq(after.reserved_retention_bytes, before.reserved_retention_bytes)
  assert_eq(after.reserved_execution_bytes, before.reserved_execution_bytes)
  assert_eq(after.live_reservations, before.live_reservations)
  assert_eq(after.attempts, before.attempts)
  assert_true(next_captured_task(run) is None)
  return_captured_task_boundary(source).unwrap()
  step(4)
  assert_true(
    captured_paused_next_sample_dependency(run, hooks, 4, generation, 0)
    is Err(Boundary(StaleBoundary)),
  )
  stop_captured_dag(run)
  close_captured_task_output(run, 1)
  close_captured_task_output(run, 0)
  let usage = @resources.ledger_usage(ledger)
  assert_eq(usage.live_reservations, 0)
  assert_eq(usage.held_bytes, 0L)
}
