///|
struct Scenario {
  installed : @builtin.ConfiguredComputeHost[@strategy.RunIssue]
  issuer : @mock.MockQueryIssuer
}

///|
fn events_storage_limits() -> @record_storage.Limits {
  {
    max_input_records: 10,
    max_records: 10,
    max_fields_per_record: 10,
    max_value_bytes: 1000,
    max_total_value_bytes: 10000,
    max_retained_value_bytes: 10000,
    max_value_nodes: 100,
    max_value_depth: 10,
    max_contract_work: 1000,
    max_work: 1000,
    max_workspace_slots: 1000,
  }
}

///|
fn open_events_host(
  run : @strategy.CapturedDAG,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue] raise {
  let sequences = dispatch_test_generated(run)
  let execution = compute_test_limits()
  let provider = @tea_provider.provider(
    events_storage_limits(),
    4096L,
    @execution.generated_sequence_capacity(sequences[1], execution, {
      max_work: 10000,
      max_bytes: 10000,
      max_nodes: 10000,
      max_depth: 100,
    }).unwrap(),
  )
  @conformance.configure_subset(run, sequences, 2, managed_providers=[provider])
}

///|
#export_name("prepareEventsSession")
pub fn prepare_events_session() -> Scenario raise {
  let (run, issuer) = captured_graph_fixture(
    local_carrier_events_chain=true,
    local_carrier_events_variant="session",
    managed_publication=true,
  )
  { installed: open_events_host(run), issuer, }
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
  @host_driver.stop_dispatch_driver(
    @builtin.configured_host_driver(scenario.installed),
  )
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
