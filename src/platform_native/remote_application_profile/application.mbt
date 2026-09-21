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
/// Composition failures keep task registration distinct from process-owned
/// Site distribution failures.
pub(all) enum NativeRemoteApplicationSiteIssue {
  Host(@remote_standard.NativeRemoteStandardHostIssue)
  Distribution(@remote_standard.NativeRemoteStandardSiteDistributionIssue)
  TransferJournalClose
}

///|
/// Complete process owner for one Store-input application Site. The standard
/// distribution must release runtime, bundle, dispatch-journal, and transport
/// authority before the transferred-input journal can close.
struct NativeRemoteApplicationSite {
  distribution : @remote_standard.NativeRemoteStandardSiteDistribution
  transfer_journal : @transfer_journal.Journal
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
    distribution,
    transfer_journal,
    distribution_closed: false,
    transfer_journal_closed: false,
    closed: false,
  })
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
/// Closes every process owner in authority order. A failed close is retryable
/// on this same value and never advances to the transferred-input journal
/// while the standard runtime still owns work.
pub fn NativeRemoteApplicationSite::close(
  self : NativeRemoteApplicationSite,
) -> Result[Bool, NativeRemoteApplicationSiteIssue] {
  if self.closed {
    return Ok(false)
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
