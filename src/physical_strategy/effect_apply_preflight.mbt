///|
pub(all) enum CapturedEffectApplyPreflightIssue {
  Plan(CapturedEffectPlanInventoryIssue)
  Binding(CapturedEffectCurrentBindingIssue)
  Guard(CapturedEffectGuardIssue)
  Capability(CapturedEffectCapabilityIssue)
  Risk(CapturedEffectRiskIssue)
  Keys(CapturedEffectApplyKeyIssue)
  Footprint(@effect.EffectFootprintIssue)
} derive(Debug)

///|
/// Evaluate every semantic apply obligation against one live captured Preview.
/// The Host must authenticate current observations, reviewer authority, and
/// payload custody before calling this function. A successful check is not a
/// mutation permit, a durable claim, or evidence that an HTTP request was sent.
///
/// `risk` is the Host-authenticated risk-acceptance body, when the Host has
/// one. It is required only when `require_partial_application` records that
/// the Host's declared policy for its delegated decision requires
/// `partial_application_accepted`; an account allow or a delegated permit
/// without that policy supplies none and none is fabricated. A supplied body
/// is always bound to this exact Preview and must approve its scope.
pub fn check_captured_effect_apply_preflight(
  preview : CapturedEffectPreviewInputs,
  proofs : Array[CapturedEffectPlanProof],
  source_binding_cids : Array[String],
  resolved_contract_cids : Array[String],
  capability_evidence_cids : Array[String],
  authority_scope_cids : Array[String],
  guards : Array[@effect.EffectTargetVersionObservation],
  routes : Array[@effect.EffectApplyCapabilityObservation],
  risk : @effect.EffectRiskAcceptanceBody?,
  require_partial_application : Bool,
  review_projection_cid : String,
  risk_authority_scope_cid : String,
  policy_cid : String,
  validity_evidence_cid : String,
  issuer_evidence_cid : String,
  authentication_evidence_cid : String,
  issuer_kind : String,
  decision : String,
  request_scope : @effect.LogicalRequestScope,
  keys : Array[Array[@effect.EffectDispatchKey]],
  max_members : Int,
  max_rows : Int,
  max_targets : Int,
  max_work : Int,
) -> Result[Unit, CapturedEffectApplyPreflightIssue] {
  match
    check_captured_effect_plan_proofs(preview, proofs, max_members, max_work) {
    Ok(_) => ()
    Err(issue) => return Err(CapturedEffectApplyPreflightIssue::Plan(issue))
  }
  if !captured_effect_preview_inputs_available(preview) {
    return Err(CapturedEffectApplyPreflightIssue::Binding(NotReady))
  }
  check_effect_preview_apply_semantics(
    @checked.effect_program_run_preview_identity(
      captured_effect_preview_owner(preview),
    ),
    source_binding_cids,
    resolved_contract_cids,
    capability_evidence_cids,
    authority_scope_cids,
    guards,
    routes,
    risk,
    require_partial_application,
    review_projection_cid,
    risk_authority_scope_cid,
    policy_cid,
    validity_evidence_cid,
    issuer_evidence_cid,
    authentication_evidence_cid,
    issuer_kind,
    decision,
    request_scope,
    keys,
    max_members,
    max_rows,
    max_targets,
    max_work,
  )
}

///|
/// Recheck the common whole-set semantic obligations from an admitted
/// private Preview. Recovery must independently establish the exact durable
/// captured Run, prior Plan proof, current Store holdings, and authenticated
/// current observations. This check is neither a send permit nor a substitute
/// for those physical and historical obligations.
pub fn check_effect_preview_apply_semantics(
  identity : @publication.EffectPreviewIdentity,
  source_binding_cids : Array[String],
  resolved_contract_cids : Array[String],
  capability_evidence_cids : Array[String],
  authority_scope_cids : Array[String],
  guards : Array[@effect.EffectTargetVersionObservation],
  routes : Array[@effect.EffectApplyCapabilityObservation],
  risk : @effect.EffectRiskAcceptanceBody?,
  require_partial_application : Bool,
  review_projection_cid : String,
  risk_authority_scope_cid : String,
  policy_cid : String,
  validity_evidence_cid : String,
  issuer_evidence_cid : String,
  authentication_evidence_cid : String,
  issuer_kind : String,
  decision : String,
  request_scope : @effect.LogicalRequestScope,
  keys : Array[Array[@effect.EffectDispatchKey]],
  max_members : Int,
  max_rows : Int,
  max_targets : Int,
  max_work : Int,
  recovery_guards? : @effect.RecoveredEffectTargetGuards,
) -> Result[Unit, CapturedEffectApplyPreflightIssue] {
  match
    check_effect_preview_current_bindings(
      identity, source_binding_cids, resolved_contract_cids, capability_evidence_cids,
      authority_scope_cids, max_members, max_work,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(CapturedEffectApplyPreflightIssue::Binding(issue))
  }
  let guard_check = match recovery_guards {
    None =>
      @effect.check_effect_preview_target_guards(
        identity, guards, max_rows, max_work,
      )
    Some(recovered) =>
      @effect.check_recovered_effect_target_guards(
        identity, request_scope, recovered, guards, max_rows, max_work,
      )
  }
  match guard_check {
    Ok(_) => ()
    Err(issue) =>
      return Err(CapturedEffectApplyPreflightIssue::Guard(Current(issue)))
  }
  match
    @effect.check_effect_preview_apply_capabilities(
      identity, routes, max_members, max_work,
    ) {
    Ok(_) => ()
    Err(issue) =>
      return Err(CapturedEffectApplyPreflightIssue::Capability(Current(issue)))
  }
  match risk {
    Some(body) =>
      match
        @effect.check_effect_risk_acceptance_body(
          identity, body, review_projection_cid, risk_authority_scope_cid, policy_cid,
          validity_evidence_cid, issuer_evidence_cid, authentication_evidence_cid,
          issuer_kind, decision, require_partial_application,
        ) {
        Ok(_) => ()
        Err(issue) =>
          return Err(CapturedEffectApplyPreflightIssue::Risk(Risk(issue)))
      }
    None =>
      if require_partial_application {
        return Err(
          CapturedEffectApplyPreflightIssue::Risk(
            Risk(@effect.EffectRiskAcceptanceIssue::MissingPartialAcceptance),
          ),
        )
      }
  }
  match
    check_effect_preview_apply_keys(
      identity, request_scope, keys, max_rows, max_work,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(CapturedEffectApplyPreflightIssue::Keys(issue))
  }
  match
    @effect.check_admitted_effect_preview_footprint_conflicts(
      identity, max_members, max_targets, max_work,
    ) {
    Ok(_) => ()
    Err(issue) =>
      return Err(CapturedEffectApplyPreflightIssue::Footprint(issue))
  }
  Ok(())
}
