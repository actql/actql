///|
struct Scenario {
  installed : @builtin.ConfiguredComputeHost[@strategy.RunIssue]
  issuer : @mock.MockQueryIssuer
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
