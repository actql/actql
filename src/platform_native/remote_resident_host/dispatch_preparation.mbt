///|
// Prepare the actual Local and Native modules against the selected immutable
// graph before acquiring a Source or borrowing a retained destination. The
// existing caller owns its original Ledger and full generated sequence array;
// this is configuration DATA, not another Run, permission or cleanup owner.
fn prepare_resident_compute_dispatch(
  prepared : ResidentSourceOwner,
  graph : @strategy.CheckedDAG,
  configuration : ResidentSourceComputeConfiguration,
  ledger : @resources.Ledger,
  generated : Array[@execution.GeneratedSequence],
) -> Result[
  (
    @standard.StrategyDispatchPreparation,
    Array[@standard.DispatchEstimateProfile],
  ),
  ResidentSourceComputeIssue,
] {
  let original_graph = resident_source_owner_graph(prepared)
  // A single trusted profile applies uniformly; otherwise each original
  // Compute task must have its own profile, with none silently ignored.
  if generated.length() != @strategy.graph_task_count(original_graph) ||
    (
      configuration.estimates.length() != 1 &&
      configuration.estimates.length() !=
      @strategy.graph_task_count(original_graph) - 1
    ) {
    return Err(UnsupportedGraph)
  }
  let selected : Array[@execution.GeneratedSequence] = []
  let estimates : Array[@standard.DispatchEstimateProfile] = []
  for task in 1..<@strategy.graph_task_count(graph) {
    guard @strategy.graph_task_original_index(graph, task) is Some(original) &&
      generated.get(original) is Some(sequence) else {
      return Err(UnsupportedGraph)
    }
    let estimate = if configuration.estimates.length() == 1 {
      configuration.estimates.get(0)
    } else {
      configuration.estimates.get(original - 1)
    }
    guard estimate is Some(profile) else { return Err(UnsupportedGraph) }
    selected.push(sequence)
    estimates.push(profile)
  }
  let registry = @connector.prepare_capability_registry(
    [
      { name: "local", acquisition: false, fixed_compute: true, effect: false, },
      {
        name: "duckdb",
        acquisition: false,
        fixed_compute: true,
        effect: false,
      },
    ],
    2,
    100,
  ).unwrap()
  @standard.prepare_strategy_dispatch(
    graph,
    ledger,
    registry,
    @connector.capability_registration_at(registry, 0).unwrap(),
    @connector.capability_registration_at(registry, 1).unwrap(),
    selected,
    configuration.dispatch,
  )
  .map(value => (value, estimates))
  .map_err(issue => Dispatch(issue))
}
