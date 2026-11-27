///|
fn[T] local_terminal_content_stop(
  issue : @local_host.NativeTerminalContentIssue,
) -> T raise ClientStop {
  match issue {
    TerminalContentInput(RowLimit)
    | TerminalContentEncoding(ContentRowLimit)
    | TerminalContentInput(Encoding(ContentRowLimit)) =>
      stop("LocalContentRowLimit")
    TerminalContentEncoding(ContentByteLimit)
    | TerminalContentInput(Encoding(ContentByteLimit)) =>
      stop("LocalContentByteLimit")
    TerminalContentCurrent => stop("LocalContentAuthorityUnavailable")
    TerminalContentWorkLimit => stop("LocalContentWorkLimit")
    TerminalContentFirstStart(Start(NeedsOriginalReconciliation)) =>
      stop("LocalRunNeedsOriginalReconciliation")
    TerminalContentFirstStart(_) => stop("LocalContentFirstStartUnavailable")
    TerminalContentPublisher(original) => {
      local_report_publisher_binding_issue(original)
      stop("LocalPublisherAuthorityUnavailable")
    }
    TerminalContentService(_) => stop("LocalPublicationAuthorityUnavailable")
    TerminalContentPlan(_) => stop("LocalSerializationPlanUnavailable")
    TerminalContentCompute(_) => stop("LocalContentPrefixUnavailable")
    TerminalContentInput(_) => stop("LocalContentInputUnavailable")
    TerminalContentEncoding(_) => stop("LocalContentEncodingFailed")
    TerminalContentIdentity(_) | TerminalContentEvidence(_) =>
      stop("LocalContentInputEvidenceUnavailable")
    TerminalContentStore(_) => stop("LocalContentStoreUnavailable")
    TerminalContentReference(_) | TerminalContentGeneration(_) =>
      stop("LocalContentReferenceUnavailable")
    TerminalContentPublication(_) => stop("LocalResultPublicationNotReady")
    TerminalContentOriginal => stop("LocalBusinessOriginalUnavailable")
  }
}

///|
fn local_execute_original_publish_terminal_content(
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
    business.request_run is Some(owner) &&
    business.store is Some(original_store) &&
    physical_equal(original_store, store) &&
    business.publication_publisher is None &&
    !business.publication_retired &&
    !business.terminal_content_selected &&
    selection.current(selection.host, settings, selection.environment) else {
    stop("LocalBusinessOriginalUnavailable")
  }
  let normalization = selection.normalization.unwrap_or_else(() => {
    stop("LocalOriginalNormalizationNotInstalled")
  })
  let evidence_entries = @local_values.terminal_serialization_evidence_entries(
    owner,
  ).unwrap_or_else(() => stop("LocalContentPublicationLimit"))
  let publisher = match
    selection.host.bind_original_run_publisher(
      operation,
      settings.principal,
      settings.connection,
      request,
      definition,
      settings.run_file.unwrap_or_else(() => {
        stop("LocalRunInstallationRequired")
      }),
      store,
    ) {
    Ok(value) => value
    Err(issue) => local_terminal_content_stop(TerminalContentPublisher(issue))
  }
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
  // The one command owner retains the terminal prefix and physical child
  // before any fallible callback can return from the same business scope.
  business.terminal_content_selected = true
  business.active = true
  operation
  .enter_business_from_original_read()
  .unwrap_or_else(() => stop("LocalBusinessScopeUnavailable"))
  let work = match
    publisher.open_terminal_content_work(owner, prepared, compiled) {
    Ok(value) => value
    Err(issue) => local_terminal_content_stop(issue)
  }
  let completed = {
    let generated = match work.generate_terminal_content() {
      Ok(value) => value
      Err(issue) => local_terminal_content_stop(issue)
    }
    let (candidate, custody) = match generated.prepare_custody() {
      Ok(value) => value
      Err(issue) => local_terminal_content_stop(issue)
    }
    business.terminal_content_custody = Some(custody)
    match generated.persist_generation(candidate, custody) {
      Ok(value) => value
      Err(issue) => local_terminal_content_stop(issue)
    }
  }
  let results = match
    completed.publication_results(run.retention, run.result_payload_bytes) {
    Ok(value) => value
    Err(issue) => local_terminal_content_stop(issue)
  }
  business.publication_results = Some(results)
  let service = match work.publication_service() {
    Ok(value) => value
    Err(issue) => local_terminal_content_stop(issue)
  }
  business._retained_publication_service = Some(service)
  let pending = match
    completed.prepare_publication(
      service, results, normalization, authoring, intent, occurrence,
    ) {
    Ok(value) => value
    Err(TerminalContentPublication(issue)) => {
      let original : @local_host.NativeClientValuesPublicationIssue = Publication(
        issue,
      )
      business.publication_failure = Some(original)
      local_publication_failure_tags(original, native_timing_amount)
      stop("LocalResultPublicationNotReady")
    }
    Err(issue) => local_terminal_content_stop(issue)
  }
  business.publication_pending = Some(pending)
  local_commit_original_publication(
    selection, settings, request, reference, business, operation, publisher, pending,
    evidence_entries,
  )
}
