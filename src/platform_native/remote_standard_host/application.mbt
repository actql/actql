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
/// Complete physical owner for one standard native Site process. Application
/// code supplies exact task factories at construction time, then this owner
/// fixes runtime progression and the shutdown order of every process-scoped
/// adapter used by the component.
struct NativeRemoteStandardSiteDistribution {
  component : NativeRemoteStandardSiteComponent
  journal : @journal.Journal
  bundles : @bundle.NativeRuntimeBundleStore
  client : @http.Client
  mut runtime_closed : Bool
  mut bundles_closed : Bool
  mut journal_closed : Bool
  mut client_closed : Bool
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
  Journal(@journal.NativeRemoteJournalIssue)
  Transfer(@transfer_client.NativeRemoteTransferClientIssue)
  TransferSend(@transfer_client.NativeRemoteTransferSendFailure)
}

///|
/// Process-owned composition failures keep common runtime progression and
/// physical adapter shutdown distinct.
pub(all) enum NativeRemoteStandardSiteDistributionIssue {
  Closed
  Component(NativeRemoteStandardSiteComponentIssue)
  Bundle(@bundle.NativeRuntimeBundleStoreIssue)
  JournalClose
  ClientClose
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
/// Opens the process-owned standard Site distribution. On success the
/// distribution, rather than application composition, owns shutdown of the
/// runtime and every physical adapter passed here.
pub fn open_native_remote_standard_site_distribution(
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
  NativeRemoteStandardSiteDistribution,
  NativeRemoteStandardSiteDistributionIssue,
] {
  let component = match
    open_native_remote_standard_site_component(
      site, active_runtime, operation_capability_cid, issuer_capability_cid, tasks,
      journal, bundles, budgets, client, poll_url, observation_url,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Component(issue))
  }
  Ok({
    component,
    journal,
    bundles,
    client,
    runtime_closed: false,
    bundles_closed: false,
    journal_closed: false,
    client_closed: false,
    closed: false,
  })
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
/// Opens the output established by one exact dispatch observation. The
/// durable Site journal remains authoritative for the material binding; the
/// environment does not project or reconstruct a generation from response
/// text.
pub fn NativeRemoteStandardSiteComponent::open_observed_output_reader(
  self : NativeRemoteStandardSiteComponent,
  request : @remote.DispatchRequest,
  completion : @runtime.NativeRemoteRuntimeCompletion,
  max_chunk_bytes : Int,
) -> Result[
  @runtime.NativeRemoteOutputReader,
  NativeRemoteStandardSiteComponentIssue,
] {
  if self.closed {
    return Err(Closed)
  }
  if completion.dispatch_request_cid !=
    @remote.dispatch_request_identity(request) {
    return Err(Runtime(@runtime.OutputReaderUnavailable))
  }
  let observed = match self.journal.observation(request) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  guard @journal.recovered_site_dispatch_subject(observed) is Some(subject) else {
    return Err(Runtime(@runtime.OutputReaderUnavailable))
  }
  if !@remote.remote_managed_output_subject_matches_dispatch(subject, request) ||
    @remote.remote_managed_output_subject_cid(subject) != completion.subject_cid {
    return Err(Runtime(@runtime.OutputReaderUnavailable))
  }
  let projection = @remote.remote_managed_output_subject_projection(subject)
  if projection.length() < 2 {
    return Err(Runtime(@runtime.OutputReaderUnavailable))
  }
  self.open_output_reader(request, projection[1], max_chunk_bytes)
}

///|
/// Open a manifest-preserving reader from an exact durable dispatch
/// observation. This is the source boundary for an independent Transfer; it
/// grants no destination authority by itself.
pub fn NativeRemoteStandardSiteComponent::open_observed_output_manifest_reader(
  self : NativeRemoteStandardSiteComponent,
  request : @remote.DispatchRequest,
  completion : @runtime.NativeRemoteRuntimeCompletion,
  max_chunk_bytes : Int,
) -> Result[
  @runtime.NativeRemoteOutputManifestReader,
  NativeRemoteStandardSiteComponentIssue,
] {
  if self.closed {
    return Err(Closed)
  }
  if completion.dispatch_request_cid !=
    @remote.dispatch_request_identity(request) {
    return Err(Runtime(@runtime.OutputReaderUnavailable))
  }
  let observed = match self.journal.observation(request) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  guard @journal.recovered_site_dispatch_subject(observed) is Some(subject) else {
    return Err(Runtime(@runtime.OutputReaderUnavailable))
  }
  if !@remote.remote_managed_output_subject_matches_dispatch(subject, request) ||
    @remote.remote_managed_output_subject_cid(subject) != completion.subject_cid {
    return Err(Runtime(@runtime.OutputReaderUnavailable))
  }
  let projection = @remote.remote_managed_output_subject_projection(subject)
  if projection.length() < 2 {
    return Err(Runtime(@runtime.OutputReaderUnavailable))
  }
  self.runtime
  .open_output_manifest_reader(request, projection[1], max_chunk_bytes)
  .map_err(issue => Runtime(issue))
}

///|
fn NativeRemoteStandardSiteComponent::open_observed_transfer_source(
  self : NativeRemoteStandardSiteComponent,
  dispatch : @remote.DispatchRequest,
  completion : @runtime.NativeRemoteRuntimeCompletion,
  transfer : @transfer.RemoteTransferRequest,
  max_chunk_bytes : Int,
) -> Result[
  @transfer_client.NativeRemoteTransferChunkSource,
  NativeRemoteStandardSiteComponentIssue,
] {
  let dispatch_key = @remote.dispatch_request_journal_key(dispatch)
  let transfer_projection = @transfer.request_projection(transfer)
  if dispatch_key.length() != 7 ||
    transfer_projection.length() != 13 ||
    transfer_projection[2] != dispatch_key[1] ||
    transfer_projection[3] != dispatch_key[2] {
    return Err(Transfer(@transfer_client.InvalidRequest))
  }
  let reader = match
    self.open_observed_output_manifest_reader(
      dispatch, completion, max_chunk_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let manifest = match reader.physical_manifest() {
    Ok(value) => value
    Err(issue) => {
      ignore(reader.close())
      return Err(Runtime(issue))
    }
  }
  let material_generation = match reader.material_generation() {
    Ok(value) => value
    Err(issue) => {
      ignore(reader.close())
      return Err(Runtime(issue))
    }
  }
  if transfer_projection[6] != material_generation ||
    transfer_projection[7] != @manifest.manifest_cid(manifest) {
    ignore(reader.close())
    return Err(Transfer(@transfer_client.SourceMismatch))
  }
  match
    @transfer_client.prepare_transfer_chunk_source(
      material_generation,
      @manifest.manifest_cid(manifest),
      index => {
        match reader.next() {
          Ok(Some(chunk)) if chunk.index == index => Ok(chunk.bytes)
          Ok(_) => Err("manifest-reader-order")
          Err(_) => Err("manifest-reader-read")
        }
      },
      () => reader.finish().map(_ => ()).map_err(_ => "manifest-reader-finish"),
      () => reader.close().map(_ => ()).map_err(_ => "manifest-reader-close"),
    ) {
    Ok(value) => Ok(value)
    Err(issue) => {
      ignore(reader.close())
      Err(Transfer(issue))
    }
  }
}

///|
/// Streams one exact observed output through the durable direct route. The
/// common runtime reader pin remains owned by the returned failure until
/// physical stop is confirmed.
pub fn NativeRemoteStandardSiteComponent::send_observed_output_direct(
  self : NativeRemoteStandardSiteComponent,
  transfer_journal : @transfer_journal.Journal,
  origin : String,
  dispatch : @remote.DispatchRequest,
  completion : @runtime.NativeRemoteRuntimeCompletion,
  transfer : @transfer.RemoteTransferRequest,
  max_chunk_bytes : Int,
) -> Result[
  @transfer.RemoteTransferRecord,
  NativeRemoteStandardSiteComponentIssue,
] {
  if self.closed {
    return Err(Closed)
  }
  let source = match
    self.open_observed_transfer_source(
      dispatch, completion, transfer, max_chunk_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match
    @transfer_client.send_durable_direct_transfer_from_source(
      transfer_journal,
      self.client,
      origin,
      transfer,
      source,
    ) {
    Ok(record) => Ok(record)
    Err(failure) => Err(TransferSend(failure))
  }
}

///|
/// Streams one exact observed output into the durable outbound-only Store
/// route without materializing the complete Result in application memory.
pub fn NativeRemoteStandardSiteComponent::send_observed_output_store(
  self : NativeRemoteStandardSiteComponent,
  transfer_journal : @transfer_journal.Journal,
  origin : String,
  dispatch : @remote.DispatchRequest,
  completion : @runtime.NativeRemoteRuntimeCompletion,
  transfer : @transfer.RemoteTransferRequest,
  max_chunk_bytes : Int,
) -> Result[
  @transfer.RemoteTransferRecord,
  NativeRemoteStandardSiteComponentIssue,
] {
  if self.closed {
    return Err(Closed)
  }
  let source = match
    self.open_observed_transfer_source(
      dispatch, completion, transfer, max_chunk_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match
    @transfer_client.send_durable_store_upload_from_source(
      transfer_journal,
      self.client,
      origin,
      transfer,
      source,
    ) {
    Ok(record) => Ok(record)
    Err(failure) => Err(TransferSend(failure))
  }
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

///|
/// Advances one authenticated occurrence through the process-owned component.
pub fn NativeRemoteStandardSiteDistribution::poll(
  self : NativeRemoteStandardSiteDistribution,
) -> Result[
  @agent.NativeRemoteAgentOutcome,
  NativeRemoteStandardSiteDistributionIssue,
] {
  if self.closed {
    return Err(Closed)
  }
  self.component.poll().map_err(issue => Component(issue))
}

///|
/// Opens a bounded output reader from the process-owned component.
pub fn NativeRemoteStandardSiteDistribution::open_output_reader(
  self : NativeRemoteStandardSiteDistribution,
  request : @remote.DispatchRequest,
  material_generation : String,
  max_chunk_bytes : Int,
) -> Result[
  @runtime.NativeRemoteOutputReader,
  NativeRemoteStandardSiteDistributionIssue,
] {
  if self.closed {
    return Err(Closed)
  }
  self.component
  .open_output_reader(request, material_generation, max_chunk_bytes)
  .map_err(issue => Component(issue))
}

///|
/// Opens a reader directly from the exact dispatch observation returned by
/// `poll`, while preserving the process-owned distribution boundary.
pub fn NativeRemoteStandardSiteDistribution::open_observed_output_reader(
  self : NativeRemoteStandardSiteDistribution,
  request : @remote.DispatchRequest,
  completion : @runtime.NativeRemoteRuntimeCompletion,
  max_chunk_bytes : Int,
) -> Result[
  @runtime.NativeRemoteOutputReader,
  NativeRemoteStandardSiteDistributionIssue,
] {
  if self.closed {
    return Err(Closed)
  }
  self.component
  .open_observed_output_reader(request, completion, max_chunk_bytes)
  .map_err(issue => Component(issue))
}

///|
/// Open the exact manifest-preserving source owned by this distribution.
pub fn NativeRemoteStandardSiteDistribution::open_observed_output_manifest_reader(
  self : NativeRemoteStandardSiteDistribution,
  request : @remote.DispatchRequest,
  completion : @runtime.NativeRemoteRuntimeCompletion,
  max_chunk_bytes : Int,
) -> Result[
  @runtime.NativeRemoteOutputManifestReader,
  NativeRemoteStandardSiteDistributionIssue,
] {
  if self.closed {
    return Err(Closed)
  }
  self.component
  .open_observed_output_manifest_reader(request, completion, max_chunk_bytes)
  .map_err(issue => Component(issue))
}

///|
pub fn NativeRemoteStandardSiteDistribution::send_observed_output_direct(
  self : NativeRemoteStandardSiteDistribution,
  transfer_journal : @transfer_journal.Journal,
  origin : String,
  dispatch : @remote.DispatchRequest,
  completion : @runtime.NativeRemoteRuntimeCompletion,
  transfer : @transfer.RemoteTransferRequest,
  max_chunk_bytes : Int,
) -> Result[
  @transfer.RemoteTransferRecord,
  NativeRemoteStandardSiteDistributionIssue,
] {
  if self.closed {
    return Err(Closed)
  }
  self.component
  .send_observed_output_direct(
    transfer_journal, origin, dispatch, completion, transfer, max_chunk_bytes,
  )
  .map_err(issue => Component(issue))
}

///|
pub fn NativeRemoteStandardSiteDistribution::send_observed_output_store(
  self : NativeRemoteStandardSiteDistribution,
  transfer_journal : @transfer_journal.Journal,
  origin : String,
  dispatch : @remote.DispatchRequest,
  completion : @runtime.NativeRemoteRuntimeCompletion,
  transfer : @transfer.RemoteTransferRequest,
  max_chunk_bytes : Int,
) -> Result[
  @transfer.RemoteTransferRecord,
  NativeRemoteStandardSiteDistributionIssue,
] {
  if self.closed {
    return Err(Closed)
  }
  self.component
  .send_observed_output_store(
    transfer_journal, origin, dispatch, completion, transfer, max_chunk_bytes,
  )
  .map_err(issue => Component(issue))
}

///|
/// Stops runtime admission before releasing its verified component holding,
/// then closes the bundle Store, dispatch journal, and HTTPS client in that
/// order. A failed step remains retryable on this exact owner; later physical
/// resources are not closed while an earlier authority still owns work.
pub fn NativeRemoteStandardSiteDistribution::close(
  self : NativeRemoteStandardSiteDistribution,
) -> Result[Bool, NativeRemoteStandardSiteDistributionIssue] {
  if self.closed {
    return Ok(false)
  }
  if !self.runtime_closed {
    match self.component.close() {
      Ok(_) => self.runtime_closed = true
      Err(issue) => return Err(Component(issue))
    }
  }
  if !self.bundles_closed {
    match self.bundles.close() {
      Ok(_) => self.bundles_closed = true
      Err(issue) => return Err(Bundle(issue))
    }
  }
  if !self.journal_closed {
    if !self.journal.close() {
      return Err(JournalClose)
    }
    self.journal_closed = true
  }
  if !self.client_closed {
    if !self.client.close() {
      return Err(ClientClose)
    }
    self.client_closed = true
  }
  self.closed = true
  Ok(true)
}
