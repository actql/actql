///|
// The selected caller retains every original child before a fallible call.
// The outer command closes them after its borrowed callback returns; an
// application exception must not run Store/Compute cleanup in the wrong scope.
fn local_execute_original_publish_values(
  selection : LocalCommandBusinessPreparation,
  settings : LocalHostSettings,
  run : LocalRunInstallation,
  compiled : @run_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  request : @run_host.ClientRequestIdentity,
  reference : @local_host.NativeClientSubmissionReference,
  attempt : String,
  store : @local_store.Store,
) -> String raise ClientStop {
  native_timing_begin(3)
  defer native_timing_end(3)
  guard selection.original.business is Some(business) &&
    business.operation is Some(operation) &&
    business.store is Some(original_store) &&
    physical_equal(original_store, store) &&
    business.publication_publisher is None &&
    !business.publication_retired &&
    selection.current(selection.host, settings, selection.environment) else {
    stop("LocalBusinessOriginalUnavailable")
  }
  let installed = run.source_free.unwrap_or_else(() => {
    stop("LocalValuesInstallationRequired")
  })
  let payload_limit = local_values_publication_payload_limit(run)
  let publisher = selection.host
    .bind_original_run_publisher(
      operation,
      settings.principal,
      settings.connection,
      request,
      definition,
      settings.run_file.unwrap_or_else(() => {
        stop("LocalRunInstallationRequired")
      }),
      store,
    )
    .unwrap_or_else(() => stop("LocalPublisherAuthorityUnavailable"))
  business.publication_publisher = Some(publisher)
  let results : Array[@local_publication.NativeCapturedResultPublicationContext] = @run_host.client_compiled_run_result_names(
    compiled,
  ).map(_ => {
    retention: run.retention,
    computation_contract_cid: @publication.publication_contract_identity(
      @run_host.client_compiled_run_plan(compiled),
    ),
    input_relation_cids: [],
    scope_cid: @publication.publication_contract_identity(definition),
    effective_data_policy_cid: installed.result_policy_cid,
    store_authority_cid: run.store_authority_cid,
    material_generation_cid: publisher
    .sample_original_generation_cid()
    .unwrap_or_else(() => stop("LocalGenerationUnavailable")),
    max_payload_bytes: run.result_payload_bytes,
  })
  business.publication_results = Some(results)
  let authoring = @publication.seal_run_evidence_value(
    "authoring_context",
    encode_request_json(
      Json::object(
        Map([
          ("version", Json::string("actql-authoring-context/0.1")),
          (
            "program_definition_cid",
            Json::string(@run_host.client_request_program_cid(request)),
          ),
          ("annotations", Json::array([])),
        ]),
      ),
      65536,
    ),
    65536,
    8192,
    64,
  ).unwrap_or_else(() => stop("LocalAuthoringEvidenceUnavailable"))
  let now = local_utc_now()
  let intent : @local_publication.NativeRunPublicationIntent = {
    namespace_id: run.namespace_id,
    authority_scope_cid: @run_host.client_request_authority_scope_cid(request),
    publication_policy_cid: publisher.publication_policy_cid(),
    publication_target_cid: run.store_authority_cid,
    requested_at: now,
  }
  let occurrence : @local_publication.NativeRunPublicationOccurrence = {
    attempt_id: attempt,
    fence_cid: publisher
    .sample_original_generation_cid()
    .unwrap_or_else(() => stop("LocalGenerationUnavailable")),
    external_idempotency_key: None,
    started_at: now,
    committed_at: now,
  }
  // The original execution was admitted before epoch/Run admission. Record
  // this attempt before suspending the parent; Err never proves non-entry.
  business.active = true
  operation
  .enter_business_from_original_read()
  .unwrap_or_else(() => stop("LocalBusinessScopeUnavailable"))
  let work = selection.open_values_work(run, compiled, definition, request)
  let (row_limits, limits) = work
    .publication_limits(payload_limit)
    .unwrap_or_else(() => stop("LocalValuesPublicationLimit"))
  let (bridge_entries, evidence_entries) = work
    .publication_entry_limits()
    .unwrap_or_else(() => stop("LocalValuesPublicationLimit"))
  work
  .publication_invocation(65536, 8192, 64)
  .unwrap_or_else(() => stop("LocalValuesPublicationEvidenceUnavailable"))
  |> ignore
  let service = match
    work.install_publication_service(
      store,
      run.namespace_id,
      _ => publisher.current(),
      65536,
      8192,
      64,
      request_authorize=Some((context, facts) => {
        publisher.authorize_request(context, facts)
      }),
    ) {
    Ok(value) => value
    Err(issue) => {
      business.publication_failure = Some(issue)
      stop("LocalPublicationAuthorityUnavailable")
    }
  }
  business._retained_publication_service = Some(service)
  let pending = match
    work.prepare_local_publication(
      service, results, authoring, intent, occurrence, row_limits, bridge_entries,
      65536, limits, 65536, 8192, 64,
    ) {
    Ok(value) => value
    Err(issue) => {
      business.publication_failure = Some(issue)
      local_publication_failure_tags(issue, native_timing_amount)
      stop("LocalResultPublicationNotReady")
    }
  }
  business.publication_pending = Some(pending)
  // The existing Journal fence owns the parent Read, while each Store method
  // owns its individual SQL exchange. No whole-publication Store flight.
  operation
  .return_business_to_original_read()
  .unwrap_or_else(() => stop("LocalBusinessScopeReturnPending"))
  business.active = false
  let saved = {
    native_timing_begin(4)
    defer native_timing_end(4)
    business.publication_attempted = true
    let published = match pending.commit() {
      Ok(value) => {
        business.publication_result = Some(value)
        value
      }
      Err(issue) => {
        business._retained_publication_commit_failure = Some(issue)
        local_publication_commit_failure_tags(issue, native_timing_amount)
        stop("LocalPublicationNeedsReconciliation")
      }
    }
    if !published.committed {
      stop("LocalPublicationNeedsReconciliation")
    }
    let saved = match
      selection.host.observe_publication_run_state(
        publisher,
        pending,
        local_utc_now(),
        evidence_entries,
        16,
        1000,
      ) {
      Ok(observed) => {
        // Retain the same accepted receipt before the following Journal action.
        // The command cuts this alias only in existing publication-child cleanup.
        business.run_receipt_original = Some(FreshRunReceipt(observed))
        selection.capture
        .retain_observed_run_state_in_original_read(
          settings.principal,
          settings.connection,
          reference,
          request,
          observed,
          @env.now().to_double(),
        )
        .unwrap_or_else(() => stop("LocalRunStateNeedsReconciliation"))
      }
      Err(Journal(@local_host.AuthorizationDenied)) => {
        if !publisher.current() ||
          !selection.current(selection.host, settings, selection.environment) {
          stop("LocalRunStateNeedsReconciliation")
        }
        stop("LocalRunStateUnavailable")
      }
      Err(_) => stop("LocalRunStateNeedsReconciliation")
    }
    saved
  }
  // The existing saved-State Owner finished its original reference/request,
  // revision and independent RunRead/current fences. Do not select by an
  // inferred ID or enter the legacy unscoped reader after this boundary.
  saved.wire()
}
