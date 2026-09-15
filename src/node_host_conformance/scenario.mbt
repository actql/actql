///|
struct Scenario {
  installed : @builtin.ConfiguredComputeHost[@strategy.RunIssue]
  issuer : @mock.MockQueryIssuer
}

///|
#export_name("prepareSortTake")
pub fn prepare_sort_take() -> Scenario raise {
  let (run, issuer) = captured_graph_fixture(
    sort_take=true,
    retention={
      received_wire_bytes: 10000,
      retained_wire_bytes: 10000,
      measurement: {
        max_columns: 10,
        max_order_work: 1000,
        max_bytes: 10000,
        max_nodes: 1000,
        max_depth: 10,
      },
    },
    rows=Some(["{\"id\":2}", "{\"id\":4}", "{\"id\":3}", "{\"id\":4}"]),
  )
  let installed = @conformance.configure_subset(
    run,
    dispatch_test_generated(run),
    0,
  )
  { installed, issuer, }
}

///|
#export_name("prepareSubset")
pub fn prepare_subset(mode : Int) -> Scenario raise {
  let (run, issuer) = captured_graph_fixture(numeric_dag=true)
  let installed = @conformance.configure_subset(
    run,
    dispatch_test_generated(run),
    mode,
  )
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
#export_name("closeSubset")
pub fn close_subset(scenario : Scenario) -> Unit {
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
