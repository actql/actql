///|
pub(all) enum ComputeDiagnosticsIssue {
  InvalidLimits
  Unavailable
  Limit
  InvalidTask
}

///|
/// The existing failed policy's original task, retained before its driver
/// stopped. No task is inferred from a stopped DAG or a caller's error shape.
/// Preserve its actual typed issue as well. A failed estimate need not have
/// reached search, so a previous strategy report is not this failure's report.
pub fn[C, E] compute_host_original_estimate_failure(
  host : ComputeHost[C, E],
) -> (Int, AdaptiveEstimateIssue[E])? {
  guard host.estimates is Some(policy) &&
    policy.failure is Some(issue) &&
    policy.seen is Some((task, _, _)) else {
    return None
  }
  Some((task, issue))
}

///|
/// Read-only explanation from the fixed installation. Labels and reasons are
/// opaque diagnostics, never capability matching, dispatch or success evidence.
/// The inspection allowance bounds registration visits and returned entries.
pub fn[C, E] compute_host_exclusions(
  host : ComputeHost[C, E],
  max_work : Int,
) -> Result[Array[(Int, String, String)], ComputeDiagnosticsIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  guard @connector.capability_implementation_registrations(
      host.contributions,
      max_work,
    )
    is Some(registrations) else {
    return Err(Unavailable)
  }
  let task_count = @strategy.graph_task_count(
    @strategy.captured_dag_graph(dispatch_driver_run(host.driver)),
  )
  let mut remaining = max_work - registrations.length()
  let result = []
  for registration in registrations {
    guard @connector.capability_implementation(host.contributions, registration)
      is Some(entry) else {
      return Err(Unavailable)
    }
    guard (entry.exclusions)(remaining) is Some(exclusions) else {
      return Err(Limit)
    }
    if @connector.capability_implementation(host.contributions, registration)
      is None {
      return Err(Unavailable)
    }
    if exclusions.length() > remaining {
      return Err(Limit)
    }
    for item in exclusions {
      if item.0 < 1 || item.0 >= task_count {
        return Err(InvalidTask)
      }
      result.push(item)
    }
    remaining -= exclusions.length()
  }
  Ok(result)
}
