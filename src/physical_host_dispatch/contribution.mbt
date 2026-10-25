///|
/// Pure entrypoints from one installed Compute bundle. None constructs
/// completion evidence nor bypasses the driver's ownership/resource boundaries.
pub(all) struct ComputeContribution[C, E] {
  exclusions : (Int) -> Array[(Int, String, String)]?
  prepare : (C, Int, @strategy.StrategyRevision, @connector.FixedComputeRequest) -> Result[
    DispatchWork,
    E,
  ]
  propose : (Unit, Int, TaskEstimateQuantities) -> Result[
    Array[@strategy.TaskOffer],
    E,
  ]
}
