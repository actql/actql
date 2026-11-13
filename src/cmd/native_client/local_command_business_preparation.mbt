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
  normalization : @run_host.ClientLocalNormalization?
  file_source : (LocalProjectMockSourceDeclaration, LocalProjectMockRowBinding)?
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
  let environment = local_command_project_environment(base_environment)
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
  let preparation = self.prepare_business_request(capture, intent, environment)
  let mut normalization = None
  let (requirements, file_source) = match
    @local_host.native_client_submitted_preparation(preparation) {
    Computation(prepared) => {
      // This original Pure route retains its unchanged normalization and
      // requirements. An Effect is never coerced into its body or authority.
      normalization = Some(
        @run_host.issue_prepared_client_local_normalization(prepared).unwrap_or_else(() => {
            stop("LocalOriginalNormalizationNotInstalled")
          },
        ),
      )
      let assets = runtime.assets
      if @run_host.prepared_client_acquisition_count(prepared) != 0 {
        let selected = self
          .select_business_file_source(prepared)
          .unwrap_or_else(() => stop("LocalBusinessProgramUnavailable"))
        (None, Some(selected))
      } else {
        let requirements = @local_values.prepare_source_free_runtime_requirements(
          prepared,
          runtime.installed_contracts,
          assets.values,
          Some(assets.fragment),
          assets.ordered,
        ).unwrap_or_else(() => stop("LocalBusinessProgramUnavailable"))
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
        (Some(requirements), None)
      }
    }
    EffectComputation(_) => (None, None)
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
    normalization,
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
  if requirements is Some(_) || file_source is Some(_) {
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
// Select only the actual checked Source's existing Project declaration and
// original prepared File provider. Names select immutable metadata, never an
// Account grant, a route fallback, a new Environment or a physical read.
fn LocalCommandPreparationOriginal::select_business_file_source(
  self : LocalCommandPreparationOriginal,
  prepared : @run_host.PreparedClientProgram,
) -> (LocalProjectMockSourceDeclaration, LocalProjectMockRowBinding)? {
  guard self.project is Some(project) &&
    project.mock_declarations is Some(original) &&
    !original.closing &&
    !original.retired else {
    return None
  }
  let graph = @run_host.prepared_client_graph(prepared)
  if @run_host.prepared_client_acquisition_count(prepared) != 1 ||
    @strategy.graph_captured_prefix(graph) != 1 ||
    @strategy.graph_result_count(graph) != 1 ||
    @strategy.graph_program_has_effects(graph) ||
    @run_host.prepared_client_uses_graph_carrier(prepared) {
    return None
  }
  guard @run_host.prepared_client_composed_infer_occurrences(prepared)
    is Some(infers) &&
    infers.is_empty() &&
    @run_host.prepared_client_serialization_occurrences(prepared).is_empty() else {
    return None
  }
  let source = match
    @run_host.prepare_client_source_acquisition(prepared, 0, 0) {
    Err(_) => return None
    Ok(value) => value
  }
  let subject = @sourceviews.declaration(
    @sourceviews.mode_input(@sourceviews.source_acquisition_mode(source)),
  )
  for declaration in original.sources {
    if declaration._retained_connection == subject.connector {
      for row in declaration._retained_rows {
        if row.view.resource == subject.resource {
          return Some((declaration, row))
        }
      }
    }
  }
  None
}
