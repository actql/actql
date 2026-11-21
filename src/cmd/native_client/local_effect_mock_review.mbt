///|
// The accepted Request and original complete computation chain.
// The Host owns key derivation, paired Store custody and Journal waiting;
// this thin caller neither substitutes a Source owner nor issues approval.
fn LocalCommandBusinessPreparation::persist_mock_effect_review(
  self : LocalCommandBusinessPreparation,
  installation : LocalRunInstallation,
) -> Unit raise ClientStop {
  guard self.original.business is Some(business) &&
    business.store is Some(store) &&
    business.effect_model is Some(state) &&
    state.proposals is Some(proposals) &&
    proposals.materials is Some(materials) &&
    state.preview is Some(preview) &&
    state.computation is Some(computation) &&
    computation._retained_manifest is Some(manifest) &&
    computation._retained_receipt is Some(receipt) &&
    computation._retained_captured is Some(captured) else {
    stop("LocalOriginalEffectReviewUnavailable")
  }
  let policy = @run_host.client_standard_effect_computation_limits()
  let persisted = if business.model_work.length() == 1 {
    let work = business.model_work[0]
    work.save_effect_review_in_original_read(
      store,
      materials,
      preview._retained_invocation,
      computation.definitions,
      computation.artifacts,
      computation.derivations,
      computation.orderings,
      computation.retentions,
      computation.schema_wires,
      computation.codec_cids,
      manifest,
      receipt,
      captured,
      @strategy.captured_effect_preview_ledger_identity(preview.inputs),
      preview._retained_wire,
      @publication.run_evidence_value_identity(preview._retained_authoring),
      installation.store_authority_cid,
      self.connection,
      native_mock_effect_record_bytes(installation),
      policy.effects.max_admission_nodes,
      policy.effects.max_admission_depth,
    )
  } else {
    guard business.model_work.is_empty() &&
      state.source_start is Some(first) &&
      state.source_review is None &&
      proposals._retained_combined_source_unit is Some(_) &&
      business.request_run is Some(run) else {
      stop("LocalOriginalEffectReviewUnavailable")
    }
    self.capture.save_original_effect_review_in_original_read(
      first,
      installation.namespace_id,
      self.principal,
      local_utc_now,
      () => self.mock_effect_source_current(state, run),
      saved => state.source_review = Some(saved),
      store,
      materials,
      preview._retained_invocation,
      computation.definitions,
      computation.artifacts,
      computation.derivations,
      computation.orderings,
      computation.retentions,
      computation.schema_wires,
      computation.codec_cids,
      manifest,
      receipt,
      captured,
      @strategy.captured_effect_preview_ledger_identity(preview.inputs),
      preview._retained_wire,
      @publication.run_evidence_value_identity(preview._retained_authoring),
      installation.store_authority_cid,
      self.connection,
      native_mock_effect_record_bytes(installation),
      policy.effects.max_admission_nodes,
      policy.effects.max_admission_depth,
    )
  }
  match persisted {
    Ok(_) => ()
    Err(issue) => {
      self.original.retain_primary(CommandBusinessModel(issue))
      stop("LocalOriginalEffectReviewPersistenceUnavailable")
    }
  }
}
