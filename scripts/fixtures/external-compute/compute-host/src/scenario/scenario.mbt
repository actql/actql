///|
struct Scenario {
  installed : @builtin.ConfiguredComputeHost[@strategy.RunIssue]
  issuer : @mock.MockQueryIssuer
}

///|
/// Uses the ordinary numeric DAG fixture, copied by the build harness from the
/// repository's generated fixture. Only the external contribution is installed.
#export_name("prepareScenario")
pub fn prepare_scenario() -> Scenario raise {
  let (run, issuer) = captured_graph_fixture(numeric_dag=true)
  let sequences = dispatch_test_generated(run)
  let registry = @connector.prepare_capability_registry(
    [
      {
        name: "external-numeric",
        acquisition: false,
        fixed_compute: true,
        effect: false,
      },
    ],
    1,
    100,
  ).unwrap()
  let driver = @host_driver.open_dispatch_driver(run)
  // Keep the same limits as connector_conformance.configure_subset(mode=1).
  let measurement : @execution.FixedInputGuardMeasureLimits = {
    max_work: 10000,
    max_bytes: 10000,
    max_nodes: 10000,
    max_depth: 100,
  }
  let values : @execution.ValueLimits = {
    max_nodes: 10000,
    max_text_bytes: 10000,
    max_depth: 100,
    max_work: 100000,
  }
  let modules = @builtin.configure_compute_modules(
    driver,
    registry,
    1,
    _ => @strategy.RunIssue::ForeignCandidate,
    with_external_numeric=Some(
      (
        @connector.capability_registration_at(registry, 0).unwrap(),
        {
          numeric: {
            sequences: sequences.map(
              @execution.generated_completion_preparation,
            ),
            limits: {
              max_work: 100,
              max_entries: 100,
              max_name_bytes: 10000,
              values,
              physical: measurement,
              roots: measurement,
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
        },
        issue => issue,
        issue => issue,
      ),
    ),
  ).unwrap()
  let installed = @builtin.open_configured_compute_host(
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
    @builtin.configured_host_runtime(installed),
    Array::make(sequences.length(), Some(1000)),
    {
      max_offers: sequences.length(),
      max_strategies: 8,
      max_work: 10000,
      max_revisions: sequences.length(),
    },
    0,
  ).unwrap()
  { installed, issuer, }
}

///|
#export_name("subsetHost")
pub fn subset_host(
  scenario : Scenario,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue] {
  scenario.installed
}

///|
#export_name("closeScenario")
pub fn close_scenario(scenario : Scenario) -> Unit {
  let driver = @builtin.configured_host_driver(scenario.installed)
  let run = @host_driver.dispatch_driver_run(driver)
  let count = @strategy.graph_task_count(@strategy.captured_dag_graph(run))
  for task = count - 1; task > 0; task = task - 1 {
    @strategy.close_captured_task_output(run, task)
  }
  @host_driver.stop_dispatch_driver(driver)
  @mock.close_mock_query_issuer(scenario.issuer)
}

///|
#export_name("outputRows")
pub fn output_rows(output : @execution.CompletedOutput) -> Int {
  @execution.completed_row_count(output)
}

///|
#export_name("outputValue")
pub fn output_value(output : @execution.CompletedOutput) -> Double {
  match @execution.completed_cell(output, 0, 0) {
    Some(Number(value)) => value
    _ => abort("expected numeric fixture output")
  }
}

///|
#export_name("outputAvailable")
pub fn output_available(output : @execution.CompletedOutput) -> Bool {
  @execution.completed_output_available(output)
}
