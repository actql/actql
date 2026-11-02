///|
// Exact previous original admission/order retained only for paired Source comparison.
fn original_range_recovery_for_comparison(
  binding : RangeBinding,
  effects_wire : String,
  recovery_wire : String,
  limits : Limits,
) -> Result[Array[Array[RangeRequest]], RangeFailure] {
  guard range_parse(effects_wire, limits, "SheetsRangeRecoveryMismatch")
    is Ok(Array(effects)) &&
    range_parse(recovery_wire, limits, "SheetsRangeRecoveryMismatch")
    is Ok(Array(saved)) &&
    saved.length() == effects.length() else {
    return Err(range_failure("SheetsRangeRecoveryMismatch"))
  }
  let output = []
  for index, effect in effects {
    guard effect is Object(effect_fields) &&
      effect_fields.get("effect_id") is Some(String(effect_id)) &&
      effect_fields.get("effect_kind") == Some("command".to_json()) &&
      effect_fields.get("resolved_command_contract_cid") ==
      Some(binding.command_cid.to_json()) &&
      effect_fields.get("changes") is Some(Array(changes)) else {
      return Err(range_failure("SheetsRangeRecoveryMismatch"))
    }
    let entries = saved.filter(entry => {
      guard entry is Object(entry) else { return false }
      range_integer(entry.get("memberIndex")) == Some(index) &&
      entry.get("kind") == Some("sheets-range-request".to_json())
    })
    guard entries.length() == 1 &&
      entries[0] is Object(entry) &&
      entry.get("wire") is Some(String(wire)) &&
      @utf8.encode(wire).length() <= range_saved_recovery_wire_byte_limit() &&
      entry.get("observationCid") is Some(String(cid)) &&
      range_parse(wire, limits, "SheetsRangeRecoveryMismatch") is Ok(value) &&
      range_canonical(value, limits) == Ok(wire) &&
      range_content_cid(value, limits) == Ok(cid) &&
      range_recovery_value(binding, effect_id) is Ok(expected) &&
      range_canonical(expected, limits) == Ok(wire) else {
      return Err(range_failure("SheetsRangeRecoveryMismatch"))
    }
    let requests = []
    for change in changes {
      guard change is Object(change) &&
        change.get("intended_changes") is Some(Object(intended)) &&
        intended.get("value") is Some(value) &&
        change.get("target_row_identity") is Some(target) &&
        range_canonical(value, binding.limits) is Ok(value_wire) &&
        range_canonical(target, binding.limits) is Ok(target_wire) else {
        return Err(range_failure("SheetsRangeRecoveryMismatch"))
      }
      match prepare_range_request(binding, value_wire, target_wire) {
        Ok(request) => requests.push(request)
        Err(issue) => return Err(issue)
      }
    }
    output.push(requests)
  }
  Ok(output)
}

///|
fn range_recovery_comparison_result(
  value : Result[Array[Array[RangeRequest]], RangeFailure],
) -> Result[Array[Array[(String, String)]], RangeFailure] {
  value.map(groups => {
    groups.map(rows => {
      rows.map(request => {
        (range_request_identity(request), range_request_body(request))
      })
    })
  })
}

///|
test "range original metadata reuse preserves old request bytes identity and exact refusal results" {
  let binding = owned_binding()
  let effects = owned_effect(binding)
  let recovery = owned_recovery(binding)
  let saved = @json.parse(recovery) catch { _ => fail("authored recovery") }
  guard saved is Array(entries) &&
    entries[0] is Object(entry) &&
    entry["wire"] is String(original_wire) else {
    fail("authored entry")
  }
  let metadata = @json.parse(original_wire) catch {
    _ => fail("authored metadata")
  }
  guard metadata is Object(fields) else { fail("authored fields") }
  fields["foreign"] = "é\n".repeat(128).to_json()
  let unrelated_wire = range_canonical(metadata, owned_limits()).unwrap()
  entry["wire"] = unrelated_wire.to_json()
  let unrelated = saved.stringify()
  let cases = [
    (effects, recovery),
    (effects, "[]"),
    (effects, recovery.replace(old="replace", new="foreign-effect")),
    (effects, recovery.replace(old="bbbbbbbb", new="cccccccc")),
    (effects, recovery.replace(old="sheets-range-request", new="foreign")),
    (effects, recovery.replace(old="memberIndex", new="unknownIndex")),
    (effects, unrelated),
    ("[]", recovery),
    (owned_effect(binding, effect_id="different-effect"), recovery),
    (effects.replace(old="command", new="update"), recovery),
    (effects, recovery.replace(old="sha256:af832292", new="sha256:bf832292")),
  ]
  let limits = [
    owned_limits(),
    { max_bytes: 100000, max_nodes: 64, max_depth: 2, max_cells: 6400, },
    { max_bytes: 1000, max_nodes: 8, max_depth: 1, max_cells: 6400, },
    { max_bytes: 300000, max_nodes: 0, max_depth: 32, max_cells: 6400, },
  ]
  for (selected_effects, selected_recovery) in cases {
    for limit in limits {
      assert_eq(
        range_recovery_comparison_result(
          recover_range_requests(
            binding, selected_effects, selected_recovery, limit,
          ),
        ),
        range_recovery_comparison_result(
          original_range_recovery_for_comparison(
            binding, selected_effects, selected_recovery, limit,
          ),
        ),
      )
    }
  }
}
