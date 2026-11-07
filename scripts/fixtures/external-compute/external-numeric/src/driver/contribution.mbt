///|
/// This external package intentionally depends on the public reference numeric
/// evaluator. It owns its contribution and adapter, not another evaluator.
pub(all) struct Configuration {
  numeric : @reference.NumericComputeConfiguration
}

///|
struct Contribution {
  numeric : @reference.NumericComputeContribution
}

///|
pub fn configure(
  driver : @host.DispatchDriver,
  registry : @connector.CapabilityRegistry,
  registration : @connector.CapabilityRegistration,
  configuration : Configuration,
) -> Result[Contribution, @strategy.RunIssue] {
  @reference.configure_numeric_compute(
    driver,
    registry,
    registration,
    configuration.numeric,
  ).map(numeric => { numeric, })
}

///|
pub fn registration(
  installed : Contribution,
) -> @connector.CapabilityRegistration {
  @reference.numeric_contribution_registration(installed.numeric)
}

///|
pub fn validate_binding(
  installed : Contribution,
  driver : @host.DispatchDriver,
  registry : @connector.CapabilityRegistry,
) -> Result[Unit, @strategy.RunIssue] {
  @reference.validate_numeric_contribution_binding(
    installed.numeric,
    driver,
    registry,
  )
}

///|
pub fn[E] contribution(
  installed : Contribution,
  dispatch_issue : (@strategy.RunIssue) -> E,
  estimate_issue : (@strategy.RunIssue) -> E,
) -> @host.ComputeContribution[Unit, E] {
  @reference.numeric_compute_contribution(
    installed.numeric,
    dispatch_issue,
    estimate_issue,
  )
}

///|
pub fn[C, E] dispatch(
  installed : Contribution,
  host : @host.DispatchHost[C, E],
  task : @host.PreparedTaskDispatch,
) -> Result[Unit, @strategy.RunIssue] {
  @reference.execute_numeric_contribution(installed.numeric, host, task)
}

///|
pub fn[C, E] dispatch_with_completion_admission(
  installed : Contribution,
  host : @host.DispatchHost[C, E],
  task : @host.PreparedTaskDispatch,
  completion_ready : () -> Bool,
) -> Result[Unit, @strategy.RunIssue] {
  @reference.execute_numeric_contribution_with_completion_admission(
    installed.numeric,
    host,
    task,
    completion_ready,
  )
}
