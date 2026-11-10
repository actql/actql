///|
priv enum LocalSavedEffectCompletionIssue {
  Member(@effect.EffectMemberReceiptEvidenceIssue)
  Set(@publication.EffectSetApplyReceiptIssuanceIssue)
  Final(@publication.EffectfulFinalReceiptIssuanceIssue)
  Admission(@publication.EffectfulPublicationCommitIssue)
}

///|
// Actual publication children of this SAME saved application. This carrier
// owns no issuer or cleanup authority. Failed payload/cancellation/commit
// originals remain here until their existing Store owners acknowledge them.
priv struct LocalNativeSavedEffectPublication {
  members : Array[@publication.PublicationContract]
  bindings : Array[@publication.PublicationContract]
  schemas : Array[String]
  generations : Array[String]
  mut failed_generation : String?
  mut output_failure : @local_publication.NativePublicationOutputIssue?
  mut pending : @local_publication.NativePreparedEffectfulRunPublication?
  mut _retained_cleanup_failure : @local_publication.NativeEffectfulPublicationCancellationIssue?
  mut commit_attempted : Bool
  mut committed : @local_publication.NativeRunPublicationResult?
}

///|
fn LocalCommandPreparationOriginal::publish_saved_effect_files(
  self : Self,
  capture : @local_host.NativeLocalJournalCapture,
  configuration : LocalCommandConfiguration,
  run : LocalRunInstallation,
  continuation : @local_host.NativeLocalEffectResumeOriginal,
) -> String raise ClientStop {
  guard self.business is Some(business) &&
    business.saved_effect_files is Some(work) &&
    work.child is None &&
    work.reservation is None &&
    !work.response_pending &&
    work.publication is None &&
    business.operation is Some(operation) &&
    business.store is Some(store) &&
    self.host is Some(_) &&
    capture.original_host() is Some(host) else {
    stop("LocalSavedEffectPublicationUnavailable")
  }
  let original = continuation
    .application_original_in_original_read()
    .unwrap_or_else(() => stop("LocalCheckpointOriginalUnavailable"))
  let materials = original.run_materials()
  let request = materials.request.unwrap_or_else(() => {
    stop("LocalCheckpointOriginalUnavailable")
  })
  let preview = original.effect_preview()
  let limits = original.publication_limits()
  let (invocation, manifest, receipt, captured, computation) = original.computation_publication_originals()
  let (
    definitions,
    artifacts,
    derivations,
    orderings,
    retentions,
    schema_wires,
    codec_cids,
  ) = original.result_publication_originals()
  let saved : LocalNativeSavedEffectPublication = {
    members: [],
    bindings: [],
    schemas: [],
    generations: [],
    failed_generation: None,
    output_failure: None,
    pending: None,
    _retained_cleanup_failure: None,
    commit_attempted: false,
    committed: None,
  }
  work.publication = Some(saved)
  for member_index in 0..<@publication.effect_preview_member_count(preview) {
    let scopes = []
    let locators = []
    let keys = []
    let bases = []
    let heads = []
    let active = []
    let receipts = []
    for terminal in work.receipts {
      if terminal.member_index == member_index {
        if terminal.ordinal != heads.length() {
          stop("LocalSavedEffectReceiptOrderUnavailable")
        }
        scopes.push(original.request_scope())
        locators.push(terminal.locator)
        keys.push(terminal.key)
        bases.push(terminal.basis)
        heads.push(Some(terminal.head))
        // Each retained terminal is appended ONLY after its SAME child close
        // acknowledged and its attempt reservation settled. A pending child
        // or unrecorded response above prevents this publication boundary.
        active.push(work.child is Some(_))
        receipts.push(Some(terminal.receipt))
      }
    }
    let member_receipt = @effect.issue_effect_member_receipt_from_row_partition(
        preview,
        member_index,
        scopes,
        locators,
        keys,
        bases,
        heads,
        active,
        receipts,
        heads.length(),
        limits.max_wire_bytes,
        limits.max_nodes,
        limits.max_depth,
      ).map_err(issue => CommandSavedEffectCompletion(Member(issue)))
      |> command_preparation_result
    saved.members.push(member_receipt)
  }
  let member_wires = saved.members.map(value => {
    @publication.publication_contract_json(value)
  })
  // All members in THIS fresh application were actually dispatched and
  // settled; no historical receipt/Unknown is upgraded to a fresh outcome.
  let set_receipt = @publication.issue_effect_set_apply_receipt_from_members(
      preview,
      saved.members,
      Array::make(saved.members.length(), false),
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    ).map_err(issue => CommandSavedEffectCompletion(Set(issue)))
    |> command_preparation_result
  let set_wire = @publication.publication_contract_json(set_receipt)
  let final_receipt = @publication.issue_effectful_final_run_receipt(
      materials.run_definition,
      receipt,
      captured,
      preview,
      set_wire,
      member_wires,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    ).map_err(issue => CommandSavedEffectCompletion(Final(issue)))
    |> command_preparation_result
  let final_evidence = @publication.admit_retained_effectful_final_run_evidence(
      materials.run_definition,
      invocation,
      definitions,
      artifacts,
      derivations,
      orderings,
      retentions,
      manifest,
      receipt,
      captured,
      preview,
      set_wire,
      member_wires,
      @publication.publication_contract_json(final_receipt),
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
      computation=Some(computation),
    ).map_err(issue => CommandSavedEffectCompletion(Admission(issue)))
    |> command_preparation_result
  let settings = configuration.settings
  let publisher = host
    .bind_original_run_publisher(
      operation,
      settings.principal,
      settings.connection,
      request,
      materials.run_definition,
      settings.run_file.unwrap_or_else(() => {
        stop("LocalRunInstallationRequired")
      }),
      store,
    )
    .unwrap_or_else(() => stop("LocalPublisherAuthorityUnavailable"))
  business.publication_publisher = Some(publisher)
  let now = local_utc_now()
  let intent : @local_publication.NativeRunPublicationIntent = {
    namespace_id: run.namespace_id,
    authority_scope_cid: @run_host.client_request_authority_scope_cid(request),
    publication_policy_cid: publisher.publication_policy_cid(),
    publication_target_cid: run.store_authority_cid,
    requested_at: now,
  }
  let occurrence : @local_publication.NativeRunPublicationOccurrence = {
    attempt_id: publisher
    .sample_original_generation_cid()
    .unwrap_or_else(() => stop("LocalGenerationUnavailable")),
    fence_cid: publisher
    .sample_original_generation_cid()
    .unwrap_or_else(() => stop("LocalGenerationUnavailable")),
    external_idempotency_key: None,
    started_at: now,
    committed_at: now,
  }
  let service = continuation
    .install_saved_publication_service_in_original_read(
      publisher,
      store,
      run.namespace_id,
    )
    .map_err(issue => CommandSavedEffectPublication(issue))
    |> command_preparation_result
  business._retained_publication_service = Some(service)
  let evidence : @local_publication.NativeEffectfulPublicationEvidence = {
    final_evidence,
    run_definition: materials.run_definition,
    invocation,
    definitions,
    artifacts,
    derivations,
    orderings,
    retentions,
    bindings: saved.bindings,
    binding_schema_wires: saved.schemas,
    manifest,
    receipt: final_receipt,
    captured_run: captured,
  }
  let preparation = @local_publication.prepare_effectful_run_publication_native(
      service, evidence, intent, occurrence,
    ).map_err(issue => CommandSavedEffectPublication(Service(issue)))
    |> command_preparation_result
  for
    index in 0..<@publication.retained_effectful_computation_result_count(
      computation,
    ) {
    let snapshot = @publication.retained_effectful_computation_result_at(
      computation, index,
    ).unwrap_or_else(() => stop("LocalSavedEffectResultUnavailable"))
    let generation = publisher
      .sample_original_generation_cid()
      .unwrap_or_else(() => stop("LocalGenerationUnavailable"))
    // Retain the original occurrence BEFORE the helper can acquire a writer.
    // Only its successful payload or an explicit cleanup failure is reclaimed.
    saved.failed_generation = Some(generation)
    let result = match
      @local_publication.persist_effectful_result_snapshot_native(
        store,
        snapshot,
        {
          run_definition: materials.run_definition,
          invocation,
          retention: retentions[index],
          publication_attempt: preparation.publication_attempt(),
          store_authority_cid: run.store_authority_cid,
          material_generation_cid: generation,
          max_payload_bytes: run.result_payload_bytes,
        },
        orderings[index],
        schema_wires[index],
        codec_cids[index],
        limits.max_wire_bytes,
        limits.max_nodes,
        limits.max_depth,
      ) {
      Ok(value) => value
      Err(issue) => {
        saved.output_failure = Some(issue)
        self.retain_primary(CommandSavedEffectOutput(issue))
        stop("LocalSavedEffectResultPersistenceUnavailable")
      }
    }
    saved.generations.push(generation)
    saved.failed_generation = None
    saved.bindings.push(result.binding)
    saved.schemas.push(result.binding_schema_wire)
  }
  let pending = @local_publication.prepare_retained_effectful_run_publication_native(
      service, evidence, intent, occurrence, preparation,
    ).map_err(issue => CommandSavedEffectPublication(Service(issue)))
    |> command_preparation_result
  saved.pending = Some(pending)
  saved.commit_attempted = true
  let committed = pending
    .commit()
    .map_err(issue => CommandSavedEffectPublication(Service(issue)))
    |> command_preparation_result
  saved.committed = Some(committed)
  if !committed.committed && !committed.idempotent {
    stop("LocalPublicationNeedsReconciliation")
  }
  let observed = host
    .observe_effectful_publication_run_state(
      publisher,
      pending,
      local_utc_now(),
      limits.max_nodes,
      16,
      1000,
    )
    .unwrap_or_else(() => stop("LocalRunStateNeedsReconciliation"))
  business.run_receipt_original = Some(FreshRunReceipt(observed))
  continuation
  .retain_saved_publication_state_in_original_read(
    observed,
    @env.now().to_double(),
  )
  .map_err(issue => CommandSavedEffectPublication(issue))
  |> command_preparation_result
  |> state => { state.wire() }
}

///|
fn LocalCommandPreparationOriginal::close_saved_effect_publication(
  self : Self,
  work : LocalNativeSavedEffectFileWork,
) -> Result[Unit, LocalCommandPreparationIssue] {
  guard work.publication is Some(saved) else { return Ok(()) }
  guard self.business is Some(business) && business.store is Some(store) else {
    return Err(CommandBusinessPublication)
  }
  if saved.commit_attempted && saved.committed is None {
    return Err(CommandBusinessPublication)
  }
  if saved.committed is None {
    if saved.output_failure is Some(Store(_)) &&
      saved.failed_generation is Some(_) {
      // begin_payload did not supply a writer/cancellation acknowledgment.
      // The original Store's pending constructor/recovery remains required;
      // absence or a thrown reply cannot clear its generation/custody here.
      return Err(CommandBusinessPublication)
    }
    if saved.pending is Some(pending) {
      match pending.cancel() {
        Ok(true) => ()
        Ok(false) => return Err(CommandBusinessPublication)
        Err(issue) => {
          saved._retained_cleanup_failure = Some(issue)
          return Err(CommandBusinessPublication)
        }
      }
    } else {
      if saved.output_failure
        is Some(
          SnapshotCleanup(_, _)
          | OutputCleanup(_, _)
          | StoreCleanup(_, _)
          | BindingCleanup(_, _)
        ) &&
        saved.failed_generation is Some(generation) {
        match store.reclaim_payload(generation) {
          Ok(_) => saved.failed_generation = None
          Err(issue) => return Err(CommandBusinessStore(issue))
        }
      }
      for generation in saved.generations {
        match store.reclaim_payload(generation) {
          Ok(_) => ()
          Err(issue) => return Err(CommandBusinessStore(issue))
        }
      }
    }
  }
  saved.pending = None
  saved.generations.clear()
  saved.bindings.clear()
  saved.schemas.clear()
  saved.members.clear()
  saved.failed_generation = None
  saved.output_failure = None
  saved._retained_cleanup_failure = None
  work.publication = None
  Ok(())
}
