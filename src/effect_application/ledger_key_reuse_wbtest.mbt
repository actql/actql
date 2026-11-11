// Exact original admission from 0385cb72bd, renamed only for a paired
// normalization-reuse regression. The original issue ordering remains oracle.

///|
fn original_ledger_admission_before_key_reuse(
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
test "Ledger admission reuses Source-normalized keys with identical original typed outcomes" {
  let wire = ledger_test_wire(
    "prepared", 1, 0, "", "", "sha256:349ed4835945b58a37a980a9acae09bbfd5703f10cc7b6aa8f6a308933f207d8",
  )
  let inputs = [
    wire,
    "{}",
    "[]",
    "{\"é\":0,\"é\":1}",
    "{\"é\":0}",
    "{\"line\\r\\nkey\":0}",
    "{\"雪\":true}",
    "{\"x\":-0}",
    "{\"x\":\"\\uD800\"}",
    "not JSON",
    wire.replace(old=ledger_test_cid("4"), new=ledger_test_cid("f")),
    wire.replace(old="unavailable", new="雪"),
    wire.replace(old="\"attempt_sequence\"", new="\"attempt_sequenc\\u0065\""),
    "{\"" + "雪".repeat(200) + "\":0}",
  ]
  for input in inputs {
    for
      (bytes, nodes, depth) in [
        (4096, 64, 3),
        (4096, 20, 1),
        (0, 64, 3),
        (4096, 19, 3),
        (4096, 64, 0),
      ] {
      let before = original_ledger_admission_before_key_reuse(
        input, bytes, nodes, depth,
      )
      let after = admit_effect_ledger_entry(input, bytes, nodes, depth)
      match (before, after) {
        (Err(left), Err(right)) => assert_eq(right, left)
        (Ok(left), Ok(right)) => {
          assert_eq(
            effect_ledger_entry_wire(right),
            effect_ledger_entry_wire(left),
          )
          assert_eq(
            effect_ledger_entry_cid(right),
            effect_ledger_entry_cid(left),
          )
          assert_eq(
            effect_ledger_entry_state_code(right),
            effect_ledger_entry_state_code(left),
          )
          assert_eq(right.fence, left.fence)
          assert_eq(right.attempt_sequence, left.attempt_sequence)
          assert_eq(
            right.logical_request_scope_cid,
            left.logical_request_scope_cid,
          )
          assert_eq(
            right.logical_item_locator_cid,
            left.logical_item_locator_cid,
          )
        }
        _ => fail("original Ledger key-normalization outcome changed")
      }
    }
  }
}
