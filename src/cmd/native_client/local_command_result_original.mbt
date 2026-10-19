///|
// Caller retention of already authenticated originals. This private selection
// issues no Account outcome, Run, grant, physical capacity or replacement Store.
priv struct LocalCommandResultOriginal {
  owner : LocalCommandPreparationOriginal
  host : @local_host.NativeLocalHostConnection
  capture : @local_host.NativeLocalJournalCapture
  original : @local_host.NativeClientOriginalRunSelection
  binding : @local_host.NativeLocalReadPolicyBinding
  store : @local_store.Store
  scope : String
}

///|
// Static caller context keeps a failed original fence identifiable without
// exposing configuration paths or replacing its actual error/cleanup duty.
fn[T] local_result_host_value(
  result : Result[T, @local_host.NativeLocalAdoptionIssue],
  stage : String,
) -> T raise ClientStop {
  match result {
    Ok(value) => value
    Err(issue) => stop(local_host_issue(issue) + " [result: " + stage + "]")
  }
}

///|
fn LocalCommandPreparationOriginal::prepare_original_result(
  self : LocalCommandPreparationOriginal,
  host : @local_host.NativeLocalHostConnection,
  capture : @local_host.NativeLocalJournalCapture,
  settings : LocalHostSettings,
  configuration_name : String,
  runtime : LocalPackagedRuntime,
  sqlite : @local_sqlite.Library,
  child : @argparse.Matches,
) -> LocalCommandResultOriginal raise ClientStop {
  guard self.journal is Some(actual_capture) &&
    physical_equal(actual_capture, capture) &&
    capture.original_host() is Some(actual_host) &&
    physical_equal(actual_host, host) &&
    self.runtime is Some(actual_runtime) &&
    physical_equal(actual_runtime, runtime.physical) &&
    self.business is Some(business) &&
    business.operation is Some(operation) &&
    self.journal_read_open &&
    !self.closing &&
    !self.closed &&
    self.primary is None else {
    stop("LocalReadOriginalCustodyUnavailable")
  }
  local_result_stdout_only(child)
  ignore(local_result_format(child))
  let configuration = local_check_original_text(
    local_result_host_value(
      capture.selected_configuration_in_original_read(configuration_name),
      "configuration",
    ),
  )
  let (environment_name, _) = local_configuration(configuration)
  let run_file = settings.run_file.unwrap_or_else(() => {
    stop("LocalRunOriginalNotSelected")
  })
  local_result_host_value(
    capture.bind_packaged_runtime_in_original_read(
      runtime.physical,
      settings.principal,
      settings.connection,
      environment_name,
      run_file,
      "runtime.json",
    ),
    "runtime binding",
  )
  local_result_host_value(
    capture.require_packaged_runtime_upgrade_in_original_read(),
    "runtime correspondence",
  )
  let scope = local_result_host_value(
    capture.authority_scope_cid_in_original_read(
      settings.principal,
      settings.connection,
    ),
    "authority",
  )
  let id = required(child, "run")
  let original = local_result_host_value(
    capture.lookup_submitted_run_original_by_id_in_original_read(
      settings.principal,
      settings.connection,
      id,
    ),
    "Run identity",
  ).unwrap_or_else(() => stop("LocalOriginalRunUnavailable"))
  let saved = local_result_host_value(
    capture.lookup_submitted_run_state_by_id_in_original_read(
      settings.principal,
      settings.connection,
      id,
      @env.now().to_double(),
    ),
    "saved Run",
  ).unwrap_or_else(() => stop("LocalOriginalRunStateUnavailable"))
  if @local_host.native_client_submission_reference_wire(saved.reference()) !=
    @local_host.native_client_submission_reference_wire(original.reference()) ||
    @publication.publication_contract_identity(saved.definition()) !=
    @publication.publication_contract_identity(original.definition()) {
    stop("LocalOriginalRunReferenceMismatch")
  }
  let profile_file = settings.run_policy_profile_file.unwrap_or_else(() => {
    stop("LocalRunPolicyOriginalUnavailable")
  })
  let read_file = settings.read_file.unwrap_or_else(() => {
    stop("LocalReadPolicyOriginalNotSelected")
  })
  let policy = local_result_host_value(
    capture.bind_run_policy_profile_in_original_read(
      settings.principal,
      settings.connection,
      profile_file,
      read_file,
      run_file,
    ),
    "Run policy",
  )
  let binding = match
    capture.bind_result_read_policy_for_run_in_original_read(
      policy,
      original.reference(),
      original.request(),
      @env.now().to_double(),
    ) {
    Ok(value) => value
    Err(issue) => stop(local_read_issue(issue))
  }
  let reference = local_original_run_reference(original.definition(), scope)
  guard reference is Object(fields) &&
    json_text(fields, "namespaceId") is Some(namespace_id) else {
    stop("LocalOriginalRunUnavailable")
  }
  let run = local_run_installation(
    local_check_original_text(
      local_result_host_value(
        capture.selected_configuration_in_original_read(run_file),
        "Run installation",
      ),
    ),
  )
  if run.namespace_id != namespace_id || run.source_free is None {
    stop("LocalOriginalRunReferenceMismatch")
  }
  let managed = local_result_host_value(
    capture.managed_root_path_in_original_read(),
    "managed Store root",
  ).unwrap_or_else(() => stop("LocalManagedRootRequired"))
  local_result_host_value(
    capture.check_current_in_original_read(),
    "Store current",
  )
  command_preparation_result(
    operation.activate().map_err(issue => CommandStoreOperation(issue)),
  )
  // Restore only the existing Store. Missing path/DB/custody cannot initialize
  // another namespace, schema, key or Run merely to obtain a public result.
  let store = self.open_business_store(sqlite, managed, run, existing=true)
  local_result_host_value(
    capture.check_current_in_original_read(),
    "Store current",
  )
  { owner: self, host, capture, original, binding, store, scope, }
}
