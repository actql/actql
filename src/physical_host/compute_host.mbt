///|
/// Fixed implementation installation, dispatch ownership and optional adaptive
/// policy for a serial completed-input Compute Host. Connector configuration and
/// typed execution channels remain with their implementations.
struct ComputeHost[C, E] {
  driver : DispatchDriver
  registry : @connector.CapabilityRegistry
  contributions : @connector.CapabilityImplementations[
    ComputeContribution[C, E],
  ]
  dispatch : DispatchHost[C, E]
  mut estimates : AdaptiveDispatch[E]?
}

///|
pub(all) enum ComputeHostIssue[E] {
  ForeignInstallation
  Installation(@connector.CapabilityInstallationIssue)
  Dispatch(InstalledDispatchIssue[E])
  Estimate(AdaptiveEstimateIssue[E])
}

///|
pub fn[C, E] open_compute_host(
  driver : DispatchDriver,
  registry : @connector.CapabilityRegistry,
  contributions : @connector.CapabilityImplementations[
    ComputeContribution[C, E],
  ],
  capacity : @connector.FixedComputeCapacity,
  max_entries : Int,
  max_name_bytes : Int,
  max_implementations : Int,
) -> Result[ComputeHost[C, E], ComputeHostIssue[E]] {
  if !physical_equal(
      registry,
      @connector.capability_implementations_registry(contributions),
    ) {
    return Err(ForeignInstallation)
  }
  let preparations = match
    @connector.project_capability_implementations(
      contributions,
      entry => entry.prepare,
      max_implementations,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Installation(issue))
  }
  let dispatch = match
    open_dispatch_host(
      driver, preparations, capacity, max_entries, max_name_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Dispatch(Dispatch(issue)))
  }
  Ok({ driver, registry, contributions, dispatch, estimates: None, })
}

///|
/// Opaque dispatch ownership for the connector's typed channel consumption.
pub fn[C, E] compute_host_dispatch(
  host : ComputeHost[C, E],
) -> DispatchHost[C, E] {
  host.dispatch
}

///|
/// Common bounded metadata budget used while deriving per-task managed
/// obligations. Connector bridges must not replace it with a private limit.
pub fn[C, E] compute_host_max_entries(host : ComputeHost[C, E]) -> Int {
  host.dispatch.max_entries
}

///|
pub fn[C, E] compute_host_has_estimates(host : ComputeHost[C, E]) -> Bool {
  host.estimates is Some(_)
}

///|
pub fn[C, E] configure_compute_host_estimates(
  host : ComputeHost[C, E],
  output_rows_per_mille : Array[Int?],
  limits : @strategy.SearchLimits,
  estimate_work : Int,
) -> Result[Unit, AdaptiveEstimateIssue[E]] {
  if host.estimates is Some(_) {
    return Err(InvalidConfiguration)
  }
  let proposals = match
    @connector.project_capability_implementations(
      host.contributions,
      entry => entry.propose,
      limits.max_offers,
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidConfiguration)
  }
  let policy = match
    open_adaptive_dispatch(
      host.driver,
      host.registry,
      proposals,
      output_rows_per_mille,
      limits,
      estimate_work,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  host.estimates = Some(policy)
  Ok(())
}

///|
pub fn[C, E] refresh_compute_host(
  host : ComputeHost[C, E],
) -> Result[Unit, AdaptiveEstimateIssue[E]] {
  guard host.estimates is Some(policy) else { return Ok(()) }
  refresh_adaptive_dispatch(policy)
}

///|
/// The environment performs policy I/O after receiving this bounded choice
/// set. The selected candidate still passes the common Run and dispatch checks.
pub fn[C, E] prepare_compute_host_policy_choice(
  host : ComputeHost[C, E],
) -> Result[@strategy.StrategyChoiceSet?, AdaptiveEstimateIssue[E]] {
  guard host.estimates is Some(policy) else { return Err(InvalidConfiguration) }
  prepare_adaptive_policy_choice(policy)
}

///|
pub fn[C, E] compute_host_policy_search_diagnostics(
  host : ComputeHost[C, E],
) -> @strategy.StrategySearchDiagnostics? {
  host.estimates.bind(policy => adaptive_policy_search_diagnostics(policy))
}

///|
pub fn[C, E] commit_compute_host_policy_choice(
  host : ComputeHost[C, E],
  position : Int?,
) -> Result[Unit, AdaptiveEstimateIssue[E]] {
  guard host.estimates is Some(policy) else { return Err(InvalidConfiguration) }
  commit_adaptive_policy_choice(policy, position)
}

///|
pub fn[C, E] commit_compute_host_policy_decision(
  host : ComputeHost[C, E],
  request : @strategy.PolicyRequest,
  response : @strategy.PolicyResponse,
  now_ms : Int64,
) -> Result[Unit, AdaptiveEstimateIssue[E]] {
  guard host.estimates is Some(policy) else { return Err(InvalidConfiguration) }
  commit_adaptive_policy_decision(policy, request, response, now_ms)
}

///|
/// Receive one authenticated policy response through the public wire contract.
/// Peer authentication and transport replay defense belong to the Host adapter.
pub fn[C, E] commit_compute_host_policy_response_json(
  host : ComputeHost[C, E],
  request : @strategy.PolicyRequest,
  body : String,
  authenticated_policy_id : String,
  now_ms : Int64,
) -> Result[Unit, AdaptiveEstimateIssue[E]] {
  guard host.estimates is Some(policy) else { return Err(InvalidConfiguration) }
  commit_adaptive_policy_response_json(
    policy, request, body, authenticated_policy_id, now_ms,
  )
}

///|
pub fn[C, E] prepare_compute_host_policy_request(
  host : ComputeHost[C, E],
  request_id : String,
  run_identity : String,
  authority : String,
  deadline_ms : Int64,
  now_ms : Int64,
) -> Result[@strategy.PolicyRequest, AdaptiveEstimateIssue[E]] {
  guard host.estimates is Some(policy) else { return Err(InvalidConfiguration) }
  prepare_adaptive_policy_request(
    policy, request_id, run_identity, authority, deadline_ms, now_ms,
  )
}

///|
pub fn[C, E] compute_host_policy_candidates(
  host : ComputeHost[C, E],
) -> @strategy.PolicyCandidateSet? {
  host.estimates.bind(policy => adaptive_policy_candidates(policy))
}

///|
pub fn[C, E] prepare_next_compute_task(
  host : ComputeHost[C, E],
  context : C,
) -> Result[PreparedTaskDispatch?, ComputeHostIssue[E]] {
  match check_dispatch_idle(host.driver) {
    Ok(_) => ()
    Err(issue) => return Err(Dispatch(Dispatch(issue)))
  }
  match refresh_compute_host(host) {
    Ok(_) => ()
    Err(issue) => return Err(Estimate(issue))
  }
  prepare_next_installed_task(host.dispatch, context).map_err(issue => {
    Dispatch(issue)
  })
}
