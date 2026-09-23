///|
pub struct EffectLedgerBasis {
  logical_request_scope_cid : String
  logical_item_locator_cid : String
  unit_definition_cid : String
  original_membership_cid : String
  intent_fingerprint_cid : String
  effect_preview_cid : String
  dispatch_key_cid : String
  canonical_request_cid : String
  recovery_contract_cid : String
  capability : String
  reservation_evidence_cid : String
  retention_contract_cid : String
}

///|
pub fn prepare_effect_ledger_basis(
  scope : LogicalRequestScope,
  locator : LogicalItemLocator,
  key : EffectDispatchKey,
  unit_definition_cid : String,
  original_membership_cid : String,
  intent_fingerprint_cid : String,
  canonical_request_cid : String,
  recovery_contract_cid : String,
  capability : String,
  reservation_evidence_cid : String,
  retention_contract_cid : String,
) -> Result[EffectLedgerBasis, EffectLedgerIssue] {
  if locator.logical_request_scope_cid != scope.cid ||
    key.logical_request_scope_cid != scope.cid ||
    !effect_cid_valid(unit_definition_cid) ||
    !effect_cid_valid(original_membership_cid) ||
    !effect_cid_valid(intent_fingerprint_cid) ||
    !effect_cid_valid(canonical_request_cid) ||
    !effect_cid_valid(recovery_contract_cid) ||
    !effect_cid_valid(reservation_evidence_cid) ||
    !effect_cid_valid(retention_contract_cid) ||
    !(capability == "native" ||
    capability == "stamped" ||
    capability == "natural_key" ||
    capability == "unavailable") {
    return Err(InvalidIdentity)
  }
  Ok({
    logical_request_scope_cid: scope.cid,
    logical_item_locator_cid: locator.cid,
    unit_definition_cid,
    original_membership_cid,
    intent_fingerprint_cid,
    effect_preview_cid: key.effect_preview_cid,
    dispatch_key_cid: key.cid,
    canonical_request_cid,
    recovery_contract_cid,
    capability,
    reservation_evidence_cid,
    retention_contract_cid,
  })
}

///|
priv struct EffectLedgerDraft {
  basis : EffectLedgerBasis
  state : EffectRowState
  fence : Int64
  attempt_sequence : Int64
  prior_entry_cid : String?
  outcome_receipt_cid : String?
}

///|
fn ledger_state_text(state : EffectRowState) -> String {
  match state {
    Prepared => "prepared"
    Dispatching => "dispatching"
    Applied => "applied"
    Accepted => "accepted"
    Failed => "failed"
    Unknown => "unknown"
  }
}

///|
fn ledger_optional_string(
  writer : @encode.Writer,
  value : String?,
) -> Unit raise @encode.EncodeFailure {
  match value {
    Some(text) => @encode.string_value(writer, text)
    None => @encode.null_value(writer)
  }
}

///|
fn emit_ledger_draft(
  draft : EffectLedgerDraft,
  self_cid : String?,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  let basis = draft.basis
  @encode.begin_object(writer)
  @encode.key(writer, "attempt_sequence")
  @encode.number_value(writer, draft.attempt_sequence.to_double())
  @encode.key(writer, "canonical_request_cid")
  @encode.string_value(writer, basis.canonical_request_cid)
  @encode.key(writer, "capability")
  @encode.string_value(writer, basis.capability)
  @encode.key(writer, "dispatch_key")
  @encode.string_value(writer, basis.dispatch_key_cid)
  @encode.key(writer, "effect_preview_cid")
  @encode.string_value(writer, basis.effect_preview_cid)
  @encode.key(writer, "fence")
  @encode.number_value(writer, draft.fence.to_double())
  @encode.key(writer, "intent_fingerprint_cid")
  @encode.string_value(writer, basis.intent_fingerprint_cid)
  @encode.key(writer, "logical_item_locator_cid")
  @encode.string_value(writer, basis.logical_item_locator_cid)
  @encode.key(writer, "logical_request_scope_cid")
  @encode.string_value(writer, basis.logical_request_scope_cid)
  @encode.key(writer, "original_membership_cid")
  @encode.string_value(writer, basis.original_membership_cid)
  @encode.key(writer, "outcome_receipt_cid")
  ledger_optional_string(writer, draft.outcome_receipt_cid)
  @encode.key(writer, "prior_entry_cid")
  ledger_optional_string(writer, draft.prior_entry_cid)
  @encode.key(writer, "recovery_contract_cid")
  @encode.string_value(writer, basis.recovery_contract_cid)
  @encode.key(writer, "reservation_evidence_cid")
  @encode.string_value(writer, basis.reservation_evidence_cid)
  @encode.key(writer, "retention_contract_cid")
  @encode.string_value(writer, basis.retention_contract_cid)
  if self_cid is Some(cid) {
    @encode.key(writer, "self_cid")
    @encode.string_value(writer, cid)
  }
  @encode.key(writer, "state")
  @encode.string_value(writer, ledger_state_text(draft.state))
  @encode.key(writer, "unit_definition_cid")
  @encode.string_value(writer, basis.unit_definition_cid)
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-logical-item-ledger-entry/0.1")
  @encode.end_object(writer)
}

///|
fn issue_ledger_draft(
  draft : EffectLedgerDraft,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[EffectLedgerEntry, EffectLedgerIssue] {
  if max_wire_bytes < 1 ||
    max_wire_bytes > 1000000 ||
    max_nodes < 20 ||
    max_nodes > 1000 ||
    max_depth < 1 ||
    max_depth > 32 {
    return Err(InvalidLimits)
  }
  let body_writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  let body = try {
    emit_ledger_draft(draft, None, body_writer)
    @encode.finish(body_writer)
  } catch {
    _ => return Err(Encoding)
  }
  let cid = "sha256:" + @sha.hex(@utf8.encode(body))
  let wire_writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  let wire = try {
    emit_ledger_draft(draft, Some(cid), wire_writer)
    @encode.finish(wire_writer)
  } catch {
    _ => return Err(Encoding)
  }
  admit_effect_ledger_entry(wire, max_wire_bytes, max_nodes, max_depth)
}

///|
pub fn issue_prepared_effect_ledger_entry(
  basis : EffectLedgerBasis,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[EffectLedgerEntry, EffectLedgerIssue] {
  issue_ledger_draft(
    {
      basis,
      state: Prepared,
      fence: 1L,
      attempt_sequence: 0L,
      prior_entry_cid: None,
      outcome_receipt_cid: None,
    },
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}

///|
pub fn issue_next_effect_ledger_entry(
  prior : EffectLedgerEntry,
  next_state : String,
  outcome_receipt_cid : String?,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[EffectLedgerEntry, EffectLedgerIssue] {
  guard ledger_state(next_state) is Some(state) &&
    prior.fence < 9007199254740991L &&
    prior.attempt_sequence < 9007199254740991L else {
    return Err(InvalidTransition)
  }
  if outcome_receipt_cid is Some(cid) && !effect_cid_valid(cid) {
    return Err(InvalidShape)
  }
  let basis : EffectLedgerBasis = {
    logical_request_scope_cid: prior.logical_request_scope_cid,
    logical_item_locator_cid: prior.logical_item_locator_cid,
    unit_definition_cid: prior.unit_definition_cid,
    original_membership_cid: prior.original_membership_cid,
    intent_fingerprint_cid: prior.intent_fingerprint_cid,
    effect_preview_cid: prior.effect_preview_cid,
    dispatch_key_cid: prior.dispatch_key_cid,
    canonical_request_cid: prior.canonical_request_cid,
    recovery_contract_cid: prior.recovery_contract_cid,
    capability: prior.capability,
    reservation_evidence_cid: prior.reservation_evidence_cid,
    retention_contract_cid: prior.retention_contract_cid,
  }
  let issued = match
    issue_ledger_draft(
      {
        basis,
        state,
        fence: prior.fence + 1L,
        attempt_sequence: if prior.state is Prepared {
          prior.attempt_sequence + 1L
        } else {
          prior.attempt_sequence
        },
        prior_entry_cid: Some(prior.cid),
        outcome_receipt_cid,
      },
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if !effect_ledger_entry_follows(Some(prior), issued) {
    return Err(InvalidTransition)
  }
  Ok(issued)
}
