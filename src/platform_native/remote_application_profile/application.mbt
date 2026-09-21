///|
/// One exact bounded application occurrence prepared for a native Remote Site.
/// The standard strategy Run and its Captured DAG output holdings remain one
/// owner even though remote input custody can end earlier.
struct NativeRemoteApplicationRun {
  captured : @strategy.CapturedDAG
  strategy : @native_host.NativeStandardStrategyRun
  mut outputs_closed : Bool
}

///|
/// Failures from the bounded application composition boundary. Physical
/// Connector execution still reports through the standard strategy owner.
pub(all) enum NativeRemoteApplicationRunIssue {
  InvalidConfiguration
  Ledger(@resources.LedgerIssue)
  Capture(@strategy.RunIssue)
  Strategy(@native_host.NativeStandardStrategyRunIssue)
}

///|
/// Physical execution limits fixed for every occurrence opened by one
/// application input factory. These are execution admission facts, not
/// transport hints that an environment adapter may replace per dispatch.
pub(all) struct NativeRemoteApplicationExecutionLimits {
  ledger : @resources.LedgerLimits
  native_fixed_ms : Int64
  resident : Bool
  imports : @native_host.NativeComputeImportLimits
  transfer_bytes : Int64
  execution_bytes : Int64
}

///|
/// Exact remote task identity and bounded output profile installed for one
/// application task. This does not grant execution until the runtime admits a
/// matching dispatch and active bundle binding.
pub(all) struct NativeRemoteApplicationTaskProfile {
  task_key : String
  expected_task : Int
  output : @remote_standard.NativeRemoteStandardTaskLimits
}

///|
/// Coordinator-authorized identities and bounds needed to derive physical
/// publication and Transfer requests for one observed output. The immutable
/// output binding itself always comes from the durable Site observation.
pub(all) struct NativeRemoteApplicationOutputIntent {
  store_authority_cid : String
  publication_attempt_cid : String
  result_definition_cid : String
  ordering_evidence_cid : String
  coordinator_authority : String
  transfer_attempt : String
  transfer_route : @transfer.RemoteTransferRoute
  destination_site_key : String
  destination_site_generation : Int
  transfer_max_bytes : Int64
  transfer_expires_unix_ms : Int64
  source_grant_cid : String
  destination_grant_cid : String
  route_capability_cid : String
}

///|
/// Exact admitted requests derived from one durable output observation. The
/// caller may execute them through physical adapters, but cannot replace the
/// observed generation, manifest, logical view, schema, or codec.
pub(all) struct NativeRemoteApplicationOutputPlan {
  payload : @payload.PublicationPayloadRequest
  transfer : @transfer.RemoteTransferRequest
}

///|
/// Durable physical results from one admitted output operation. Publication
/// commit and destination completion remain separate Coordinator decisions.
pub(all) struct NativeRemoteApplicationOutputResult {
  payload : @publication_store.NativePublicationPayloadInfo
  transfer : @transfer.RemoteTransferRecord
  observation : @remote.RemoteOutputResult
}

///|
/// Output planning fails before any publication writer or Transfer reader is
/// opened.
pub(all) enum NativeRemoteApplicationOutputPlanIssue {
  OutputFacts(NativeRemoteApplicationSiteIssue)
  InvalidOutputFacts
  Publication(@payload.PublicationPayloadIssue)
  Transfer(@transfer.RemoteTransferIssue)
}

///|
pub(all) enum NativeRemoteApplicationOutputIssue {
  InvalidOperation
  Observation(NativeRemoteApplicationSiteIssue)
  Plan(NativeRemoteApplicationOutputPlanIssue)
  PayloadStore(@publication_store.NativePublicationStoreIssue)
  PayloadStream(@remote_standard.NativeRemoteStandardPayloadFailure)
  Transfer(NativeRemoteApplicationSiteIssue)
  Protocol(@remote.DispatchIssue)
}

///|
pub fn native_remote_application_output_cleanup_pending(
  issue : NativeRemoteApplicationOutputIssue,
) -> Bool {
  match issue {
    PayloadStream(failure) =>
      @remote_standard.native_remote_standard_payload_failure_cleanup_pending(
        failure,
      )
    Transfer(
      Distribution(
        @remote_standard.Component(@remote_standard.TransferSend(failure))
      )
    ) => @transfer_client.transfer_send_failure_cleanup_pending(failure)
    _ => false
  }
}

///|
/// Retry only physical cleanup retained by one failed output occurrence.
/// This never repeats payload creation, Transfer, or Compute.
pub fn retry_native_remote_application_output_cleanup(
  issue : NativeRemoteApplicationOutputIssue,
) -> Bool {
  match issue {
    PayloadStream(failure) =>
      @remote_standard.retry_native_remote_standard_payload_failure_cleanup(
        failure,
      )
    Transfer(
      Distribution(
        @remote_standard.Component(@remote_standard.TransferSend(failure))
      )
    ) => @transfer_client.retry_transfer_send_failure_cleanup(failure)
    _ => false
  }
}

///|
/// Composition failures keep task registration distinct from process-owned
/// Site distribution failures.
pub(all) enum NativeRemoteApplicationSiteIssue {
  Host(@remote_standard.NativeRemoteStandardHostIssue)
  Distribution(@remote_standard.NativeRemoteStandardSiteDistributionIssue)
  OutputCleanupPending
  TransferJournalClose
}

///|
/// Complete process owner for one Store-input application Site. The standard
/// distribution must release runtime, bundle, dispatch-journal, and transport
/// authority before the transferred-input journal can close.
struct NativeRemoteApplicationSite {
  site : @site.ExecutionSite
  distribution : @remote_standard.NativeRemoteStandardSiteDistribution
  transfer_journal : @transfer_journal.Journal
  mut pending_output : NativeRemoteApplicationOutputIssue?
  mut distribution_closed : Bool
  mut transfer_journal_closed : Bool
  mut closed : Bool
}

///|
/// Fixed filenames for one bounded application definition directory. Keeping
/// names explicit lets packaging choose a layout without granting the runtime
/// an unbounded directory scan.
pub(all) struct NativeRemoteApplicationFiles {
  program : String
  environment : String
  environment_cid : String
  parameters : String
  registry : String
  values : String
  fragment : String
  query : String
  evidence : String
  two_receipt : String
}

///|
/// A physical file read failure is kept distinct from rejection by the
/// portable Program checker and application builder.
pub(all) enum NativeRemoteApplicationLoadIssue {
  File(String, @bounded_files.NativeBoundedTextIssue)
  InvalidApplication
}

///|
fn read_application_file(
  root : String,
  name : String,
  max_bytes : Int64,
  trim_newline : Bool,
) -> Result[String, NativeRemoteApplicationLoadIssue] {
  @bounded_files.read_bounded_text_file(root, name, max_bytes, trim_newline~).map_err(issue => {
      File(name, issue)
    },
  )
}

///|
/// Loads one immutable, bounded application definition and delegates all
/// syntax, checking, planning, and Connector construction to the portable
/// MoonBit application builder. File access is the only native concern here.
pub fn load_native_remote_application(
  root : String,
  files : NativeRemoteApplicationFiles,
  max_file_bytes : Int64,
  database_schema : String,
  table : String,
) -> Result[@application.Application, NativeRemoteApplicationLoadIssue] {
  if max_file_bytes <= 0L {
    return Err(InvalidApplication)
  }
  let program = match
    read_application_file(root, files.program, max_file_bytes, false) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let environment = match
    read_application_file(root, files.environment, max_file_bytes, false) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let environment_cid = match
    read_application_file(root, files.environment_cid, max_file_bytes, true) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let parameters = match
    read_application_file(root, files.parameters, max_file_bytes, false) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let registry = match
    read_application_file(root, files.registry, max_file_bytes, false) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let values = match
    read_application_file(root, files.values, max_file_bytes, false) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let fragment = match
    read_application_file(root, files.fragment, max_file_bytes, false) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let query = match
    read_application_file(root, files.query, max_file_bytes, false) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let evidence = match
    read_application_file(root, files.evidence, max_file_bytes, false) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let two_receipt = match
    read_application_file(root, files.two_receipt, max_file_bytes, false) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok(
    @application.prepare_application(
      program, environment, environment_cid, parameters, registry, values, fragment,
      query, evidence, two_receipt, database_schema, table,
    ),
  ) catch {
    _ => Err(InvalidApplication)
  }
}

///|
/// Projects the exact checked Program identity used by remote dispatch
/// admission. This does not expose or reimplement Program canonicalization in
/// an environment adapter.
pub fn native_remote_application_program_definition_cid(
  app : @application.Application,
) -> String {
  @strategy.graph_program_definition_cid(@application.application_graph(app))
}

///|
/// Projects the checked task count for configuration and diagnostics.
pub fn native_remote_application_task_count(
  app : @application.Application,
) -> Int {
  @strategy.graph_task_count(@application.application_graph(app))
}

///|
/// Opens one fresh application occurrence from an already verified physical
/// input source. Program checking and strategy construction are reused from
/// the portable application builder; this native package adds no parser,
/// planner, or completion rule.
pub fn open_native_remote_application_run(
  app : @application.Application,
  source : @query.CapturedInputSource,
  ledger_limits : @resources.LedgerLimits,
  native_fixed_ms : Int64,
  resident : Bool,
  import_limits : @native_host.NativeComputeImportLimits,
  transfer_bytes : Int64,
  execution_bytes : Int64,
  library? : @native_duckdb.Library? = None,
  database_path? : String = "",
) -> Result[NativeRemoteApplicationRun, NativeRemoteApplicationRunIssue] {
  if native_fixed_ms < 0L || transfer_bytes < 0L || execution_bytes < 0L {
    return Err(InvalidConfiguration)
  }
  let ledger = match @resources.create_ledger(ledger_limits) {
    Ok(value) => value
    Err(issue) => return Err(Ledger(issue))
  }
  let captured = match
    @strategy.open_captured_dag(
      @application.application_graph(app),
      source,
      ledger,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Capture(issue))
  }
  let dispatch = @application.application_strategy_dispatch(
    app, captured, native_fixed_ms, resident,
  ) catch {
    _ => return Err(InvalidConfiguration)
  }
  let strategy = match
    @native_host.open_native_standard_strategy_run(
      dispatch,
      import_limits,
      transfer_bytes,
      execution_bytes,
      library~,
      database_path~,
    ) {
    Ok(value) => value
    Err(issue) => {
      @strategy.stop_captured_dag(captured)
      return Err(Strategy(issue))
    }
  }
  Ok({ captured, strategy, outputs_closed: false, })
}

///|
/// Binds this exact application occurrence into the common remote standard
/// owner. The returned owner releases captured outputs after strategy stop and
/// releases the physical input independently.
pub fn bind_native_remote_application_run(
  run : NativeRemoteApplicationRun,
  finish_input_owner : () -> Bool,
) -> @remote_standard.NativeRemoteStandardRunOwner {
  @remote_standard.prepare_native_remote_standard_captured_run_owner(
    run.strategy,
    () => run.finish_outputs(),
    finish_input_owner,
  )
}

///|
/// Transfers an application occurrence and its Captured DAG output owner into
/// a Store or direct input factory. The factory adds the physical input owner
/// only after it has verified and captured the exact transferred relation.
pub fn prepare_native_remote_application_compute_owner(
  run : NativeRemoteApplicationRun,
) -> @remote_standard.NativeRemoteStandardComputeOwner {
  @remote_standard.prepare_native_remote_standard_compute_owner(run.strategy, () => {
    run.finish_outputs()
  })
}

///|
/// Registers a durable Store input factory for one exact checked
/// application. Program identity, acquisition sequence, Connector execution,
/// and Captured DAG cleanup all come from the portable application owner.
pub fn register_native_remote_application_store_run_factory(
  app : @application.Application,
  journal : @transfer_journal.Journal,
  root : @filesystem.Root,
  codec : @remote_standard.NativeRemoteStandardRowCodec,
  binding_limits : @remote_standard.NativeRemoteStandardTransferBindingLimits,
  source_limits : @remote_standard.NativeRemoteStandardTransferSourceLimits,
  execution : NativeRemoteApplicationExecutionLimits,
  library? : @native_duckdb.Library? = None,
  database_path? : String = "",
) -> Result[
  @remote_standard.NativeRemoteStandardStoreRunFactory,
  @remote_standard.NativeRemoteStandardHostIssue,
] {
  @remote_standard.register_native_remote_standard_store_run_factory(
    journal,
    root,
    codec,
    @application.application_input_sequence(app),
    @application.application_program_identity(app),
    binding_limits,
    source_limits,
    source => {
      match
        open_native_remote_application_run(
          app,
          source,
          execution.ledger,
          execution.native_fixed_ms,
          execution.resident,
          execution.imports,
          execution.transfer_bytes,
          execution.execution_bytes,
          library~,
          database_path~,
        ) {
        Ok(run) => Ok(prepare_native_remote_application_compute_owner(run))
        Err(_) => Err(())
      }
    },
  )
}

///|
/// Registers a direct-stream input factory for the same exact application
/// profile. The direct transport owns only bounded physical delivery; this
/// factory retains the checked input and execution authorities.
pub fn register_native_remote_application_direct_run_factory(
  app : @application.Application,
  codec : @remote_standard.NativeRemoteStandardRowCodec,
  binding_limits : @remote_standard.NativeRemoteStandardTransferBindingLimits,
  source_limits : @remote_standard.NativeRemoteStandardTransferSourceLimits,
  execution : NativeRemoteApplicationExecutionLimits,
  library? : @native_duckdb.Library? = None,
  database_path? : String = "",
) -> Result[
  @remote_standard.NativeRemoteStandardDirectRunFactory,
  @remote_standard.NativeRemoteStandardHostIssue,
] {
  @remote_standard.register_native_remote_standard_direct_run_factory(
    codec,
    @application.application_input_sequence(app),
    @application.application_program_identity(app),
    binding_limits,
    source_limits,
    source => {
      match
        open_native_remote_application_run(
          app,
          source,
          execution.ledger,
          execution.native_fixed_ms,
          execution.resident,
          execution.imports,
          execution.transfer_bytes,
          execution.execution_bytes,
          library~,
          database_path~,
        ) {
        Ok(run) => Ok(prepare_native_remote_application_compute_owner(run))
        Err(_) => Err(())
      }
    },
  )
}

///|
/// Opens the complete process-owned Store-input Site distribution for one
/// checked application task. Application code cannot replace the checked
/// Program, input verifier, Connector progression, output evidence, or
/// shutdown ordering after this product composition boundary returns.
pub fn open_native_remote_application_store_site_distribution(
  app : @application.Application,
  transfer_journal : @transfer_journal.Journal,
  transfer_root : @filesystem.Root,
  codec : @remote_standard.NativeRemoteStandardRowCodec,
  binding_limits : @remote_standard.NativeRemoteStandardTransferBindingLimits,
  source_limits : @remote_standard.NativeRemoteStandardTransferSourceLimits,
  execution : NativeRemoteApplicationExecutionLimits,
  task : NativeRemoteApplicationTaskProfile,
  site : @site.ExecutionSite,
  active_runtime : @bundle.NativeActiveRuntimeBinding,
  operation_capability_cid : String,
  issuer_capability_cid : String,
  journal : @journal.Journal,
  bundles : @bundle.NativeRuntimeBundleStore,
  budgets : Array[@remote.RemoteDispatchBudget],
  client : @http.Client,
  poll_url : String,
  observation_url : String,
  library? : @native_duckdb.Library? = None,
  database_path? : String = "",
) -> Result[NativeRemoteApplicationSite, NativeRemoteApplicationSiteIssue] {
  let factory = match
    register_native_remote_application_store_run_factory(
      app,
      transfer_journal,
      transfer_root,
      codec,
      binding_limits,
      source_limits,
      execution,
      library~,
      database_path~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Host(issue))
  }
  let executor = match
    @remote_standard.install_native_remote_standard_store_task_executor(
      @strategy.graph_program_definition_cid(
        @application.application_graph(app),
      ),
      task.task_key,
      task.expected_task,
      factory,
      task.output,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Host(issue))
  }
  let distribution = match
    @remote_standard.open_native_remote_standard_site_distribution(
      site,
      active_runtime,
      operation_capability_cid,
      issuer_capability_cid,
      [executor],
      journal,
      bundles,
      budgets,
      client,
      poll_url,
      observation_url,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Distribution(issue))
  }
  Ok({
    site,
    distribution,
    transfer_journal,
    pending_output: None,
    distribution_closed: false,
    transfer_journal_closed: false,
    closed: false,
  })
}

///|
/// Derive publication and Transfer requests from an exact durable output
/// observation. This performs no physical I/O and does not create a reader
/// pin. Coordinator-supplied intent cannot replace Site-owned output facts.
pub fn NativeRemoteApplicationSite::prepare_observed_output_plan(
  self : NativeRemoteApplicationSite,
  request : @remote.DispatchRequest,
  completion : @runtime.NativeRemoteRuntimeCompletion,
  intent : NativeRemoteApplicationOutputIntent,
) -> Result[
  NativeRemoteApplicationOutputPlan,
  NativeRemoteApplicationOutputPlanIssue,
] {
  let facts = match self.inspect_observed_output_facts(request, completion) {
    Ok(value) => value
    Err(issue) => return Err(OutputFacts(issue))
  }
  prepare_native_remote_application_output_plan(self.site, facts, intent)
}

///|
fn prepare_native_remote_application_output_plan(
  site : @site.ExecutionSite,
  facts : @runtime.NativeRemoteOutputFacts,
  intent : NativeRemoteApplicationOutputIntent,
) -> Result[
  NativeRemoteApplicationOutputPlan,
  NativeRemoteApplicationOutputPlanIssue,
] {
  let manifest = facts.physical_manifest
  if facts.result_schema_cid != manifest.schema_contract_cid ||
    facts.logical_view_cid != manifest.view_contract_cid ||
    facts.representation_codec_cid != manifest.codec_contract_cid ||
    facts.row_count != manifest.row_count ||
    facts.retained_bytes != manifest.referenced_bytes {
    return Err(InvalidOutputFacts)
  }
  let payload = match
    @payload.prepare_publication_payload_request(
      intent.store_authority_cid,
      intent.publication_attempt_cid,
      facts.material_generation,
      intent.result_definition_cid,
      facts.logical_view_cid,
      facts.result_schema_cid,
      intent.ordering_evidence_cid,
      facts.representation_codec_cid,
      manifest.referenced_bytes,
      manifest.row_count.to_int64(),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Publication(issue))
  }
  let transfer = match
    @transfer.prepare_request(
      intent.coordinator_authority,
      intent.transfer_attempt,
      intent.transfer_route,
      @site.site_key(site),
      @site.site_generation(site),
      intent.destination_site_key,
      intent.destination_site_generation,
      facts.material_generation,
      manifest,
      intent.transfer_max_bytes,
      intent.transfer_expires_unix_ms,
      intent.source_grant_cid,
      intent.destination_grant_cid,
      intent.route_capability_cid,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Transfer(issue))
  }
  Ok({ payload, transfer, })
}

///|
fn native_remote_application_output_intent(
  intent : @remote.RemoteOutputIntent,
) -> NativeRemoteApplicationOutputIntent {
  let projection = @remote.remote_output_intent_projection(intent)
  {
    store_authority_cid: projection.store_authority_cid,
    publication_attempt_cid: projection.publication_attempt_cid,
    result_definition_cid: projection.result_definition_cid,
    ordering_evidence_cid: projection.ordering_evidence_cid,
    coordinator_authority: projection.coordinator_authority,
    transfer_attempt: projection.transfer_attempt,
    transfer_route: projection.transfer_route,
    destination_site_key: projection.destination_site_key,
    destination_site_generation: projection.destination_site_generation,
    transfer_max_bytes: projection.transfer_max_bytes,
    transfer_expires_unix_ms: projection.transfer_expires_unix_ms,
    source_grant_cid: projection.source_grant_cid,
    destination_grant_cid: projection.destination_grant_cid,
    route_capability_cid: projection.route_capability_cid,
  }
}

///|
/// Derive the canonical physical requests for a Coordinator planning poll.
/// No publication writer, Transfer reader, or destination operation starts.
pub fn NativeRemoteApplicationSite::prepare_remote_output_plan(
  self : NativeRemoteApplicationSite,
  output : @remote.RemotePollOutput,
) -> Result[@remote.RemoteOutputPlan, NativeRemoteApplicationOutputIssue] {
  if self.closed || self.pending_output is Some(_) {
    return Err(InvalidOperation)
  }
  let request = @remote.remote_poll_output_request(output)
  let remote_intent = @remote.remote_poll_output_intent(output)
  if !@remote.remote_output_intent_matches_dispatch(remote_intent, request) {
    return Err(InvalidOperation)
  }
  let completion = match self.distribution.observed_completion(request) {
    Ok(value) => value
    Err(issue) => return Err(Observation(Distribution(issue)))
  }
  let subject = match
    self.distribution.observed_output_subject(request, completion) {
    Ok(value) => value
    Err(issue) => return Err(Observation(Distribution(issue)))
  }
  let plan = match
    self.prepare_observed_output_plan(
      request,
      completion,
      native_remote_application_output_intent(remote_intent),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Plan(issue))
  }
  @remote.prepare_remote_output_plan(
    output,
    subject,
    plan.payload,
    plan.transfer,
  ).map_err(issue => Protocol(issue))
}

///|
/// Advances one authenticated outbound operation through the exact
/// application task registry.
pub fn NativeRemoteApplicationSite::poll(
  self : NativeRemoteApplicationSite,
) -> Result[@agent.NativeRemoteAgentOutcome, NativeRemoteApplicationSiteIssue] {
  if self.closed {
    return Err(Distribution(@remote_standard.Closed))
  }
  self.distribution.poll().map_err(issue => Distribution(issue))
}

///|
/// Execute one output operation selected by the Coordinator. The Site first
/// reconciles the exact retained completion, then derives both physical
/// requests from that observation. An exact retry reuses a sealed publication
/// payload and the durable Transfer journal instead of rerunning Compute.
pub fn NativeRemoteApplicationSite::execute_output(
  self : NativeRemoteApplicationSite,
  output : @remote.RemotePollOutput,
  store : @publication_store.Store,
  max_chunk_bytes : Int,
) -> Result[
  NativeRemoteApplicationOutputResult,
  NativeRemoteApplicationOutputIssue,
] {
  if self.closed || max_chunk_bytes < 1 {
    return Err(InvalidOperation)
  }
  if self.pending_output is Some(_) {
    return Err(InvalidOperation)
  }
  let request = @remote.remote_poll_output_request(output)
  let remote_intent = @remote.remote_poll_output_intent(output)
  if !@remote.remote_output_intent_matches_dispatch(remote_intent, request) {
    return Err(InvalidOperation)
  }
  let completion = match self.distribution.observed_completion(request) {
    Ok(value) => value
    Err(issue) => return Err(Observation(Distribution(issue)))
  }
  let projection = @remote.remote_output_intent_projection(remote_intent)
  let intent = native_remote_application_output_intent(remote_intent)
  let plan = match
    self.prepare_observed_output_plan(request, completion, intent) {
    Ok(value) => value
    Err(issue) => return Err(Plan(issue))
  }
  let payload = match store.reconcile_payload(plan.payload) {
    Ok(Some(value)) => value
    Ok(None) =>
      match
        self.persist_observed_output_payload(
          request,
          completion,
          plan.payload,
          store,
          max_chunk_bytes,
        ) {
        Ok(value) => value
        Err(issue) => {
          let failure = PayloadStream(issue)
          if native_remote_application_output_cleanup_pending(failure) {
            self.pending_output = Some(failure)
          }
          return Err(failure)
        }
      }
    Err(issue) => return Err(PayloadStore(issue))
  }
  let transfer = match projection.transfer_route {
    @transfer.DirectStream =>
      self.send_observed_output_direct(
        projection.transfer_origin,
        request,
        completion,
        plan.transfer,
        max_chunk_bytes,
      )
    @transfer.TransferStore =>
      self.send_observed_output_store(
        projection.transfer_origin,
        request,
        completion,
        plan.transfer,
        max_chunk_bytes,
      )
  }
  match transfer {
    Ok(value) => {
      let observation = match
        @remote.prepare_remote_output_result(
          output,
          plan.payload,
          payload.physical_digest,
          value,
        ) {
        Ok(result) => result
        Err(issue) => return Err(Protocol(issue))
      }
      Ok({ payload, transfer: value, observation, })
    }
    Err(issue) => {
      let failure = NativeRemoteApplicationOutputIssue::Transfer(issue)
      if native_remote_application_output_cleanup_pending(failure) {
        self.pending_output = Some(failure)
      }
      Err(failure)
    }
  }
}

///|
pub fn NativeRemoteApplicationSite::output_cleanup_pending(
  self : NativeRemoteApplicationSite,
) -> Bool {
  self.pending_output is Some(issue) &&
  native_remote_application_output_cleanup_pending(issue)
}

///|
/// Post one canonical physical output result. This does not authorize source
/// release; Coordinator admission and a later exact release operation remain
/// separate.
pub fn NativeRemoteApplicationSite::acknowledge_output_result(
  self : NativeRemoteApplicationSite,
  result : NativeRemoteApplicationOutputResult,
) -> Result[Unit, NativeRemoteApplicationSiteIssue] {
  if self.closed {
    return Err(Distribution(@remote_standard.Closed))
  }
  self.distribution
  .acknowledge_output_result(result.observation)
  .map_err(issue => Distribution(issue))
}

///|
pub fn NativeRemoteApplicationSite::acknowledge_output_plan(
  self : NativeRemoteApplicationSite,
  plan : @remote.RemoteOutputPlan,
) -> Result[Unit, NativeRemoteApplicationSiteIssue] {
  if self.closed {
    return Err(Distribution(@remote_standard.Closed))
  }
  self.distribution
  .acknowledge_output_plan(plan)
  .map_err(issue => Distribution(issue))
}

///|
/// Retry the exact physical output owner retained by this Site. Completion of
/// this cleanup does not turn the failed output operation into success.
pub fn NativeRemoteApplicationSite::retry_output_cleanup(
  self : NativeRemoteApplicationSite,
) -> Bool {
  guard self.pending_output is Some(issue) else { return false }
  ignore(retry_native_remote_application_output_cleanup(issue))
  if native_remote_application_output_cleanup_pending(issue) {
    false
  } else {
    self.pending_output = None
    true
  }
}

///|
/// Opens the output fixed by a successful dispatch observation without
/// exposing physical generation selection or journal projection to the
/// executable adapter.
pub fn NativeRemoteApplicationSite::open_observed_output_reader(
  self : NativeRemoteApplicationSite,
  request : @remote.DispatchRequest,
  completion : @runtime.NativeRemoteRuntimeCompletion,
  max_chunk_bytes : Int,
) -> Result[@runtime.NativeRemoteOutputReader, NativeRemoteApplicationSiteIssue] {
  if self.closed {
    return Err(Distribution(@remote_standard.Closed))
  }
  self.distribution
  .open_observed_output_reader(request, completion, max_chunk_bytes)
  .map_err(issue => Distribution(issue))
}

///|
/// Inspect immutable output facts selected by the durable dispatch
/// observation without opening a physical reader.
pub fn NativeRemoteApplicationSite::inspect_observed_output_facts(
  self : NativeRemoteApplicationSite,
  request : @remote.DispatchRequest,
  completion : @runtime.NativeRemoteRuntimeCompletion,
) -> Result[@runtime.NativeRemoteOutputFacts, NativeRemoteApplicationSiteIssue] {
  if self.closed {
    return Err(Distribution(@remote_standard.Closed))
  }
  self.distribution
  .inspect_observed_output_facts(request, completion)
  .map_err(issue => Distribution(issue))
}

///|
/// Stream an observed output directly into the publication Store. This
/// persists only the exact admitted payload; formal Manifest and public-index
/// commit remain owned by common publication control.
pub fn NativeRemoteApplicationSite::persist_observed_output_payload(
  self : NativeRemoteApplicationSite,
  request : @remote.DispatchRequest,
  completion : @runtime.NativeRemoteRuntimeCompletion,
  payload_request : @payload.PublicationPayloadRequest,
  store : @publication_store.Store,
  max_chunk_bytes : Int,
) -> Result[
  @publication_store.NativePublicationPayloadInfo,
  @remote_standard.NativeRemoteStandardPayloadFailure,
] {
  self.distribution.persist_observed_output_payload(
    request, completion, payload_request, store, max_chunk_bytes,
  )
}

///|
/// Open the exact physical manifest source for an independent output
/// Transfer. The application owner keeps all Site and runtime custody alive
/// until this reader is finished or physically closed.
pub fn NativeRemoteApplicationSite::open_observed_output_manifest_reader(
  self : NativeRemoteApplicationSite,
  request : @remote.DispatchRequest,
  completion : @runtime.NativeRemoteRuntimeCompletion,
  max_chunk_bytes : Int,
) -> Result[
  @runtime.NativeRemoteOutputManifestReader,
  NativeRemoteApplicationSiteIssue,
] {
  if self.closed {
    return Err(Distribution(@remote_standard.Closed))
  }
  self.distribution
  .open_observed_output_manifest_reader(request, completion, max_chunk_bytes)
  .map_err(issue => Distribution(issue))
}

///|
/// Sends one exact observed application output over the direct route. The
/// Site-owned Transfer journal preserves reconciliation independently from
/// the dispatch journal and application completion.
pub fn NativeRemoteApplicationSite::send_observed_output_direct(
  self : NativeRemoteApplicationSite,
  origin : String,
  dispatch : @remote.DispatchRequest,
  completion : @runtime.NativeRemoteRuntimeCompletion,
  transfer : @transfer.RemoteTransferRequest,
  max_chunk_bytes : Int,
) -> Result[@transfer.RemoteTransferRecord, NativeRemoteApplicationSiteIssue] {
  if self.closed {
    return Err(Distribution(@remote_standard.Closed))
  }
  self.distribution
  .send_observed_output_direct(
    self.transfer_journal,
    origin,
    dispatch,
    completion,
    transfer,
    max_chunk_bytes,
  )
  .map_err(issue => Distribution(issue))
}

///|
/// Sends one exact observed application output through the outbound-only
/// Store route while retaining the same verified manifest boundaries.
pub fn NativeRemoteApplicationSite::send_observed_output_store(
  self : NativeRemoteApplicationSite,
  origin : String,
  dispatch : @remote.DispatchRequest,
  completion : @runtime.NativeRemoteRuntimeCompletion,
  transfer : @transfer.RemoteTransferRequest,
  max_chunk_bytes : Int,
) -> Result[@transfer.RemoteTransferRecord, NativeRemoteApplicationSiteIssue] {
  if self.closed {
    return Err(Distribution(@remote_standard.Closed))
  }
  self.distribution
  .send_observed_output_store(
    self.transfer_journal,
    origin,
    dispatch,
    completion,
    transfer,
    max_chunk_bytes,
  )
  .map_err(issue => Distribution(issue))
}

///|
/// Closes every process owner in authority order. A failed close is retryable
/// on this same value and never advances to the transferred-input journal
/// while the standard runtime still owns work.
pub fn NativeRemoteApplicationSite::close(
  self : NativeRemoteApplicationSite,
) -> Result[Bool, NativeRemoteApplicationSiteIssue] {
  if self.closed {
    return Ok(false)
  }
  if self.pending_output is Some(_) {
    ignore(self.retry_output_cleanup())
    if self.output_cleanup_pending() {
      return Err(OutputCleanupPending)
    }
  }
  if !self.distribution_closed {
    match self.distribution.close() {
      Ok(_) => self.distribution_closed = true
      Err(issue) => return Err(Distribution(issue))
    }
  }
  if !self.transfer_journal_closed {
    if !self.transfer_journal.close() {
      return Err(TransferJournalClose)
    }
    self.transfer_journal_closed = true
  }
  self.closed = true
  Ok(true)
}

///|
fn NativeRemoteApplicationRun::finish_outputs(
  self : NativeRemoteApplicationRun,
) -> Bool {
  if self.outputs_closed {
    return true
  }
  let graph = @strategy.captured_dag_graph(self.captured)
  for task = @strategy.graph_task_count(graph) - 1; task > 0; task = task - 1 {
    @strategy.close_captured_task_output(self.captured, task)
  }
  let usage = @resources.ledger_usage(
    @strategy.captured_dag_ledger(self.captured),
  )
  if usage.reserved_execution_bytes != 0L ||
    usage.reserved_retention_bytes != 0L ||
    usage.held_bytes != 0L {
    return false
  }
  self.outputs_closed = true
  true
}
