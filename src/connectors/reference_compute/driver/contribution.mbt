///|
struct NumericComputeContribution {
  installed : NumericDispatchModule
  milliseconds : Int64?
  max_work : Int
}

///|
pub fn prepare_numeric_contribution(
  installed : NumericDispatchModule,
  milliseconds : Int64?,
  max_work : Int,
) -> Result[NumericComputeContribution, @strategy.RunIssue] {
  if max_work < 1 || (milliseconds is Some(value) && value < 0L) {
    return Err(numeric_dispatch_issue(Limit))
  }
  Ok({ installed, milliseconds, max_work, })
}

///|
pub fn numeric_contribution_registration(
  configured : NumericComputeContribution,
) -> @connector.CapabilityRegistration {
  configured.installed.registration
}

///|
pub fn[E] numeric_compute_contribution(
  configured : NumericComputeContribution,
  dispatch_issue : (@strategy.RunIssue) -> E,
  estimate_issue : (@strategy.RunIssue) -> E,
) -> @host.ComputeContribution[Unit, E] {
  {
    prepare: fn(_context, task, revision, request) {
      prepare_numeric_dispatch(configured.installed, task, revision, request).map_err(
        dispatch_issue,
      )
    },
    propose: fn(_context, task, _quantities) {
      estimate_numeric_dispatch_offer(
        configured.installed,
        task,
        configured.milliseconds,
        configured.max_work,
      )
      .map(value => {
        match value {
          Some(offer) => [offer]
          None => []
        }
      })
      .map_err(estimate_issue)
    },
  }
}
