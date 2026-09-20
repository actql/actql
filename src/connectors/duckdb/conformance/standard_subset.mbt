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
