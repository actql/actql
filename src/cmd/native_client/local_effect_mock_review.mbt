///|
// SAME accepted Request/ModelWork and original complete computation chain.
// The Host owns key derivation, paired Store custody and Journal waiting;
// this thin caller neither substitutes a Source owner nor issues approval.
fn LocalCommandBusinessPreparation::persist_mock_effect_review(
  self : LocalCommandBusinessPreparation,
  installation : LocalRunInstallation,
) -> Unit raise ClientStop {
  guard self.original.business is Some(business) &&
    business.store is Some(store) &&
    business.model_work.length() == 1 &&
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
  match
    business.model_work[0].save_effect_review_in_original_read(
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
    ) {
    Ok(_) => ()
    Err(issue) => {
      self.original.retain_primary(CommandBusinessModel(issue))
      stop("LocalOriginalEffectReviewPersistenceUnavailable")
    }
  }
}
