///|
pub(all) enum EffectLedgerIssue {
  InvalidLimits
  InvalidWire
  InvalidShape
  InvalidIdentity
  InvalidTransition
  Encoding
} derive(Eq, Debug)

///|
pub struct EffectLedgerEntry {
  wire : String
  cid : String
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
  state : EffectRowState
  fence : Int64
  attempt_sequence : Int64
  prior_entry_cid : String?
  outcome_receipt_cid : String?
  reservation_evidence_cid : String
  retention_contract_cid : String
}

///|
fn ledger_string(value : @json.CanonicalValue, field : String) -> String? {
  match @json.object_field(value, field) {
    Some(@json.String(text)) => Some(text)
    _ => None
  }
}

///|
fn ledger_cid(value : @json.CanonicalValue, field : String) -> String? {
  match ledger_string(value, field) {
    Some(text) if effect_cid_valid(text) => Some(text)
    _ => None
  }
}

///|
fn ledger_optional_cid(
  value : @json.CanonicalValue,
  field : String,
) -> Result[String?, EffectLedgerIssue] {
  match @json.object_field(value, field) {
    Some(@json.Null) => Ok(None)
    Some(@json.String(text)) if effect_cid_valid(text) => Ok(Some(text))
    _ => Err(InvalidShape)
  }
}

///|
fn ledger_integer(
  value : @json.CanonicalValue,
  field : String,
  minimum : Int64,
) -> Int64? {
  match @json.object_field(value, field) {
    Some(@json.Number(number)) => {
      if number < minimum.to_double() || number > 9007199254740991.0 {
        return None
      }
      let integer = number.to_int64()
      if integer.to_double() != number {
        return None
      }
      Some(integer)
    }
    _ => None
  }
}

///|
fn ledger_state(text : String) -> EffectRowState? {
  match text {
    "prepared" => Some(Prepared)
    "dispatching" => Some(Dispatching)
    "applied" => Some(Applied)
    "accepted" => Some(Accepted)
    "failed" => Some(Failed)
    "unknown" => Some(Unknown)
    _ => None
  }
}

///|
pub fn admit_effect_ledger_entry(
  wire : String,
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
  let parsed = match
    @source.parse_json(wire, {
      max_input_bytes: max_wire_bytes,
      max_nodes,
      max_depth,
    }) {
    Ok(value) => value
    Err(_) => return Err(InvalidWire)
  }
  let value = @json.from_source(parsed, max_nodes, max_depth, max_wire_bytes) catch {
    _ => return Err(InvalidWire)
  }
  let canonical = @json.stringify_value(
    value, max_wire_bytes, max_nodes, max_depth,
  ) catch {
    _ => return Err(Encoding)
  }
  if canonical != wire {
    return Err(InvalidWire)
  }
  guard @json.object_fields(value) is Some(fields) &&
    fields.length() == 19 &&
    ledger_string(value, "version") ==
    Some("actql-logical-item-ledger-entry/0.1") &&
    ledger_cid(value, "logical_request_scope_cid")
    is Some(logical_request_scope_cid) &&
    ledger_cid(value, "logical_item_locator_cid")
    is Some(logical_item_locator_cid) &&
    ledger_cid(value, "unit_definition_cid") is Some(unit_definition_cid) &&
    ledger_cid(value, "original_membership_cid")
    is Some(original_membership_cid) &&
    ledger_cid(value, "intent_fingerprint_cid") is Some(intent_fingerprint_cid) &&
    ledger_cid(value, "effect_preview_cid") is Some(effect_preview_cid) &&
    ledger_cid(value, "dispatch_key") is Some(dispatch_key_cid) &&
    ledger_cid(value, "canonical_request_cid") is Some(canonical_request_cid) &&
    ledger_cid(value, "recovery_contract_cid") is Some(recovery_contract_cid) &&
    ledger_cid(value, "reservation_evidence_cid")
    is Some(reservation_evidence_cid) &&
    ledger_cid(value, "retention_contract_cid") is Some(retention_contract_cid) &&
    ledger_string(value, "capability") is Some(capability) &&
    (
      capability == "native" ||
      capability == "stamped" ||
      capability == "natural_key" ||
      capability == "unavailable"
    ) &&
    ledger_string(value, "state") is Some(state_text) &&
    ledger_state(state_text) is Some(state) &&
    ledger_integer(value, "fence", 1L) is Some(fence) &&
    ledger_integer(value, "attempt_sequence", 0L) is Some(attempt_sequence) &&
    ledger_cid(value, "self_cid") is Some(cid) else {
    return Err(InvalidShape)
  }
  let prior_entry_cid = match ledger_optional_cid(value, "prior_entry_cid") {
    Ok(result) => result
    Err(issue) => return Err(issue)
  }
  let outcome_receipt_cid = match
    ledger_optional_cid(value, "outcome_receipt_cid") {
    Ok(result) => result
    Err(issue) => return Err(issue)
  }
  guard @json.object_without_field(value, "self_cid") is Some(body) else {
    return Err(InvalidShape)
  }
  let expected = @json.cid_value(body, max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  if expected != cid {
    return Err(InvalidIdentity)
  }
  Ok({
    wire,
    cid,
    logical_request_scope_cid,
    logical_item_locator_cid,
    unit_definition_cid,
    original_membership_cid,
    intent_fingerprint_cid,
    effect_preview_cid,
    dispatch_key_cid,
    canonical_request_cid,
    recovery_contract_cid,
    capability,
    state,
    fence,
    attempt_sequence,
    prior_entry_cid,
    outcome_receipt_cid,
    reservation_evidence_cid,
    retention_contract_cid,
  })
}

///|
pub fn effect_ledger_entry_cid(entry : EffectLedgerEntry) -> String {
  entry.cid
}

///|
pub fn effect_ledger_entry_locator_cid(entry : EffectLedgerEntry) -> String {
  entry.logical_item_locator_cid
}

///|
pub fn effect_ledger_entry_scope_cid(entry : EffectLedgerEntry) -> String {
  entry.logical_request_scope_cid
}

///|
pub fn effect_ledger_entry_wire(entry : EffectLedgerEntry) -> String {
  entry.wire
}

///|
/// The physical adapter must additionally confirm that this exact entry is
/// the durable Store head. A valid in-memory entry alone is not send authority.
pub fn effect_ledger_entry_admits_dispatch(
  entry : EffectLedgerEntry,
  scope : LogicalRequestScope,
  locator : LogicalItemLocator,
  key : EffectDispatchKey,
  canonical_request_cid : String,
) -> Bool {
  entry.state == Dispatching &&
  entry.logical_request_scope_cid == scope.cid &&
  entry.logical_item_locator_cid == locator.cid &&
  entry.effect_preview_cid == key.effect_preview_cid &&
  entry.dispatch_key_cid == key.cid &&
  entry.canonical_request_cid == canonical_request_cid
}

///|
/// An exact retry must retain every immutable basis field, not just the
/// row key and physical request CID used for recovery classification.
pub fn effect_ledger_entry_matches_basis(
  entry : EffectLedgerEntry,
  basis : EffectLedgerBasis,
) -> Bool {
  entry.logical_request_scope_cid == basis.logical_request_scope_cid &&
  entry.logical_item_locator_cid == basis.logical_item_locator_cid &&
  entry.unit_definition_cid == basis.unit_definition_cid &&
  entry.original_membership_cid == basis.original_membership_cid &&
  entry.intent_fingerprint_cid == basis.intent_fingerprint_cid &&
  entry.effect_preview_cid == basis.effect_preview_cid &&
  entry.dispatch_key_cid == basis.dispatch_key_cid &&
  entry.canonical_request_cid == basis.canonical_request_cid &&
  entry.recovery_contract_cid == basis.recovery_contract_cid &&
  entry.capability == basis.capability &&
  entry.reservation_evidence_cid == basis.reservation_evidence_cid &&
  entry.retention_contract_cid == basis.retention_contract_cid
}

///|
/// Validate the immutable intent and append-only chain. Physical CAS still
/// belongs to the Store; this check alone never admits an HTTP mutation.
pub fn effect_ledger_entry_follows(
  previous : EffectLedgerEntry?,
  next : EffectLedgerEntry,
) -> Bool {
  match previous {
    None =>
      next.state == Prepared &&
      next.fence == 1L &&
      next.attempt_sequence == 0L &&
      next.prior_entry_cid is None &&
      next.outcome_receipt_cid is None
    Some(prior) => {
      if prior.logical_request_scope_cid != next.logical_request_scope_cid ||
        prior.logical_item_locator_cid != next.logical_item_locator_cid ||
        prior.unit_definition_cid != next.unit_definition_cid ||
        prior.original_membership_cid != next.original_membership_cid ||
        prior.intent_fingerprint_cid != next.intent_fingerprint_cid ||
        prior.effect_preview_cid != next.effect_preview_cid ||
        prior.dispatch_key_cid != next.dispatch_key_cid ||
        prior.canonical_request_cid != next.canonical_request_cid ||
        prior.recovery_contract_cid != next.recovery_contract_cid ||
        prior.capability != next.capability ||
        prior.reservation_evidence_cid != next.reservation_evidence_cid ||
        prior.retention_contract_cid != next.retention_contract_cid ||
        prior.fence == 9007199254740991L ||
        next.fence != prior.fence + 1L ||
        next.prior_entry_cid != Some(prior.cid) {
        return false
      }
      match prior.state {
        Prepared =>
          next.state == Dispatching &&
          prior.attempt_sequence < 9007199254740991L &&
          next.attempt_sequence == prior.attempt_sequence + 1L &&
          next.outcome_receipt_cid is None
        Dispatching =>
          (
            next.state == Applied ||
            next.state == Accepted ||
            next.state == Failed ||
            next.state == Unknown
          ) &&
          next.attempt_sequence == prior.attempt_sequence &&
          (next.state == Unknown || next.outcome_receipt_cid is Some(_))
        Unknown =>
          (
            next.state == Applied ||
            next.state == Accepted ||
            next.state == Failed ||
            next.state == Unknown
          ) &&
          next.attempt_sequence == prior.attempt_sequence &&
          (next.state == Unknown || next.outcome_receipt_cid is Some(_))
        Applied | Accepted | Failed => false
      }
    }
  }
}
