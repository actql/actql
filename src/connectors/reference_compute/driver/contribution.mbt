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
/// Consume only this configured module's exact typed dispatch channel.
pub fn[C, E] execute_numeric_contribution(
  configured : NumericComputeContribution,
  host : @host.DispatchHost[C, E],
  task : @host.PreparedTaskDispatch,
) -> Result[Unit, @strategy.RunIssue] {
  execute_numeric_dispatch(configured.installed, host, task)
}

///|
/// Node and Workers Site bridges use this path so forced Site revocation can
/// reject common completion after synchronous execution has settled.
pub fn[C, E] execute_numeric_contribution_with_completion_admission(
  configured : NumericComputeContribution,
  host : @host.DispatchHost[C, E],
  task : @host.PreparedTaskDispatch,
  completion_ready : () -> Bool,
) -> Result[Unit, @strategy.RunIssue] {
  execute_numeric_dispatch_with_completion_admission(
    configured.installed,
    host,
    task,
    completion_ready,
  )
}

///|
pub fn[E] numeric_compute_contribution(
  configured : NumericComputeContribution,
  dispatch_issue : (@strategy.RunIssue) -> E,
  estimate_issue : (@strategy.RunIssue) -> E,
) -> @host.ComputeContribution[Unit, E] {
  {
    exclusions: max_entries => if max_entries < 0 { None } else { Some([]) },
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
