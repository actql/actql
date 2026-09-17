///|
/// Test fixture ownership only. All checking, lowering, candidate selection,
/// execution, budgets and completion use the ordinary product implementation.
struct Scenario {
  installed : @builtin.ConfiguredComputeHost[@strategy.RunIssue]
  issuer : @mock.MockQueryIssuer
}

///|
priv suberror ScenarioFailure {
  Local(@local_driver.LocalDispatchIssue)
  Estimate(@local_driver.LocalEstimateIssue)
}

///|
#export_name("prepareWorkersScenario")
pub fn prepare_scenario(
  rows : Array[String],
  nullable : Bool,
  max_rows : Int,
  compute_filter : String,
) -> Scenario raise {
  let (run, issuer) = captured_graph_fixture(
    nullable~,
    compute_filter~,
    rows=Some(rows),
    retention={
      received_wire_bytes: 10000,
      retained_wire_bytes: 20000,
      measurement: {
        max_columns: 10,
        max_order_work: 1000,
        max_bytes: 20000,
        max_nodes: 10000,
        max_depth: 100,
      },
    },
  )
  let sequences = dispatch_test_generated(run)
  let registry = @connector.prepare_capability_registry(
    [{ name: "in-process", acquisition: false, fixed_compute: true, }],
    1,
    100,
  ).unwrap()
  let driver = @host_driver.open_dispatch_driver(run)
  let modules = @builtin.configure_compute_modules(
    driver,
    registry,
    1,
    _ => @strategy.RunIssue::ForeignCandidate,
    with_local=Some(
      (
        @connector.capability_registration_at(registry, 0).unwrap(),
        {
          sequences,
          managed_capacity: {
            contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
            max_rows,
            max_value_bytes: 10000,
            common_fragment: None,
          },
          execution: compute_test_limits(),
          measurement: {
            max_work: 100000,
            max_bytes: 100000,
            max_nodes: 10000,
            max_depth: 100,
          },
          max_work: 10000,
        },
        issue => {
          @strategy.RunIssue::Implementation(ScenarioFailure::Local(issue))
        },
        issue => {
          @strategy.RunIssue::Implementation(ScenarioFailure::Estimate(issue))
        },
      ),
    ),
  ).unwrap()
  let schedule = @cost.prepare_rate_schedule(
    @builtin.local_estimate_work_slots(),
    [
      {
        work_slots: [0, 1, 2, 3, 4],
        fixed_ms: Some(1L),
        per_row_ms: Some(0L),
        per_wire_byte_ms: Some(0L),
        per_pair_ms: Some(0L),
      },
    ],
    100,
  ).unwrap()
  let policy = @builtin.prepare_local_estimate_policy(modules, {
    schedules: Array::make(sequences.length(), schedule),
    max_work: 10000,
  }).unwrap()
  @builtin.install_configured_estimate_policy(policy).unwrap()
  let installed = @builtin.open_configured_compute_host(
    modules,
    registry,
    {
      contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
      max_rows,
      max_value_bytes: 1000,
      common_fragment: None,
    },
    100,
    10000,
    1,
  ).unwrap()
  @host_driver.configure_compute_host_estimates(
    @builtin.configured_host_runtime(installed),
    Array::make(sequences.length(), Some(1000)),
    { max_offers: 10, max_strategies: 10, max_work: 10000, max_revisions: 3, },
    0,
  ).unwrap()
  { installed, issuer, }
}

///|
#export_name("workersScenarioHost")
pub fn scenario_host(
  scenario : Scenario,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue] {
  scenario.installed
}

///|
#export_name("closeWorkersScenario")
pub fn close_scenario(scenario : Scenario) -> Unit {
  @host_driver.stop_dispatch_driver(
    @builtin.configured_host_driver(scenario.installed),
  )
  @mock.close_mock_query_issuer(scenario.issuer)
}

///|
#export_name("workersOutputIdentity")
pub fn output_identity(output : @execution.CompletedOutput) -> String {
  @execution.row_wire_cid(
    @execution.identify_completed_rows(output, {
      max_bytes: 100000,
      max_nodes: 10000,
      max_depth: 100,
      max_columns: 100,
      max_order_work: 10000,
    }).unwrap(),
  )
}

///|
#export_name("workersOutputRows")
pub fn output_rows(output : @execution.CompletedOutput) -> Int {
  @execution.completed_row_count(output)
}

///|
#export_name("workersFailureText")
pub fn failure_text(error : Error) -> String {
  match error {
    NodeHostFailure::Dispatch(Dispatch(Dispatch(Candidate(CommonInputRows)))) =>
      "common-input-rows"
    _ => error.to_string()
  }
}

///|
#export_name("workersArithmeticFailure")
pub fn arithmetic_failure(scenario : Scenario) -> Array[Int] {
  let run = @host_driver.dispatch_driver_run(
    @builtin.configured_host_driver(scenario.installed),
  )
  match @strategy.captured_dag_failure(run) {
    Some((task, Compute(Execution(Rows(step, Evaluation(row, slot, issue)))))) =>
      if issue.kind is Scalar(ArithmeticFailure) &&
        @lower.expression_location(issue.expression).range is Some(range) {
        [task, step, row, slot, range.start, range.end]
      } else {
        []
      }
    _ => []
  }
}

///|
/// Adversarial use of ordinary public dispatch APIs, not a test-only authority.
/// Both Runs are constructed inside the same module instance.
#export_name("workersForeignDispatch")
pub fn foreign_dispatch() -> Array[Bool] raise {
  let a = prepare_scenario(["{\"id\":3}"], false, 100, "id > 2")
  let b = prepare_scenario(["{\"id\":3}"], false, 100, "id > 2")
  let task = @host_driver.prepare_next_compute_task(
      @builtin.configured_host_runtime(a.installed),
      (),
    )
    .unwrap()
    .unwrap()
  let rejected = @builtin.execute_configured_in_process(b.installed, task)
    is Err(_)
  let run_a = @host_driver.dispatch_driver_run(
    @builtin.configured_host_driver(a.installed),
  )
  let run_b = @host_driver.dispatch_driver_run(
    @builtin.configured_host_driver(b.installed),
  )
  let no_partial = !@strategy.captured_task_completed(run_a, 1) &&
    !@strategy.captured_task_completed(run_b, 1)
  let own = @builtin.execute_configured_in_process(a.installed, task) is Ok(_)
  let independent = @strategy.captured_task_completed(run_a, 1) &&
    !@strategy.captured_task_completed(run_b, 1)
  @strategy.close_captured_task_output(run_a, 1)
  close_scenario(a)
  close_scenario(b)
  [rejected, no_partial, own, independent]
}

///|
#export_name("workersRejectInvalidProgram")
pub fn reject_invalid_program() -> Bool raise {
  try {
    // Syntactically valid expression, but no such declared input field.
    query_checked_program_fixture(acquisition_filter="missing_field > 2")
    |> ignore
    false
  } catch {
    @program_check.LocalConstructionFailure::Source(_) => true
    error => raise error
  }
}
