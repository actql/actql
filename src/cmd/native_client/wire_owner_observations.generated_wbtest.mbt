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

///|
fn wire_rule_1136(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "actql-run-plan-view/0.1") {
    return false
  }
  true
}

///|
fn wire_rule_1139(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "actql-plan-view/0.1") {
    return false
  }
  true
}

///|
fn wire_rule_1142(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "actql-logical-map/0.1") {
    return false
  }
  true
}

///|
fn wire_rule_1149(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "actql-logical-step-key/0.1") {
    return false
  }
  true
}

///|
fn wire_rule_1154(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "operation") {
    return false
  }
  true
}

///|
fn wire_rule_1153(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "kind" || key == "operation_ordinal") {
      return false
    }
  }
  if !fields.contains("kind") {
    return false
  }
  if !fields.contains("operation_ordinal") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_1154(item) {
      return false
    }
  }
  if fields.get("operation_ordinal") is Some(item) {
    if !wire_rule_919(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1157(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "input_output") {
    return false
  }
  true
}

///|
fn wire_rule_1156(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "kind" || key == "input_port_ordinal") {
      return false
    }
  }
  if !fields.contains("kind") {
    return false
  }
  if !fields.contains("input_port_ordinal") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_1157(item) {
      return false
    }
  }
  if fields.get("input_port_ordinal") is Some(item) {
    if !wire_rule_919(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1152(value : Json) -> Bool {
  if [wire_rule_1153(value), wire_rule_1156(value)]
    .filter(fn(ok) { ok })
    .length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_rule_1148(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "version" ||
      key == "compiled_plan_cid" ||
      key == "stage_ordinal" ||
      key == "occurrence" ||
      key == "self_cid") {
      return false
    }
  }
  if !fields.contains("version") {
    return false
  }
  if !fields.contains("compiled_plan_cid") {
    return false
  }
  if !fields.contains("stage_ordinal") {
    return false
  }
  if !fields.contains("occurrence") {
    return false
  }
  if !fields.contains("self_cid") {
    return false
  }
  if fields.get("version") is Some(item) {
    if !wire_rule_1149(item) {
      return false
    }
  }
  if fields.get("compiled_plan_cid") is Some(item) {
    if !wire_rule_1(item) {
      return false
    }
  }
  if fields.get("stage_ordinal") is Some(item) {
    if !wire_rule_919(item) {
      return false
    }
  }
  if fields.get("occurrence") is Some(item) {
    if !wire_rule_1152(item) {
      return false
    }
  }
  if fields.get("self_cid") is Some(item) {
    if !wire_rule_1(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1161(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if text.iter().count() < 1 {
    return false
  }
  true
}

///|
fn wire_rule_1160(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  if items.length() < 0 {
    return false
  }
  for item in items {
    if !wire_rule_1161(item) {
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
fn wire_rule_1164(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "analytic" ||
    text == "append" ||
    text == "apply_graph_delta" ||
    text == "asof_join" ||
    text == "assert_rows" ||
    text == "calendar_bucket" ||
    text == "calendar_series" ||
    text == "components" ||
    text == "cross_join" ||
    text == "dedupe_events" ||
    text == "dedupe_rows" ||
    text == "degree" ||
    text == "derive" ||
    text == "distinct" ||
    text == "drop" ||
    text == "edge_rows" ||
    text == "events" ||
    text == "except" ||
    text == "filter" ||
    text == "graft_graph" ||
    text == "graph" ||
    text == "graph_bounds" ||
    text == "graph_diff" ||
    text == "graphs_equal" ||
    text == "group" ||
    text == "infer" ||
    text == "intersect" ||
    text == "interval_join" ||
    text == "join" ||
    text == "json_pick" ||
    text == "lag" ||
    text == "match_edges" ||
    text == "match_nodes" ||
    text == "mean_graphs" ||
    text == "merge_rankings" ||
    text == "nearest" ||
    text == "nest" ||
    text == "node_rows" ||
    text == "normalize_graph" ||
    text == "normalize_vectors" ||
    text == "pivot" ||
    text == "pool_vectors" ||
    text == "reach" ||
    text == "rename" ||
    text == "row_window" ||
    text == "score_vectors" ||
    text == "select" ||
    text == "sequence" ||
    text == "session" ||
    text == "shortest_path" ||
    text == "sort" ||
    text == "subgraph" ||
    text == "subtract_graphs" ||
    text == "take" ||
    text == "text_rank" ||
    text == "time_series" ||
    text == "to_events" ||
    text == "to_vectors" ||
    text == "top_k" ||
    text == "top_k_by" ||
    text == "traverse" ||
    text == "union_graphs" ||
    text == "unnest" ||
    text == "unpivot" ||
    text == "values" ||
    text == "vectors" ||
    text == "watermark_events" ||
    text == "watermark_rows" ||
    text == "window_events" ||
    text == "window_group") {
    return false
  }
  guard value is String(text) else { return false }
  true
}

///|
fn wire_rule_1162(value : Json) -> Bool {
  if [wire_rule_1127(value), wire_rule_1164(value)]
    .filter(fn(ok) { ok })
    .length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_rule_1168(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "input" || text == "output") {
    return false
  }
  guard value is String(text) else { return false }
  true
}

///|
fn wire_rule_1170(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "relation" ||
    text == "graph" ||
    text == "vectors" ||
    text == "events") {
    return false
  }
  guard value is String(text) else { return false }
  true
}

///|
fn wire_rule_1174(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "stage_input") {
    return false
  }
  true
}

///|
fn wire_rule_1173(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "kind" || key == "stage_ordinal" || key == "input_port_ordinal") {
      return false
    }
  }
  if !fields.contains("kind") {
    return false
  }
  if !fields.contains("stage_ordinal") {
    return false
  }
  if !fields.contains("input_port_ordinal") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_1174(item) {
      return false
    }
  }
  if fields.get("stage_ordinal") is Some(item) {
    if !wire_rule_919(item) {
      return false
    }
  }
  if fields.get("input_port_ordinal") is Some(item) {
    if !wire_rule_919(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1178(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "logical_output") {
    return false
  }
  true
}

///|
fn wire_rule_1177(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "kind" || key == "step_id" || key == "output_port_id") {
      return false
    }
  }
  if !fields.contains("kind") {
    return false
  }
  if !fields.contains("step_id") {
    return false
  }
  if !fields.contains("output_port_id") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_1178(item) {
      return false
    }
  }
  if fields.get("step_id") is Some(item) {
    if !wire_rule_1(item) {
      return false
    }
  }
  if fields.get("output_port_id") is Some(item) {
    if !wire_rule_1(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1172(value : Json) -> Bool {
  if [wire_rule_1173(value), wire_rule_1177(value)]
    .filter(fn(ok) { ok })
    .length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_rule_1181(value : Json) -> Bool {
  if !(value is True || value is False) {
    return false
  }
  true
}

///|
fn wire_rule_1182(value : Json) -> Bool {
  if [wire_rule_1127(value), wire_rule_1161(value)]
    .filter(fn(ok) { ok })
    .length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_rule_1166(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "port_id" ||
      key == "role" ||
      key == "port_ordinal" ||
      key == "carrier" ||
      key == "carrier_contract_cid" ||
      key == "source" ||
      key == "can_sample" ||
      key == "sample_reason") {
      return false
    }
  }
  if !fields.contains("port_id") {
    return false
  }
  if !fields.contains("role") {
    return false
  }
  if !fields.contains("port_ordinal") {
    return false
  }
  if !fields.contains("carrier") {
    return false
  }
  if !fields.contains("carrier_contract_cid") {
    return false
  }
  if !fields.contains("source") {
    return false
  }
  if !fields.contains("can_sample") {
    return false
  }
  if !fields.contains("sample_reason") {
    return false
  }
  if fields.get("port_id") is Some(item) {
    if !wire_rule_1(item) {
      return false
    }
  }
  if fields.get("role") is Some(item) {
    if !wire_rule_1168(item) {
      return false
    }
  }
  if fields.get("port_ordinal") is Some(item) {
    if !wire_rule_919(item) {
      return false
    }
  }
  if fields.get("carrier") is Some(item) {
    if !wire_rule_1170(item) {
      return false
    }
  }
  if fields.get("carrier_contract_cid") is Some(item) {
    if !wire_rule_1(item) {
      return false
    }
  }
  if fields.get("source") is Some(item) {
    if !wire_rule_1172(item) {
      return false
    }
  }
  if fields.get("can_sample") is Some(item) {
    if !wire_rule_1181(item) {
      return false
    }
  }
  if fields.get("sample_reason") is Some(item) {
    if !wire_rule_1182(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1165(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  if items.length() < 1 {
    return false
  }
  for item in items {
    if !wire_rule_1166(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1146(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "step_id" ||
      key == "key" ||
      key == "names" ||
      key == "operator" ||
      key == "ports" ||
      key == "can_stop_before" ||
      key == "can_stop_after" ||
      key == "stop_reason") {
      return false
    }
  }
  if !fields.contains("step_id") {
    return false
  }
  if !fields.contains("key") {
    return false
  }
  if !fields.contains("names") {
    return false
  }
  if !fields.contains("operator") {
    return false
  }
  if !fields.contains("ports") {
    return false
  }
  if !fields.contains("can_stop_before") {
    return false
  }
  if !fields.contains("can_stop_after") {
    return false
  }
  if !fields.contains("stop_reason") {
    return false
  }
  if fields.get("step_id") is Some(item) {
    if !wire_rule_1(item) {
      return false
    }
  }
  if fields.get("key") is Some(item) {
    if !wire_rule_1148(item) {
      return false
    }
  }
  if fields.get("names") is Some(item) {
    if !wire_rule_1160(item) {
      return false
    }
  }
  if fields.get("operator") is Some(item) {
    if !wire_rule_1162(item) {
      return false
    }
  }
  if fields.get("ports") is Some(item) {
    if !wire_rule_1165(item) {
      return false
    }
  }
  if fields.get("can_stop_before") is Some(item) {
    if !wire_rule_1181(item) {
      return false
    }
  }
  if fields.get("can_stop_after") is Some(item) {
    if !wire_rule_1181(item) {
      return false
    }
  }
  if fields.get("stop_reason") is Some(item) {
    if !wire_rule_1182(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1145(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  if items.length() < 0 {
    return false
  }
  for item in items {
    if !wire_rule_1146(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1141(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "version" ||
      key == "compiled_plan_cid" ||
      key == "program_definition_cid" ||
      key == "steps" ||
      key == "self_cid") {
      return false
    }
  }
  if !fields.contains("version") {
    return false
  }
  if !fields.contains("compiled_plan_cid") {
    return false
  }
  if !fields.contains("program_definition_cid") {
    return false
  }
  if !fields.contains("steps") {
    return false
  }
  if !fields.contains("self_cid") {
    return false
  }
  if fields.get("version") is Some(item) {
    if !wire_rule_1142(item) {
      return false
    }
  }
  if fields.get("compiled_plan_cid") is Some(item) {
    if !wire_rule_1(item) {
      return false
    }
  }
  if fields.get("program_definition_cid") is Some(item) {
    if !wire_rule_1(item) {
      return false
    }
  }
  if fields.get("steps") is Some(item) {
    if !wire_rule_1145(item) {
      return false
    }
  }
  if fields.get("self_cid") is Some(item) {
    if !wire_rule_1(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1189(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "static") {
    return false
  }
  true
}

///|
fn wire_rule_1190(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !(number == 0.0) {
    return false
  }
  true
}

///|
fn wire_rule_1194(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "exact" || text == "bound" || text == "estimate") {
    return false
  }
  guard value is String(text) else { return false }
  true
}

///|
fn wire_rule_1195(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if text.is_empty() || (text.length() > 1 && text[0] == '0') {
    return false
  }
  for character in text {
    if character < '0' || character > '9' {
      return false
    }
  }
  true
}

///|
fn wire_rule_1193(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "kind" ||
      key == "value" ||
      key == "unit" ||
      key == "scope_cid" ||
      key == "basis_cid") {
      return false
    }
  }
  if !fields.contains("kind") {
    return false
  }
  if !fields.contains("value") {
    return false
  }
  if !fields.contains("unit") {
    return false
  }
  if !fields.contains("scope_cid") {
    return false
  }
  if !fields.contains("basis_cid") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_1194(item) {
      return false
    }
  }
  if fields.get("value") is Some(item) {
    if !wire_rule_1195(item) {
      return false
    }
  }
  if fields.get("unit") is Some(item) {
    if !wire_rule_1161(item) {
      return false
    }
  }
  if fields.get("scope_cid") is Some(item) {
    if !wire_rule_1(item) {
      return false
    }
  }
  if fields.get("basis_cid") is Some(item) {
    if !wire_rule_1(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1199(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "kind" || key == "unit" || key == "reason") {
      return false
    }
  }
  if !fields.contains("kind") {
    return false
  }
  if !fields.contains("unit") {
    return false
  }
  if !fields.contains("reason") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_913(item) {
      return false
    }
  }
  if fields.get("unit") is Some(item) {
    if !wire_rule_1161(item) {
      return false
    }
  }
  if fields.get("reason") is Some(item) {
    if !wire_rule_1161(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1192(value : Json) -> Bool {
  if [wire_rule_1193(value), wire_rule_1199(value)]
    .filter(fn(ok) { ok })
    .length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_rule_1191(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  if items.length() < 0 {
    return false
  }
  for item in items {
    if !wire_rule_1192(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1207(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  if items.length() < 0 {
    return false
  }
  for item in items {
    if !wire_rule_1170(item) {
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
fn wire_rule_1203(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "static_plan" ||
      key == "inspect" ||
      key == "durable_control" ||
      key == "sample_capture" ||
      key == "full_intermediate_retention" ||
      key == "cost_guard" ||
      key == "execution_batch" ||
      key == "policy_revision_cid") {
      return false
    }
  }
  if !fields.contains("static_plan") {
    return false
  }
  if !fields.contains("inspect") {
    return false
  }
  if !fields.contains("durable_control") {
    return false
  }
  if !fields.contains("sample_capture") {
    return false
  }
  if !fields.contains("full_intermediate_retention") {
    return false
  }
  if !fields.contains("cost_guard") {
    return false
  }
  if !fields.contains("execution_batch") {
    return false
  }
  if !fields.contains("policy_revision_cid") {
    return false
  }
  if fields.get("static_plan") is Some(item) {
    if !wire_rule_1181(item) {
      return false
    }
  }
  if fields.get("inspect") is Some(item) {
    if !wire_rule_1181(item) {
      return false
    }
  }
  if fields.get("durable_control") is Some(item) {
    if !wire_rule_1181(item) {
      return false
    }
  }
  if fields.get("sample_capture") is Some(item) {
    if !wire_rule_1207(item) {
      return false
    }
  }
  if fields.get("full_intermediate_retention") is Some(item) {
    if !wire_rule_1207(item) {
      return false
    }
  }
  if fields.get("cost_guard") is Some(item) {
    if !wire_rule_1181(item) {
      return false
    }
  }
  if fields.get("execution_batch") is Some(item) {
    if !wire_rule_1181(item) {
      return false
    }
  }
  if fields.get("policy_revision_cid") is Some(item) {
    if !wire_rule_1(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1138(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "version" ||
      key == "compiled_plan_cid" ||
      key == "logical_map" ||
      key == "observation" ||
      key == "provider_io" ||
      key == "quantities" ||
      key == "capabilities") {
      return false
    }
  }
  if !fields.contains("version") {
    return false
  }
  if !fields.contains("compiled_plan_cid") {
    return false
  }
  if !fields.contains("logical_map") {
    return false
  }
  if !fields.contains("observation") {
    return false
  }
  if !fields.contains("provider_io") {
    return false
  }
  if !fields.contains("quantities") {
    return false
  }
  if !fields.contains("capabilities") {
    return false
  }
  if fields.get("version") is Some(item) {
    if !wire_rule_1139(item) {
      return false
    }
  }
  if fields.get("compiled_plan_cid") is Some(item) {
    if !wire_rule_1(item) {
      return false
    }
  }
  if fields.get("logical_map") is Some(item) {
    if !wire_rule_1141(item) {
      return false
    }
  }
  if fields.get("observation") is Some(item) {
    if !wire_rule_1189(item) {
      return false
    }
  }
  if fields.get("provider_io") is Some(item) {
    if !wire_rule_1190(item) {
      return false
    }
  }
  if fields.get("quantities") is Some(item) {
    if !wire_rule_1191(item) {
      return false
    }
  }
  if fields.get("capabilities") is Some(item) {
    if !wire_rule_1203(item) {
      return false
    }
  }
  true
}

///|
fn wire_run_plan_view_shape(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "version" || key == "run_ref" || key == "plan_view") {
      return false
    }
  }
  if !fields.contains("version") {
    return false
  }
  if !fields.contains("run_ref") {
    return false
  }
  if !fields.contains("plan_view") {
    return false
  }
  if fields.get("version") is Some(item) {
    if !wire_rule_1136(item) {
      return false
    }
  }
  if fields.get("run_ref") is Some(item) {
    if !wire_rule_13(item) {
      return false
    }
  }
  if fields.get("plan_view") is Some(item) {
    if !wire_rule_1138(item) {
      return false
    }
  }
  true
}
