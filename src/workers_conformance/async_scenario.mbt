///|
struct AsyncScenario {
  installed : @probe.ConfiguredComputeHost[@strategy.RunIssue]
  issuer : @mock.MockQueryIssuer
}

///|
#export_name("prepareAsyncScenario")
pub fn prepare_async_scenario() -> AsyncScenario raise {
  let (run, issuer) = captured_graph_fixture(numeric_dag=true)
  let sequences = dispatch_test_generated(run)
  let registry = @connector.prepare_capability_registry(
    [
      {
        name: "independent-probe",
        acquisition: false,
        fixed_compute: true,
        effect: false,
      },
    ],
    1,
    100,
  ).unwrap()
  let driver = @host_driver.open_dispatch_driver(run)
  let measure : @execution.FixedInputGuardMeasureLimits = {
    max_work: 10000,
    max_bytes: 10000,
    max_nodes: 10000,
    max_depth: 100,
  }
  let modules = @probe.configure_compute_modules(
    driver,
    registry,
    1,
    _ => @strategy.RunIssue::ForeignCandidate,
    with_reference_compute=Some(
      (
        @connector.capability_registration_at(registry, 0).unwrap(),
        {
          sequences: sequences.map(@execution.generated_completion_preparation),
          limits: {
            max_work: 100,
            max_entries: 100,
            max_name_bytes: 10000,
            values: {
              max_nodes: 10000,
              max_text_bytes: 10000,
              max_depth: 100,
              max_work: 100000,
            },
            physical: measure,
            roots: measure,
          },
          expressions: {
            max_nodes: 1000,
            max_work: 10000,
            max_depth: 100,
            max_literal_nodes: 1000,
            max_literal_text_bytes: 10000,
          },
          milliseconds: Some(1L),
          max_work: 100,
        },
        issue => issue,
        issue => issue,
      ),
    ),
  ).unwrap()
  let installed = @probe.open_configured_compute_host(
    modules,
    registry,
    {
      contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
      max_rows: 100,
      max_value_bytes: 10000,
      common_fragment: None,
    },
    100,
    10000,
    1,
  ).unwrap()
  @host_driver.configure_compute_host_estimates(
    @probe.configured_host_runtime(installed),
    Array::make(3, Some(1000)),
    { max_offers: 3, max_strategies: 8, max_work: 10000, max_revisions: 3, },
    0,
  ).unwrap()
  { installed, issuer, }
}

///|
#export_name("asyncScenarioHost")
pub fn async_scenario_host(
  scenario : AsyncScenario,
) -> @probe.ConfiguredComputeHost[@strategy.RunIssue] {
  scenario.installed
}

///|
#export_name("closeAsyncScenario")
pub fn close_async_scenario(scenario : AsyncScenario) -> Unit {
  @host_driver.stop_dispatch_driver(
    @probe.configured_host_driver(scenario.installed),
  )
  @mock.close_mock_query_issuer(scenario.issuer)
}

///|
pub suberror ProbeFailure {
  Run(@strategy.RunIssue)
}

///|
#export_name("beginAsyncProbe")
pub fn begin_async_probe(
  setup : @probe.ConfiguredComputeHost[@strategy.RunIssue],
  task : @host_driver.PreparedTaskDispatch,
) -> @numeric_driver.AsyncNumericExecution raise ProbeFailure {
  match
    @numeric_driver.begin_numeric_contribution(
      @probe.configured_reference_compute_module(
        @probe.configured_host_modules(setup),
      ).unwrap(),
      @host_driver.compute_host_dispatch(@probe.configured_host_runtime(setup)),
      task,
    ) {
    Ok(value) => value
    Err(issue) => raise Run(issue)
  }
}

///|
#export_name("executeAsyncProbe")
pub fn execute_async_probe(
  work : @numeric_driver.AsyncNumericExecution,
) -> Unit raise ProbeFailure {
  match @numeric_driver.execute_async_numeric(work) {
    Ok(_) => ()
    Err(issue) => raise Run(issue)
  }
}

///|
#export_name("completeAsyncProbe")
pub fn complete_async_probe(
  work : @numeric_driver.AsyncNumericExecution,
) -> Unit raise ProbeFailure {
  match @numeric_driver.complete_async_numeric(work) {
    Ok(_) => ()
    Err(issue) => raise Run(issue)
  }
}

///|
#export_name("settleAsyncProbe")
pub fn settle_async_probe(
  work : @numeric_driver.AsyncNumericExecution,
) -> Unit raise ProbeFailure {
  match @numeric_driver.settle_async_numeric(work) {
    Ok(_) => ()
    Err(issue) => raise Run(issue)
  }
}

///|
#export_name("closeAsyncProbe")
pub fn close_async_probe(work : @numeric_driver.AsyncNumericExecution) -> Unit {
  @numeric_driver.close_async_numeric(work)
}
