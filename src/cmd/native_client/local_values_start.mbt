///|
// Preserve the original pre-Start refusal for an empty publication allowance.
// This validates configuration only; the live work supplies all plan bounds.
fn local_values_publication_payload_limit(
  run : LocalRunInstallation,
) -> Int raise ClientStop {
  let bytes = run.result_payload_bytes.to_int()
  if bytes < 1 {
    stop("LocalValuesPublicationLimit")
  }
  bytes
}

///|
// A source-free Run retains its installed Result Policy before its first-start
// claim, whether or not a separate read installation is enabled. Missing
// originals on an already started Run are not backfilled by this caller.
fn local_retain_values_policy_originals(
  host : @local_host.NativeLocalHostConnection,
  settings : LocalHostSettings,
  crypto : @local_crypto.Library,
  request : @run_host.ClientRequestIdentity,
  prepared : @run_host.PreparedClientProgram,
  compiled : @run_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  business? : LocalCommandBusinessPreparation? = None,
) -> Unit raise ClientStop {
  let retained = match business {
    None =>
      host.retain_publication_policy_originals(
        crypto,
        settings.principal,
        settings.connection,
        request,
        prepared,
        compiled,
        definition,
      )
    Some(original) =>
      local_business_policy_result(
        original,
        original.capture.retain_publication_policy_in_original_read(
          settings.principal,
          settings.connection,
          request,
          prepared,
          compiled,
          definition,
        ),
      )
  }
  match retained {
    Ok(_) => ()
    Err(PublicationPolicy(@checked.MissingDependency)) =>
      stop("LocalResultPolicyOriginalsMissing")
    Err(PublicationPolicy(@checked.BudgetExceeded) | CapacityExceeded) =>
      stop("LocalResultPolicyOriginalsLimit")
    Err(AuthorizationDenied) => stop("LocalResultPolicyAuthorityDenied")
    Err(Fenced) => stop("LocalResultPolicyOriginalsFenced")
    Err(CustodyLost | PublicationPolicy(@checked.ForeignBody)) =>
      stop("LocalResultPolicyOriginalsCustodyLost")
    Err(_) => stop("LocalResultPolicyOriginalsUnavailable")
  }
}

///|
// This route uses only the retained Values/normalization/publication owners.
// It neither loads a Source adapter nor issues a Result read grant.
fn local_execute_publish_values(
  host : @local_host.NativeLocalHostConnection,
  settings : LocalHostSettings,
  run : LocalRunInstallation,
  prepared : @run_host.PreparedClientProgram,
  compiled : @run_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  request : @run_host.ClientRequestIdentity,
  reference : @local_host.NativeClientSubmissionReference,
  attempt : String,
  crypto : @local_crypto.Library,
  store : @local_store.Store,
  current : () -> Bool,
) -> String raise ClientStop {
  if !current() {
    stop("LocalSubmissionAuthorizationDenied")
  }
  let installed = run.source_free.unwrap_or_else(() => {
    stop("LocalValuesInstallationRequired")
  })
  let payload_limit = local_values_publication_payload_limit(run)
  let work = match
    host.open_values_work(
      crypto,
      settings.principal,
      settings.connection,
      request,
      prepared,
      compiled,
      definition,
      installed.installed_contracts,
      installed.values_body,
      installed.fragment_body,
      installed.ordered_body,
      16,
      1000,
    ) {
    Ok(value) => value
    Err(failure) => {
      local_values_failure_tags(
        @local_host.native_client_values_work_failure_issue(failure),
        native_timing_amount,
      )
      if !failure.close() {
        stop("LocalValuesCleanupPending")
      }
      stop("LocalOriginalValuesWorkUnavailable")
    }
  }
  let reply = {
    errdefer (if !work.close() { stop("LocalValuesCleanupPending") })
    let (row_limits, limits) = work
      .publication_limits(payload_limit)
      .unwrap_or_else(() => stop("LocalValuesPublicationLimit"))
    let (bridge_entries, evidence_entries) = work
      .publication_entry_limits()
      .unwrap_or_else(() => stop("LocalValuesPublicationLimit"))
    let (_, _) = work
      .publication_invocation(65536, 8192, 64)
      .unwrap_or_else(() => stop("LocalValuesPublicationEvidenceUnavailable"))
    let results : Array[
      @local_publication.NativeCapturedResultPublicationContext,
    ] = @run_host.client_compiled_run_result_names(compiled).map(_ => {
      retention: run.retention,
      computation_contract_cid: @publication.publication_contract_identity(
        @run_host.client_compiled_run_plan(compiled),
      ),
      input_relation_cids: [],
      scope_cid: @publication.publication_contract_identity(definition),
      effective_data_policy_cid: installed.result_policy_cid,
      store_authority_cid: run.store_authority_cid,
      material_generation_cid: local_generation_cid(crypto),
      max_payload_bytes: run.result_payload_bytes,
    })
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
    let publisher = host
      .bind_run_publisher(
        crypto,
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
      fence_cid: local_generation_cid(crypto),
      external_idempotency_key: None,
      started_at: now,
      committed_at: now,
    }
    let service = work
      .install_publication_service(
        store,
        run.namespace_id,
        _ => publisher.current(),
        65536,
        8192,
        64,
        request_authorize=Some((context, facts) => {
          publisher.authorize_request(context, facts)
        }),
      )
      .unwrap_or_else(() => stop("LocalPublicationAuthorityUnavailable"))
    let pending = work
      .prepare_local_publication(
        service, results, authoring, intent, occurrence, row_limits, bridge_entries,
        65536, limits, 65536, 8192, 64,
      )
      .unwrap_or_else(() => stop("LocalResultPublicationNotReady"))
    // Unknown commit retains the original Store attempt; it does not cancel
    // publication, reopen Compute or install another generation automatically.
    let published = pending
      .commit()
      .unwrap_or_else(() => stop("LocalPublicationNeedsReconciliation"))
    if !published.committed {
      stop("LocalPublicationNeedsReconciliation")
    }
    // The original actual Store observation, never start bool/index inference.
    // Submit/publish do not imply RunRead: an initially denied reader leaves
    // optional state unavailable without adding a new execution permission.
    match
      host.observe_publication_run_state(
        publisher,
        pending,
        local_utc_now(),
        evidence_entries,
        16,
        1000,
      ) {
      Ok(observed) =>
        match
          host.retain_submitted_run_state(
            crypto,
            settings.principal,
            settings.connection,
            reference,
            request,
            observed,
            @env.now().to_double(),
          ) {
          Ok(_) => ()
          Err(_) => stop("LocalRunStateNeedsReconciliation")
        }
      Err(Journal(@local_host.AuthorizationDenied)) =>
        // A missing read purpose cannot conceal loss of the original submit
        // or publish purpose. Recheck their actual existing Owners here.
        if !publisher.current() || !current() {
          stop("LocalRunStateNeedsReconciliation")
        }
      Err(_) => stop("LocalRunStateNeedsReconciliation")
    }
    local_run_publication_reply(
      definition, request, reference, run, compiled, published,
    )
  }
  if !work.close() {
    stop("LocalValuesCleanupPending")
  }
  reply
}
