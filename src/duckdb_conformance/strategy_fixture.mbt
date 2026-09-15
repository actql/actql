///|
// Conformance preparation only; execution uses the standard composition and
// connector-owned Node bridges, never this package as a transport runtime.
struct StrategyFixture {
  native : IssuedNativeFixture
  graph : @strategy.CheckedDAG
  ledger : @resources.Ledger
  registry : @connector.CapabilityRegistry
  mut search_configured : Bool
  mut selected : @strategy.StrategyRevision?
  registry_json : String
  values_json : String
  fragment_json : String
  mut run : @strategy.CapturedDAG?
}

///|
#export_name("strategyFixtureCreate")
pub fn strategy_fixture_create(
  environment_json : String,
  environment_cid : String,
  registry_json : String,
  values_json : String,
  fragment_json : String,
  query_json : String,
  evidence_json : String,
  two_receipt_json : String,
  program_json : String,
) -> StrategyFixture {
  strategy_fixture_create_impl(
    environment_json, environment_cid, registry_json, values_json, fragment_json,
    query_json, evidence_json, two_receipt_json, program_json, false,
  )
}

///|
#export_name("strategyFixtureJoinCreate")
pub fn strategy_fixture_join_create(
  environment_json : String,
  environment_cid : String,
  registry_json : String,
  values_json : String,
  fragment_json : String,
  query_json : String,
  evidence_json : String,
  two_receipt_json : String,
  program_json : String,
) -> StrategyFixture {
  strategy_fixture_create_impl(
    environment_json, environment_cid, registry_json, values_json, fragment_json,
    query_json, evidence_json, two_receipt_json, program_json, true,
  )
}

///|
fn strategy_fixture_create_impl(
  environment_json : String,
  environment_cid : String,
  registry_json : String,
  values_json : String,
  fragment_json : String,
  query_json : String,
  evidence_json : String,
  two_receipt_json : String,
  program_json : String,
  join : Bool,
  multiple_resources? : Bool = false,
) -> StrategyFixture {
  try {
    let program = issued_fixture_checked(
      environment_json,
      environment_cid,
      source_override=Some(program_json),
      visits=if join { [1, 2, 2, 5, 6] } else { [1, 2, 2, 3] },
      join~,
    )
    let native = issued_native_create_impl(
      environment_json,
      environment_cid,
      registry_json,
      values_json,
      fragment_json,
      query_json,
      evidence_json,
      two_receipt_json,
      100,
      _ => false,
      checked_override=Some(program),
    )
    let identity = @program_check.source_identity(program)
    let owners = Array::makei(@program_check.unit_count(program), index => {
      if index == 0 {
        @duckdb.native_query_owner(@duckdb.native_scan_query(native.scan))
      } else {
        let prepared = @lower.prepare(
          @program_check.unit_pipeline(program, index).unwrap(),
          {
            max_nodes: 100,
            max_references: 100,
            max_work: 100000,
            max_identifier_bytes: 10000,
          },
        ).unwrap()
        let parameters = @parameters.bound_values(
          @context.stage_identity_parameter_values(
            @context.program_identity_stage_at(identity, index).unwrap(),
          ),
        )
        @lower.bind_parameters(
          prepared,
          Some(parameters),
          max_parameters=100,
          max_name_bytes=10000,
        ).unwrap()
      }
    })
    let graph = @strategy.prepare_checked_dag(program, owners, 5, 10000).unwrap()
    @acquisition_host.close_native_host(native.host) // unused fixture issuer, not real Host
    let ledger = @resources.create_ledger({
      planning_work: if join || multiple_resources {
        100000
      } else {
        10000
      },
      attempts: if join || multiple_resources {
        20
      } else {
        10
      },
      holdings: if join || multiple_resources {
        20
      } else {
        10
      },
      transfer_bytes: if join || multiple_resources {
        1000000L
      } else {
        300000L
      },
      retained_bytes: 32000000L,
      execution_bytes: if multiple_resources {
        536870912L
      } else {
        268435456L
      },
    }).unwrap()
    {
      native,
      graph,
      ledger,
      registry: @connector.prepare_capability_registry(
        [
          { name: "local", acquisition: false, fixed_compute: true, },
          { name: "duckdb", acquisition: false, fixed_compute: true, },
        ],
        2,
        100,
      ).unwrap(),
      search_configured: false,
      selected: None,
      registry_json,
      values_json,
      fragment_json,
      run: None,
    }
  } catch {
    _ => abort("strategy conformance setup")
  }
}

///|
#export_name("strategyFixtureAcquisition")
pub fn strategy_fixture_acquisition(
  f : StrategyFixture,
) -> @acquisition_host.NativeHostConfiguration {
  f.native.configuration
}

///|
#export_name("strategyFixtureAccounted")
pub fn strategy_fixture_accounted(f : StrategyFixture) -> StrategyFixture {
  // This fixture includes conservative retained capacities for all three
  // evidence records, the observation, scan and native output, not just Compute.
  let ledger = @resources.create_ledger({
    planning_work: 10000,
    attempts: 10,
    holdings: 10,
    transfer_bytes: 300000L,
    retained_bytes: 200000000L,
    execution_bytes: 268435456L,
  }).unwrap()
  { ..f, ledger, run: None, }
}

///|
#export_name("strategyFixtureLedger")
pub fn strategy_fixture_ledger(f : StrategyFixture) -> @resources.Ledger {
  f.ledger
}

///|
#export_name("strategyFixtureGraph")
pub fn strategy_fixture_graph(f : StrategyFixture) -> @strategy.CheckedDAG {
  f.graph
}

///|
#export_name("strategyFixtureAttach")
pub fn strategy_fixture_attach(
  f : StrategyFixture,
  run : @strategy.CapturedDAG,
) -> Bool {
  if f.run is Some(_) ||
    !physical_equal(f.ledger, @strategy.captured_dag_ledger(run)) {
    return false
  }
  f.run = Some(run)
  true
}

///|
#export_name("strategyFixtureOpen")
pub fn strategy_fixture_open(
  f : StrategyFixture,
  source : @query.CapturedInputSource,
) -> Bool {
  if f.run is Some(_) {
    return false
  }
  match @strategy.open_captured_dag(f.graph, source, f.ledger) {
    Ok(run) => {
      f.run = Some(run)
      true
    }
    Err(_) => false
  }
}

///|
#export_name("strategyFixtureRun")
pub fn strategy_fixture_run(f : StrategyFixture) -> @strategy.CapturedDAG {
  f.run.unwrap()
}

///|
fn strategy_fixture_request(
  f : StrategyFixture,
  task : Int,
) -> @connector.FixedComputeRequest {
  let input = @strategy.captured_task_input(f.run.unwrap(), task, 100, 10000).unwrap()
  @connector.prepare_fixed_compute_request([input], {
    contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
    max_rows: 100,
    max_value_bytes: 1000,
    common_fragment: None,
  }).unwrap()
}

///|
#export_name("strategyFixtureDispatch")
pub fn strategy_fixture_dispatch(
  f : StrategyFixture,
) -> @dbhost.StrategyHostDispatch {
  let generated = []
  for task in 1..<@strategy.graph_task_count(f.graph) {
    generated.push(
      fixture_generated(
        @strategy.graph_task_owner(f.graph, task).unwrap(),
        f.registry_json,
        f.values_json,
        f.fragment_json,
        true,
      ) catch {
        _ => abort("dispatch fixture generation")
      },
    )
  }
  @dbhost.configure_strategy_dispatch(
    f.run.unwrap(),
    f.registry,
    @connector.capability_registration_at(f.registry, 0).unwrap(),
    @connector.capability_registration_at(f.registry, 1).unwrap(),
    generated,
    {
      input_entries: 100,
      input_name_bytes: 10000,
      candidate_work: 100,
      join_validation: { max_rows: 100, max_work: 10000, max_entries: 1000, },
      capacity: {
        contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
        max_rows: 100,
        max_value_bytes: 1000,
        common_fragment: None,
      },
      local_execution: issued_execution_limits(100),
      guards: issued_native_measure_limits(),
      native_query: {
        max_entries: 100,
        max_sql_bytes: 10000,
        expressions: {
          max_nodes: 1000,
          max_work: 10000,
          max_depth: 100,
          max_literal_nodes: 1000,
          max_literal_text_bytes: 10000,
        },
      },
      native: {
        values: issued_native_measure_limits(),
        demand: issued_native_measure_limits(),
        physical: {
          max_rows: 100,
          max_cells: 1000,
          max_nodes: 1000,
          max_text_bytes: 10000,
        },
        retention: {
          max_nodes: 10000,
          max_text_bytes: 10000,
          max_depth: 100,
          max_work: 100000,
        },
        metadata_work: 10000,
        completion_entries: 100,
        completion_name_bytes: 10000,
      },
      transport: {
        max_bytes: 100000,
        max_nodes: 10000,
        max_columns: 10,
        max_rows: 100,
        max_text_bytes: 100000,
      },
    },
  ).unwrap()
}

///|
#export_name("strategyFixtureCompute")
pub fn strategy_fixture_compute(
  f : StrategyFixture,
  task : Int,
) -> @duckdb_driver.StrategyComputeHostConfiguration {
  try {
    let request = strategy_fixture_request(f, task)
    let registry = f.registry
    let candidate = @duckdb_compute.duckdb_fixed_compute_candidate(
      @connector.capability_registration_at(registry, 1).unwrap(),
      request,
      "owned_input",
      {
        max_entries: 100,
        max_sql_bytes: 10000,
        expressions: {
          max_nodes: 1000,
          max_work: 10000,
          max_depth: 100,
          max_literal_nodes: 1000,
          max_literal_text_bytes: 10000,
        },
      },
      [{ work_slots: [0, 1, 2, 3, 4, 5, 6, 7], milliseconds: Some(1L), }],
      { transfer_bytes: None, retained_bytes: None, money_units: None, },
      100,
    ).unwrap()
    guard @connector.choose_fixed_compute_candidate(
        registry,
        request,
        [@connector.prepared_compute_candidate(candidate)],
        None,
        100,
      ).unwrap()
      is Proposed(choice) else {
      abort("choice")
    }
    let generated = fixture_generated(
      @execution.producer_read_receiver(
        @connector.fixed_compute_request_input(request, 0).unwrap(),
      ),
      f.registry_json,
      f.values_json,
      f.fragment_json,
      true,
    )
    @duckdb_driver.configure_strategy_compute_host(
      f.run.unwrap(),
      task,
      @duckdb_driver.configure_compute_host(
        choice,
        candidate,
        generated,
        {
          values: issued_native_measure_limits(),
          demand: issued_native_measure_limits(),
          physical: {
            max_rows: 100,
            max_cells: 1000,
            max_nodes: 1000,
            max_text_bytes: 10000,
          },
          retention: {
            max_nodes: 10000,
            max_text_bytes: 10000,
            max_depth: 100,
            max_work: 100000,
          },
          metadata_work: 10000,
          completion_entries: 100,
          completion_name_bytes: 10000,
        },
        {
          max_bytes: 100000,
          max_nodes: 10000,
          max_columns: 10,
          max_rows: 100,
          max_text_bytes: 100000,
        },
      ),
    )
  } catch {
    _ => abort("strategy compute fixture")
  }
}

///|
#export_name("strategyFixtureLocal")
pub fn strategy_fixture_local(f : StrategyFixture, task : Int) -> Bool {
  try {
    let request = strategy_fixture_request(f, task)
    let registry = f.registry
    let generated = fixture_generated(
      @execution.producer_read_receiver(
        @connector.fixed_compute_request_input(request, 0).unwrap(),
      ),
      f.registry_json,
      f.values_json,
      f.fragment_json,
      true,
    )
    let candidate = @local_connector.local_fixed_compute_candidate(
      @connector.capability_registration_at(registry, 0).unwrap(),
      request,
      generated,
      [{ work_slots: [0, 1, 2, 3, 4], milliseconds: Some(1L), }],
      { transfer_bytes: None, retained_bytes: None, money_units: None, },
      100,
    ).unwrap()
    guard @connector.choose_fixed_compute_candidate(
        registry,
        request,
        [@connector.prepared_compute_candidate(candidate)],
        None,
        100,
      ).unwrap()
      is Proposed(choice) else {
      return false
    }
    let compute = @local_connector.prepare_local_compute_execution(
      choice,
      candidate,
      issued_execution_limits(100),
      issued_native_measure_limits(),
      join_output_ceiling=@strategy.captured_task_join_output_limit(
        f.run.unwrap(),
        task,
      ).map(limit => (0, limit)),
    ).unwrap()
    @strategy.execute_captured_synchronous_task(f.run.unwrap(), task, compute)
    is Ok(_)
  } catch {
    _ => false
  }
}

///|
#export_name("strategyFixtureCid")
pub fn strategy_fixture_cid(f : StrategyFixture, task : Int) -> String {
  guard f.run is Some(run) &&
    @strategy.captured_task_target(run, task) is Some(target) &&
    @strategy.captured_task_output(run, task, target) is Some(output) else {
    return "null"
  }
  match
    @execution.identify_completed_rows(output, {
      max_columns: 10,
      max_order_work: 10000,
      max_bytes: 100000,
      max_nodes: 10000,
      max_depth: 100,
    }) {
    Ok(identity) => @execution.row_wire_cid(identity)
    Err(_) => "null"
  }
}

///|
#export_name("strategyFixtureNext")
pub fn strategy_fixture_next(f : StrategyFixture) -> Int {
  f.run.bind(run => @strategy.next_captured_task(run)).unwrap_or(-1)
}

///|
#export_name("strategyFixtureConsume")
pub fn strategy_fixture_consume(
  f : StrategyFixture,
  task : Int,
  steps : String,
) -> String {
  guard f.run is Some(run) &&
    @strategy.captured_task_target(run, task) is Some(target) &&
    @strategy.captured_task_output(run, task, target) is Some(output) &&
    @strategy.graph_task_owner(f.graph, task) is Some(owner) else {
    return "null"
  }
  let consumer = issued_fixture_consumer(owner, target~, steps~)
  let generated = fixture_generated(
    consumer,
    f.registry_json,
    f.values_json,
    f.fragment_json,
    false,
  ) catch {
    _ => return "null"
  }
  guard @execution.bind_completed_input(consumer, 0, owner, output) is Ok(input) else {
    return "null"
  }
  guard @execution.execute_generated_sequence(
      generated,
      [],
      issued_execution_limits(100),
      produced=[input],
    )
    is Ok(completed) else {
    return "null"
  }
  guard @execution.completed_output(completed, Step(0)) is Some(result) else {
    return "null"
  }
  match
    @execution.identify_completed_rows(result, {
      max_columns: 10,
      max_order_work: 10000,
      max_bytes: 100000,
      max_nodes: 10000,
      max_depth: 100,
    }) {
    Ok(identity) => @execution.row_wire_cid(identity)
    Err(_) => "null"
  }
}

///|
#export_name("strategyFixtureCanBind")
pub fn strategy_fixture_can_bind(f : StrategyFixture, task : Int) -> Bool {
  guard f.run is Some(run) &&
    @strategy.captured_task_target(run, task) is Some(target) &&
    @strategy.captured_task_output(run, task, target) is Some(output) &&
    @strategy.graph_task_owner(f.graph, task) is Some(owner) else {
    return false
  }
  @execution.bind_completed_input(
    issued_fixture_consumer(owner, target~),
    0,
    owner,
    output,
  )
  is Ok(_)
}

///|
#export_name("strategyFixtureUsage")
pub fn strategy_fixture_usage(f : StrategyFixture, field : Int) -> Int64 {
  let usage = @resources.ledger_usage(f.ledger)
  match field {
    0 => usage.transferred_bytes
    1 => usage.reserved_transfer_bytes
    2 => usage.reserved_execution_bytes
    4 => usage.held_bytes
    5 => usage.reserved_retention_bytes
    _ => usage.attempts.to_int64()
  }
}

///|
#export_name("strategyFixtureCloseOutput")
pub fn strategy_fixture_close_output(f : StrategyFixture, task : Int) -> Unit {
  if f.run is Some(run) {
    @strategy.close_captured_task_output(run, task)
  }
}
