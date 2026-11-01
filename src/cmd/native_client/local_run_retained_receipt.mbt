///|
// Observe the exact committed receipt of the retained Run. This path requires
// independent RunRead, not Result delivery, a Publisher or another submission.
fn LocalCommandPreparationOriginal::export_retained_run_receipt(
  self : LocalCommandPreparationOriginal,
  host : @local_host.NativeLocalHostConnection,
  capture : @local_host.NativeLocalJournalCapture,
  configuration : LocalCommandConfiguration,
  runtime : LocalPackagedRuntime,
  sqlite : @local_sqlite.Library,
  crypto : @local_crypto.Library,
  retained : @local_host.NativeClientSavedRunStateSelection,
  path : String,
) -> Unit raise ClientStop {
  guard self.journal is Some(actual_capture) &&
    physical_equal(actual_capture, capture) &&
    capture.original_host() is Some(actual_host) &&
    physical_equal(actual_host, host) &&
    self.runtime is Some(actual_runtime) &&
    physical_equal(actual_runtime, runtime.physical) &&
    self.business is Some(business) &&
    business.operation is Some(operation) &&
    business.store is None &&
    business.run_receipt_original is None &&
    self.journal_read_open &&
    !self.closing &&
    !self.closed &&
    self.primary is None else {
    stop("LocalReadOriginalCustodyUnavailable")
  }
  let settings = configuration.settings
  let run_file = settings.run_file.unwrap_or_else(() => {
    stop("LocalRunOriginalNotSelected")
  })
  local_host_result(
    capture.bind_packaged_runtime_in_original_read(
      runtime.physical,
      settings.principal,
      settings.connection,
      configuration.environment_name,
      run_file,
      "runtime.json",
    ),
  )
  |> ignore
  let original = retained.original()
  let scope = local_host_result(
    capture.authority_scope_cid_in_original_read(
      settings.principal,
      settings.connection,
    ),
  )
  let reference = local_original_run_reference(original.definition(), scope)
  guard reference is Object(fields) &&
    json_text(fields, "namespaceId") is Some(namespace_id) else {
    stop("LocalOriginalRunUnavailable")
  }
  let run = configuration.run_installation(
    run_file,
    local_host_result(capture.selected_configuration_in_original_read(run_file)),
  )
  if run.namespace_id != namespace_id {
    stop("LocalOriginalRunReferenceMismatch")
  }
  let managed = local_host_result(capture.managed_root_path_in_original_read()).unwrap_or_else(() => {
      stop("LocalManagedRootRequired")
    },
  )
  local_host_result(capture.check_current_in_original_read()) |> ignore
  command_preparation_result(
    operation.activate().map_err(issue => CommandStoreOperation(issue)),
  )
  // Open only the existing installed Store. Every partial remains in the same
  // command's existing child-first cleanup; missing custody never initializes.
  let store = self.open_business_store(sqlite, managed, run, existing=true)
  let location = local_result_file_location(path)
  let observed = match
    local_host_result(
      capture.observe_retained_run_receipt_in_original_read(
        settings.principal,
        settings.connection,
        original,
        store,
        namespace_id,
        path,
        location.parent_path,
        location.directory_name,
      ),
    ) {
    Ok(value) => value
    Err(_) => stop("LocalRunReceiptReadUnavailable")
  }
  // Retain before the external Writer can fail. Existing publication-child
  // retirement drops this exact Store alias before closing that original.
  business.run_receipt_original = Some(RetainedRunReceipt(observed))
  guard business.run_receipt_original
    is Some(RetainedRunReceipt(retained_observation)) else {
    stop("LocalRunReceiptOriginalUnavailable")
  }
  local_write_result_receipt(
    path,
    @publication.publication_contract_json(
      retained_observation.original_receipt(),
    ),
    crypto,
  )
  retained_observation
  .check_current_export()
  .unwrap_or_else(() => stop("LocalRunReceiptReadUnavailable"))
}
