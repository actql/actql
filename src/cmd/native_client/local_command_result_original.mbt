///|
// Caller retention of already authenticated originals. This private selection
// issues no Account outcome, Run, grant, physical capacity or replacement Store.
priv struct LocalCommandResultOriginal {
  owner : LocalCommandPreparationOriginal
  host : @local_host.NativeLocalHostConnection
  capture : @local_host.NativeLocalJournalCapture
  original : @local_host.NativeClientOriginalRunSelection
  binding : @local_host.NativeLocalReadPolicyBinding
  policy : @local_host.NativeLocalRunPolicyBinding
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
  publication? : LocalCommandBusinessPreparation? = None,
  configuration? : LocalCommandConfiguration? = None,
  retained? : @local_host.NativeClientSavedRunStateSelection? = None,
) -> LocalCommandResultOriginal raise ClientStop {
  native_timing_begin(6)
  defer native_timing_end(6)
  native_timing_begin(20)
  defer native_timing_end(20)
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
  let directory = @env.current_dir().unwrap_or_else(() => {
    stop("ProjectConfigurationDirectoryUnavailable")
  })
  let delivery = local_result_delivery_selection(child, directory)
  if delivery.files.is_empty() {
    local_result_stdout_only(child)
  }
  ignore(local_result_format(child))
  let environment_name = match configuration {
    Some(original) => {
      guard original.configuration_name == configuration_name &&
        physical_equal(original.settings, settings) else {
        stop("LocalConfigurationChanged")
      }
      original.environment_name
    }
    None if publication is Some(original) => {
      guard original.configuration_name == configuration_name &&
        physical_equal(original.original, self) &&
        physical_equal(original.host, host) &&
        physical_equal(original.capture, capture) else {
        stop("LocalConfigurationChanged")
      }
      original.environment_name
    }
    None => {
      let text = local_check_original_text(
        local_result_host_value(
          capture.selected_configuration_in_original_read(configuration_name),
          "configuration",
        ),
      )
      local_configuration(text).0
    }
  }
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
  let scope = local_result_host_value(
    capture.authority_scope_cid_in_original_read(
      settings.principal,
      settings.connection,
    ),
    "authority",
  )
  let id = required(child, "run")
  let saved = match retained {
    Some(value) => {
      if @publication.run_definition_run_id(value.definition()) != Ok(id) {
        stop("LocalOriginalRunReferenceMismatch")
      }
      value
    }
    None =>
      local_result_host_value(
        capture.lookup_submitted_run_state_by_id_in_original_read(
          settings.principal,
          settings.connection,
          id,
          @env.now().to_double(),
        ),
        "saved Run",
      ).unwrap_or_else(() => stop("LocalOriginalRunStateUnavailable"))
  }
  // State restoration selected and authenticated this exact original already.
  // No callback or mutation intervenes; consume it without another indexed
  // identity transaction or comparing reconstructed copies of the same fields.
  let original = saved.original()
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
  let selected_read = if delivery.files.is_empty() {
    capture.bind_result_read_policy_for_run_in_original_read(
      policy,
      original.reference(),
      original.request(),
      @env.now().to_double(),
    )
  } else {
    if !settings.installation_files.contains("file-read.json") {
      stop("LocalResultFileOriginalNotSelected")
    }
    capture.bind_result_file_read_policy_for_run_in_original_read(
      policy,
      original.reference(),
      original.request(),
      @env.now().to_double(),
      "file-read.json",
    )
  }
  let binding = match selected_read {
    Ok(value) => value
    Err(issue) => stop(local_read_issue(issue))
  }
  let reference = local_original_run_reference(original.definition(), scope)
  guard reference is Object(fields) &&
    json_text(fields, "namespaceId") is Some(namespace_id) else {
    stop("LocalOriginalRunUnavailable")
  }
  let run_body = local_result_host_value(
    capture.selected_configuration_in_original_read(run_file),
    "Run installation",
  )
  let run = match configuration {
    Some(original) => original.run_installation(run_file, run_body)
    None if publication is Some(original) =>
      original.configuration.run_installation(run_file, run_body)
    None => local_run_installation(local_check_original_text(run_body))
  }
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
  // Restore only the existing Store. Missing path/DB/custody cannot initialize
  // another namespace, schema, key or Run merely to obtain a public result.
  let store = match publication {
    None =>
      match business.store {
        None => {
          command_preparation_result(
            operation.activate().map_err(issue => CommandStoreOperation(issue)),
          )
          self.open_business_store(sqlite, managed, run, existing=true)
        }
        Some(store) => {
          // The retained receipt already opened this same original Store.
          // Keep independent Result policy/current admission above; do not
          // acquire another physical Store or treat receipt visibility as Allow.
          let bridge = operation
            .sqlite_original()
            .unwrap_or_else(() => stop("LocalReadOriginalCustodyUnavailable"))
          if !store.matches_original_operation(bridge) {
            stop("LocalReadOriginalCustodyUnavailable")
          }
          store
        }
      }
    Some(published) => {
      // A quick query reads the Store that published this exact request. It
      // neither opens a second DB nor retires the still-owned Values children.
      if !physical_equal(published.original, self) ||
        !physical_equal(published.capture, capture) ||
        !published.current(host, settings, published.environment) {
        stop("LocalReadOriginalCustodyUnavailable")
      }
      guard @local_host.native_client_submitted_preparation(published.preparation)
        is Computation(prepared) else {
        stop("LocalReadOriginalCustodyUnavailable")
      }
      let request = @run_host.prepare_source_free_client_request_identity(
        prepared,
        published.scope,
        @run_host.client_request_caller_id(original.request()),
      ).unwrap_or_else(() => stop("LocalOriginalRunReferenceMismatch"))
      if @run_host.client_request_identity_relation(request, original.request()) !=
        @run_host.SameRequest {
        stop("LocalOriginalRunReferenceMismatch")
      }
      let store = business.store.unwrap_or_else(() => {
        stop("LocalReadOriginalCustodyUnavailable")
      })
      let bridge = operation
        .sqlite_original()
        .unwrap_or_else(() => stop("LocalReadOriginalCustodyUnavailable"))
      if !store.matches_original_operation(bridge) {
        stop("LocalReadOriginalCustodyUnavailable")
      }
      store
    }
  }
  local_result_host_value(
    capture.check_current_in_original_read(),
    "Store current",
  )
  { owner: self, host, capture, original, binding, policy, store, scope, }
}
