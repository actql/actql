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
  installed_contracts : @local_values.ClientInstalledSequenceContracts
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
  let environment = local_command_project_environment(
    configuration.checked_environment(),
  )
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
  let requirements = match
    @local_host.native_client_submitted_preparation(preparation) {
    Computation(prepared) => {
      // This original Pure route retains its unchanged normalization and
      // requirements. An Effect is never coerced into its body or authority.
      @run_host.issue_prepared_client_local_normalization(prepared).unwrap_or_else(() => {
          stop("LocalOriginalNormalizationNotInstalled")
        },
      )
      |> ignore
      let assets = runtime.assets
      let requirements = @local_values.prepare_source_free_local_requirements(
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
      Some(requirements)
    }
    EffectComputation(_) => None
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
    installed_contracts: runtime.installed_contracts,
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
  if requirements is Some(_) {
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
