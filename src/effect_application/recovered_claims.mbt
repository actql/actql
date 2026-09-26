///|
pub(all) enum EffectRecoveredClaimIssue {
  InvalidLimits
  ForeignPreviewRow(Int, Int)
  MissingHead(Int, Int)
  ForeignHead(Int, Int)
} derive(Eq, Debug)

///|
/// A locator derived from an admitted Preview. It only identifies a durable
/// row head; it is not an apply permit or a request to send again.
pub struct EffectRecoveryBinding {
  scope : LogicalRequestScope
  locator : LogicalItemLocator
  key : EffectDispatchKey
}

///|
/// The immutable claim facts recovered from an exact durable Ledger head.
/// Current authorization and physical request custody are separate.
pub struct EffectRecoveredClaim {
  binding : EffectRecoveryBinding
  basis : EffectLedgerBasis
  intent_fingerprint_cid : String
  canonical_request_cid : String
}

///|
pub fn prepare_effect_recovery_bindings(
  preview : @publication.EffectPreviewIdentity,
  scope : LogicalRequestScope,
  program_id : String,
  node_id : String,
  max_rows : Int,
  max_work : Int,
) -> Result[Array[Array[EffectRecoveryBinding]], EffectRecoveredClaimIssue] {
  if max_rows < 1 || max_work < 1 {
    return Err(InvalidLimits)
  }
  let preview_cid = @publication.effect_preview_semantic_identity(preview)
  let program_bytes = @utf8.encode(program_id).length()
  let node_bytes = @utf8.encode(node_id).length()
  let bindings : Array[Array[EffectRecoveryBinding]] = []
  let mut work = 0
  let mut total_rows = 0
  for member_index in 0..<@publication.effect_preview_member_count(preview) {
    work += 1
    if work > max_work {
      return Err(InvalidLimits)
    }
    guard @publication.effect_preview_member_effect_id(preview, member_index)
      is Some(effect_id) &&
      @publication.effect_preview_member_kind(preview, member_index)
      is Some(effect_kind) &&
      @publication.effect_preview_row_count(preview, member_index)
      is Some(row_count) &&
      row_count <= max_rows - total_rows else {
      return Err(InvalidLimits)
    }
    total_rows += row_count
    let effect_bytes = @utf8.encode(effect_id).length()
    let mut name_bytes = program_bytes
    if node_bytes > name_bytes {
      name_bytes = node_bytes
    }
    if effect_bytes > name_bytes {
      name_bytes = effect_bytes
    }
    let rows : Array[EffectRecoveryBinding] = []
    for row_index in 0..<row_count {
      work += 1
      if work > max_work {
        return Err(InvalidLimits)
      }
      guard @publication.effect_preview_ordered_row_correlation_wire(
          preview, member_index, row_index,
        )
        is Some(correlation) &&
        @publication.effect_preview_ordered_row_identity(
          preview, member_index, row_index,
        )
        is Some(row_cid) else {
        return Err(ForeignPreviewRow(member_index, row_index))
      }
      let item_bytes = @utf8.encode(correlation).length()
      let key = match
        prepare_effect_dispatch_key(
          scope, preview_cid, correlation, item_bytes, 1000, 32,
        ) {
        Ok(value) => value
        Err(_) => return Err(ForeignPreviewRow(member_index, row_index))
      }
      let locator = match
        prepare_logical_item_locator(
          scope, program_id, node_id, effect_id, correlation, name_bytes, item_bytes,
          1000, 32,
        ) {
        Ok(value) => value
        Err(_) => return Err(ForeignPreviewRow(member_index, row_index))
      }
      if admit_effect_single_row(
          preview, member_index, row_index, effect_kind, scope, row_cid, locator,
          key,
        )
        is Err(_) {
        return Err(ForeignPreviewRow(member_index, row_index))
      }
      rows.push({ scope, locator, key, })
    }
    bindings.push(rows)
  }
  Ok(bindings)
}

///|
pub fn effect_recovery_binding_locator_cid(
  binding : EffectRecoveryBinding,
) -> String {
  binding.locator.cid
}

///|
/// Reconstruct only rows that already have a durable exact head. A missing
/// head cannot be treated as unsent without a separately retained intent.
pub fn recover_effect_claims_from_heads(
  bindings : Array[Array[EffectRecoveryBinding]],
  heads : Array[Array[EffectLedgerEntry?]],
  max_rows : Int,
) -> Result[Array[Array[EffectRecoveredClaim]], EffectRecoveredClaimIssue] {
  if max_rows < 1 || bindings.length() != heads.length() {
    return Err(InvalidLimits)
  }
  let claims : Array[Array[EffectRecoveredClaim]] = []
  let mut total_rows = 0
  for member_index in 0..<bindings.length() {
    let row_bindings = bindings[member_index]
    let row_heads = heads[member_index]
    if row_bindings.length() != row_heads.length() ||
      row_bindings.length() > max_rows - total_rows {
      return Err(InvalidLimits)
    }
    total_rows += row_bindings.length()
    let rows : Array[EffectRecoveredClaim] = []
    for row_index in 0..<row_bindings.length() {
      let binding = row_bindings[row_index]
      guard row_heads[row_index] is Some(head) else {
        return Err(MissingHead(member_index, row_index))
      }
      let basis = match
        prepare_effect_ledger_basis(
          binding.scope,
          binding.locator,
          binding.key,
          head.unit_definition_cid,
          head.original_membership_cid,
          head.intent_fingerprint_cid,
          head.canonical_request_cid,
          head.recovery_contract_cid,
          head.capability,
          head.reservation_evidence_cid,
          head.retention_contract_cid,
        ) {
        Ok(value) => value
        Err(_) => return Err(ForeignHead(member_index, row_index))
      }
      if !effect_ledger_entry_matches_basis(head, basis) {
        return Err(ForeignHead(member_index, row_index))
      }
      rows.push({
        binding,
        basis,
        intent_fingerprint_cid: head.intent_fingerprint_cid,
        canonical_request_cid: head.canonical_request_cid,
      })
    }
    claims.push(rows)
  }
  Ok(claims)
}

///|
pub fn effect_recovered_claim_scope(
  claim : EffectRecoveredClaim,
) -> LogicalRequestScope {
  claim.binding.scope
}

///|
pub fn effect_recovered_claim_locator(
  claim : EffectRecoveredClaim,
) -> LogicalItemLocator {
  claim.binding.locator
}

///|
pub fn effect_recovered_claim_key(
  claim : EffectRecoveredClaim,
) -> EffectDispatchKey {
  claim.binding.key
}

///|
pub fn effect_recovered_claim_basis(
  claim : EffectRecoveredClaim,
) -> EffectLedgerBasis {
  claim.basis
}

///|
pub fn effect_recovered_claim_intent_fingerprint_cid(
  claim : EffectRecoveredClaim,
) -> String {
  claim.intent_fingerprint_cid
}

///|
pub fn effect_recovered_claim_canonical_request_cid(
  claim : EffectRecoveredClaim,
) -> String {
  claim.canonical_request_cid
}
