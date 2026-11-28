///|
priv enum LocalCommandFileSources {
  Original(
    Array[LocalProjectMockSourceDeclaration],
    Array[LocalProjectMockFileSource]?
  )
  Whole(LocalProjectMockSourceDeclaration, LocalProjectMockRowBinding)
  Query(Array[@local_host.NativeRelationFileQuerySource])
  WholeSet(Array[@local_host.NativeRelationFileWholeSource])
}

///|
// One retained selection, prepared before the first durable Submission action.
// The existing Owners still admit the input, Program, Account and physical
// execution independently. Recovery never constructs this fresh selection.
priv struct LocalCommandBusinessPreparation {
  original : LocalCommandPreparationOriginal
  host : @local_host.NativeLocalHostConnection
  capture : @local_host.NativeLocalJournalCapture
  configuration : LocalCommandConfiguration
  configuration_name : String
  configuration_body : Bytes
  environment_name : String
  environment_body : Bytes
  environment : @checked.CheckEnvironment
  principal : String
  connection : String
  scope : String
  intent : @run_host.ClientSubmittedIntent
  preparation : @local_host.NativeClientSubmittedPreparation
  requirements : @local_values.ClientLocalRequirements?
  model_compilation : LocalCommandModelCompilation?
  normalization : @run_host.ClientLocalNormalization?
  authoring : @run_host.ClientAuthoringContextPreparation?
  mut file_source : LocalCommandFileSources?
  installed_contracts : @local_values.ClientInstalledSequenceContracts
  assets : @run_host.ClientLocalProductAssets
  submission : LocalRunSubmission?
}

///|
fn LocalCommandPreparationOriginal::prepare_business_submission(
  self : LocalCommandPreparationOriginal,
  host : @local_host.NativeLocalHostConnection,
  capture : @local_host.NativeLocalJournalCapture,
  configuration : LocalCommandConfiguration,
  runtime : LocalPackagedRuntime,
  input_root : String,
  operation : String,
  child : @argparse.Matches,
  original_input? : (LocalRunSubmission, @run_host.ClientSubmittedIntent)? = None,
) -> LocalCommandBusinessPreparation raise ClientStop {
  native_timing_begin(30)
  defer native_timing_end(30)
  guard self.journal is Some(journal) &&
    physical_equal(journal, capture) &&
    self.runtime is Some(physical) &&
    physical_equal(physical, runtime.physical) &&
    self.journal_read_open &&
    !self.closing &&
    !self.closed &&
    self.primary is None else {
    stop("LocalBusinessOriginalUnavailable")
  }
  guard capture.original_host() is Some(captured_host) &&
    physical_equal(captured_host, host) else {
    stop("LocalBusinessOriginalUnavailable")
  }
  if operation != "aql" && operation != "sql" && operation != "start" {
    stop("LocalBusinessProgramUnavailable")
  }
  // The explicit path supplies its already read original reference and input
  // snapshot. Admitted Runs are observed before reaching this constructor;
  // a still-preparing intent supplies its original input to first completion.
  if optional(child, "submission-ref-file") is Some(_) ||
    optional(child, "operation-attempt-id") is Some(_) {
    guard original_input is Some((submission, _)) &&
      !submission.fresh &&
      optional(child, "operation-attempt-id") == Some(submission.attempt) &&
      local_submission_nonce_matches(
        submission.reference,
        optional(child, "request-id"),
      ) else {
      stop("LocalBusinessOriginalReferenceRequired")
    }
  } else if original_input is Some(_) {
    stop("LocalBusinessOriginalReferenceRequired")
  }
  // A retained original cannot be downgraded into this Native profile. Refuse
  // before configuration binding, input construction or the first compiler.
  if original_input is Some((_, intent)) &&
    @run_host.client_submitted_intent_execution_profile(intent) == Debug {
    self.retain_primary(CommandApplication("LocalExecutionProfileUnsupported"))
    stop("LocalExecutionProfileUnsupported")
  }
  let configuration_name = configuration.configuration_name
  let configuration_body = configuration.configuration_body
  let settings = configuration.settings
  let environment_name = configuration.environment_name
  let environment_body = configuration.environment_body
  let base_environment = configuration.checked_environment()
  let account = local_host_result(capture.configuration_in_original_read())
  if account.account_id() != settings.account_id {
    stop("LocalConfigurationChanged")
  }
  let scope = local_host_result(
    capture.authority_scope_cid_in_original_read(
      settings.principal,
      settings.connection,
    ),
  )
  let run_file = settings.run_file.unwrap_or_else(() => {
    stop("LocalRunInstallationRequired")
  })
  local_host_result(
    capture.bind_packaged_runtime_in_original_read(
      runtime.physical,
      settings.principal,
      settings.connection,
      environment_name,
      run_file,
      "runtime.json",
    ),
  )
  // Select the actual Runtime/Host originals before publishing Project write
  // targets to the SAME Request. Static catalogue strings cannot supply them.
  self.bind_project_mock_runtime(runtime.physical, capture, settings.principal)
  self.prepare_declared_file_sources(configuration, capture)
  let environment = local_command_project_environment(
    base_environment,
    Some(capture),
    settings,
  )
  let producer : LocalCommandBusinessInput = {
    root: input_root,
    operation,
    arguments: child,
    retained_intent: original_input.map(value => value.1),
  }
  command_preparation_result(
    self.prepare_business_request_capacity(capture, producer),
    stage=Some("business-request-capacity"),
  )
  self.begin_business_request(capture)
  let intent = self.with_business_request(capture, () => {
    self.construct_business_intent()
  })
  let (preparation, normalization, authoring) = self.prepare_business_request(
    capture, intent, environment,
  )
  if settings.model_http_installations is Some(_) &&
    self.project is Some(project) &&
    project.selects_operator_file_effect("run") {
    guard @local_host.native_client_submitted_preparation(preparation)
      is EffectComputation(effect) &&
      @run_host.prepared_client_effect_infer_count(effect) == Some(1) else {
      stop("LocalOriginalModelHttpEffectUnavailable")
    }
  }
  let model_compilation = match
    (
      settings.model_http_installations,
      @local_host.native_client_submitted_preparation(preparation),
    ) {
    (Some(installation), Computation(prepared)) =>
      self.prepare_model_compilation(capture, prepared, installation, runtime)
    _ => None
  }
  let (requirements, file_source, terminal_content) = match
    @local_host.native_client_submitted_preparation(preparation) {
    Computation(prepared) => {
      // This original Pure route retains its unchanged normalization and
      // requirements. An Effect is never coerced into its body or authority.
      guard normalization is Some(_) else {
        stop("LocalOriginalNormalizationNotInstalled")
      }
      guard authoring is Some(_) else {
        stop("LocalAuthoringEvidenceUnavailable")
      }
      let assets = runtime.assets
      // This gate only separates Programs with checked Source work from
      // source-free Programs. Their actual file route is selected later on
      // the same Request, once its original occurrences are backed.
      if @run_host.prepared_client_has_checked_sources(prepared) {
        let selected = self
          .select_business_file_source(prepared, model_compilation)
          .unwrap_or_else(() => stop("LocalBusinessProgramUnavailable"))
        (None, Some(selected), false)
      } else if model_compilation is Some(_) {
        (None, None, false)
      } else {
        // The same Request already reserved its original Plan/body envelope.
        // Construct sequences in that business allocator, keeping any typed
        // failure primary before the original scope/Journal return can fail.
        let (requirements, terminal_content) = self.with_business_request(
          capture,
          () => {
            if local_terminal_serialization_occurrence(prepared) is Some(_) {
              return (None, true)
            }
            match
              @local_values.prepare_source_free_runtime_requirements_result(
                prepared,
                runtime.installed_contracts,
                assets.values,
                Some(assets.fragment),
                assets.ordered,
              ) {
              Ok(original) => (Some(original), false)
              Err(issue) => local_stop_runtime_requirements(issue)
            }
          },
        )
        if requirements is Some(requirements) {
          command_preparation_result(
            self.require_business_program(
              prepared,
              runtime.installed_contracts,
              assets,
              requirements,
            ),
            stage=Some("business-program"),
          )
          |> ignore
        }
        (requirements, None, terminal_content)
      }
    }
    EffectComputation(_) => (None, None, false)
  }
  let selection : LocalCommandBusinessPreparation = {
    original: self,
    host,
    capture,
    configuration,
    configuration_name,
    configuration_body,
    environment_name,
    environment_body,
    environment,
    principal: settings.principal,
    connection: settings.connection,
    scope,
    intent,
    preparation,
    requirements,
    model_compilation,
    normalization,
    authoring,
    file_source,
    installed_contracts: runtime.installed_contracts,
    assets: runtime.assets,
    submission: original_input.map(value => value.0),
  }
  if !selection.current(host, settings, environment) {
    stop("LocalSubmissionAuthorizationDenied")
  }
  guard self.business is Some(business) &&
    business.operation is Some(original_operation) else {
    stop("LocalBusinessOriginalUnavailable")
  }
  // The receiver was retained in outer control before Read entry. Only this
  // exact admitted Runtime/Program/current selection may activate its route.
  if requirements is Some(_) ||
    file_source is Some(_) ||
    model_compilation is Some(_) ||
    terminal_content {
    command_preparation_result(
      original_operation
      .activate()
      .map_err(issue => CommandStoreOperation(issue)),
      stage=Some("business-activation"),
    )
  }
  selection
}

///|
// Called only while the same captured original Read is entered. A successful
// comparison is neither a new resource issue nor an authorization cache.
fn LocalCommandBusinessPreparation::current(
  self : LocalCommandBusinessPreparation,
  host : @local_host.NativeLocalHostConnection,
  settings : LocalHostSettings,
  environment : @checked.CheckEnvironment,
) -> Bool {
  if !physical_equal(self.host, host) ||
    !physical_equal(self.environment, environment) ||
    self.original.closing ||
    self.original.closed ||
    self.original.primary is Some(_) ||
    settings.principal != self.principal ||
    settings.connection != self.connection {
    return false
  }
  guard self.original.host is Some(physical) &&
    self.original.pair is Some(pair) &&
    self.original.read is Some(read) &&
    physical.observe_local_host_consuming_read_scope(pair, read)
    is Ok(@initial_arena.ReadEntered) &&
    self.original.business is Some(business) &&
    business.execution is Some(execution) &&
    physical.require_domain_retained_execution_current(execution) is Ok(_) else {
    return false
  }
  self.capture.check_current_in_original_read() is Ok(_) &&
  self.capture.selected_configuration_in_original_read(self.configuration_name)
  is Ok(configuration) &&
  configuration == self.configuration_body &&
  self.capture.selected_configuration_in_original_read(self.environment_name)
  is Ok(original_environment) &&
  original_environment == self.environment_body &&
  self.configuration.declared_file_source_current(self.capture) &&
  self.capture.authority_scope_cid_in_original_read(
    self.principal,
    self.connection,
  )
  is Ok(scope) &&
  scope == self.scope &&
  self.capture.authorize_in_original_read({
    principal: self.principal,
    connection: self.connection,
    resource: "run",
    operation: "submit",
  })
  is Ok(Allow(_))
}

///|
// Select the source-free terminal family. Its exact checked coordinates and
// Result roots are verified by the existing dedicated Content Graph issuer.
fn local_terminal_serialization_occurrence(
  prepared : @run_host.PreparedClientProgram,
) -> (Int, Int)? {
  guard @run_host.prepared_client_acquisition_count(prepared) == 0 &&
    @strategy.graph_task_count(@run_host.prepared_client_graph(prepared)) == 1 &&
    @run_host.prepared_client_composed_infer_occurrences(prepared)
    is Some(infers) &&
    infers.is_empty() else {
    return None
  }
  let occurrences = @run_host.prepared_client_serialization_occurrences(
    prepared,
  )
  if occurrences.length() == 1 {
    occurrences.get(0)
  } else {
    None
  }
}

///|
// Select only the actual checked Source's existing Project declaration and
// original prepared File provider. Names select immutable metadata, never an
// Account grant, a route fallback, a new Environment or a physical read.
fn LocalCommandPreparationOriginal::select_business_file_source(
  self : LocalCommandPreparationOriginal,
  prepared : @run_host.PreparedClientProgram,
  model : LocalCommandModelCompilation?,
) -> LocalCommandFileSources? {
  let graph = @run_host.prepared_client_graph(prepared)
  if @strategy.graph_result_count(graph) <= 0 ||
    @strategy.graph_program_has_effects(graph) ||
    @run_host.prepared_client_uses_graph_carrier(prepared) {
    return None
  }
  let model_matches = match model {
    Some(original) => physical_equal(original.program, prepared)
    None => @run_host.prepared_client_composed_infer_count(prepared) == Some(0)
  }
  guard model_matches &&
    @run_host.prepared_client_serialization_occurrences(prepared).is_empty() else {
    return None
  }
  // The same Request's next Plan phase binds each original checked subject
  // to the already prepared locator of this command.
  if self.declared_file_sources is Some((sources, listings)) {
    return Some(Original(sources, Some(listings)))
  }
  guard self.project is Some(project) &&
    project.mock_declarations is Some(original) &&
    !original.closing &&
    !original.retired else {
    return None
  }
  Some(Original(original.sources, original.file_sources))
}
