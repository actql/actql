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
fn task_completion_fixture_graph() -> @graph.CheckedDAG {
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
  let program =
    #|{"version":"actql/0.1","id":"boundary.single-operation","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"n":{"type":"number","nullable":false}},"rows":[{"n":1}]},"as":"data"}],"results":{"rows":{"from":"data","fields":["n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
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
        max_stages: 1,
      },
      compilation: {
        work: 100000,
        artifacts: { bytes: 65536, nodes: 8192, depth: 32, },
        structure: {
          stages: 1,
          steps: 4,
          results: 4,
          parameters: 4,
          bindings: 128,
          slots: 128,
          references: 128,
          requirements: 128,
          tokens: 128,
        },
        traversal: {
          nodes: 8192,
          depth: 32,
          text_bytes: 65536,
          string_bytes: 8192,
          name_bytes: 8192,
          pointer_units: 8192,
          comparison_pairs: 8192,
        },
        values: { nodes: 8192, depth: 32, text_bytes: 65536, },
        policy: { bytes: 65536, nodes: 8192, depth: 32, },
        patterns: { bytes: 65536, nodes: 8192, depth: 32, },
      },
    },
    format=Json,
  )
  guard outcome is @checked.Checked(checked) else {
    abort("ExpectedCheckedTaskFixture")
  }
  let lowered = @lower.prepare(@checked.unit_pipeline(checked, 0).unwrap(), {
    max_nodes: 1000,
    max_references: 1000,
    max_work: 10000,
    max_identifier_bytes: 4096,
  }).unwrap()
  let owner = @lower.bind_parameters(
    lowered,
    None,
    max_parameters=4,
    max_name_bytes=4096,
  ).unwrap()
  prepare_checked_dag(checked, [owner], 1, 10000, source_free_root=true).unwrap()
}

///|
fn task_completion_fixture_output(
  load : TaskCompletionFixtureRequire,
  graph : @graph.CheckedDAG,
) -> @execution.CompletedOutput raise {
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
  let owner = graph_task_owner(graph, 0).unwrap()
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
  let target = @lower.node_at(@lower.bound_preparation(owner), 0).unwrap()
  let sequence = @execution.prepare_generated_sequence(
    contracts,
    prepared,
    [],
    [@lower.node_id(target)],
    10000,
    10000,
  ).unwrap()
  let limits : @execution.ValueLimits = {
    max_nodes: 10000,
    max_text_bytes: 10000,
    max_depth: 100,
    max_work: 100000,
  }
  let result = @execution.execute_generated_sequence(sequence, [], {
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
  @execution.completed_output(result, @pipeline.Step(0)).unwrap()
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
