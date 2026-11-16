///|
// The public 0.1 Ledger entry is a flat nineteen-field object. For the
// synthetic Prepared -> Dispatching pair, eleven basis CIDs plus self/prior
// are all 71 ASCII bytes; both counters are one digit. Fixed keys,
// separators, version/state, numbers and null outcome contribute 477 bytes;
// thirteen CIDs add 923, hence 1400 before the capability spelling. The
// Prepared wire is 72 bytes
// shorter. Both have twenty value nodes and depth one.
// This proves only codec eligibility, never an entry CID, durable state or
// permission. Tighter or unsupported codecs keep their original issuer path.
const EFFECT_LEDGER_CLAIM_DISPATCH_FIXED_BYTES : Int = 1400

///|
/// 0: use the original codec; 1: exact immutable facts match; 2: mismatch.
/// This replaces only construction of temporary Prepared/Dispatching entries
/// for a binding comparison. Durable heads, frontier, current and grants are
/// independently checked by their existing owners on every use.
pub fn effect_ledger_claim_facts_status(
  basis : EffectLedgerBasis,
  scope : LogicalRequestScope,
  locator : LogicalItemLocator,
  key : EffectDispatchKey,
  intent_fingerprint_cid : String,
  canonical_request_cid : String,
  expected_scope_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Int {
  // Eligibility precedes fact comparison, preserving the original codec's
  // refusal precedence even when an unsupported caller also changes facts.
  if max_wire_bytes < 1 ||
    max_wire_bytes > 1000000 ||
    max_nodes < 20 ||
    max_nodes > 1000 ||
    max_depth < 1 ||
    max_depth > 32 {
    return 0
  }
  if !(basis.capability == "native" ||
    basis.capability == "stamped" ||
    basis.capability == "natural_key" ||
    basis.capability == "unavailable") ||
    !effect_cid_valid(basis.logical_request_scope_cid) ||
    !effect_cid_valid(basis.logical_item_locator_cid) ||
    !effect_cid_valid(basis.unit_definition_cid) ||
    !effect_cid_valid(basis.original_membership_cid) ||
    !effect_cid_valid(basis.intent_fingerprint_cid) ||
    !effect_cid_valid(basis.effect_preview_cid) ||
    !effect_cid_valid(basis.dispatch_key_cid) ||
    !effect_cid_valid(basis.canonical_request_cid) ||
    !effect_cid_valid(basis.recovery_contract_cid) ||
    !effect_cid_valid(basis.reservation_evidence_cid) ||
    !effect_cid_valid(basis.retention_contract_cid) ||
    max_wire_bytes <
    EFFECT_LEDGER_CLAIM_DISPATCH_FIXED_BYTES + basis.capability.length() {
    return 0
  }
  // Exactly the former prepared scope, Dispatching admission, and Prepared
  // recovery-action comparisons. The opaque Basis already owns the other
  // immutable fields; fresh head validation still compares all of those too.
  if basis.logical_request_scope_cid != expected_scope_cid ||
    basis.logical_request_scope_cid != logical_request_scope_cid(scope) ||
    basis.logical_item_locator_cid != locator.cid ||
    basis.effect_preview_cid != key.effect_preview_cid ||
    basis.dispatch_key_cid != key.cid ||
    basis.canonical_request_cid != canonical_request_cid ||
    basis.intent_fingerprint_cid != intent_fingerprint_cid ||
    locator.logical_request_scope_cid != key.logical_request_scope_cid {
    2
  } else {
    1
  }
}
