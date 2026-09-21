///|
/// One standard native Site component. The exact task registry, runtime
/// bundle binding, durable journal, and outbound transport are fixed before
/// any poll occurrence can enter admission.
struct NativeRemoteStandardSiteComponent {
  runtime : @runtime.NativeRemoteRuntime
  journal : @journal.Journal
  client : @http.Client
  poll_url : String
  observation_url : String
  mut closed : Bool
}

///|
/// Component composition, outbound progression, and runtime cleanup remain
/// distinct from physical HTTP, journal, and bundle failures.
pub(all) enum NativeRemoteStandardSiteComponentIssue {
  Closed
  Host(NativeRemoteStandardHostIssue)
  Agent(@agent.NativeRemoteAgentIssue)
  Runtime(@runtime.NativeRemoteRuntimeIssue)
}

///|
/// Opens a standard Site component from one verified active runtime and an
/// exact opaque task registry. The caller supplies physical adapters, but it
/// cannot replace runtime progression after this boundary succeeds.
pub fn open_native_remote_standard_site_component(
  site : @site.ExecutionSite,
  active_runtime : @bundle.NativeActiveRuntimeBinding,
  operation_capability_cid : String,
  issuer_capability_cid : String,
  tasks : Array[NativeRemoteStandardTaskExecutor],
  journal : @journal.Journal,
  bundles : @bundle.NativeRuntimeBundleStore,
  budgets : Array[@remote.RemoteDispatchBudget],
  client : @http.Client,
  poll_url : String,
  observation_url : String,
) -> Result[
  NativeRemoteStandardSiteComponent,
  NativeRemoteStandardSiteComponentIssue,
] {
  if poll_url.is_empty() || observation_url.is_empty() {
    return Err(Host(InvalidConfiguration))
  }
  let runtime = match
    open_native_remote_standard_site_runtime(
      site, active_runtime, operation_capability_cid, issuer_capability_cid, tasks,
      journal, bundles, budgets,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Host(issue))
  }
  Ok({ runtime, journal, client, poll_url, observation_url, closed: false, })
}

///|
/// Advances one authenticated outbound occurrence through the component's
/// exact runtime. Transport acknowledgement cannot substitute another
/// runtime or task registry.
pub fn NativeRemoteStandardSiteComponent::poll(
  self : NativeRemoteStandardSiteComponent,
) -> Result[
  @agent.NativeRemoteAgentOutcome,
  NativeRemoteStandardSiteComponentIssue,
] {
  if self.closed {
    return Err(Closed)
  }
  @agent.run_native_outbound_site_occurrence(
    self.runtime,
    self.journal,
    self.client,
    self.poll_url,
    self.observation_url,
  ).map_err(issue => Agent(issue))
}

///|
/// Opens one bounded reader owned by this component's exact runtime.
pub fn NativeRemoteStandardSiteComponent::open_output_reader(
  self : NativeRemoteStandardSiteComponent,
  request : @remote.DispatchRequest,
  material_generation : String,
  max_chunk_bytes : Int,
) -> Result[
  @runtime.NativeRemoteOutputReader,
  NativeRemoteStandardSiteComponentIssue,
] {
  if self.closed {
    return Err(Closed)
  }
  self.runtime
  .open_output_reader(request, material_generation, max_chunk_bytes)
  .map_err(issue => Runtime(issue))
}

///|
/// Stops new admission and closes the common runtime. Physical adapter owners
/// remain with application composition and may be closed only after this
/// method confirms that all runtime custody has ended.
pub fn NativeRemoteStandardSiteComponent::close(
  self : NativeRemoteStandardSiteComponent,
) -> Result[Bool, NativeRemoteStandardSiteComponentIssue] {
  if self.closed {
    return Ok(false)
  }
  match self.runtime.close() {
    Ok(_) => {
      self.closed = true
      Ok(true)
    }
    Err(issue) => Err(Runtime(issue))
  }
}
