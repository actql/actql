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
  ordered_json : String?
  supplied : Array[@execution.CapturedRows]
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
/// Explicit SGA-enabled conformance fixture. The default fixture keeps the
/// RelA-only checker and artifact surface.
#export_name("strategyFixtureSgaCreate")
pub fn strategy_fixture_sga_create(
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
    environment_json,
    environment_cid,
    registry_json,
    values_json,
    fragment_json,
    query_json,
    evidence_json,
    two_receipt_json,
    program_json,
    false,
    sga=true,
  )
}

///|
#export_name("strategyFixtureTeaCreate")
pub fn strategy_fixture_tea_create(
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
    environment_json,
    environment_cid,
    registry_json,
    values_json,
    fragment_json,
    query_json,
    evidence_json,
    two_receipt_json,
    program_json,
    false,
    tea=true,
  )
}

///|
#export_name("strategyFixtureTeaSequenceCreate")
pub fn strategy_fixture_tea_sequence_create(
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
    environment_json,
    environment_cid,
    registry_json,
    values_json,
    fragment_json,
    query_json,
    evidence_json,
    two_receipt_json,
    program_json,
    false,
    tea=true,
    sequence_match=true,
  )
}

///|
#export_name("strategyFixtureVecaCreate")
pub fn strategy_fixture_veca_create(
  environment_json : String,
  environment_cid : String,
  registry_json : String,
  values_json : String,
  fragment_json : String,
  query_json : String,
  evidence_json : String,
  two_receipt_json : String,
  program_json : String,
  ordered_json : String,
) -> StrategyFixture {
  strategy_fixture_create_impl(
    environment_json,
    environment_cid,
    registry_json,
    values_json,
    fragment_json,
    query_json,
    evidence_json,
    two_receipt_json,
    program_json,
    false,
    veca=true,
    ordered_json=Some(ordered_json),
  )
}

///|
#export_name("strategyFixtureVecaScoredCreate")
pub fn strategy_fixture_veca_scored_create(
  environment_json : String,
  environment_cid : String,
  registry_json : String,
  values_json : String,
  fragment_json : String,
  query_json : String,
  evidence_json : String,
  two_receipt_json : String,
  program_json : String,
  ordered_json : String,
  rows : Int,
) -> StrategyFixture {
  strategy_fixture_create_impl(
    environment_json,
    environment_cid,
    registry_json,
    values_json,
    fragment_json,
    query_json,
    evidence_json,
    two_receipt_json,
    program_json,
    false,
    veca=true,
    ordered_json=Some(ordered_json),
    supplied_ranking_rows=Some(rows),
  )
}

///|
#export_name("strategyFixtureSgaSizedCreate")
pub fn strategy_fixture_sga_sized_create(
  environment_json : String,
  environment_cid : String,
  registry_json : String,
  values_json : String,
  fragment_json : String,
  query_json : String,
  evidence_json : String,
  two_receipt_json : String,
  program_json : String,
  rows : Int64,
) -> StrategyFixture {
  strategy_fixture_create_impl(
    environment_json,
    environment_cid,
    registry_json,
    values_json,
    fragment_json,
    query_json,
    evidence_json,
    two_receipt_json,
    program_json,
    false,
    sga=true,
    sga_rows=Some(rows),
  )
}

///|
#export_name("strategyFixtureSgaDerivedCreate")
pub fn strategy_fixture_sga_derived_create(
  environment_json : String,
  environment_cid : String,
  registry_json : String,
  values_json : String,
  fragment_json : String,
  query_json : String,
  evidence_json : String,
  two_receipt_json : String,
  program_json : String,
  rows : Int64,
) -> StrategyFixture {
  strategy_fixture_create_impl(
    environment_json,
    environment_cid,
    registry_json,
    values_json,
    fragment_json,
    query_json,
    evidence_json,
    two_receipt_json,
    program_json,
    false,
    sga=true,
    sga_derived_rows=Some(rows),
  )
}

///|
#export_name("strategyFixtureSgaComponentsCreate")
pub fn strategy_fixture_sga_components_create(
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
    environment_json,
    environment_cid,
    registry_json,
    values_json,
    fragment_json,
    query_json,
    evidence_json,
    two_receipt_json,
    program_json,
    false,
    sga=true,
    components=true,
  )
}

///|
#export_name("strategyFixtureSgaComponentsSizedCreate")
pub fn strategy_fixture_sga_components_sized_create(
  environment_json : String,
  environment_cid : String,
  registry_json : String,
  values_json : String,
  fragment_json : String,
  query_json : String,
  evidence_json : String,
  two_receipt_json : String,
  program_json : String,
  rows : Int64,
) -> StrategyFixture {
  strategy_fixture_create_impl(
    environment_json,
    environment_cid,
    registry_json,
    values_json,
    fragment_json,
    query_json,
    evidence_json,
    two_receipt_json,
    program_json,
    false,
    sga=true,
    components=true,
    components_rows=rows,
  )
}

///|
#export_name("strategyFixtureSgaReachCreate")
pub fn strategy_fixture_sga_reach_create(
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
    environment_json,
    environment_cid,
    registry_json,
    values_json,
    fragment_json,
    query_json,
    evidence_json,
    two_receipt_json,
    program_json,
    false,
    sga=true,
    reach=true,
  )
}

///|
#export_name("strategyFixtureSgaReachSizedCreate")
pub fn strategy_fixture_sga_reach_sized_create(
  environment_json : String,
  environment_cid : String,
  registry_json : String,
  values_json : String,
  fragment_json : String,
  query_json : String,
  evidence_json : String,
  two_receipt_json : String,
  program_json : String,
  rows : Int64,
) -> StrategyFixture {
  strategy_fixture_create_impl(
    environment_json,
    environment_cid,
    registry_json,
    values_json,
    fragment_json,
    query_json,
    evidence_json,
    two_receipt_json,
    program_json,
    false,
    sga=true,
    reach=true,
    sga_rows=Some(rows),
  )
}

///|
#export_name("strategyFixtureSgaTraverseSizedCreate")
pub fn strategy_fixture_sga_traverse_sized_create(
  environment_json : String,
  environment_cid : String,
  registry_json : String,
  values_json : String,
  fragment_json : String,
  query_json : String,
  evidence_json : String,
  two_receipt_json : String,
  program_json : String,
  rows : Int64,
) -> StrategyFixture {
  strategy_fixture_create_impl(
    environment_json,
    environment_cid,
    registry_json,
    values_json,
    fragment_json,
    query_json,
    evidence_json,
    two_receipt_json,
    program_json,
    false,
    sga=true,
    traverse=true,
    sga_rows=Some(rows),
  )
}

///|
#export_name("strategyFixtureSgaTraversePathsSizedCreate")
pub fn strategy_fixture_sga_traverse_paths_sized_create(
  environment_json : String,
  environment_cid : String,
  registry_json : String,
  values_json : String,
  fragment_json : String,
  query_json : String,
  evidence_json : String,
  two_receipt_json : String,
  program_json : String,
  rows : Int64,
) -> StrategyFixture {
  strategy_fixture_create_impl(
    environment_json,
    environment_cid,
    registry_json,
    values_json,
    fragment_json,
    query_json,
    evidence_json,
    two_receipt_json,
    program_json,
    false,
    sga=true,
    traverse=true,
    traverse_paths=true,
    sga_rows=Some(rows),
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
  sga? : Bool = false,
  tea? : Bool = false,
  veca? : Bool = false,
  ordered_json? : String? = None,
  components? : Bool = false,
  components_rows? : Int64 = 2L,
  reach? : Bool = false,
  traverse? : Bool = false,
  traverse_paths? : Bool = false,
  sga_rows? : Int64? = None,
  sga_derived_rows? : Int64? = None,
  supplied_ranking_rows? : Int? = None,
  sequence_match? : Bool = false,
) -> StrategyFixture {
  try {
    let program = issued_fixture_checked(
      environment_json,
      environment_cid,
      source_override=Some(program_json),
      join~,
      sga~,
      tea~,
      veca~,
      components~,
      components_rows~,
      reach~,
      traverse~,
      traverse_paths~,
      sga_rows~,
      sga_derived_rows~,
      sequence_match~,
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
    let expression_profiles = @program_check.selected_expression_profiles(
      program,
    )
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
          expression_profiles={
            text_time: expression_profiles.text_time,
            veca: expression_profiles.veca,
          },
        ).unwrap()
      }
    })
    let graph = @strategy.prepare_checked_dag(program, owners, 10, 10000).unwrap()
    let supplied = match supplied_ranking_rows {
      Some(rows) => {
        guard rows > 0 && rows <= 100 else {
          fail("invalid scored ranking fixture rows")
        }
        let inputs = Array::makei(2, input => {
          let values = Array::makei(rows, index => {
            let score = 1.0 -
              (index * 2 + input).to_double() / (rows * 4).to_double()
            cursor(
              "{\"q\":1,\"id\":" +
              (index + 1).to_string() +
              ",\"score\":" +
              score.to_string() +
              "}",
            )
          })
          @execution.capture_input(owners[1], input, values, max_rows=100, {
            max_nodes: 10000,
            max_text_bytes: 10000,
            max_depth: 10,
            max_work: 100000,
          }).unwrap()
        })
        inputs
      }
      None => []
    }
    @acquisition_host.close_native_host(native.host) // unused fixture issuer, not real Host
    let extended = @program_check.unit_count(program) > 4
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
      holdings: if join || multiple_resources || extended {
        20
      } else {
        10
      },
      transfer_bytes: if join || multiple_resources || extended {
        1000000L
      } else {
        300000L
      },
      retained_bytes: if extended {
        64000000L
      } else {
        32000000L
      },
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
      ordered_json,
      supplied,
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
  match
    @strategy.open_captured_dag(f.graph, source, f.ledger, supplied=f.supplied) {
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
fn fixture_example_dispatch(
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
        @execution.generated_completion_preparation(generated),
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
      join_output_ceiling=@strategy.captured_task_join_output_at(
        f.run.unwrap(),
        task,
        0,
      ),
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
#export_name("strategyFixtureManagedOutputMatches")
pub fn strategy_fixture_managed_output_matches(
  f : StrategyFixture,
  task : Int,
  output : @execution.ManagedCompletedOutput[Int],
) -> Bool {
  guard f.run is Some(run) &&
    @strategy.captured_task_target(run, task) is Some(target) else {
    return false
  }
  @strategy.captured_managed_task_output_matches(run, task, target, output)
}

///|
#export_name("strategyFixtureManagedInput")
pub fn strategy_fixture_managed_input(
  f : StrategyFixture,
  task : Int,
  output : @execution.ManagedCompletedOutput[Int],
) -> @execution.ManagedProducerRead[Int] {
  @strategy.captured_managed_task_input(
    f.run.unwrap(),
    task,
    output,
    100,
    10000,
  ).unwrap()
}

///|
#export_name("strategyFixtureManagedRequest")
pub fn strategy_fixture_managed_request(
  f : StrategyFixture,
  task : Int,
  output : @execution.ManagedCompletedOutput[Int],
) -> @connector.ManagedFixedComputeRequest[Int] {
  let input = @strategy.captured_managed_task_input(
    f.run.unwrap(),
    task,
    output,
    100,
    10000,
  ).unwrap()
  @connector.prepare_managed_fixed_compute_request(
    [input],
    {
      contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
      max_rows: 100,
      max_value_bytes: 1000,
      common_fragment: None,
    },
    @execution.process_managed_obligations(
      @execution.managed_producer_read_receiver(input),
    ),
  ).unwrap()
}

///|
#export_name("strategyFixtureManagedRequestInputCount")
pub fn strategy_fixture_managed_request_input_count(
  request : @connector.ManagedFixedComputeRequest[Int],
) -> Int {
  @connector.managed_fixed_compute_request_input_count(request)
}

///|
/// Independent expectation view for the Host-owned obligation derivation.
/// This diagnostic is not an identity capability and cannot establish a CID.
#export_name("strategyFixtureManagedObligationLabels")
pub fn strategy_fixture_managed_obligation_labels(
  f : StrategyFixture,
  publication : Bool,
  consumer : Bool,
  host_policy : Bool,
) -> Array[String] {
  guard f.run is Some(run) &&
    @strategy.configure_captured_managed_identity_policy(
      run, true, publication, consumer, host_policy,
    ) else {
    return []
  }
  let obligations = match @strategy.captured_next_managed_obligations(run, 64) {
    Ok(value) => value
    Err(_) => return []
  }
  @execution.managed_obligations_identities(obligations).map(identity => {
    let domain = match identity.domain {
      LogicalRow => "logical-row"
      OrderedRows => "ordered-rows"
      LogicalRelation => "logical-relation"
    }
    let subject = match identity.subject {
      ReceivedValidationRows => "received-validation-rows"
      ReceivedNativeRows => "received-native-rows"
      AcquisitionOutput => "acquisition-output"
      TaskOutput => "task-output"
      NamedResult => "named-result"
    }
    let deadline = match identity.need {
      UnestablishedRetained => "retained"
      EstablishedBy(BeforeCidOperation) => "before-cid-operation"
      EstablishedBy(BeforePublication) => "before-publication"
      EstablishedBy(BeforeDiscard) => "before-discard"
    }
    let occurrence = identity.occurrence
      .map(@execution.managed_result_occurrence_name)
      .unwrap_or("-")
    domain + ":" + subject + ":" + deadline + ":" + occurrence
  })
}

///|
/// Independent pre-start policy-admission diagnostic. False means the checked
/// Program requests a publication family outside this managed Compute profile;
/// it is not a connector support decision.
#export_name("strategyFixtureManagedPolicyAccepted")
pub fn strategy_fixture_managed_policy_accepted(
  f : StrategyFixture,
  publication : Bool,
  consumer : Bool,
  host_policy : Bool,
) -> Bool {
  guard f.run is Some(run) else { return false }
  @strategy.configure_captured_managed_identity_policy(
    run, true, publication, consumer, host_policy,
  )
}

///|
#export_name("strategyFixtureManagedRequestAccepts")
pub fn strategy_fixture_managed_request_accepts(
  input : @execution.ManagedProducerRead[Int],
  max_rows : Int,
) -> Bool {
  @connector.prepare_managed_fixed_compute_request(
    [input],
    {
      contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
      max_rows,
      max_value_bytes: 1000,
      common_fragment: None,
    },
    @execution.process_managed_obligations(
      @execution.managed_producer_read_receiver(input),
    ),
  )
  is Ok(_)
}

///|
/// A CID-dependent consumer/publication requirement is fixed before native
/// candidate comparison. The installed DuckDB managed candidate does not yet
/// establish that identity and therefore must not enter comparison.
#export_name("strategyFixtureManagedIdentityCandidateAccepts")
pub fn strategy_fixture_managed_identity_candidate_accepts(
  f : StrategyFixture,
  task : Int,
  output : @execution.ManagedCompletedOutput[Int],
) -> Bool {
  let input = @strategy.captured_managed_task_input(
    f.run.unwrap(),
    task,
    output,
    100,
    10000,
  ).unwrap()
  let owner = @execution.managed_producer_read_receiver(input)
  let obligations = @execution.prepare_managed_obligations(
    owner,
    [
      {
        domain: OrderedRows,
        subject: TaskOutput,
        occurrence: None,
        need: EstablishedBy(BeforeCidOperation),
      },
    ],
    LogicalContentAddressed,
    LogicalContentIdentity,
    1,
  ).unwrap()
  let request = @connector.prepare_managed_fixed_compute_request(
    [input],
    {
      contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
      max_rows: 100,
      max_value_bytes: 1000,
      common_fragment: None,
    },
    obligations,
  ).unwrap()
  @duckdb_compute.duckdb_managed_fixed_compute_candidate(
    @connector.capability_registration_at(f.registry, 1).unwrap(),
    request,
    "managed_input",
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
  )
  is Ok(_)
}

///|
#export_name("strategyFixtureManagedRequestQuery")
pub fn strategy_fixture_managed_request_query(
  f : StrategyFixture,
  request : @connector.ManagedFixedComputeRequest[Int],
) -> @duckdb.ManagedFixedQuery[Int] {
  let prepared = strategy_fixture_managed_candidate(f, request)
  guard @connector.choose_managed_fixed_compute_candidate(
      f.registry,
      request,
      [@connector.prepared_managed_compute_candidate(prepared)],
      None,
      100,
    ).unwrap()
    is Proposed(choice) else {
    abort("managed choice")
  }
  @connector.managed_fixed_compute_choice_payload(choice, prepared).unwrap()
}

///|
fn strategy_fixture_managed_candidate(
  f : StrategyFixture,
  request : @connector.ManagedFixedComputeRequest[Int],
) -> @connector.PreparedManagedCompute[Int, @duckdb.ManagedFixedQuery[Int]] {
  @duckdb_compute.duckdb_managed_fixed_compute_candidate(
    @connector.capability_registration_at(f.registry, 1).unwrap(),
    request,
    "managed_input",
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
}

///|
#export_name("strategyFixtureManagedCandidateAccepts")
pub fn strategy_fixture_managed_candidate_accepts(
  f : StrategyFixture,
  candidate_request : @connector.ManagedFixedComputeRequest[Int],
  selected_request : @connector.ManagedFixedComputeRequest[Int],
) -> Bool {
  let prepared = strategy_fixture_managed_candidate(f, candidate_request)
  @connector.choose_managed_fixed_compute_candidate(
    f.registry,
    selected_request,
    [@connector.prepared_managed_compute_candidate(prepared)],
    None,
    100,
  )
  is Ok(Proposed(_))
}

///|
/// Conformance construction of the product's opaque managed Host
/// configuration. The selected request and generated completion owner are
/// fixed here; callers cannot inject SQL or a replacement verifier.
#export_name("strategyFixtureManagedConfiguration")
pub fn strategy_fixture_managed_configuration(
  f : StrategyFixture,
  task : Int,
  request : @connector.ManagedFixedComputeRequest[Int],
  profile : @execution.ManagedExecutionProfile,
  output_file_bytes : Int64,
) -> @duckdb_driver.ManagedStrategyComputeHostConfiguration[Int] {
  let prepared = strategy_fixture_managed_candidate(f, request)
  guard @connector.choose_managed_fixed_compute_candidate(
      f.registry,
      request,
      [@connector.prepared_managed_compute_candidate(prepared)],
      None,
      100,
    ).unwrap()
    is Proposed(choice) else {
    abort("managed choice")
  }
  let query = @connector.managed_fixed_compute_choice_payload(choice, prepared).unwrap()
  let generated = fixture_generated(
    @duckdb.managed_fixed_query_owner(query),
    f.registry_json,
    f.values_json,
    f.fragment_json,
    @duckdb.managed_fixed_query_requires_fragment(query),
  ) catch {
    _ => abort("managed completion fixture")
  }
  let output_schema = @lower.preparation_schema_at(
    @lower.bound_preparation(@duckdb.managed_fixed_query_owner(query)),
    @duckdb.managed_fixed_query_target(query),
  ).unwrap()
  let row_ceiling = @duckdb.managed_fixed_query_output_row_ceiling(
    query,
    @connector.managed_fixed_compute_request_capacity(request).max_rows,
  )
  let width = @schema.field_count(output_schema)
  let max_index_cells = if width == 0 || row_ceiling <= 0 {
    0
  } else if row_ceiling > 1000000 / width {
    abort("managed index ceiling")
  } else {
    row_ceiling * width
  }
  @duckdb_driver.configure_managed_strategy_compute_host(
    f.run.unwrap(),
    task,
    choice,
    prepared,
    @execution.generated_completion_preparation(generated),
    profile,
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
    output_file_bytes,
    max_index_cells,
    [],
  ).unwrap()
}

///|
/// Common lifecycle conformance only: this registers the selected managed
/// payload but performs no native I/O. Product dispatch must additionally own
/// the Store pin, authority and concrete transport execution.
#export_name("strategyFixtureManagedExecutionStart")
pub fn strategy_fixture_managed_execution_start(
  f : StrategyFixture,
  task : Int,
  request : @connector.ManagedFixedComputeRequest[Int],
  profile : @execution.ManagedExecutionProfile,
) -> @strategy.TaskExecution {
  let configured = strategy_fixture_managed_configuration(
    f, task, request, profile, 0L,
  )
  @duckdb_driver.start_configured_managed_strategy_compute_host(
    configured,
    0L,
    1L,
    fn() { true },
    fn(_) { true },
    fn() { true },
  ).unwrap()
  |> @duckdb_driver.captured_managed_duckdb_execution
}

///|
#export_name("strategyFixtureManagedExecutionSettle")
pub fn strategy_fixture_managed_execution_settle(
  f : StrategyFixture,
  execution : @strategy.TaskExecution,
) -> Bool {
  @strategy.settle_task_execution(f.run.unwrap(), execution, true) is Ok(_)
}

///|
#export_name("strategyFixtureManagedExecutionClose")
pub fn strategy_fixture_managed_execution_close(
  f : StrategyFixture,
  execution : @strategy.TaskExecution,
) -> Unit {
  @strategy.close_task_execution(f.run.unwrap(), execution)
}

///|
#export_name("strategyFixtureManagedRequestQuerySql")
pub fn strategy_fixture_managed_request_query_sql(
  query : @duckdb.ManagedFixedQuery[Int],
) -> Array[String] {
  [
    @duckdb.managed_fixed_query_create_sql(query),
    @duckdb.managed_fixed_query_sql(query),
  ]
}

///|
/// Conformance probe for the product wrapper's exact native occurrence check.
/// It neither executes SQL nor issues completion evidence.
#export_name("strategyFixtureManagedSelectionMatches")
pub fn strategy_fixture_managed_selection_matches(
  query : @duckdb.ManagedFixedQuery[Int],
  rows : Array[Int],
) -> Bool {
  @duckdb.prepare_managed_fixed_query_selection(query, rows, 1000, 10000)
  is Ok(_)
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

///|
#export_name("strategyFixtureDispatch")
pub fn strategy_fixture_dispatch(
  f : StrategyFixture,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue] {
  @dbhost.dispatch_installation(fixture_example_dispatch(f))
}
