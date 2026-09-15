///|
/// Two pure entrypoints from one installed Compute bundle. Neither constructs
/// completion evidence nor bypasses the driver's ownership/resource boundaries.
pub(all) struct ComputeContribution[C, E] {
  prepare : (C, Int, @strategy.StrategyRevision, @connector.FixedComputeRequest) -> Result[
    DispatchWork,
    E,
  ]
  propose : (Unit, Int, TaskEstimateQuantities) -> Result[
    Array[@strategy.TaskOffer],
    E,
  ]
}
