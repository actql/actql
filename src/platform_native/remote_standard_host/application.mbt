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
/// Physical persistence failures for one already admitted remote output.
/// Result-occurrence and publication-policy admission happen before this
/// boundary; this type keeps physical source and destination cleanup owners
/// attached to the failed copy without changing publication state.
pub(all) enum NativeRemoteStandardPayloadIssue {
  InvalidBinding
  Runtime(@runtime.NativeRemoteRuntimeIssue)
  Store(@publication_store.NativePublicationStoreIssue)
}

///|
/// A failed Site-to-publication-Store stream. Cleanup retry never reopens the
/// output reader or retries publication; it only stops the exact source and
/// destination owners retained by the failed physical occurrence.
struct NativeRemoteStandardPayloadFailure {
  issue : NativeRemoteStandardPayloadIssue
  mut reader : @runtime.NativeRemoteOutputReader?
  mut writer : @publication_store.PayloadWriter?
  mut store_recovery : @publication_store.PayloadCleanupOwner?
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
pub fn native_remote_standard_payload_failure_issue(
  failure : NativeRemoteStandardPayloadFailure,
) -> NativeRemoteStandardPayloadIssue {
  failure.issue
}

///|
pub fn native_remote_standard_payload_failure_cleanup_pending(
  failure : NativeRemoteStandardPayloadFailure,
) -> Bool {
  failure.reader is Some(_) ||
  failure.writer is Some(_) ||
  failure.store_recovery is Some(_)
}

///|
/// Retry only the physical owners retained by a failed payload stream.
pub fn retry_native_remote_standard_payload_failure_cleanup(
  failure : NativeRemoteStandardPayloadFailure,
) -> Bool {
  match failure.reader {
    Some(reader) =>
      match reader.close() {
        Ok(_) => failure.reader = None
        Err(_) => ()
      }
    None => ()
  }
  match failure.writer {
    Some(writer) =>
      match writer.cancel() {
        Ok(_) => failure.writer = None
        Err(_) => ()
      }
    None => ()
  }
  if failure.writer is None {
    match failure.store_recovery {
      Some(owner) =>
        match owner.retry() {
          Ok(_) => failure.store_recovery = None
          Err(_) => ()
        }
      None => ()
    }
  }
  !native_remote_standard_payload_failure_cleanup_pending(failure)
}

///|
fn failed_payload_stream(
  issue : NativeRemoteStandardPayloadIssue,
  reader : @runtime.NativeRemoteOutputReader?,
  writer : @publication_store.PayloadWriter?,
  store : @publication_store.Store?,
  request : @payload.PublicationPayloadRequest?,
) -> NativeRemoteStandardPayloadFailure {
  let failure : NativeRemoteStandardPayloadFailure = {
    issue,
    reader,
    writer,
    store_recovery: None,
  }
  let acquire_store_recovery = fn() {
    guard failure.store_recovery is None else { return }
    guard store is Some(owner) else { return }
    guard request is Some(exact) else { return }
    match owner.acquire_payload_cleanup(exact) {
      Ok(cleanup) => failure.store_recovery = Some(cleanup)
      Err(_) => ()
    }
  }
  match issue {
    Store(@publication_store.CleanupPending) => acquire_store_recovery()
    _ => ()
  }
  match failure.reader {
    Some(owner) =>
      match owner.close() {
        Ok(_) => failure.reader = None
        Err(_) => ()
      }
    None => ()
  }
  match failure.writer {
    Some(owner) =>
      match owner.cancel() {
        Ok(_) => failure.writer = None
        Err(_) => acquire_store_recovery()
      }
    None => ()
  }
  failure
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
/// Inspect the exact immutable output facts selected by a durable dispatch
/// observation. This does not open a physical reader or grant byte access.
pub fn NativeRemoteStandardSiteComponent::inspect_observed_output_facts(
  self : NativeRemoteStandardSiteComponent,
  request : @remote.DispatchRequest,
  completion : @runtime.NativeRemoteRuntimeCompletion,
) -> Result[
  @runtime.NativeRemoteOutputFacts,
  NativeRemoteStandardSiteComponentIssue,
] {
  if self.closed ||
    completion.dispatch_request_cid !=
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
  .inspect_output_facts(request, projection[1])
  .map_err(issue => Runtime(issue))
}

///|
/// Reconcile one retained completion from the exact durable Site observation.
/// The environment cannot manufacture evidence or material identities here.
pub fn NativeRemoteStandardSiteComponent::observed_completion(
  self : NativeRemoteStandardSiteComponent,
  request : @remote.DispatchRequest,
) -> Result[
  @runtime.NativeRemoteRuntimeCompletion,
  NativeRemoteStandardSiteComponentIssue,
] {
  if self.closed {
    return Err(Closed)
  }
  let observed = match self.journal.observation(request) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  let completion = match self.runtime.observed_completion(request) {
    Ok(value) => value
    Err(issue) => return Err(Runtime(issue))
  }
  let record = @journal.recovered_site_dispatch_record(observed)
  if !@remote.dispatch_record_matches_request(record, request) ||
    @remote.dispatch_record_revision(record) != completion.revision {
    return Err(Runtime(@runtime.OutputReaderUnavailable))
  }
  Ok(completion)
}

///|
/// Stream one exact observed output into the native publication Store. The
/// caller supplies a payload request already admitted by common publication
/// control; this boundary checks every physical and logical representation
/// binding available in the durable Site observation before opening a writer.
/// It does not commit a Result Manifest or a public index.
pub fn NativeRemoteStandardSiteComponent::persist_observed_output_payload(
  self : NativeRemoteStandardSiteComponent,
  request : @remote.DispatchRequest,
  completion : @runtime.NativeRemoteRuntimeCompletion,
  payload_request : @payload.PublicationPayloadRequest,
  store : @publication_store.Store,
  max_chunk_bytes : Int,
) -> Result[
  @publication_store.NativePublicationPayloadInfo,
  NativeRemoteStandardPayloadFailure,
] {
  if self.closed || max_chunk_bytes < 1 {
    return Err(failed_payload_stream(InvalidBinding, None, None, None, None))
  }
  let reader = match
    self.open_observed_output_reader(request, completion, max_chunk_bytes) {
    Ok(value) => value
    Err(Runtime(issue)) =>
      return Err(failed_payload_stream(Runtime(issue), None, None, None, None))
    Err(_) =>
      return Err(failed_payload_stream(InvalidBinding, None, None, None, None))
  }
  let manifest = match reader.physical_manifest() {
    Ok(value) => value
    Err(issue) =>
      return Err(
        failed_payload_stream(Runtime(issue), Some(reader), None, None, None),
      )
  }
  let material_generation = match reader.material_generation() {
    Ok(value) => value
    Err(issue) =>
      return Err(
        failed_payload_stream(Runtime(issue), Some(reader), None, None, None),
      )
  }
  if @payload.publication_payload_material_identity(payload_request) !=
    material_generation ||
    @payload.publication_payload_request_logical_relation(payload_request) !=
    manifest.view_contract_cid ||
    @payload.publication_payload_request_schema(payload_request) !=
    manifest.schema_contract_cid ||
    @payload.publication_payload_request_codec(payload_request) !=
    manifest.codec_contract_cid ||
    @payload.publication_payload_request_row_count(payload_request) !=
    manifest.row_count.to_int64() ||
    @payload.publication_payload_request_max_bytes(payload_request) !=
    manifest.referenced_bytes {
    return Err(
      failed_payload_stream(InvalidBinding, Some(reader), None, None, None),
    )
  }
  let writer = match store.begin_payload(payload_request) {
    Ok(value) => value
    Err(issue) =>
      return Err(
        failed_payload_stream(
          Store(issue),
          Some(reader),
          None,
          Some(store),
          Some(payload_request),
        ),
      )
  }
  let mut finished = false
  while !finished {
    let chunk = match reader.next() {
      Ok(value) => value
      Err(issue) =>
        return Err(
          failed_payload_stream(
            Runtime(issue),
            Some(reader),
            Some(writer),
            Some(store),
            Some(payload_request),
          ),
        )
    }
    match writer.append(chunk.bytes) {
      Ok(_) => ()
      Err(issue) =>
        return Err(
          failed_payload_stream(
            Store(issue),
            Some(reader),
            Some(writer),
            Some(store),
            Some(payload_request),
          ),
        )
    }
    finished = chunk.eof
  }
  match reader.finish() {
    Ok(_) => ()
    Err(issue) =>
      return Err(
        failed_payload_stream(
          Runtime(issue),
          Some(reader),
          Some(writer),
          Some(store),
          Some(payload_request),
        ),
      )
  }
  let payload = match writer.seal() {
    Ok(value) => value
    Err(issue) =>
      return Err(
        failed_payload_stream(
          Store(issue),
          None,
          Some(writer),
          Some(store),
          Some(payload_request),
        ),
      )
  }
  if payload.material_generation_cid != material_generation ||
    payload.logical_relation_cid != manifest.view_contract_cid ||
    payload.result_schema_cid != manifest.schema_contract_cid ||
    payload.durable_codec_cid != manifest.codec_contract_cid ||
    payload.row_count != manifest.row_count.to_int64() ||
    payload.generation.size != manifest.referenced_bytes {
    let cleanup = match store.reclaim_payload(material_generation) {
      Ok(_) => None
      Err(_) =>
        match store.acquire_payload_cleanup(payload_request) {
          Ok(owner) => Some(owner)
          Err(_) => None
        }
    }
    return Err({
      issue: InvalidBinding,
      reader: None,
      writer: None,
      store_recovery: cleanup,
    })
  }
  Ok(payload)
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
/// Acknowledge one canonical physical output result through the same
/// authenticated control channel that delivered its exact output intent.
pub fn NativeRemoteStandardSiteComponent::acknowledge_output_result(
  self : NativeRemoteStandardSiteComponent,
  result : @remote.RemoteOutputResult,
) -> Result[Unit, NativeRemoteStandardSiteComponentIssue] {
  if self.closed {
    return Err(Closed)
  }
  @client.acknowledge_output_result(self.client, self.observation_url, result).map_err(issue => {
      Agent(@agent.Client(issue))
    },
  )
}

///|
pub fn NativeRemoteStandardSiteDistribution::acknowledge_output_result(
  self : NativeRemoteStandardSiteDistribution,
  result : @remote.RemoteOutputResult,
) -> Result[Unit, NativeRemoteStandardSiteDistributionIssue] {
  if self.closed {
    return Err(Closed)
  }
  self.component
  .acknowledge_output_result(result)
  .map_err(issue => Component(issue))
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
/// Inspect output metadata through the process-owned distribution without
/// creating a physical reader or exposing runtime owner selection.
pub fn NativeRemoteStandardSiteDistribution::inspect_observed_output_facts(
  self : NativeRemoteStandardSiteDistribution,
  request : @remote.DispatchRequest,
  completion : @runtime.NativeRemoteRuntimeCompletion,
) -> Result[
  @runtime.NativeRemoteOutputFacts,
  NativeRemoteStandardSiteDistributionIssue,
] {
  if self.closed {
    return Err(Closed)
  }
  self.component
  .inspect_observed_output_facts(request, completion)
  .map_err(issue => Component(issue))
}

///|
/// Reconcile a retained completion through the process-owned distribution.
pub fn NativeRemoteStandardSiteDistribution::observed_completion(
  self : NativeRemoteStandardSiteDistribution,
  request : @remote.DispatchRequest,
) -> Result[
  @runtime.NativeRemoteRuntimeCompletion,
  NativeRemoteStandardSiteDistributionIssue,
] {
  if self.closed {
    return Err(Closed)
  }
  self.component.observed_completion(request).map_err(issue => Component(issue))
}

///|
/// Persist an observed output without routing its bytes through Coordinator
/// memory. Publication admission and public-index commit remain separate.
pub fn NativeRemoteStandardSiteDistribution::persist_observed_output_payload(
  self : NativeRemoteStandardSiteDistribution,
  request : @remote.DispatchRequest,
  completion : @runtime.NativeRemoteRuntimeCompletion,
  payload_request : @payload.PublicationPayloadRequest,
  store : @publication_store.Store,
  max_chunk_bytes : Int,
) -> Result[
  @publication_store.NativePublicationPayloadInfo,
  NativeRemoteStandardPayloadFailure,
] {
  if self.closed {
    return Err(failed_payload_stream(InvalidBinding, None, None, None, None))
  }
  self.component.persist_observed_output_payload(
    request, completion, payload_request, store, max_chunk_bytes,
  )
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
