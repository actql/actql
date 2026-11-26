///|
// The selected caller retains every original child before a fallible call.
// The outer command closes them after its borrowed callback returns; an
// application exception must not run Store/Compute cleanup in the wrong scope.
fn local_execute_original_publish_file_source(
  selection : LocalCommandBusinessPreparation,
  settings : LocalHostSettings,
  run : LocalRunInstallation,
  compiled : @run_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  prepared : @run_host.PreparedClientProgram,
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
  if business.model_run is Some(_) {
    selection.prepare_configured_model_works(business, request, run, store)
  }
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
  let authoring = selection.publication_authoring(prepared)
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
  let (entry, generations) = selection.prepare_file_work_entry(
    prepared, compiled, definition, request, publisher,
  )
  errdefer (if business.file_work is None && business.file_failure is None {
    // Only a confirmed original Read-side cancellation can discard this
    // never-taken view. An entered/ambiguous original remains for cleanup.
    if entry.cancel_unclaimed_in_original_read() {
      business.file_entry = None
    }
  })
  // The original execution was admitted before epoch/Run admission. Record
  // this attempt before suspending the parent; Err never proves non-entry.
  business.active = true
  operation
  .enter_business_from_original_read()
  .unwrap_or_else(() => stop("LocalBusinessScopeUnavailable"))
  let work = selection.open_file_work(entry, attempt, run, reference)
  let model_leader = if business.model_run is Some(model) {
    guard business.model_work.get(0) is Some(leader) else {
      stop("LocalOriginalModelUnavailable")
    }
    selection.original.require_model_step(
      leader.prepare_model_run_observation(business.model_work, model.graphs),
    )
    while !selection.original.require_model_step(leader.advance_observation()) {

    }
    match work.bind_model_publication(leader) {
      Ok(_) => ()
      Err(issue) => {
        business.file_publication_failure = Some(issue)
        stop("LocalSourcePublicationEvidenceUnavailable")
      }
    }
    Some(leader)
  } else {
    None
  }
  let (_, limits) = work
    .publication_limits(local_values_publication_payload_limit(run))
    .unwrap_or_else(() => stop("LocalSourcePublicationLimit"))
  let (_, evidence_entries) = work
    .publication_entry_limits()
    .unwrap_or_else(() => stop("LocalSourcePublicationLimit"))
  let (_, _, _, _, input, policy) = work
    .publication_invocation(65536, 8192, 64)
    .unwrap_or_else(() => {
      stop(
        local_file_publication_failure_message(
          work.publication_invocation_failure(),
        ),
      )
    })
  // The retained Work supplied this resolved policy. Preserve the original
  // finite custody/timestamps while binding its Result envelope to that SAME
  // policy; neither this projection nor its CID grants an extension or read.
  // Work's preceding metadata grow covers this fifth coexisting envelope.
  let retention = @publication.issue_result_retention_for_data_policy(
    run.retention,
    policy,
    8192,
    64,
    8,
  ).unwrap_or_else(() => stop("LocalSourceResultRetentionUnavailable"))
  let results : Array[@local_publication.NativeCapturedResultPublicationContext] = generations.map(generation => {
      retention,
      computation_contract_cid: @publication.publication_contract_identity(
        @run_host.client_compiled_run_plan(compiled),
      ),
      input_relation_cids: input,
      scope_cid: @publication.publication_contract_identity(definition),
      effective_data_policy_cid: policy,
      store_authority_cid: run.store_authority_cid,
      material_generation_cid: generation,
      max_payload_bytes: run.result_payload_bytes,
    },
  )
  business.publication_results = Some(results)
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
      business.file_publication_failure = Some(issue)
      stop("LocalPublicationAuthorityUnavailable")
    }
  }
  business._retained_publication_service = Some(service)
  let normalization = selection.normalization.unwrap_or_else(() => {
    stop("LocalOriginalNormalizationNotInstalled")
  })
  let pending = match
    work.prepare_local_publication(
      service,
      results,
      normalization,
      authoring,
      intent,
      occurrence,
      limits,
      65536,
      8192,
      64,
      model_leader~,
    ) {
    Ok(value) => value
    Err(issue) => {
      business.file_publication_failure = Some(issue)
      stop("LocalResultPublicationNotReady")
    }
  }
  business.publication_pending = Some(pending)
  local_commit_original_publication(
    selection, settings, request, reference, business, operation, publisher, pending,
    evidence_entries,
  )
}

///|
// The generation vector and every CID survive the original Read. The existing
// Read routing inventory covers the publisher callback; add its per-call
// wrappers, the fixed SHA state/block/schedule and the nonce and digest buffers.
// Account for each sample before any new string or growing vector is built.
fn local_file_generation_capacity(count : Int) -> Int64? {
  if count <= 0 {
    return None
  }
  let count = count.to_int64()
  guard @execution.preparation_array_representation(1L, count, true)
    is Some(array) &&
    @execution.preparation_representation_cost(array) is Some(vector) &&
    @execution.preparation_representation_cost({
      record_headers: 40L,
      reference_slots: 64L,
      scalar_words: 120L,
      owned_utf16_units: 200L,
      owned_wire_bytes: 320L,
    })
    is Some(sample) else {
    return None
  }
  @execution.checked_preparation_add_product(vector, count, sample)
}
