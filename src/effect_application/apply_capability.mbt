///|
/// The selected physical route is distinct from the authored row policy.
/// A collection route cannot implement ordered halt by relying on a batch
/// response, even if that response preserves its input order.
pub(all) enum EffectApplyRoute {
  SingleSerial
  CollectionContinue
} derive(Debug, Eq)

///|
pub(all) enum EffectMutationAtomicity {
  PerItem
  ProviderBatchAtomic
  UnknownAtomicity
} derive(Debug, Eq)

///|
pub(all) enum EffectFailureGranularity {
  PerItemFailure
  WholeRequestFailure
  UnknownFailureGranularity
} derive(Debug, Eq)

///|
pub(all) enum EffectUnknownReconciliation {
  ExactReconciliation
  ManualReconciliation
  NoReconciliation
} derive(Debug, Eq)

///|
pub(all) enum EffectIdempotencySupport {
  NativeIdempotency
  EmulatedIdempotency
  UnavailableIdempotency
} derive(Debug, Eq)

///|
pub struct EffectApplyCapabilityObservation {
  evidence_cid : String
  route : EffectApplyRoute
  atomicity : EffectMutationAtomicity
  failure_granularity : EffectFailureGranularity
  row_error_identity : Bool
  request_order_preserved : Bool
  idempotency : EffectIdempotencySupport
  reconciliation : EffectUnknownReconciliation
}

///|
pub(all) enum EffectApplyCapabilityIssue {
  InvalidEvidence
  InvalidCode
  InvalidLimits
  InventoryMismatch
  CapacityExceeded
  ForeignEvidence(Int)
  UnsupportedPolicy(Int)
  UnknownWithoutReconciliation(Int)
} derive(Debug)

///|
/// The caller must obtain this observation from the currently registered
/// implementation under Site authority. Supplying a CID and flags here does
/// not authenticate that implementation or grant permission to mutate.
pub fn prepare_effect_apply_capability_observation(
  evidence_cid : String,
  route : EffectApplyRoute,
  atomicity : EffectMutationAtomicity,
  failure_granularity : EffectFailureGranularity,
  row_error_identity : Bool,
  request_order_preserved : Bool,
  idempotency : EffectIdempotencySupport,
  reconciliation : EffectUnknownReconciliation,
) -> Result[EffectApplyCapabilityObservation, EffectApplyCapabilityIssue] {
  if !effect_cid_valid(evidence_cid) {
    return Err(InvalidEvidence)
  }
  Ok({
    evidence_cid,
    route,
    atomicity,
    failure_granularity,
    row_error_identity,
    request_order_preserved,
    idempotency,
    reconciliation,
  })
}

///|
/// Code projection for environment adapters. It never authenticates the
/// supplied evidence; the registered Site boundary must do that first.
pub fn prepare_effect_apply_capability_from_codes(
  evidence_cid : String,
  route_code : Int,
  atomicity_code : Int,
  failure_code : Int,
  row_error_identity : Bool,
  request_order_preserved : Bool,
  idempotency_code : Int,
  reconciliation_code : Int,
) -> Result[EffectApplyCapabilityObservation, EffectApplyCapabilityIssue] {
  let route = match route_code {
    0 => SingleSerial
    1 => CollectionContinue
    _ => return Err(InvalidCode)
  }
  let atomicity = match atomicity_code {
    0 => PerItem
    1 => ProviderBatchAtomic
    2 => UnknownAtomicity
    _ => return Err(InvalidCode)
  }
  let failure_granularity = match failure_code {
    0 => PerItemFailure
    1 => WholeRequestFailure
    2 => UnknownFailureGranularity
    _ => return Err(InvalidCode)
  }
  let reconciliation = match reconciliation_code {
    0 => ExactReconciliation
    1 => ManualReconciliation
    2 => NoReconciliation
    _ => return Err(InvalidCode)
  }
  let idempotency = match idempotency_code {
    0 => NativeIdempotency
    1 => EmulatedIdempotency
    2 => UnavailableIdempotency
    _ => return Err(InvalidCode)
  }
  prepare_effect_apply_capability_observation(
    evidence_cid, route, atomicity, failure_granularity, row_error_identity, request_order_preserved,
    idempotency, reconciliation,
  )
}

///|
pub fn effect_apply_capability_idempotency_mode(
  value : EffectApplyCapabilityObservation,
) -> String {
  match value.idempotency {
    NativeIdempotency => "native"
    EmulatedIdempotency => "emulated"
    UnavailableIdempotency => "unavailable"
  }
}

///|
pub fn effect_apply_capability_reconciliation_mode(
  value : EffectApplyCapabilityObservation,
) -> String {
  match value.reconciliation {
    ExactReconciliation => "exact"
    ManualReconciliation => "manual"
    NoReconciliation => "unavailable"
  }
}

///|
/// Check the complete selected-route inventory before any member sends.
/// This is one apply-admission obligation, not an apply permit: source,
/// target guards, approval, payload and current grant remain separate.
pub fn check_effect_preview_apply_capabilities(
  preview : @publication.EffectPreviewIdentity,
  observations : Array[EffectApplyCapabilityObservation],
  max_members : Int,
  max_work : Int,
) -> Result[Unit, EffectApplyCapabilityIssue] {
  let count = @publication.effect_preview_member_count(preview)
  if max_members < 1 || max_members > 1000 || max_work < 1 {
    return Err(InvalidLimits)
  }
  if count < 1 || count > max_members || observations.length() != count {
    return Err(InventoryMismatch)
  }
  if count > max_work {
    return Err(CapacityExceeded)
  }
  for index in 0..<count {
    let observation = observations[index]
    if @publication.effect_preview_member_capability_evidence_cid(
        preview, index,
      ) !=
      Some(observation.evidence_cid) {
      return Err(ForeignEvidence(index))
    }
    if observation.reconciliation == NoReconciliation {
      return Err(UnknownWithoutReconciliation(index))
    }
    let policy = @publication.effect_preview_member_failure_policy(
      preview, index,
    )
    if observation.atomicity != PerItem ||
      observation.failure_granularity != PerItemFailure ||
      !observation.row_error_identity ||
      (
        policy == Some("halt") &&
        (
          observation.route != SingleSerial ||
          !observation.request_order_preserved
        )
      ) ||
      (
        policy == Some("continue") &&
        observation.route != SingleSerial &&
        observation.route != CollectionContinue
      ) ||
      (policy != Some("halt") && policy != Some("continue")) {
      return Err(UnsupportedPolicy(index))
    }
  }
  Ok(())
}
