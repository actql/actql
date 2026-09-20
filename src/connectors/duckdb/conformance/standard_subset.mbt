///|
/// Fixture setup only; the standard generated bridge and installed modules own
/// every execution operation. No unused Compute provider configuration is built.
#export_name("strategyFixtureModuleSubset")
pub fn strategy_fixture_module_subset(
  f : StrategyFixture,
  mode : Int,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue] {
  let generated = Array::makei(@strategy.graph_task_count(f.graph) - 1, i => {
    fixture_generated(
      @strategy.graph_task_owner(f.graph, i + 1).unwrap(),
      f.registry_json,
      f.values_json,
      f.fragment_json,
      true,
    ) catch {
      _ => abort("invalid fixture generation")
    }
  })
  @connector_conformance.configure_subset(f.run.unwrap(), generated, mode)
}

///|
/// Explicit SGA-enabled conformance artifact. The ordinary module subset does
/// not import or install this family provider.
#export_name("strategyFixtureSgaSubset")
pub fn strategy_fixture_sga_subset(
  f : StrategyFixture,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue] {
  let generated = Array::makei(@strategy.graph_task_count(f.graph) - 1, i => {
    fixture_generated(
      @strategy.graph_task_owner(f.graph, i + 1).unwrap(),
      f.registry_json,
      f.values_json,
      f.fragment_json,
      true,
    ) catch {
      _ => abort("invalid SGA fixture generation")
    }
  })
  let execution : @execution.SequenceExecutionLimits = {
    rows: {
      max_rows: 100,
      metadata_entries: 10000,
      retained_entries: 10000,
      operation_entries: 10000,
      input_values: {
        max_nodes: 10000,
        max_text_bytes: 10000,
        max_depth: 100,
        max_work: 100000,
      },
      output_values: {
        max_nodes: 10000,
        max_text_bytes: 10000,
        max_depth: 100,
        max_work: 100000,
      },
    },
    max_work: 100000,
    max_frames: 100,
  }
  let provider = @local_sga_provider.provider(
    {
      max_input_rows: 100,
      max_nodes: 100,
      max_edges: 100,
      max_value_bytes: 10000,
      max_total_value_bytes: 100000,
      max_retained_value_bytes: 100000,
      max_value_nodes: 10000,
      max_value_depth: 100,
      max_contract_work: 10000,
      max_work: 100000,
      max_workspace_slots: 10000,
    },
    100000L,
    @execution.generated_sequence_capacity(generated[1], execution, {
      max_work: 10000,
      max_bytes: 10000,
      max_nodes: 10000,
      max_depth: 100,
    }).unwrap(),
  )
  if !@local_connector.managed_provider_accepts(provider, generated[1]) {
    abort("SGA fixture provider rejected its graph sequence")
  }
  @conformance.configure_subset(f.run.unwrap(), generated, 0, managed_providers=[
    provider,
  ])
}
