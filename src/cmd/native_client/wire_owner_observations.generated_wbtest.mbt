// Generated from spec/contracts/actql-client-host.json.
// Run: node scripts/generate-client-host-wire.mjs --write

///|
fn wire_rule_961(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "run" ||
    text == "effect" ||
    text == "publication" ||
    text == "delivery" ||
    text == "site") {
    return false
  }
  true
}

///|
fn wire_owner_ref_shape(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "kind" || key == "scopeCid" || key == "streamCid") {
      return false
    }
  }
  if !fields.contains("kind") {
    return false
  }
  if !fields.contains("scopeCid") {
    return false
  }
  if !fields.contains("streamCid") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_961(item) {
      return false
    }
  }
  if fields.get("scopeCid") is Some(item) {
    if !wire_rule_1(item) {
      return false
    }
  }
  if fields.get("streamCid") is Some(item) {
    if !wire_rule_1(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_965(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if text.iter().count() < 1 {
    return false
  }
  if text.length() > 8192 {
    return false
  }
  true
}

///|
fn wire_owner_cursor_shape(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "owner" || key == "value") {
      return false
    }
  }
  if !fields.contains("owner") {
    return false
  }
  if !fields.contains("value") {
    return false
  }
  if fields.get("owner") is Some(item) {
    if !wire_owner_ref_shape(item) {
      return false
    }
  }
  if fields.get("value") is Some(item) {
    if !wire_rule_965(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_967(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "non_atomic") {
    return false
  }
  true
}

///|
fn wire_rule_968(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "owner_local") {
    return false
  }
  true
}

///|
fn wire_rule_973(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "unavailable") {
    return false
  }
  true
}

///|
fn wire_rule_975(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "acquisition_failed" ||
    text == "limit_exceeded" ||
    text == "history_unrecoverable" ||
    text == "cursor_mismatch") {
    return false
  }
  true
}

///|
fn wire_rule_974(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "kind") {
      return false
    }
  }
  if !fields.contains("kind") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_975(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_971(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "owner" || key == "kind" || key == "problem") {
      return false
    }
  }
  if !fields.contains("owner") {
    return false
  }
  if !fields.contains("kind") {
    return false
  }
  if fields.get("owner") is Some(item) {
    if !wire_rule_961(item) {
      return false
    }
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_973(item) {
      return false
    }
  }
  if fields.get("problem") is Some(item) {
    if !wire_rule_974(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_977(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "run") {
    return false
  }
  true
}

///|
fn wire_rule_979(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "observed") {
    return false
  }
  true
}

///|
fn wire_rule_982(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "not_provided") {
    return false
  }
  true
}

///|
fn wire_rule_981(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "kind") {
      return false
    }
  }
  if !fields.contains("kind") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_982(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_984(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "retention_expired") {
    return false
  }
  true
}

///|
fn wire_rule_983(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "kind") {
      return false
    }
  }
  if !fields.contains("kind") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_984(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_986(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "history_unrecoverable") {
    return false
  }
  true
}

///|
fn wire_rule_985(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "kind") {
      return false
    }
  }
  if !fields.contains("kind") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_986(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_988(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "cursor_mismatch") {
    return false
  }
  true
}

///|
fn wire_rule_987(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "kind") {
      return false
    }
  }
  if !fields.contains("kind") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_988(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_990(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "cursor_expired") {
    return false
  }
  true
}

///|
fn wire_rule_989(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "kind") {
      return false
    }
  }
  if !fields.contains("kind") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_990(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_992(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "limit_exceeded") {
    return false
  }
  true
}

///|
fn wire_rule_991(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "kind") {
      return false
    }
  }
  if !fields.contains("kind") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_992(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_994(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "acquisition_failed") {
    return false
  }
  true
}

///|
fn wire_rule_993(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "kind") {
      return false
    }
  }
  if !fields.contains("kind") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_994(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_996(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "page") {
    return false
  }
  true
}

///|
fn wire_rule_1001(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "prepared" ||
    text == "dispatching" ||
    text == "applied" ||
    text == "accepted" ||
    text == "failed" ||
    text == "unknown") {
    return false
  }
  true
}

///|
fn wire_rule_998(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "revision" || key == "entryCid" || key == "state") {
      return false
    }
  }
  if !fields.contains("revision") {
    return false
  }
  if !fields.contains("entryCid") {
    return false
  }
  if !fields.contains("state") {
    return false
  }
  if fields.get("revision") is Some(item) {
    if !wire_rule_4(item) {
      return false
    }
  }
  if fields.get("entryCid") is Some(item) {
    if !wire_rule_1(item) {
      return false
    }
  }
  if fields.get("state") is Some(item) {
    if !wire_rule_1001(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_997(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  if items.length() > 1000 {
    return false
  }
  for item in items {
    if !wire_rule_998(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_995(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "kind" || key == "entries" || key == "cursor") {
      return false
    }
  }
  if !fields.contains("kind") {
    return false
  }
  if !fields.contains("entries") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_996(item) {
      return false
    }
  }
  if fields.get("entries") is Some(item) {
    if !wire_rule_997(item) {
      return false
    }
  }
  if fields.get("cursor") is Some(item) {
    if !wire_owner_cursor_shape(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_980(value : Json) -> Bool {
  if [
      wire_rule_981(value),
      wire_rule_983(value),
      wire_rule_985(value),
      wire_rule_987(value),
      wire_rule_989(value),
      wire_rule_991(value),
      wire_rule_993(value),
      wire_rule_995(value),
    ]
    .filter(fn(ok) { ok })
    .length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_rule_1009(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "waiting_checkpoint") {
    return false
  }
  true
}

///|
fn wire_rule_1008(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("status") {
    return false
  }
  if fields.get("status") is Some(item) {
    if !wire_rule_1009(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1012(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "resolve_checkpoint") {
    return false
  }
  true
}

///|
fn wire_rule_1011(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("kind") {
    return false
  }
  if !fields.contains("checkpoint_id") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_1012(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1010(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("checkpoint") {
    return false
  }
  if fields.get("next_action") is Some(item) {
    if !wire_rule_1011(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1007(value : Json) -> Bool {
  if wire_rule_1008(value) && !wire_rule_1010(value) {
    return false
  }
  true
}

///|
fn wire_rule_1015(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "needs_reconciliation") {
    return false
  }
  true
}

///|
fn wire_rule_1014(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("status") {
    return false
  }
  if fields.get("status") is Some(item) {
    if !wire_rule_1015(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1017(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("checkpoint") {
    return false
  }
  true
}

///|
fn wire_rule_1020(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "reconcile") {
    return false
  }
  true
}

///|
fn wire_rule_1021(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  if items.length() < 1 {
    return false
  }
  for item in items {
    if !wire_rule_676(item) {
      return false
    }
  }
  let seen : Map[String, Bool] = Map([])
  for item in items {
    guard item is String(text) else { return false }
    if seen.contains(text) {
      return false
    }
    seen[text] = true
  }
  true
}

///|
fn wire_rule_1019(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "kind" || key == "effects") {
      return false
    }
  }
  if !fields.contains("kind") {
    return false
  }
  if !fields.contains("effects") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_1020(item) {
      return false
    }
  }
  if fields.get("effects") is Some(item) {
    if !wire_rule_1021(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1024(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "reconcile_run") {
    return false
  }
  true
}

///|
fn wire_rule_1025(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "execution_unknown") {
    return false
  }
  true
}

///|
fn wire_rule_1023(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "kind" || key == "reason") {
      return false
    }
  }
  if !fields.contains("kind") {
    return false
  }
  if !fields.contains("reason") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_1024(item) {
      return false
    }
  }
  if fields.get("reason") is Some(item) {
    if !wire_rule_1025(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1018(value : Json) -> Bool {
  if [wire_rule_1019(value), wire_rule_1023(value)]
    .filter(fn(ok) { ok })
    .length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_rule_1016(value : Json) -> Bool {
  if wire_rule_1017(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  if fields.get("next_action") is Some(item) {
    if !wire_rule_1018(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1013(value : Json) -> Bool {
  if wire_rule_1014(value) && !wire_rule_1016(value) {
    return false
  }
  true
}

///|
fn wire_rule_1028(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "succeeded") {
    return false
  }
  true
}

///|
fn wire_rule_1027(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("status") {
    return false
  }
  if fields.get("status") is Some(item) {
    if !wire_rule_1028(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1032(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "read_result" || text == "refresh_availability" || text == "none") {
    return false
  }
  true
}

///|
fn wire_rule_1031(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("kind") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_1032(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1029(value : Json) -> Bool {
  if wire_rule_1017(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  if fields.get("next_action") is Some(item) {
    if !wire_rule_1031(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1026(value : Json) -> Bool {
  if wire_rule_1027(value) && !wire_rule_1029(value) {
    return false
  }
  true
}

///|
fn wire_rule_1035(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "preparing" ||
    text == "running" ||
    text == "resuming" ||
    text == "failed" ||
    text == "cancelled") {
    return false
  }
  true
}

///|
fn wire_rule_1034(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("status") {
    return false
  }
  if fields.get("status") is Some(item) {
    if !wire_rule_1035(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1039(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "none") {
    return false
  }
  true
}

///|
fn wire_rule_1038(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("kind") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_1039(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1036(value : Json) -> Bool {
  if wire_rule_1017(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  if fields.get("next_action") is Some(item) {
    if !wire_rule_1038(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1033(value : Json) -> Bool {
  if wire_rule_1034(value) && !wire_rule_1036(value) {
    return false
  }
  true
}

///|
fn wire_rule_1042(_value : Json) -> Bool {
  true
}

///|
fn wire_rule_1041(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("result_availability") {
    return false
  }
  if fields.get("result_availability") is Some(item) {
    if !wire_rule_1042(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1046(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "none" ||
    text == "resolve_checkpoint" ||
    text == "reconcile" ||
    text == "reconcile_run") {
    return false
  }
  true
}

///|
fn wire_rule_1045(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("kind") is Some(item) {
    if !wire_rule_1046(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1043(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("result_available") is Some(item) {
    if !wire_rule_663(item) {
      return false
    }
  }
  if fields.get("next_action") is Some(item) {
    if !wire_rule_1045(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1040(value : Json) -> Bool {
  if wire_rule_1041(value) && !wire_rule_1043(value) {
    return false
  }
  true
}

///|
fn wire_rule_1047(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "actql-run-state/0.1") {
    return false
  }
  true
}

///|
fn wire_rule_1049(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "preparing" ||
    text == "running" ||
    text == "waiting_checkpoint" ||
    text == "resuming" ||
    text == "needs_reconciliation" ||
    text == "succeeded" ||
    text == "failed" ||
    text == "cancelled") {
    return false
  }
  true
}

///|
fn wire_rule_1050(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if text.length() != 24 {
    return false
  }
  let mut index = 0
  for character in text {
    let separator = match index {
      4 | 7 => Some('-')
      10 => Some('T')
      13 | 16 => Some(':')
      19 => Some('.')
      23 => Some('Z')
      _ => None
    }
    match separator {
      Some(expected) => if character != expected { return false }
      None => if character < '0' || character > '9' { return false }
    }
    index = index + 1
  }
  true
}

///|
fn wire_rule_1054(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "run_scope" ||
    text == "read_access" ||
    text == "data_egress" ||
    text == "cost_scope" ||
    text == "effect_set" ||
    text == "model_invocation") {
    return false
  }
  true
}

///|
fn wire_rule_1051(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "checkpoint_id" || key == "checkpoint_cid" || key == "kind") {
      return false
    }
  }
  if !fields.contains("checkpoint_id") {
    return false
  }
  if !fields.contains("checkpoint_cid") {
    return false
  }
  if !fields.contains("kind") {
    return false
  }
  if fields.get("checkpoint_id") is Some(item) {
    if !wire_rule_676(item) {
      return false
    }
  }
  if fields.get("checkpoint_cid") is Some(item) {
    if !wire_rule_759(item) {
      return false
    }
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_1054(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1056(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "kind" || key == "checkpoint_id") {
      return false
    }
  }
  if !fields.contains("kind") {
    return false
  }
  if !fields.contains("checkpoint_id") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_1012(item) {
      return false
    }
  }
  if fields.get("checkpoint_id") is Some(item) {
    if !wire_rule_676(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1061(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "read_result") {
    return false
  }
  true
}

///|
fn wire_rule_1060(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "kind" || key == "results") {
      return false
    }
  }
  if !fields.contains("kind") {
    return false
  }
  if !fields.contains("results") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_1061(item) {
      return false
    }
  }
  if fields.get("results") is Some(item) {
    if !wire_rule_1021(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1064(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "refresh_availability") {
    return false
  }
  true
}

///|
fn wire_rule_1063(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "kind" || key == "results") {
      return false
    }
  }
  if !fields.contains("kind") {
    return false
  }
  if !fields.contains("results") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_1064(item) {
      return false
    }
  }
  if fields.get("results") is Some(item) {
    if !wire_rule_1021(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1066(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "kind") {
      return false
    }
  }
  if !fields.contains("kind") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_1039(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1055(value : Json) -> Bool {
  if [
      wire_rule_1056(value),
      wire_rule_1019(value),
      wire_rule_1060(value),
      wire_rule_1063(value),
      wire_rule_1066(value),
      wire_rule_1023(value),
    ]
    .filter(fn(ok) { ok })
    .length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_rule_1071(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if text.length() < 9 || !text.has_prefix("ACTQL_E_") {
    return false
  }
  for character in text[8:] {
    if !((character >= 'A' && character <= 'Z') ||
      (character >= '0' && character <= '9') ||
      character == '_') {
      return false
    }
  }
  true
}

///|
fn wire_rule_1070(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "code" || key == "message") {
      return false
    }
  }
  if !fields.contains("code") {
    return false
  }
  if !fields.contains("message") {
    return false
  }
  if fields.get("code") is Some(item) {
    if !wire_rule_1071(item) {
      return false
    }
  }
  if fields.get("message") is Some(item) {
    if !wire_rule_676(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1077(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "available") {
    return false
  }
  true
}

///|
fn wire_rule_1076(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("state") {
    return false
  }
  if fields.get("state") is Some(item) {
    if !wire_rule_1077(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1079(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "confirmed_present") {
    return false
  }
  true
}

///|
fn wire_rule_1078(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("reason") is Some(item) {
    if !wire_rule_1079(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1075(value : Json) -> Bool {
  if wire_rule_1076(value) && !wire_rule_1078(value) {
    return false
  }
  true
}

///|
fn wire_rule_1081(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("state") {
    return false
  }
  if fields.get("state") is Some(item) {
    if !wire_rule_783(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1084(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "retention_expired" ||
    text == "deleted" ||
    text == "policy_unavailable" ||
    text == "integrity_failed" ||
    text == "not_published") {
    return false
  }
  true
}

///|
fn wire_rule_1083(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("reason") is Some(item) {
    if !wire_rule_1084(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1080(value : Json) -> Bool {
  if wire_rule_1081(value) && !wire_rule_1083(value) {
    return false
  }
  true
}

///|
fn wire_rule_1087(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "unknown") {
    return false
  }
  true
}

///|
fn wire_rule_1086(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("state") {
    return false
  }
  if fields.get("state") is Some(item) {
    if !wire_rule_1087(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1089(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "store_query_failed" ||
    text == "clock_uncertain" ||
    text == "verification_pending") {
    return false
  }
  true
}

///|
fn wire_rule_1088(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("reason") is Some(item) {
    if !wire_rule_1089(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1085(value : Json) -> Bool {
  if wire_rule_1086(value) && !wire_rule_1088(value) {
    return false
  }
  true
}

///|
fn wire_rule_1090(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "available" || text == "unavailable" || text == "unknown") {
    return false
  }
  true
}

///|
fn wire_rule_1092(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "confirmed_present" ||
    text == "retention_expired" ||
    text == "deleted" ||
    text == "policy_unavailable" ||
    text == "integrity_failed" ||
    text == "not_published" ||
    text == "store_query_failed" ||
    text == "clock_uncertain" ||
    text == "verification_pending") {
    return false
  }
  true
}

///|
fn wire_rule_1074(value : Json) -> Bool {
  if !wire_rule_1075(value) {
    return false
  }
  if !wire_rule_1080(value) {
    return false
  }
  if !wire_rule_1085(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "state" ||
      key == "observed_at" ||
      key == "reason" ||
      key == "cause_cid") {
      return false
    }
  }
  if !fields.contains("state") {
    return false
  }
  if !fields.contains("observed_at") {
    return false
  }
  if !fields.contains("reason") {
    return false
  }
  if fields.get("state") is Some(item) {
    if !wire_rule_1090(item) {
      return false
    }
  }
  if fields.get("observed_at") is Some(item) {
    if !wire_rule_1050(item) {
      return false
    }
  }
  if fields.get("reason") is Some(item) {
    if !wire_rule_1092(item) {
      return false
    }
  }
  if fields.get("cause_cid") is Some(item) {
    if !wire_rule_759(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1095(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if text.iter().count() < 1 {
    return false
  }
  true
}

///|
fn wire_rule_1094(value : Json) -> Bool {
  if value is String(_) {
    return wire_rule_1095(value)
  }
  true
}

///|
fn wire_rule_1073(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for _key, item in fields {
    if !false && !wire_rule_1074(item) {
      return false
    }
  }
  for key, _ in fields {
    if !wire_rule_1094(Json::string(key)) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1097(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if number != number.floor() ||
    number < -9007199254740991.0 ||
    number > 9007199254740991.0 {
    return false
  }
  if number < 0.0 {
    return false
  }
  if number > 2147483647.0 {
    return false
  }
  true
}

///|
fn wire_rule_1099(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "unknown" || text == "confirmed") {
    return false
  }
  true
}

///|
fn wire_rule_1096(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "revision" ||
      key == "cancellation_requested" ||
      key == "physical_stop") {
      return false
    }
  }
  if !fields.contains("revision") {
    return false
  }
  if !fields.contains("cancellation_requested") {
    return false
  }
  if !fields.contains("physical_stop") {
    return false
  }
  if fields.get("revision") is Some(item) {
    if !wire_rule_1097(item) {
      return false
    }
  }
  if fields.get("cancellation_requested") is Some(item) {
    if !wire_rule_367(item) {
      return false
    }
  }
  if fields.get("physical_stop") is Some(item) {
    if !wire_rule_1099(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1006(value : Json) -> Bool {
  if !wire_rule_1007(value) {
    return false
  }
  if !wire_rule_1013(value) {
    return false
  }
  if !wire_rule_1026(value) {
    return false
  }
  if !wire_rule_1033(value) {
    return false
  }
  if !wire_rule_1040(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "version" ||
      key == "run_id" ||
      key == "status" ||
      key == "updated_at" ||
      key == "checkpoint" ||
      key == "next_action" ||
      key == "result_available" ||
      key == "terminal_error" ||
      key == "result_availability" ||
      key == "control") {
      return false
    }
  }
  if !fields.contains("version") {
    return false
  }
  if !fields.contains("run_id") {
    return false
  }
  if !fields.contains("status") {
    return false
  }
  if !fields.contains("updated_at") {
    return false
  }
  if !fields.contains("next_action") {
    return false
  }
  if !fields.contains("result_available") {
    return false
  }
  if !fields.contains("result_availability") {
    return false
  }
  if fields.get("version") is Some(item) {
    if !wire_rule_1047(item) {
      return false
    }
  }
  if fields.get("run_id") is Some(item) {
    if !wire_rule_676(item) {
      return false
    }
  }
  if fields.get("status") is Some(item) {
    if !wire_rule_1049(item) {
      return false
    }
  }
  if fields.get("updated_at") is Some(item) {
    if !wire_rule_1050(item) {
      return false
    }
  }
  if fields.get("checkpoint") is Some(item) {
    if !wire_rule_1051(item) {
      return false
    }
  }
  if fields.get("next_action") is Some(item) {
    if !wire_rule_1055(item) {
      return false
    }
  }
  if fields.get("result_available") is Some(item) {
    if !wire_rule_367(item) {
      return false
    }
  }
  if fields.get("terminal_error") is Some(item) {
    if !wire_rule_1070(item) {
      return false
    }
  }
  if fields.get("result_availability") is Some(item) {
    if !wire_rule_1073(item) {
      return false
    }
  }
  if fields.get("control") is Some(item) {
    if !wire_rule_1096(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1005(value : Json) -> Bool {
  if !wire_rule_1006(value) {
    return false
  }
  true
}

///|
fn wire_rule_1003(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "revision" || key == "value") {
      return false
    }
  }
  if !fields.contains("value") {
    return false
  }
  if fields.get("revision") is Some(item) {
    if !wire_rule_3(item) {
      return false
    }
  }
  if fields.get("value") is Some(item) {
    if !wire_rule_1005(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_976(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "owner" ||
      key == "ownerRef" ||
      key == "kind" ||
      key == "history" ||
      key == "snapshot") {
      return false
    }
  }
  if !fields.contains("owner") {
    return false
  }
  if !fields.contains("ownerRef") {
    return false
  }
  if !fields.contains("kind") {
    return false
  }
  if !fields.contains("history") {
    return false
  }
  if !fields.contains("snapshot") {
    return false
  }
  if fields.get("owner") is Some(item) {
    if !wire_rule_977(item) {
      return false
    }
  }
  if fields.get("ownerRef") is Some(item) {
    if !wire_owner_ref_shape(item) {
      return false
    }
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_979(item) {
      return false
    }
  }
  if fields.get("history") is Some(item) {
    if !wire_rule_980(item) {
      return false
    }
  }
  if fields.get("snapshot") is Some(item) {
    if !wire_rule_1003(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1106(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "limit_exceeded" || text == "acquisition_failed") {
    return false
  }
  true
}

///|
fn wire_rule_1105(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "kind") {
      return false
    }
  }
  if !fields.contains("kind") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_1106(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1100(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "owner" ||
      key == "ownerRef" ||
      key == "kind" ||
      key == "history" ||
      key == "snapshotProblem") {
      return false
    }
  }
  if !fields.contains("owner") {
    return false
  }
  if !fields.contains("ownerRef") {
    return false
  }
  if !fields.contains("kind") {
    return false
  }
  if !fields.contains("history") {
    return false
  }
  if !fields.contains("snapshotProblem") {
    return false
  }
  if fields.get("owner") is Some(item) {
    if !wire_rule_977(item) {
      return false
    }
  }
  if fields.get("ownerRef") is Some(item) {
    if !wire_owner_ref_shape(item) {
      return false
    }
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_979(item) {
      return false
    }
  }
  if fields.get("history") is Some(item) {
    if !wire_rule_980(item) {
      return false
    }
  }
  if fields.get("snapshotProblem") is Some(item) {
    if !wire_rule_1105(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1108(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "effect") {
    return false
  }
  true
}

///|
fn wire_rule_1114(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "state") {
      return false
    }
  }
  if !fields.contains("state") {
    return false
  }
  if fields.get("state") is Some(item) {
    if !wire_rule_1001(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1112(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "revision" || key == "value") {
      return false
    }
  }
  if !fields.contains("value") {
    return false
  }
  if fields.get("revision") is Some(item) {
    if !wire_rule_3(item) {
      return false
    }
  }
  if fields.get("value") is Some(item) {
    if !wire_rule_1114(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1107(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "owner" ||
      key == "ownerRef" ||
      key == "kind" ||
      key == "history" ||
      key == "snapshot") {
      return false
    }
  }
  if !fields.contains("owner") {
    return false
  }
  if !fields.contains("ownerRef") {
    return false
  }
  if !fields.contains("kind") {
    return false
  }
  if !fields.contains("history") {
    return false
  }
  if !fields.contains("snapshot") {
    return false
  }
  if fields.get("owner") is Some(item) {
    if !wire_rule_1108(item) {
      return false
    }
  }
  if fields.get("ownerRef") is Some(item) {
    if !wire_owner_ref_shape(item) {
      return false
    }
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_979(item) {
      return false
    }
  }
  if fields.get("history") is Some(item) {
    if !wire_rule_980(item) {
      return false
    }
  }
  if fields.get("snapshot") is Some(item) {
    if !wire_rule_1112(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1116(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "owner" ||
      key == "ownerRef" ||
      key == "kind" ||
      key == "history" ||
      key == "snapshotProblem") {
      return false
    }
  }
  if !fields.contains("owner") {
    return false
  }
  if !fields.contains("ownerRef") {
    return false
  }
  if !fields.contains("kind") {
    return false
  }
  if !fields.contains("history") {
    return false
  }
  if !fields.contains("snapshotProblem") {
    return false
  }
  if fields.get("owner") is Some(item) {
    if !wire_rule_1108(item) {
      return false
    }
  }
  if fields.get("ownerRef") is Some(item) {
    if !wire_owner_ref_shape(item) {
      return false
    }
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_979(item) {
      return false
    }
  }
  if fields.get("history") is Some(item) {
    if !wire_rule_980(item) {
      return false
    }
  }
  if fields.get("snapshotProblem") is Some(item) {
    if !wire_rule_1105(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_970(value : Json) -> Bool {
  if [
      wire_rule_971(value),
      wire_rule_976(value),
      wire_rule_1100(value),
      wire_rule_1107(value),
      wire_rule_1116(value),
    ]
    .filter(fn(ok) { ok })
    .length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_rule_969(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  if items.length() > 5 {
    return false
  }
  for item in items {
    if !wire_rule_970(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1127(value : Json) -> Bool {
  guard value is Null else { return false }
  true
}

///|
fn wire_rule_1128(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "generation" || key == "revision" || key == "entryCid") {
      return false
    }
  }
  if !fields.contains("generation") {
    return false
  }
  if !fields.contains("revision") {
    return false
  }
  if !fields.contains("entryCid") {
    return false
  }
  if fields.get("generation") is Some(item) {
    if !wire_rule_1(item) {
      return false
    }
  }
  if fields.get("revision") is Some(item) {
    if !wire_rule_4(item) {
      return false
    }
  }
  if fields.get("entryCid") is Some(item) {
    if !wire_rule_1(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1126(value : Json) -> Bool {
  if [wire_rule_1127(value), wire_rule_1128(value)]
    .filter(fn(ok) { ok })
    .length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_rule_1123(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "owner" || key == "snapshotCid" || key == "historyHead") {
      return false
    }
  }
  if !fields.contains("owner") {
    return false
  }
  if fields.get("owner") is Some(item) {
    if !wire_owner_ref_shape(item) {
      return false
    }
  }
  if fields.get("snapshotCid") is Some(item) {
    if !wire_rule_1(item) {
      return false
    }
  }
  if fields.get("historyHead") is Some(item) {
    if !wire_rule_1126(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1122(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  if items.length() > 5 {
    return false
  }
  for item in items {
    if !wire_rule_1123(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1134(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if number != number.floor() ||
    number < -9007199254740991.0 ||
    number > 9007199254740991.0 {
    return false
  }
  if number < 0.0 {
    return false
  }
  if number > 4.0 {
    return false
  }
  true
}

///|
fn wire_rule_1133(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "index" || key == "kind") {
      return false
    }
  }
  if !fields.contains("index") {
    return false
  }
  if !fields.contains("kind") {
    return false
  }
  if fields.get("index") is Some(item) {
    if !wire_rule_1134(item) {
      return false
    }
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_973(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1132(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  if items.length() > 5 {
    return false
  }
  for item in items {
    if !wire_rule_1133(item) {
      return false
    }
  }
  true
}

///|
fn wire_owner_observations_shape(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "ref" ||
      key == "consistency" ||
      key == "ordering" ||
      key == "owners" ||
      key == "revisionVector" ||
      key == "unmatchedCursors") {
      return false
    }
  }
  if !fields.contains("ref") {
    return false
  }
  if !fields.contains("consistency") {
    return false
  }
  if !fields.contains("ordering") {
    return false
  }
  if !fields.contains("owners") {
    return false
  }
  if !fields.contains("revisionVector") {
    return false
  }
  if fields.get("ref") is Some(item) {
    if !wire_rule_13(item) {
      return false
    }
  }
  if fields.get("consistency") is Some(item) {
    if !wire_rule_967(item) {
      return false
    }
  }
  if fields.get("ordering") is Some(item) {
    if !wire_rule_968(item) {
      return false
    }
  }
  if fields.get("owners") is Some(item) {
    if !wire_rule_969(item) {
      return false
    }
  }
  if fields.get("revisionVector") is Some(item) {
    if !wire_rule_1122(item) {
      return false
    }
  }
  if fields.get("unmatchedCursors") is Some(item) {
    if !wire_rule_1132(item) {
      return false
    }
  }
  true
}
