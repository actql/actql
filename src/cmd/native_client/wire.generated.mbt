// Generated from spec/contracts/actql-client-host.json.
// Run: node scripts/generate-client-host-wire.mjs --write

///|
fn wire_finite_number(number : Double) -> Bool {
  !number.is_nan() &&
  !number.is_inf() &&
  number.reinterpret_as_uint64() != 0x8000000000000000UL
}

///|
fn wire_rule_0(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "actql-submission-epoch/0.1") {
    return false
  }
  true
}

///|
fn wire_rule_1(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if text.length() != 71 || !text.has_prefix("sha256:") {
    return false
  }
  for character in text[7:] {
    if !((character >= '0' && character <= '9') ||
      (character >= 'a' && character <= 'f')) {
      return false
    }
  }
  true
}

///|
fn wire_rule_2(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if text.length() != 64 {
    return false
  }
  for character in text {
    if !((character >= '0' && character <= '9') ||
      (character >= 'a' && character <= 'f')) {
      return false
    }
  }
  true
}

///|
fn wire_rule_3(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) ||
    number != number.floor() ||
    number < -9007199254740991.0 ||
    number > 9007199254740991.0 {
    return false
  }
  if number < 0.0 {
    return false
  }
  if number > 9007199254740991.0 {
    return false
  }
  true
}

///|
fn wire_rule_4(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) ||
    number != number.floor() ||
    number < -9007199254740991.0 ||
    number > 9007199254740991.0 {
    return false
  }
  if number < 1.0 {
    return false
  }
  if number > 9007199254740991.0 {
    return false
  }
  true
}

///|
fn wire_submission_epoch_shape(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "version" ||
      key == "authorityScopeCid" ||
      key == "epochNonce" ||
      key == "notBefore" ||
      key == "expiresAt" ||
      key == "authenticator") {
      return false
    }
  }
  if !fields.contains("version") {
    return false
  }
  if !fields.contains("authorityScopeCid") {
    return false
  }
  if !fields.contains("epochNonce") {
    return false
  }
  if !fields.contains("notBefore") {
    return false
  }
  if !fields.contains("expiresAt") {
    return false
  }
  if !fields.contains("authenticator") {
    return false
  }
  if fields.get("version") is Some(item) {
    if !wire_rule_0(item) {
      return false
    }
  }
  if fields.get("authorityScopeCid") is Some(item) {
    if !wire_rule_1(item) {
      return false
    }
  }
  if fields.get("epochNonce") is Some(item) {
    if !wire_rule_2(item) {
      return false
    }
  }
  if fields.get("notBefore") is Some(item) {
    if !wire_rule_3(item) {
      return false
    }
  }
  if fields.get("expiresAt") is Some(item) {
    if !wire_rule_4(item) {
      return false
    }
  }
  if fields.get("authenticator") is Some(item) {
    if !wire_rule_2(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_7(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if text.iter().count() < 1 {
    return false
  }
  if text.length() > 256 {
    return false
  }
  if text.is_empty() {
    return false
  }
  for character in text {
    if character.to_int() < 32 || character.to_int() == 127 {
      return false
    }
  }
  true
}

///|
fn wire_submission_ref_shape(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "epoch" || key == "nonce") {
      return false
    }
  }
  if !fields.contains("epoch") {
    return false
  }
  if !fields.contains("nonce") {
    return false
  }
  if fields.get("epoch") is Some(item) {
    if !wire_submission_epoch_shape(item) {
      return false
    }
  }
  if fields.get("nonce") is Some(item) {
    if !wire_rule_7(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_9(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "ready") {
    return false
  }
  true
}

///|
fn wire_rule_13(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "namespaceId" ||
      key == "authorityScopeCid" ||
      key == "runDefinitionCid") {
      return false
    }
  }
  if !fields.contains("namespaceId") {
    return false
  }
  if !fields.contains("authorityScopeCid") {
    return false
  }
  if !fields.contains("runDefinitionCid") {
    return false
  }
  if fields.get("namespaceId") is Some(item) {
    if !wire_rule_7(item) {
      return false
    }
  }
  if fields.get("authorityScopeCid") is Some(item) {
    if !wire_rule_1(item) {
      return false
    }
  }
  if fields.get("runDefinitionCid") is Some(item) {
    if !wire_rule_1(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_17(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "volatile" || text == "durable") {
    return false
  }
  true
}

///|
fn wire_rule_18(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) ||
    number != number.floor() ||
    number < -9007199254740991.0 ||
    number > 9007199254740991.0 {
    return false
  }
  if number < 0.0 {
    return false
  }
  true
}

///|
fn wire_rule_12(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "ref" || key == "durability" || key == "revision") {
      return false
    }
  }
  if !fields.contains("ref") {
    return false
  }
  if !fields.contains("durability") {
    return false
  }
  if !fields.contains("revision") {
    return false
  }
  if fields.get("ref") is Some(item) {
    if !wire_rule_13(item) {
      return false
    }
  }
  if fields.get("durability") is Some(item) {
    if !wire_rule_17(item) {
      return false
    }
  }
  if fields.get("revision") is Some(item) {
    if !wire_rule_18(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_21(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "possible_prior_execution_and_effects") {
    return false
  }
  true
}

///|
fn wire_rule_19(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "submissionRef" || key == "acknowledgement") {
      return false
    }
  }
  if !fields.contains("submissionRef") {
    return false
  }
  if !fields.contains("acknowledgement") {
    return false
  }
  if fields.get("submissionRef") is Some(item) {
    if !wire_submission_ref_shape(item) {
      return false
    }
  }
  if fields.get("acknowledgement") is Some(item) {
    if !wire_rule_21(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_8(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "kind" ||
      key == "submissionRef" ||
      key == "intentCid" ||
      key == "admission" ||
      key == "unresolvedHistory") {
      return false
    }
  }
  if !fields.contains("kind") {
    return false
  }
  if !fields.contains("submissionRef") {
    return false
  }
  if !fields.contains("intentCid") {
    return false
  }
  if !fields.contains("admission") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_9(item) {
      return false
    }
  }
  if fields.get("submissionRef") is Some(item) {
    if !wire_submission_ref_shape(item) {
      return false
    }
  }
  if fields.get("intentCid") is Some(item) {
    if !wire_rule_1(item) {
      return false
    }
  }
  if fields.get("admission") is Some(item) {
    if !wire_rule_12(item) {
      return false
    }
  }
  if fields.get("unresolvedHistory") is Some(item) {
    if !wire_rule_19(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_23(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "held") {
    return false
  }
  true
}

///|
fn wire_rule_30(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("endReason") {
    return false
  }
  true
}

///|
fn wire_rule_29(value : Json) -> Bool {
  if wire_rule_30(value) {
    return false
  }
  true
}

///|
fn wire_rule_32(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("terminalErrorCode") {
    return false
  }
  true
}

///|
fn wire_rule_31(value : Json) -> Bool {
  if wire_rule_32(value) {
    return false
  }
  true
}

///|
fn wire_rule_33(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "waiting_checkpoint") {
    return false
  }
  true
}

///|
fn wire_rule_28(value : Json) -> Bool {
  if !wire_rule_29(value) {
    return false
  }
  if !wire_rule_31(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  if !fields.contains("checkpoint") {
    return false
  }
  if fields.get("state") is Some(item) {
    if !wire_rule_33(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_37(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "resuming") {
    return false
  }
  true
}

///|
fn wire_rule_34(value : Json) -> Bool {
  if !wire_rule_29(value) {
    return false
  }
  if !wire_rule_31(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  if fields.get("state") is Some(item) {
    if !wire_rule_37(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_39(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "ended") {
    return false
  }
  true
}

///|
fn wire_rule_38(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("endReason") {
    return false
  }
  if fields.get("state") is Some(item) {
    if !wire_rule_39(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_27(value : Json) -> Bool {
  if [wire_rule_28(value), wire_rule_34(value), wire_rule_38(value)]
    .filter(fn(ok) { ok })
    .length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_rule_43(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "waiting_checkpoint" || text == "resuming" || text == "ended") {
    return false
  }
  true
}

///|
fn wire_rule_44(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "durable") {
    return false
  }
  true
}

///|
fn wire_rule_49(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "run_scope" ||
    text == "read_access" ||
    text == "data_egress" ||
    text == "cost_scope" ||
    text == "effect_set") {
    return false
  }
  true
}

///|
fn wire_rule_46(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "checkpointId" ||
      key == "checkpointCid" ||
      key == "kind" ||
      key == "expiresAt") {
      return false
    }
  }
  if !fields.contains("checkpointId") {
    return false
  }
  if !fields.contains("checkpointCid") {
    return false
  }
  if !fields.contains("kind") {
    return false
  }
  if !fields.contains("expiresAt") {
    return false
  }
  if fields.get("checkpointId") is Some(item) {
    if !wire_rule_7(item) {
      return false
    }
  }
  if fields.get("checkpointCid") is Some(item) {
    if !wire_rule_1(item) {
      return false
    }
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_49(item) {
      return false
    }
  }
  if fields.get("expiresAt") is Some(item) {
    if !wire_rule_7(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_26(value : Json) -> Bool {
  if !wire_rule_27(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "kind" ||
      key == "requestId" ||
      key == "prepareAttemptId" ||
      key == "state" ||
      key == "durability" ||
      key == "lookupExpiresAt" ||
      key == "checkpoint" ||
      key == "endReason" ||
      key == "terminalErrorCode") {
      return false
    }
  }
  if !fields.contains("kind") {
    return false
  }
  if !fields.contains("requestId") {
    return false
  }
  if !fields.contains("prepareAttemptId") {
    return false
  }
  if !fields.contains("state") {
    return false
  }
  if !fields.contains("durability") {
    return false
  }
  if !fields.contains("lookupExpiresAt") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_23(item) {
      return false
    }
  }
  if fields.get("requestId") is Some(item) {
    if !wire_rule_7(item) {
      return false
    }
  }
  if fields.get("prepareAttemptId") is Some(item) {
    if !wire_rule_7(item) {
      return false
    }
  }
  if fields.get("state") is Some(item) {
    if !wire_rule_43(item) {
      return false
    }
  }
  if fields.get("durability") is Some(item) {
    if !wire_rule_44(item) {
      return false
    }
  }
  if fields.get("lookupExpiresAt") is Some(item) {
    if !wire_rule_7(item) {
      return false
    }
  }
  if fields.get("checkpoint") is Some(item) {
    if !wire_rule_46(item) {
      return false
    }
  }
  if fields.get("endReason") is Some(item) {
    if !wire_rule_7(item) {
      return false
    }
  }
  if fields.get("terminalErrorCode") is Some(item) {
    if !wire_rule_7(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_22(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "kind" ||
      key == "submissionRef" ||
      key == "intentCid" ||
      key == "held" ||
      key == "unresolvedHistory") {
      return false
    }
  }
  if !fields.contains("kind") {
    return false
  }
  if !fields.contains("submissionRef") {
    return false
  }
  if !fields.contains("intentCid") {
    return false
  }
  if !fields.contains("held") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_23(item) {
      return false
    }
  }
  if fields.get("submissionRef") is Some(item) {
    if !wire_submission_ref_shape(item) {
      return false
    }
  }
  if fields.get("intentCid") is Some(item) {
    if !wire_rule_1(item) {
      return false
    }
  }
  if fields.get("held") is Some(item) {
    if !wire_rule_26(item) {
      return false
    }
  }
  if fields.get("unresolvedHistory") is Some(item) {
    if !wire_rule_19(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_55(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "preparing") {
    return false
  }
  true
}

///|
fn wire_rule_54(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "kind" ||
      key == "submissionRef" ||
      key == "intentCid" ||
      key == "unresolvedHistory") {
      return false
    }
  }
  if !fields.contains("kind") {
    return false
  }
  if !fields.contains("submissionRef") {
    return false
  }
  if !fields.contains("intentCid") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_55(item) {
      return false
    }
  }
  if fields.get("submissionRef") is Some(item) {
    if !wire_submission_ref_shape(item) {
      return false
    }
  }
  if fields.get("intentCid") is Some(item) {
    if !wire_rule_1(item) {
      return false
    }
  }
  if fields.get("unresolvedHistory") is Some(item) {
    if !wire_rule_19(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_60(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "not_accepted") {
    return false
  }
  true
}

///|
fn wire_rule_67(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "completed") {
    return false
  }
  true
}

///|
fn wire_rule_71(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "invalid") {
    return false
  }
  true
}

///|
fn wire_rule_70(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("verdict") is Some(item) {
    if !wire_rule_71(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_74(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "no") {
    return false
  }
  true
}

///|
fn wire_rule_73(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("verdict") is Some(item) {
    if !wire_rule_74(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_72(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("runnable") is Some(item) {
    if !wire_rule_73(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_69(value : Json) -> Bool {
  if wire_rule_70(value) && !wire_rule_72(value) {
    return false
  }
  true
}

///|
fn wire_rule_77(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "undetermined") {
    return false
  }
  true
}

///|
fn wire_rule_76(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("verdict") is Some(item) {
    if !wire_rule_77(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_75(value : Json) -> Bool {
  if wire_rule_76(value) && !wire_rule_72(value) {
    return false
  }
  true
}

///|
fn wire_rule_81(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "verified") {
    return false
  }
  true
}

///|
fn wire_rule_80(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("verdict") is Some(item) {
    if !wire_rule_81(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_86(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "bound_input") {
    return false
  }
  true
}

///|
fn wire_rule_85(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("kind") is Some(item) {
    if !wire_rule_86(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_84(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scope") is Some(item) {
    if !wire_rule_85(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_89(_value : Json) -> Bool {
  true
}

///|
fn wire_rule_88(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  if items.length() > 0 {
    return false
  }
  for item in items {
    if !wire_rule_89(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_87(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("requirements") is Some(item) {
    if !wire_rule_88(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_83(value : Json) -> Bool {
  if wire_rule_84(value) && !wire_rule_87(value) {
    return false
  }
  true
}

///|
fn wire_rule_93(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "template_only") {
    return false
  }
  true
}

///|
fn wire_rule_92(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("kind") is Some(item) {
    if !wire_rule_93(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_91(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scope") is Some(item) {
    if !wire_rule_92(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_98(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "parameter_value_required") {
    return false
  }
  true
}

///|
fn wire_rule_97(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_98(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_96(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  for item in items {
    if !wire_rule_97(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_95(value : Json) -> Bool {
  if value is Array(_) {
    return wire_rule_96(value)
  }
  true
}

///|
fn wire_rule_94(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("requirements") is Some(item) {
    if !wire_rule_95(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_90(value : Json) -> Bool {
  if wire_rule_91(value) && !wire_rule_94(value) {
    return false
  }
  true
}

///|
fn wire_rule_99(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("omissions") {
    return false
  }
  true
}

///|
fn wire_rule_101(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("limits") is Some(item) {
    if !wire_rule_88(item) {
      return false
    }
  }
  if fields.get("unresolved") is Some(item) {
    if !wire_rule_88(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_82(value : Json) -> Bool {
  if !wire_rule_83(value) {
    return false
  }
  if !wire_rule_90(value) {
    return false
  }
  if wire_rule_99(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  if fields.get("reasons") is Some(item) {
    if !wire_rule_88(item) {
      return false
    }
  }
  if fields.get("coverage") is Some(item) {
    if !wire_rule_101(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_79(value : Json) -> Bool {
  if wire_rule_80(value) && !wire_rule_82(value) {
    return false
  }
  true
}

///|
fn wire_rule_107(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  if items.length() < 1 {
    return false
  }
  for item in items {
    if !wire_rule_89(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_106(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("reasons") is Some(item) {
    if !wire_rule_107(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_104(value : Json) -> Bool {
  if wire_rule_70(value) && !wire_rule_106(value) {
    return false
  }
  true
}

///|
fn wire_rule_113(value : Json) -> Bool {
  if wire_rule_101(value) {
    return false
  }
  true
}

///|
fn wire_rule_111(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("reasons") is Some(item) {
    if !wire_rule_88(item) {
      return false
    }
  }
  if fields.get("coverage") is Some(item) {
    if !wire_rule_113(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_109(value : Json) -> Bool {
  if wire_rule_76(value) && !wire_rule_111(value) {
    return false
  }
  true
}

///|
fn wire_rule_118(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "yes") {
    return false
  }
  true
}

///|
fn wire_rule_117(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("verdict") is Some(item) {
    if !wire_rule_118(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_121(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  if items.length() > 0 {
    return false
  }
  true
}

///|
fn wire_rule_120(value : Json) -> Bool {
  if value is Array(_) {
    return wire_rule_121(value)
  }
  true
}

///|
fn wire_rule_119(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("reasons") is Some(item) {
    if !wire_rule_120(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_116(value : Json) -> Bool {
  if wire_rule_117(value) && !wire_rule_119(value) {
    return false
  }
  true
}

///|
fn wire_rule_126(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  if items.length() < 1 {
    return false
  }
  true
}

///|
fn wire_rule_125(value : Json) -> Bool {
  if value is Array(_) {
    return wire_rule_126(value)
  }
  true
}

///|
fn wire_rule_124(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("reasons") is Some(item) {
    if !wire_rule_125(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_122(value : Json) -> Bool {
  if wire_rule_73(value) && !wire_rule_124(value) {
    return false
  }
  true
}

///|
fn wire_rule_127(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "yes" || text == "no") {
    return false
  }
  true
}

///|
fn wire_rule_130(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if text.is_empty() || text.length() > 64 {
    return false
  }
  if text[0] < 'a' || text[0] > 'z' {
    return false
  }
  for character in text {
    if !((character >= 'a' && character <= 'z') ||
      (character >= '0' && character <= '9') ||
      character == '_') {
      return false
    }
  }
  true
}

///|
fn wire_rule_129(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "code") {
      return false
    }
  }
  if !fields.contains("code") {
    return false
  }
  if fields.get("code") is Some(item) {
    if !wire_rule_130(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_128(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  for item in items {
    if !wire_rule_129(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_115(value : Json) -> Bool {
  if !wire_rule_116(value) {
    return false
  }
  if !wire_rule_122(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "verdict" || key == "reasons") {
      return false
    }
  }
  if !fields.contains("verdict") {
    return false
  }
  if !fields.contains("reasons") {
    return false
  }
  if fields.get("verdict") is Some(item) {
    if !wire_rule_127(item) {
      return false
    }
  }
  if fields.get("reasons") is Some(item) {
    if !wire_rule_128(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_131(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if text.iter().count() < 1 {
    return false
  }
  if text.length() > 128 {
    return false
  }
  if text.is_empty() {
    return false
  }
  for character in text {
    if !((character >= 'A' && character <= 'Z') ||
      (character >= 'a' && character <= 'z') ||
      (character >= '0' && character <= '9') ||
      character == ':' ||
      character == '_' ||
      character == '-') {
      return false
    }
  }
  true
}

///|
fn wire_rule_133(value : Json) -> Bool {
  if !(value is True || value is False) {
    return false
  }
  if !(value is True) {
    return false
  }
  true
}

///|
fn wire_rule_132(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "requirements") {
      return false
    }
  }
  if !fields.contains("requirements") {
    return false
  }
  if fields.get("requirements") is Some(item) {
    if !wire_rule_133(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_136(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "source" ||
    text == "program" ||
    text == "parameter_declarations" ||
    text == "parameters") {
    return false
  }
  true
}

///|
fn wire_rule_137(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if text.length() != 68 || !text.has_prefix("rev:") {
    return false
  }
  for character in text[4:] {
    if !((character >= '0' && character <= '9') ||
      (character >= 'a' && character <= 'f')) {
      return false
    }
  }
  true
}

///|
fn wire_rule_138(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "text" || text == "structured") {
    return false
  }
  true
}

///|
fn wire_rule_139(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) ||
    number != number.floor() ||
    number < -9007199254740991.0 ||
    number > 9007199254740991.0 {
    return false
  }
  if number < 0.0 {
    return false
  }
  if number > 9007199254740991.0 {
    return false
  }
  true
}

///|
fn wire_rule_135(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "document_id" ||
      key == "revision" ||
      key == "kind" ||
      key == "byte_length") {
      return false
    }
  }
  if !fields.contains("document_id") {
    return false
  }
  if !fields.contains("revision") {
    return false
  }
  if !fields.contains("kind") {
    return false
  }
  if !fields.contains("byte_length") {
    return false
  }
  if fields.get("document_id") is Some(item) {
    if !wire_rule_136(item) {
      return false
    }
  }
  if fields.get("revision") is Some(item) {
    if !wire_rule_137(item) {
      return false
    }
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_138(item) {
      return false
    }
  }
  if fields.get("byte_length") is Some(item) {
    if !wire_rule_139(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_134(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  if items.length() < 1 {
    return false
  }
  if items.length() > 3 {
    return false
  }
  for item in items {
    if !wire_rule_135(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_145(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "implementation_limit" || text == "analysis_budget_exhausted") {
    return false
  }
  true
}

///|
fn wire_rule_147(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "structured") {
    return false
  }
  true
}

///|
fn wire_rule_148(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "program") {
    return false
  }
  true
}

///|
fn wire_rule_150(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if text.length() > 4096 {
    return false
  }
  if !text.is_empty() && !text.has_prefix("/") {
    return false
  }
  let mut escape = false
  for character in text {
    if escape {
      if character != '0' && character != '1' {
        return false
      }
      escape = false
    } else if character == '~' {
      escape = true
    }
  }
  if escape {
    return false
  }
  true
}

///|
fn wire_rule_146(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "kind" ||
      key == "document_id" ||
      key == "revision" ||
      key == "pointer") {
      return false
    }
  }
  if !fields.contains("kind") {
    return false
  }
  if !fields.contains("document_id") {
    return false
  }
  if !fields.contains("revision") {
    return false
  }
  if !fields.contains("pointer") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_147(item) {
      return false
    }
  }
  if fields.get("document_id") is Some(item) {
    if !wire_rule_148(item) {
      return false
    }
  }
  if fields.get("revision") is Some(item) {
    if !wire_rule_137(item) {
      return false
    }
  }
  if fields.get("pointer") is Some(item) {
    if !wire_rule_150(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_144(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "code" || key == "location") {
      return false
    }
  }
  if !fields.contains("code") {
    return false
  }
  if !fields.contains("location") {
    return false
  }
  if fields.get("code") is Some(item) {
    if !wire_rule_145(item) {
      return false
    }
  }
  if fields.get("location") is Some(item) {
    if !wire_rule_146(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_152(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "implementation_limit") {
    return false
  }
  true
}

///|
fn wire_rule_154(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "function_lowering_unresolved") {
    return false
  }
  true
}

///|
fn wire_rule_153(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "issue") {
      return false
    }
  }
  if !fields.contains("issue") {
    return false
  }
  if fields.get("issue") is Some(item) {
    if !wire_rule_154(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_156(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "text") {
    return false
  }
  true
}

///|
fn wire_rule_157(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "source") {
    return false
  }
  true
}

///|
fn wire_rule_159(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) ||
    number != number.floor() ||
    number < -9007199254740991.0 ||
    number > 9007199254740991.0 {
    return false
  }
  if number < 0.0 {
    return false
  }
  if number > 1048576.0 {
    return false
  }
  true
}

///|
fn wire_rule_161(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "exact" || text == "approximate") {
    return false
  }
  true
}

///|
fn wire_rule_155(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "kind" ||
      key == "document_id" ||
      key == "revision" ||
      key == "start_byte" ||
      key == "end_byte" ||
      key == "precision") {
      return false
    }
  }
  if !fields.contains("kind") {
    return false
  }
  if !fields.contains("document_id") {
    return false
  }
  if !fields.contains("revision") {
    return false
  }
  if !fields.contains("start_byte") {
    return false
  }
  if !fields.contains("end_byte") {
    return false
  }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_156(item) {
      return false
    }
  }
  if fields.get("document_id") is Some(item) {
    if !wire_rule_157(item) {
      return false
    }
  }
  if fields.get("revision") is Some(item) {
    if !wire_rule_137(item) {
      return false
    }
  }
  if fields.get("start_byte") is Some(item) {
    if !wire_rule_159(item) {
      return false
    }
  }
  if fields.get("end_byte") is Some(item) {
    if !wire_rule_159(item) {
      return false
    }
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_161(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_151(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "code" || key == "facts" || key == "location") {
      return false
    }
  }
  if !fields.contains("code") {
    return false
  }
  if !fields.contains("facts") {
    return false
  }
  if fields.get("code") is Some(item) {
    if !wire_rule_152(item) {
      return false
    }
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_153(item) {
      return false
    }
  }
  if fields.get("location") is Some(item) {
    if !wire_rule_155(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_142(value : Json) -> Bool {
  if [wire_rule_129(value), wire_rule_144(value), wire_rule_151(value)]
    .filter(fn(ok) { ok })
    .length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_rule_141(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  for item in items {
    if !wire_rule_142(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_165(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "unresolved_protected") {
    return false
  }
  true
}

///|
fn wire_rule_163(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "boundary" || key == "reason") {
      return false
    }
  }
  if !fields.contains("boundary") {
    return false
  }
  if !fields.contains("reason") {
    return false
  }
  if fields.get("boundary") is Some(item) {
    if !wire_rule_130(item) {
      return false
    }
  }
  if fields.get("reason") is Some(item) {
    if !wire_rule_165(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_162(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  for item in items {
    if !wire_rule_163(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_140(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "limits" || key == "unresolved") {
      return false
    }
  }
  if !fields.contains("limits") {
    return false
  }
  if !fields.contains("unresolved") {
    return false
  }
  if fields.get("limits") is Some(item) {
    if !wire_rule_141(item) {
      return false
    }
  }
  if fields.get("unresolved") is Some(item) {
    if !wire_rule_162(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_170(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "program_structure_invalid") {
    return false
  }
  true
}

///|
fn wire_rule_169(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_170(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_172(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("fixes") {
    return false
  }
  true
}

///|
fn wire_rule_174(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "missing_field" ||
    text == "wrong_type" ||
    text == "unexpected_null" ||
    text == "invalid_structure") {
    return false
  }
  true
}

///|
fn wire_rule_173(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "issue") {
      return false
    }
  }
  if !fields.contains("issue") {
    return false
  }
  if fields.get("issue") is Some(item) {
    if !wire_rule_174(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_175(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("kind") is Some(item) {
    if !wire_rule_147(item) {
      return false
    }
  }
  if fields.get("document_id") is Some(item) {
    if !wire_rule_148(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_171(value : Json) -> Bool {
  if wire_rule_172(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  if !fields.contains("facts") {
    return false
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_173(item) {
      return false
    }
  }
  if fields.get("location") is Some(item) {
    if !wire_rule_175(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_168(value : Json) -> Bool {
  if wire_rule_169(value) && !wire_rule_171(value) {
    return false
  }
  true
}

///|
fn wire_rule_180(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "numeric_reduction_profile_required") {
    return false
  }
  true
}

///|
fn wire_rule_179(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_180(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_183(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("location") {
    return false
  }
  true
}

///|
fn wire_rule_182(value : Json) -> Bool {
  if wire_rule_183(value) {
    return false
  }
  true
}

///|
fn wire_rule_184(value : Json) -> Bool {
  if wire_rule_172(value) {
    return false
  }
  true
}

///|
fn wire_rule_187(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text ==
    "sha256:d771391b2e4f3e52a3cf48810571a09c6c272df64fbb77c245dfabcf456be5df") {
    return false
  }
  true
}

///|
fn wire_rule_188(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "checking_context_owner") {
    return false
  }
  true
}

///|
fn wire_rule_189(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "checking") {
    return false
  }
  true
}

///|
fn wire_rule_186(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "profile_cid" || key == "supplier" || key == "stage") {
      return false
    }
  }
  if !fields.contains("profile_cid") {
    return false
  }
  if !fields.contains("supplier") {
    return false
  }
  if !fields.contains("stage") {
    return false
  }
  if fields.get("profile_cid") is Some(item) {
    if !wire_rule_187(item) {
      return false
    }
  }
  if fields.get("supplier") is Some(item) {
    if !wire_rule_188(item) {
      return false
    }
  }
  if fields.get("stage") is Some(item) {
    if !wire_rule_189(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_181(value : Json) -> Bool {
  if !wire_rule_182(value) {
    return false
  }
  if !wire_rule_184(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  if !fields.contains("facts") {
    return false
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_186(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_178(value : Json) -> Bool {
  if wire_rule_179(value) && !wire_rule_181(value) {
    return false
  }
  true
}

///|
fn wire_rule_192(value : Json) -> Bool {
  if wire_rule_180(value) {
    return false
  }
  true
}

///|
fn wire_rule_191(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_192(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_196(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("profile_cid") {
    return false
  }
  true
}

///|
fn wire_rule_195(value : Json) -> Bool {
  if wire_rule_196(value) {
    return false
  }
  true
}

///|
fn wire_rule_194(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("facts") is Some(item) {
    if !wire_rule_195(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_190(value : Json) -> Bool {
  if wire_rule_191(value) && !wire_rule_194(value) {
    return false
  }
  true
}

///|
fn wire_rule_199(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "host_capacity_policy_required") {
    return false
  }
  true
}

///|
fn wire_rule_198(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_199(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_204(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text ==
    "sha256:6a419d77cad73380825177f80901a12e24eb742055e89bbb27ffa5a3cc9e7da9") {
    return false
  }
  true
}

///|
fn wire_rule_205(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text ==
    "sha256:3cc98bb9d2850a8070a6c9e66f6e3baf52e5f32e997488a3d91dd809fe95b265") {
    return false
  }
  true
}

///|
fn wire_rule_206(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "/schema") {
    return false
  }
  true
}

///|
fn wire_rule_203(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "contract_cid" ||
      key == "schema_cid" ||
      key == "schema_pointer" ||
      key == "supplier" ||
      key == "stage") {
      return false
    }
  }
  if !fields.contains("contract_cid") {
    return false
  }
  if !fields.contains("schema_cid") {
    return false
  }
  if !fields.contains("schema_pointer") {
    return false
  }
  if !fields.contains("supplier") {
    return false
  }
  if !fields.contains("stage") {
    return false
  }
  if fields.get("contract_cid") is Some(item) {
    if !wire_rule_204(item) {
      return false
    }
  }
  if fields.get("schema_cid") is Some(item) {
    if !wire_rule_205(item) {
      return false
    }
  }
  if fields.get("schema_pointer") is Some(item) {
    if !wire_rule_206(item) {
      return false
    }
  }
  if fields.get("supplier") is Some(item) {
    if !wire_rule_188(item) {
      return false
    }
  }
  if fields.get("stage") is Some(item) {
    if !wire_rule_189(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_200(value : Json) -> Bool {
  if !wire_rule_182(value) {
    return false
  }
  if !wire_rule_184(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  if !fields.contains("facts") {
    return false
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_203(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_197(value : Json) -> Bool {
  if wire_rule_198(value) && !wire_rule_200(value) {
    return false
  }
  true
}

///|
fn wire_rule_211(value : Json) -> Bool {
  if wire_rule_199(value) {
    return false
  }
  true
}

///|
fn wire_rule_210(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_211(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_215(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("schema_pointer") {
    return false
  }
  true
}

///|
fn wire_rule_214(value : Json) -> Bool {
  if wire_rule_215(value) {
    return false
  }
  true
}

///|
fn wire_rule_213(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("facts") is Some(item) {
    if !wire_rule_214(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_209(value : Json) -> Bool {
  if wire_rule_210(value) && !wire_rule_213(value) {
    return false
  }
  true
}

///|
fn wire_rule_217(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_152(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_220(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("issue") {
    return false
  }
  if fields.get("issue") is Some(item) {
    if !wire_rule_154(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_224(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "source" || text == "program") {
    return false
  }
  true
}

///|
fn wire_rule_222(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("kind") is Some(item) {
    if !wire_rule_138(item) {
      return false
    }
  }
  if fields.get("document_id") is Some(item) {
    if !wire_rule_224(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_219(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("facts") is Some(item) {
    if !wire_rule_220(item) {
      return false
    }
  }
  if fields.get("location") is Some(item) {
    if !wire_rule_222(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_216(value : Json) -> Bool {
  if wire_rule_217(value) && !wire_rule_219(value) {
    return false
  }
  true
}

///|
fn wire_rule_227(value : Json) -> Bool {
  if wire_rule_98(value) {
    return false
  }
  true
}

///|
fn wire_rule_226(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_227(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_231(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("admission") {
    return false
  }
  true
}

///|
fn wire_rule_230(value : Json) -> Bool {
  if wire_rule_231(value) {
    return false
  }
  true
}

///|
fn wire_rule_229(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("facts") is Some(item) {
    if !wire_rule_230(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_225(value : Json) -> Bool {
  if wire_rule_226(value) && !wire_rule_229(value) {
    return false
  }
  true
}

///|
fn wire_rule_235(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "query_lexical_invalid") {
    return false
  }
  true
}

///|
fn wire_rule_237(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "unterminated_comment") {
    return false
  }
  true
}

///|
fn wire_rule_236(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("issue") is Some(item) {
    if !wire_rule_237(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_240(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "exact") {
    return false
  }
  true
}

///|
fn wire_rule_238(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("kind") is Some(item) {
    if !wire_rule_156(item) {
      return false
    }
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_240(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_234(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("facts") {
    return false
  }
  if !fields.contains("location") {
    return false
  }
  if fields.get("code") is Some(item) {
    if !wire_rule_235(item) {
      return false
    }
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_236(item) {
      return false
    }
  }
  if fields.get("location") is Some(item) {
    if !wire_rule_238(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_232(value : Json) -> Bool {
  if wire_rule_172(value) && !wire_rule_234(value) {
    return false
  }
  true
}

///|
fn wire_rule_243(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "query_syntax_invalid" || text == "parameter_undeclared") {
    return false
  }
  true
}

///|
fn wire_rule_242(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_243(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_245(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("kind") is Some(item) {
    if !wire_rule_156(item) {
      return false
    }
  }
  if fields.get("document_id") is Some(item) {
    if !wire_rule_157(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_244(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("location") is Some(item) {
    if !wire_rule_245(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_241(value : Json) -> Bool {
  if wire_rule_242(value) && !wire_rule_244(value) {
    return false
  }
  true
}

///|
fn wire_rule_250(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "supplied_value_type_mismatch" ||
    text == "supplied_value_constraint_violation" ||
    text == "supplied_value_invalid" ||
    text == "supplied_parameters_invalid") {
    return false
  }
  true
}

///|
fn wire_rule_249(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_250(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_254(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "parameters") {
    return false
  }
  true
}

///|
fn wire_rule_252(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("kind") is Some(item) {
    if !wire_rule_147(item) {
      return false
    }
  }
  if fields.get("document_id") is Some(item) {
    if !wire_rule_254(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_251(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("location") is Some(item) {
    if !wire_rule_252(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_248(value : Json) -> Bool {
  if wire_rule_249(value) && !wire_rule_251(value) {
    return false
  }
  true
}

///|
fn wire_rule_257(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "parameter_declarations_invalid" ||
    text == "parameter_value_required") {
    return false
  }
  true
}

///|
fn wire_rule_256(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_257(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_261(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "parameter_declarations" || text == "program") {
    return false
  }
  true
}

///|
fn wire_rule_259(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("kind") is Some(item) {
    if !wire_rule_147(item) {
      return false
    }
  }
  if fields.get("document_id") is Some(item) {
    if !wire_rule_261(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_258(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("location") is Some(item) {
    if !wire_rule_259(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_255(value : Json) -> Bool {
  if wire_rule_256(value) && !wire_rule_258(value) {
    return false
  }
  true
}

///|
fn wire_rule_264(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "supplied_value_type_mismatch") {
    return false
  }
  true
}

///|
fn wire_rule_263(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_264(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_266(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("actual_type") {
    return false
  }
  true
}

///|
fn wire_rule_265(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("facts") {
    return false
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_266(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_262(value : Json) -> Bool {
  if wire_rule_263(value) && !wire_rule_265(value) {
    return false
  }
  true
}

///|
fn wire_rule_269(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "parameter_default_type_mismatch") {
    return false
  }
  true
}

///|
fn wire_rule_268(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_269(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_270(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("facts") {
    return false
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_266(item) {
      return false
    }
  }
  if fields.get("location") is Some(item) {
    if !wire_rule_259(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_267(value : Json) -> Bool {
  if wire_rule_268(value) && !wire_rule_270(value) {
    return false
  }
  true
}

///|
fn wire_rule_275(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "parameter_undeclared") {
    return false
  }
  true
}

///|
fn wire_rule_274(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_275(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_279(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("expected_type") {
    return false
  }
  true
}

///|
fn wire_rule_278(value : Json) -> Bool {
  if wire_rule_279(value) {
    return false
  }
  true
}

///|
fn wire_rule_281(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("constraint") {
    return false
  }
  true
}

///|
fn wire_rule_280(value : Json) -> Bool {
  if wire_rule_281(value) {
    return false
  }
  true
}

///|
fn wire_rule_283(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("domain") {
    return false
  }
  true
}

///|
fn wire_rule_282(value : Json) -> Bool {
  if wire_rule_283(value) {
    return false
  }
  true
}

///|
fn wire_rule_277(value : Json) -> Bool {
  if !wire_rule_278(value) {
    return false
  }
  if !wire_rule_280(value) {
    return false
  }
  if !wire_rule_282(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  if !fields.contains("parameter") {
    return false
  }
  true
}

///|
fn wire_rule_276(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("facts") {
    return false
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_277(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_273(value : Json) -> Bool {
  if wire_rule_274(value) && !wire_rule_276(value) {
    return false
  }
  true
}

///|
fn wire_rule_287(value : Json) -> Bool {
  if wire_rule_266(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  if !fields.contains("parameter") {
    return false
  }
  if !fields.contains("expected_type") {
    return false
  }
  true
}

///|
fn wire_rule_286(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("facts") {
    return false
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_287(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_284(value : Json) -> Bool {
  if wire_rule_97(value) && !wire_rule_286(value) {
    return false
  }
  true
}

///|
fn wire_rule_291(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "parameter_unused") {
    return false
  }
  true
}

///|
fn wire_rule_290(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_291(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_294(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if text.iter().count() < 1 {
    return false
  }
  if text.length() > 256 {
    return false
  }
  true
}

///|
fn wire_rule_293(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "parameter") {
      return false
    }
  }
  if !fields.contains("parameter") {
    return false
  }
  if fields.get("parameter") is Some(item) {
    if !wire_rule_294(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_292(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("facts") {
    return false
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_293(item) {
      return false
    }
  }
  if fields.get("location") is Some(item) {
    if !wire_rule_259(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_289(value : Json) -> Bool {
  if wire_rule_290(value) && !wire_rule_292(value) {
    return false
  }
  true
}

///|
fn wire_rule_298(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "supplied_value_constraint_violation") {
    return false
  }
  true
}

///|
fn wire_rule_297(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_298(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_299(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("facts") {
    return false
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_281(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_296(value : Json) -> Bool {
  if wire_rule_297(value) && !wire_rule_299(value) {
    return false
  }
  true
}

///|
fn wire_rule_303(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "expression_type_mismatch") {
    return false
  }
  true
}

///|
fn wire_rule_302(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_303(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_306(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "number" || text == "boolean" || text == "string") {
    return false
  }
  true
}

///|
fn wire_rule_305(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "expected_type") {
      return false
    }
  }
  if !fields.contains("expected_type") {
    return false
  }
  if fields.get("expected_type") is Some(item) {
    if !wire_rule_306(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_304(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("facts") {
    return false
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_305(item) {
      return false
    }
  }
  if fields.get("location") is Some(item) {
    if !wire_rule_222(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_301(value : Json) -> Bool {
  if wire_rule_302(value) && !wire_rule_304(value) {
    return false
  }
  true
}

///|
fn wire_rule_310(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "operation_parameter_invalid") {
    return false
  }
  true
}

///|
fn wire_rule_309(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_310(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_315(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "parameters" || text == "parameter_declarations") {
    return false
  }
  true
}

///|
fn wire_rule_313(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("kind") is Some(item) {
    if !wire_rule_147(item) {
      return false
    }
  }
  if fields.get("document_id") is Some(item) {
    if !wire_rule_315(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_311(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("facts") {
    return false
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_283(item) {
      return false
    }
  }
  if fields.get("location") is Some(item) {
    if !wire_rule_313(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_308(value : Json) -> Bool {
  if wire_rule_309(value) && !wire_rule_311(value) {
    return false
  }
  true
}

///|
fn wire_rule_318(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "binding_json_invalid") {
    return false
  }
  true
}

///|
fn wire_rule_317(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_318(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_322(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("document") is Some(item) {
    if !wire_rule_254(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_321(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("facts") is Some(item) {
    if !wire_rule_322(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_325(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("document_id") is Some(item) {
    if !wire_rule_254(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_324(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("location") is Some(item) {
    if !wire_rule_325(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_320(value : Json) -> Bool {
  if wire_rule_321(value) && !wire_rule_324(value) {
    return false
  }
  true
}

///|
fn wire_rule_330(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "parameter_declarations") {
    return false
  }
  true
}

///|
fn wire_rule_329(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("document") is Some(item) {
    if !wire_rule_330(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_328(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("facts") is Some(item) {
    if !wire_rule_329(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_332(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("document_id") is Some(item) {
    if !wire_rule_330(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_331(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("location") is Some(item) {
    if !wire_rule_332(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_327(value : Json) -> Bool {
  if wire_rule_328(value) && !wire_rule_331(value) {
    return false
  }
  true
}

///|
fn wire_rule_336(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "invalid_unicode" ||
    text == "unexpected_end" ||
    text == "unexpected_token" ||
    text == "invalid_string" ||
    text == "invalid_escape" ||
    text == "invalid_number" ||
    text == "number_out_of_range" ||
    text == "negative_zero" ||
    text == "expected_colon" ||
    text == "expected_array_separator" ||
    text == "expected_object_separator" ||
    text == "duplicate_key" ||
    text == "trailing_content") {
    return false
  }
  true
}

///|
fn wire_rule_334(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "document" || key == "issue") {
      return false
    }
  }
  if !fields.contains("document") {
    return false
  }
  if !fields.contains("issue") {
    return false
  }
  if fields.get("document") is Some(item) {
    if !wire_rule_315(item) {
      return false
    }
  }
  if fields.get("issue") is Some(item) {
    if !wire_rule_336(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_337(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("kind") is Some(item) {
    if !wire_rule_147(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_319(value : Json) -> Bool {
  if !wire_rule_320(value) {
    return false
  }
  if !wire_rule_327(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  if !fields.contains("facts") {
    return false
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_334(item) {
      return false
    }
  }
  if fields.get("location") is Some(item) {
    if !wire_rule_337(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_316(value : Json) -> Bool {
  if wire_rule_317(value) && !wire_rule_319(value) {
    return false
  }
  true
}

///|
fn wire_rule_340(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_235(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_344(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "unexpected_end" ||
    text == "unexpected_token" ||
    text == "invalid_escape" ||
    text == "invalid_scalar" ||
    text == "empty_identifier" ||
    text == "unterminated_comment" ||
    text == "invalid_number" ||
    text == "invalid_parameter") {
    return false
  }
  true
}

///|
fn wire_rule_343(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("issue") {
    return false
  }
  if fields.get("issue") is Some(item) {
    if !wire_rule_344(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_345(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("kind") is Some(item) {
    if !wire_rule_156(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_342(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("facts") {
    return false
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_343(item) {
      return false
    }
  }
  if fields.get("location") is Some(item) {
    if !wire_rule_345(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_339(value : Json) -> Bool {
  if wire_rule_340(value) && !wire_rule_342(value) {
    return false
  }
  true
}

///|
fn wire_rule_349(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "query_expression_invalid") {
    return false
  }
  true
}

///|
fn wire_rule_348(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_349(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_352(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "unknown_reference" ||
    text == "invalid_arguments" ||
    text == "invalid_number" ||
    text == "expected_boolean") {
    return false
  }
  true
}

///|
fn wire_rule_351(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("issue") {
    return false
  }
  if fields.get("issue") is Some(item) {
    if !wire_rule_352(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_350(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("facts") {
    return false
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_351(item) {
      return false
    }
  }
  if fields.get("location") is Some(item) {
    if !wire_rule_222(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_347(value : Json) -> Bool {
  if wire_rule_348(value) && !wire_rule_350(value) {
    return false
  }
  true
}

///|
fn wire_rule_356(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "query_frame_invalid") {
    return false
  }
  true
}

///|
fn wire_rule_355(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_356(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_359(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "invalid_bounds") {
    return false
  }
  true
}

///|
fn wire_rule_358(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("issue") {
    return false
  }
  if fields.get("issue") is Some(item) {
    if !wire_rule_359(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_357(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("facts") {
    return false
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_358(item) {
      return false
    }
  }
  if fields.get("location") is Some(item) {
    if !wire_rule_222(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_354(value : Json) -> Bool {
  if wire_rule_355(value) && !wire_rule_357(value) {
    return false
  }
  true
}

///|
fn wire_rule_363(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "graph_operation_invalid") {
    return false
  }
  true
}

///|
fn wire_rule_362(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_363(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_366(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "components" || text == "subgraph") {
    return false
  }
  true
}

///|
fn wire_rule_367(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "invalid_kind" ||
    text == "invalid_output_rows" ||
    text == "invalid_node_selector") {
    return false
  }
  true
}

///|
fn wire_rule_365(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("operation") {
    return false
  }
  if !fields.contains("issue") {
    return false
  }
  if fields.get("operation") is Some(item) {
    if !wire_rule_366(item) {
      return false
    }
  }
  if fields.get("issue") is Some(item) {
    if !wire_rule_367(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_364(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("facts") {
    return false
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_365(item) {
      return false
    }
  }
  if fields.get("location") is Some(item) {
    if !wire_rule_222(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_361(value : Json) -> Bool {
  if wire_rule_362(value) && !wire_rule_364(value) {
    return false
  }
  true
}

///|
fn wire_rule_371(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "source_selector_unregistered") {
    return false
  }
  true
}

///|
fn wire_rule_370(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_371(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_376(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if text.iter().count() < 1 {
    return false
  }
  if text.length() > 65536 {
    return false
  }
  true
}

///|
fn wire_rule_374(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "namespace" ||
      key == "connector" ||
      key == "resource" ||
      key == "view") {
      return false
    }
  }
  if !fields.contains("namespace") {
    return false
  }
  if !fields.contains("connector") {
    return false
  }
  if !fields.contains("resource") {
    return false
  }
  if fields.get("namespace") is Some(item) {
    if !wire_rule_294(item) {
      return false
    }
  }
  if fields.get("connector") is Some(item) {
    if !wire_rule_376(item) {
      return false
    }
  }
  if fields.get("resource") is Some(item) {
    if !wire_rule_376(item) {
      return false
    }
  }
  if fields.get("view") is Some(item) {
    if !wire_rule_376(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_372(value : Json) -> Bool {
  if wire_rule_172(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  if !fields.contains("facts") {
    return false
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_374(item) {
      return false
    }
  }
  if fields.get("location") is Some(item) {
    if !wire_rule_175(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_369(value : Json) -> Bool {
  if wire_rule_370(value) && !wire_rule_372(value) {
    return false
  }
  true
}

///|
fn wire_rule_382(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "query_alias_absent") {
    return false
  }
  true
}

///|
fn wire_rule_381(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_382(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_390(value : Json) -> Bool {
  if !(value is True || value is False) {
    return false
  }
  true
}

///|
fn wire_rule_388(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "value" || key == "quoted") {
      return false
    }
  }
  if !fields.contains("value") {
    return false
  }
  if !fields.contains("quoted") {
    return false
  }
  if fields.get("value") is Some(item) {
    if !wire_rule_376(item) {
      return false
    }
  }
  if fields.get("quoted") is Some(item) {
    if !wire_rule_390(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_387(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  if items.length() < 1 {
    return false
  }
  if items.length() > 8192 {
    return false
  }
  for item in items {
    if !wire_rule_388(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_385(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "namespace" || key == "reference") {
      return false
    }
  }
  if !fields.contains("namespace") {
    return false
  }
  if !fields.contains("reference") {
    return false
  }
  if fields.get("namespace") is Some(item) {
    if !wire_rule_294(item) {
      return false
    }
  }
  if fields.get("reference") is Some(item) {
    if !wire_rule_387(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_383(value : Json) -> Bool {
  if wire_rule_172(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  if !fields.contains("facts") {
    return false
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_385(item) {
      return false
    }
  }
  if fields.get("location") is Some(item) {
    if !wire_rule_245(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_380(value : Json) -> Bool {
  if wire_rule_381(value) && !wire_rule_383(value) {
    return false
  }
  true
}

///|
fn wire_rule_395(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "supplied_value_type_mismatch" ||
    text == "parameter_default_type_mismatch" ||
    text == "parameter_value_required" ||
    text == "parameter_undeclared" ||
    text == "parameter_unused" ||
    text == "supplied_value_constraint_violation" ||
    text == "binding_json_invalid" ||
    text == "query_lexical_invalid" ||
    text == "query_expression_invalid" ||
    text == "query_frame_invalid" ||
    text == "graph_operation_invalid" ||
    text == "operation_parameter_invalid" ||
    text == "expression_type_mismatch" ||
    text == "implementation_limit" ||
    text == "host_capacity_policy_required" ||
    text == "numeric_reduction_profile_required" ||
    text == "program_structure_invalid" ||
    text == "source_selector_unregistered" ||
    text == "query_alias_absent") {
    return false
  }
  true
}

///|
fn wire_rule_394(value : Json) -> Bool {
  if wire_rule_395(value) {
    return false
  }
  true
}

///|
fn wire_rule_393(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_394(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_397(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("facts") {
    return false
  }
  true
}

///|
fn wire_rule_396(value : Json) -> Bool {
  if wire_rule_397(value) {
    return false
  }
  true
}

///|
fn wire_rule_392(value : Json) -> Bool {
  if wire_rule_393(value) && !wire_rule_396(value) {
    return false
  }
  true
}

///|
fn wire_rule_400(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "parameter_value_required" ||
    text == "host_capacity_policy_required" ||
    text == "numeric_reduction_profile_required") {
    return false
  }
  true
}

///|
fn wire_rule_399(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_400(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_398(value : Json) -> Bool {
  if wire_rule_399(value) {
    return false
  }
  true
}

///|
fn wire_rule_406(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "program" ||
    text == "parameter_declarations" ||
    text == "parameters") {
    return false
  }
  true
}

///|
fn wire_rule_404(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "kind" ||
      key == "document_id" ||
      key == "revision" ||
      key == "pointer") {
      return false
    }
  }
  if !fields.contains("kind") {
    return false
  }
  if !fields.contains("document_id") {
    return false
  }
  if !fields.contains("revision") {
    return false
  }
  if !fields.contains("pointer") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_147(item) {
      return false
    }
  }
  if fields.get("document_id") is Some(item) {
    if !wire_rule_406(item) {
      return false
    }
  }
  if fields.get("revision") is Some(item) {
    if !wire_rule_137(item) {
      return false
    }
  }
  if fields.get("pointer") is Some(item) {
    if !wire_rule_150(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_402(value : Json) -> Bool {
  if [wire_rule_155(value), wire_rule_404(value)].filter(fn(ok) { ok }).length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_rule_411(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "close_block_comment") {
    return false
  }
  true
}

///|
fn wire_rule_412(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "requires_review") {
    return false
  }
  true
}

///|
fn wire_rule_413(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "syntax_structure") {
    return false
  }
  true
}

///|
fn wire_rule_414(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "document_id" || key == "revision") {
      return false
    }
  }
  if !fields.contains("document_id") {
    return false
  }
  if !fields.contains("revision") {
    return false
  }
  if fields.get("document_id") is Some(item) {
    if !wire_rule_157(item) {
      return false
    }
  }
  if fields.get("revision") is Some(item) {
    if !wire_rule_137(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_421(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "*/") {
    return false
  }
  true
}

///|
fn wire_rule_418(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "start_byte" || key == "end_byte" || key == "replacement") {
      return false
    }
  }
  if !fields.contains("start_byte") {
    return false
  }
  if !fields.contains("end_byte") {
    return false
  }
  if !fields.contains("replacement") {
    return false
  }
  if fields.get("start_byte") is Some(item) {
    if !wire_rule_159(item) {
      return false
    }
  }
  if fields.get("end_byte") is Some(item) {
    if !wire_rule_159(item) {
      return false
    }
  }
  if fields.get("replacement") is Some(item) {
    if !wire_rule_421(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_417(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  if items.length() < 1 {
    return false
  }
  if items.length() > 1 {
    return false
  }
  for item in items {
    if !wire_rule_418(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_410(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "code" ||
      key == "applicability" ||
      key == "risk" ||
      key == "target" ||
      key == "edits") {
      return false
    }
  }
  if !fields.contains("code") {
    return false
  }
  if !fields.contains("applicability") {
    return false
  }
  if !fields.contains("risk") {
    return false
  }
  if !fields.contains("target") {
    return false
  }
  if !fields.contains("edits") {
    return false
  }
  if fields.get("code") is Some(item) {
    if !wire_rule_411(item) {
      return false
    }
  }
  if fields.get("applicability") is Some(item) {
    if !wire_rule_412(item) {
      return false
    }
  }
  if fields.get("risk") is Some(item) {
    if !wire_rule_413(item) {
      return false
    }
  }
  if fields.get("target") is Some(item) {
    if !wire_rule_414(item) {
      return false
    }
  }
  if fields.get("edits") is Some(item) {
    if !wire_rule_417(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_409(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  if items.length() < 1 {
    return false
  }
  if items.length() > 1 {
    return false
  }
  for item in items {
    if !wire_rule_410(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_426(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "null" ||
    text == "boolean" ||
    text == "number" ||
    text == "string" ||
    text == "array" ||
    text == "object" ||
    text == "date" ||
    text == "timestamp" ||
    text == "decimal" ||
    text == "json" ||
    text == "vector" ||
    text == "resource_ref" ||
    text == "content_ref") {
    return false
  }
  true
}

///|
fn wire_rule_424(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "parameter" || key == "expected_type" || key == "actual_type") {
      return false
    }
  }
  if !fields.contains("parameter") {
    return false
  }
  if !fields.contains("expected_type") {
    return false
  }
  if !fields.contains("actual_type") {
    return false
  }
  if fields.get("parameter") is Some(item) {
    if !wire_rule_294(item) {
      return false
    }
  }
  if fields.get("expected_type") is Some(item) {
    if !wire_rule_426(item) {
      return false
    }
  }
  if fields.get("actual_type") is Some(item) {
    if !wire_rule_426(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_432(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text ==
    "sha256:2eeca1588b33cf19cfdbd1891820a6657ccd5a80cade9c159784d2e744cbbe6c") {
    return false
  }
  true
}

///|
fn wire_rule_433(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "parameter_declaration") {
    return false
  }
  true
}

///|
fn wire_rule_439(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if !(number == 1.0) {
    return false
  }
  true
}

///|
fn wire_rule_438(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_439(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_442(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if number > 1.0 {
    return false
  }
  true
}

///|
fn wire_rule_441(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_442(value)
  }
  true
}

///|
fn wire_rule_440(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_441(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_437(value : Json) -> Bool {
  if wire_rule_438(value) && !wire_rule_440(value) {
    return false
  }
  true
}

///|
fn wire_rule_445(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if !(number == 2.0) {
    return false
  }
  true
}

///|
fn wire_rule_444(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_445(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_448(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if number > 2.0 {
    return false
  }
  true
}

///|
fn wire_rule_447(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_448(value)
  }
  true
}

///|
fn wire_rule_446(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_447(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_443(value : Json) -> Bool {
  if wire_rule_444(value) && !wire_rule_446(value) {
    return false
  }
  true
}

///|
fn wire_rule_451(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if !(number == 3.0) {
    return false
  }
  true
}

///|
fn wire_rule_450(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_451(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_454(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if number > 3.0 {
    return false
  }
  true
}

///|
fn wire_rule_453(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_454(value)
  }
  true
}

///|
fn wire_rule_452(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_453(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_449(value : Json) -> Bool {
  if wire_rule_450(value) && !wire_rule_452(value) {
    return false
  }
  true
}

///|
fn wire_rule_457(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if !(number == 4.0) {
    return false
  }
  true
}

///|
fn wire_rule_456(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_457(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_460(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if number > 4.0 {
    return false
  }
  true
}

///|
fn wire_rule_459(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_460(value)
  }
  true
}

///|
fn wire_rule_458(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_459(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_455(value : Json) -> Bool {
  if wire_rule_456(value) && !wire_rule_458(value) {
    return false
  }
  true
}

///|
fn wire_rule_463(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if !(number == 5.0) {
    return false
  }
  true
}

///|
fn wire_rule_462(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_463(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_466(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if number > 5.0 {
    return false
  }
  true
}

///|
fn wire_rule_465(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_466(value)
  }
  true
}

///|
fn wire_rule_464(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_465(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_461(value : Json) -> Bool {
  if wire_rule_462(value) && !wire_rule_464(value) {
    return false
  }
  true
}

///|
fn wire_rule_469(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if !(number == 6.0) {
    return false
  }
  true
}

///|
fn wire_rule_468(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_469(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_472(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if number > 6.0 {
    return false
  }
  true
}

///|
fn wire_rule_471(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_472(value)
  }
  true
}

///|
fn wire_rule_470(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_471(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_467(value : Json) -> Bool {
  if wire_rule_468(value) && !wire_rule_470(value) {
    return false
  }
  true
}

///|
fn wire_rule_475(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if !(number == 7.0) {
    return false
  }
  true
}

///|
fn wire_rule_474(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_475(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_478(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if number > 7.0 {
    return false
  }
  true
}

///|
fn wire_rule_477(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_478(value)
  }
  true
}

///|
fn wire_rule_476(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_477(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_473(value : Json) -> Bool {
  if wire_rule_474(value) && !wire_rule_476(value) {
    return false
  }
  true
}

///|
fn wire_rule_481(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if !(number == 8.0) {
    return false
  }
  true
}

///|
fn wire_rule_480(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_481(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_484(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if number > 8.0 {
    return false
  }
  true
}

///|
fn wire_rule_483(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_484(value)
  }
  true
}

///|
fn wire_rule_482(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_483(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_479(value : Json) -> Bool {
  if wire_rule_480(value) && !wire_rule_482(value) {
    return false
  }
  true
}

///|
fn wire_rule_487(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if !(number == 9.0) {
    return false
  }
  true
}

///|
fn wire_rule_486(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_487(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_490(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if number > 9.0 {
    return false
  }
  true
}

///|
fn wire_rule_489(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_490(value)
  }
  true
}

///|
fn wire_rule_488(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_489(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_485(value : Json) -> Bool {
  if wire_rule_486(value) && !wire_rule_488(value) {
    return false
  }
  true
}

///|
fn wire_rule_493(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if !(number == 10.0) {
    return false
  }
  true
}

///|
fn wire_rule_492(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_493(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_496(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if number > 10.0 {
    return false
  }
  true
}

///|
fn wire_rule_495(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_496(value)
  }
  true
}

///|
fn wire_rule_494(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_495(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_491(value : Json) -> Bool {
  if wire_rule_492(value) && !wire_rule_494(value) {
    return false
  }
  true
}

///|
fn wire_rule_499(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if !(number == 11.0) {
    return false
  }
  true
}

///|
fn wire_rule_498(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_499(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_502(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if number > 11.0 {
    return false
  }
  true
}

///|
fn wire_rule_501(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_502(value)
  }
  true
}

///|
fn wire_rule_500(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_501(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_497(value : Json) -> Bool {
  if wire_rule_498(value) && !wire_rule_500(value) {
    return false
  }
  true
}

///|
fn wire_rule_505(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if !(number == 12.0) {
    return false
  }
  true
}

///|
fn wire_rule_504(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_505(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_508(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if number > 12.0 {
    return false
  }
  true
}

///|
fn wire_rule_507(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_508(value)
  }
  true
}

///|
fn wire_rule_506(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_507(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_503(value : Json) -> Bool {
  if wire_rule_504(value) && !wire_rule_506(value) {
    return false
  }
  true
}

///|
fn wire_rule_511(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if !(number == 13.0) {
    return false
  }
  true
}

///|
fn wire_rule_510(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_511(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_514(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if number > 13.0 {
    return false
  }
  true
}

///|
fn wire_rule_513(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_514(value)
  }
  true
}

///|
fn wire_rule_512(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_513(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_509(value : Json) -> Bool {
  if wire_rule_510(value) && !wire_rule_512(value) {
    return false
  }
  true
}

///|
fn wire_rule_517(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if !(number == 14.0) {
    return false
  }
  true
}

///|
fn wire_rule_516(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_517(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_520(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if number > 14.0 {
    return false
  }
  true
}

///|
fn wire_rule_519(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_520(value)
  }
  true
}

///|
fn wire_rule_518(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_519(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_515(value : Json) -> Bool {
  if wire_rule_516(value) && !wire_rule_518(value) {
    return false
  }
  true
}

///|
fn wire_rule_523(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if !(number == 15.0) {
    return false
  }
  true
}

///|
fn wire_rule_522(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_523(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_526(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if number > 15.0 {
    return false
  }
  true
}

///|
fn wire_rule_525(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_526(value)
  }
  true
}

///|
fn wire_rule_524(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_525(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_521(value : Json) -> Bool {
  if wire_rule_522(value) && !wire_rule_524(value) {
    return false
  }
  true
}

///|
fn wire_rule_529(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if !(number == 16.0) {
    return false
  }
  true
}

///|
fn wire_rule_528(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_529(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_532(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if number > 16.0 {
    return false
  }
  true
}

///|
fn wire_rule_531(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_532(value)
  }
  true
}

///|
fn wire_rule_530(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_531(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_527(value : Json) -> Bool {
  if wire_rule_528(value) && !wire_rule_530(value) {
    return false
  }
  true
}

///|
fn wire_rule_535(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if !(number == 17.0) {
    return false
  }
  true
}

///|
fn wire_rule_534(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_535(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_538(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if number > 17.0 {
    return false
  }
  true
}

///|
fn wire_rule_537(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_538(value)
  }
  true
}

///|
fn wire_rule_536(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_537(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_533(value : Json) -> Bool {
  if wire_rule_534(value) && !wire_rule_536(value) {
    return false
  }
  true
}

///|
fn wire_rule_541(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if !(number == 18.0) {
    return false
  }
  true
}

///|
fn wire_rule_540(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_541(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_544(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if number > 18.0 {
    return false
  }
  true
}

///|
fn wire_rule_543(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_544(value)
  }
  true
}

///|
fn wire_rule_542(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_543(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_539(value : Json) -> Bool {
  if wire_rule_540(value) && !wire_rule_542(value) {
    return false
  }
  true
}

///|
fn wire_rule_547(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if !(number == 19.0) {
    return false
  }
  true
}

///|
fn wire_rule_546(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_547(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_550(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if number > 19.0 {
    return false
  }
  true
}

///|
fn wire_rule_549(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_550(value)
  }
  true
}

///|
fn wire_rule_548(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_549(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_545(value : Json) -> Bool {
  if wire_rule_546(value) && !wire_rule_548(value) {
    return false
  }
  true
}

///|
fn wire_rule_553(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if !(number == 20.0) {
    return false
  }
  true
}

///|
fn wire_rule_552(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_553(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_556(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if number > 20.0 {
    return false
  }
  true
}

///|
fn wire_rule_555(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_556(value)
  }
  true
}

///|
fn wire_rule_554(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_555(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_551(value : Json) -> Bool {
  if wire_rule_552(value) && !wire_rule_554(value) {
    return false
  }
  true
}

///|
fn wire_rule_559(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if !(number == 21.0) {
    return false
  }
  true
}

///|
fn wire_rule_558(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_559(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_562(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if number > 21.0 {
    return false
  }
  true
}

///|
fn wire_rule_561(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_562(value)
  }
  true
}

///|
fn wire_rule_560(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_561(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_557(value : Json) -> Bool {
  if wire_rule_558(value) && !wire_rule_560(value) {
    return false
  }
  true
}

///|
fn wire_rule_565(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if !(number == 22.0) {
    return false
  }
  true
}

///|
fn wire_rule_564(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_565(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_568(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if number > 22.0 {
    return false
  }
  true
}

///|
fn wire_rule_567(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_568(value)
  }
  true
}

///|
fn wire_rule_566(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_567(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_563(value : Json) -> Bool {
  if wire_rule_564(value) && !wire_rule_566(value) {
    return false
  }
  true
}

///|
fn wire_rule_571(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if !(number == 23.0) {
    return false
  }
  true
}

///|
fn wire_rule_570(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_571(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_574(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if number > 23.0 {
    return false
  }
  true
}

///|
fn wire_rule_573(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_574(value)
  }
  true
}

///|
fn wire_rule_572(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_573(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_569(value : Json) -> Bool {
  if wire_rule_570(value) && !wire_rule_572(value) {
    return false
  }
  true
}

///|
fn wire_rule_577(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if !(number == 24.0) {
    return false
  }
  true
}

///|
fn wire_rule_576(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_577(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_580(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if number > 24.0 {
    return false
  }
  true
}

///|
fn wire_rule_579(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_580(value)
  }
  true
}

///|
fn wire_rule_578(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_579(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_575(value : Json) -> Bool {
  if wire_rule_576(value) && !wire_rule_578(value) {
    return false
  }
  true
}

///|
fn wire_rule_583(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if !(number == 25.0) {
    return false
  }
  true
}

///|
fn wire_rule_582(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_583(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_586(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if number > 25.0 {
    return false
  }
  true
}

///|
fn wire_rule_585(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_586(value)
  }
  true
}

///|
fn wire_rule_584(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_585(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_581(value : Json) -> Bool {
  if wire_rule_582(value) && !wire_rule_584(value) {
    return false
  }
  true
}

///|
fn wire_rule_589(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if !(number == 26.0) {
    return false
  }
  true
}

///|
fn wire_rule_588(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_589(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_592(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if number > 26.0 {
    return false
  }
  true
}

///|
fn wire_rule_591(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_592(value)
  }
  true
}

///|
fn wire_rule_590(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_591(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_587(value : Json) -> Bool {
  if wire_rule_588(value) && !wire_rule_590(value) {
    return false
  }
  true
}

///|
fn wire_rule_595(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if !(number == 27.0) {
    return false
  }
  true
}

///|
fn wire_rule_594(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_595(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_598(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if number > 27.0 {
    return false
  }
  true
}

///|
fn wire_rule_597(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_598(value)
  }
  true
}

///|
fn wire_rule_596(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_597(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_593(value : Json) -> Bool {
  if wire_rule_594(value) && !wire_rule_596(value) {
    return false
  }
  true
}

///|
fn wire_rule_601(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if !(number == 28.0) {
    return false
  }
  true
}

///|
fn wire_rule_600(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_601(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_604(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if number > 28.0 {
    return false
  }
  true
}

///|
fn wire_rule_603(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_604(value)
  }
  true
}

///|
fn wire_rule_602(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_603(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_599(value : Json) -> Bool {
  if wire_rule_600(value) && !wire_rule_602(value) {
    return false
  }
  true
}

///|
fn wire_rule_607(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if !(number == 29.0) {
    return false
  }
  true
}

///|
fn wire_rule_606(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_607(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_610(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if number > 29.0 {
    return false
  }
  true
}

///|
fn wire_rule_609(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_610(value)
  }
  true
}

///|
fn wire_rule_608(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_609(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_605(value : Json) -> Bool {
  if wire_rule_606(value) && !wire_rule_608(value) {
    return false
  }
  true
}

///|
fn wire_rule_613(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if !(number == 30.0) {
    return false
  }
  true
}

///|
fn wire_rule_612(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_613(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_616(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if number > 30.0 {
    return false
  }
  true
}

///|
fn wire_rule_615(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_616(value)
  }
  true
}

///|
fn wire_rule_614(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_615(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_611(value : Json) -> Bool {
  if wire_rule_612(value) && !wire_rule_614(value) {
    return false
  }
  true
}

///|
fn wire_rule_619(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if !(number == 31.0) {
    return false
  }
  true
}

///|
fn wire_rule_618(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_619(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_622(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if number > 31.0 {
    return false
  }
  true
}

///|
fn wire_rule_621(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_622(value)
  }
  true
}

///|
fn wire_rule_620(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_621(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_617(value : Json) -> Bool {
  if wire_rule_618(value) && !wire_rule_620(value) {
    return false
  }
  true
}

///|
fn wire_rule_625(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if !(number == 32.0) {
    return false
  }
  true
}

///|
fn wire_rule_624(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_625(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_628(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if number > 32.0 {
    return false
  }
  true
}

///|
fn wire_rule_627(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_628(value)
  }
  true
}

///|
fn wire_rule_626(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_627(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_623(value : Json) -> Bool {
  if wire_rule_624(value) && !wire_rule_626(value) {
    return false
  }
  true
}

///|
fn wire_rule_631(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if !(number == 33.0) {
    return false
  }
  true
}

///|
fn wire_rule_630(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_631(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_634(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if number > 33.0 {
    return false
  }
  true
}

///|
fn wire_rule_633(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_634(value)
  }
  true
}

///|
fn wire_rule_632(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_633(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_629(value : Json) -> Bool {
  if wire_rule_630(value) && !wire_rule_632(value) {
    return false
  }
  true
}

///|
fn wire_rule_637(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if !(number == 34.0) {
    return false
  }
  true
}

///|
fn wire_rule_636(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_637(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_640(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if number > 34.0 {
    return false
  }
  true
}

///|
fn wire_rule_639(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_640(value)
  }
  true
}

///|
fn wire_rule_638(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_639(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_635(value : Json) -> Bool {
  if wire_rule_636(value) && !wire_rule_638(value) {
    return false
  }
  true
}

///|
fn wire_rule_643(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if !(number == 35.0) {
    return false
  }
  true
}

///|
fn wire_rule_642(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_643(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_646(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if number > 35.0 {
    return false
  }
  true
}

///|
fn wire_rule_645(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_646(value)
  }
  true
}

///|
fn wire_rule_644(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_645(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_641(value : Json) -> Bool {
  if wire_rule_642(value) && !wire_rule_644(value) {
    return false
  }
  true
}

///|
fn wire_rule_649(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if !(number == 36.0) {
    return false
  }
  true
}

///|
fn wire_rule_648(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_649(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_652(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if number > 36.0 {
    return false
  }
  true
}

///|
fn wire_rule_651(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_652(value)
  }
  true
}

///|
fn wire_rule_650(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_651(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_647(value : Json) -> Bool {
  if wire_rule_648(value) && !wire_rule_650(value) {
    return false
  }
  true
}

///|
fn wire_rule_655(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if !(number == 37.0) {
    return false
  }
  true
}

///|
fn wire_rule_654(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_655(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_658(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if number > 37.0 {
    return false
  }
  true
}

///|
fn wire_rule_657(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_658(value)
  }
  true
}

///|
fn wire_rule_656(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_657(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_653(value : Json) -> Bool {
  if wire_rule_654(value) && !wire_rule_656(value) {
    return false
  }
  true
}

///|
fn wire_rule_661(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if !(number == 38.0) {
    return false
  }
  true
}

///|
fn wire_rule_660(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_661(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_664(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  if number > 38.0 {
    return false
  }
  true
}

///|
fn wire_rule_663(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_664(value)
  }
  true
}

///|
fn wire_rule_662(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_663(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_659(value : Json) -> Bool {
  if wire_rule_660(value) && !wire_rule_662(value) {
    return false
  }
  true
}

///|
fn wire_rule_665(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "decimal") {
    return false
  }
  true
}

///|
fn wire_rule_667(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) ||
    number != number.floor() ||
    number < -9007199254740991.0 ||
    number > 9007199254740991.0 {
    return false
  }
  if number < 1.0 {
    return false
  }
  if number > 38.0 {
    return false
  }
  true
}

///|
fn wire_rule_668(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) ||
    number != number.floor() ||
    number < -9007199254740991.0 ||
    number > 9007199254740991.0 {
    return false
  }
  if number < 0.0 {
    return false
  }
  if number > 38.0 {
    return false
  }
  true
}

///|
fn wire_rule_436(value : Json) -> Bool {
  if !wire_rule_437(value) {
    return false
  }
  if !wire_rule_443(value) {
    return false
  }
  if !wire_rule_449(value) {
    return false
  }
  if !wire_rule_455(value) {
    return false
  }
  if !wire_rule_461(value) {
    return false
  }
  if !wire_rule_467(value) {
    return false
  }
  if !wire_rule_473(value) {
    return false
  }
  if !wire_rule_479(value) {
    return false
  }
  if !wire_rule_485(value) {
    return false
  }
  if !wire_rule_491(value) {
    return false
  }
  if !wire_rule_497(value) {
    return false
  }
  if !wire_rule_503(value) {
    return false
  }
  if !wire_rule_509(value) {
    return false
  }
  if !wire_rule_515(value) {
    return false
  }
  if !wire_rule_521(value) {
    return false
  }
  if !wire_rule_527(value) {
    return false
  }
  if !wire_rule_533(value) {
    return false
  }
  if !wire_rule_539(value) {
    return false
  }
  if !wire_rule_545(value) {
    return false
  }
  if !wire_rule_551(value) {
    return false
  }
  if !wire_rule_557(value) {
    return false
  }
  if !wire_rule_563(value) {
    return false
  }
  if !wire_rule_569(value) {
    return false
  }
  if !wire_rule_575(value) {
    return false
  }
  if !wire_rule_581(value) {
    return false
  }
  if !wire_rule_587(value) {
    return false
  }
  if !wire_rule_593(value) {
    return false
  }
  if !wire_rule_599(value) {
    return false
  }
  if !wire_rule_605(value) {
    return false
  }
  if !wire_rule_611(value) {
    return false
  }
  if !wire_rule_617(value) {
    return false
  }
  if !wire_rule_623(value) {
    return false
  }
  if !wire_rule_629(value) {
    return false
  }
  if !wire_rule_635(value) {
    return false
  }
  if !wire_rule_641(value) {
    return false
  }
  if !wire_rule_647(value) {
    return false
  }
  if !wire_rule_653(value) {
    return false
  }
  if !wire_rule_659(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "type" ||
      key == "nullable" ||
      key == "precision" ||
      key == "scale") {
      return false
    }
  }
  if !fields.contains("type") {
    return false
  }
  if !fields.contains("nullable") {
    return false
  }
  if !fields.contains("precision") {
    return false
  }
  if !fields.contains("scale") {
    return false
  }
  if fields.get("type") is Some(item) {
    if !wire_rule_665(item) {
      return false
    }
  }
  if fields.get("nullable") is Some(item) {
    if !wire_rule_390(item) {
      return false
    }
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_667(item) {
      return false
    }
  }
  if fields.get("scale") is Some(item) {
    if !wire_rule_668(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_670(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "string") {
    return false
  }
  true
}

///|
fn wire_rule_672(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) ||
    number != number.floor() ||
    number < -9007199254740991.0 ||
    number > 9007199254740991.0 {
    return false
  }
  if number < 0.0 {
    return false
  }
  true
}

///|
fn wire_rule_676(value : Json) -> Bool {
  guard value is String(_) else { return false }
  true
}

///|
fn wire_rule_675(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  for item in items {
    if !wire_rule_676(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_669(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "type" ||
      key == "nullable" ||
      key == "min_length" ||
      key == "max_codepoints" ||
      key == "max_utf8_bytes" ||
      key == "enum") {
      return false
    }
  }
  if !fields.contains("type") {
    return false
  }
  if !fields.contains("nullable") {
    return false
  }
  if fields.get("type") is Some(item) {
    if !wire_rule_670(item) {
      return false
    }
  }
  if fields.get("nullable") is Some(item) {
    if !wire_rule_390(item) {
      return false
    }
  }
  if fields.get("min_length") is Some(item) {
    if !wire_rule_672(item) {
      return false
    }
  }
  if fields.get("max_codepoints") is Some(item) {
    if !wire_rule_672(item) {
      return false
    }
  }
  if fields.get("max_utf8_bytes") is Some(item) {
    if !wire_rule_672(item) {
      return false
    }
  }
  if fields.get("enum") is Some(item) {
    if !wire_rule_675(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_678(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "number" ||
    text == "boolean" ||
    text == "timestamp" ||
    text == "date" ||
    text == "json") {
    return false
  }
  true
}

///|
fn wire_rule_677(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "type" || key == "nullable") {
      return false
    }
  }
  if !fields.contains("type") {
    return false
  }
  if !fields.contains("nullable") {
    return false
  }
  if fields.get("type") is Some(item) {
    if !wire_rule_678(item) {
      return false
    }
  }
  if fields.get("nullable") is Some(item) {
    if !wire_rule_390(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_681(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "array") {
    return false
  }
  true
}

///|
fn wire_rule_680(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "type" ||
      key == "nullable" ||
      key == "items" ||
      key == "max_items") {
      return false
    }
  }
  if !fields.contains("type") {
    return false
  }
  if !fields.contains("nullable") {
    return false
  }
  if !fields.contains("items") {
    return false
  }
  if fields.get("type") is Some(item) {
    if !wire_rule_681(item) {
      return false
    }
  }
  if fields.get("nullable") is Some(item) {
    if !wire_rule_390(item) {
      return false
    }
  }
  if fields.get("items") is Some(item) {
    if !wire_rule_434(item) {
      return false
    }
  }
  if fields.get("max_items") is Some(item) {
    if !wire_rule_672(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_686(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "object") {
    return false
  }
  true
}

///|
fn wire_rule_688(value : Json) -> Bool {
  if !(value is True || value is False) {
    return false
  }
  if !(value is False) {
    return false
  }
  true
}

///|
fn wire_rule_692(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if text.is_empty() ||
    text == "__cid" ||
    text.has_prefix("__actql_") ||
    text.contains(".") {
    return false
  }
  let mut nonblank = false
  for character in text {
    let code = character.to_int()
    if !(code == 9 ||
      code == 10 ||
      code == 11 ||
      code == 12 ||
      code == 13 ||
      code == 32 ||
      code == 160 ||
      code == 5760 ||
      (code >= 8192 && code <= 8202) ||
      code == 8232 ||
      code == 8233 ||
      code == 8239 ||
      code == 8287 ||
      code == 12288 ||
      code == 65279) {
      nonblank = true
    }
  }
  if !nonblank {
    return false
  }
  true
}

///|
fn wire_rule_691(value : Json) -> Bool {
  if value is String(_) {
    return wire_rule_692(value)
  }
  true
}

///|
fn wire_rule_689(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for _key, item in fields {
    if !false && !wire_rule_434(item) {
      return false
    }
  }
  for key, _ in fields {
    if !wire_rule_691(Json::string(key)) {
      return false
    }
  }
  true
}

///|
fn wire_rule_685(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "type" ||
      key == "nullable" ||
      key == "additional_properties" ||
      key == "fields") {
      return false
    }
  }
  if !fields.contains("type") {
    return false
  }
  if !fields.contains("nullable") {
    return false
  }
  if !fields.contains("additional_properties") {
    return false
  }
  if !fields.contains("fields") {
    return false
  }
  if fields.get("type") is Some(item) {
    if !wire_rule_686(item) {
      return false
    }
  }
  if fields.get("nullable") is Some(item) {
    if !wire_rule_390(item) {
      return false
    }
  }
  if fields.get("additional_properties") is Some(item) {
    if !wire_rule_688(item) {
      return false
    }
  }
  if fields.get("fields") is Some(item) {
    if !wire_rule_689(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_694(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "vector") {
    return false
  }
  true
}

///|
fn wire_rule_696(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) ||
    number != number.floor() ||
    number < -9007199254740991.0 ||
    number > 9007199254740991.0 {
    return false
  }
  if number < 1.0 {
    return false
  }
  true
}

///|
fn wire_rule_697(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "f32") {
    return false
  }
  true
}

///|
fn wire_rule_693(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "type" ||
      key == "nullable" ||
      key == "dimensions" ||
      key == "element_type") {
      return false
    }
  }
  if !fields.contains("type") {
    return false
  }
  if !fields.contains("nullable") {
    return false
  }
  if !fields.contains("dimensions") {
    return false
  }
  if !fields.contains("element_type") {
    return false
  }
  if fields.get("type") is Some(item) {
    if !wire_rule_694(item) {
      return false
    }
  }
  if fields.get("nullable") is Some(item) {
    if !wire_rule_390(item) {
      return false
    }
  }
  if fields.get("dimensions") is Some(item) {
    if !wire_rule_696(item) {
      return false
    }
  }
  if fields.get("element_type") is Some(item) {
    if !wire_rule_697(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_699(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "resource_ref") {
    return false
  }
  true
}

///|
fn wire_rule_701(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if text.iter().count() < 1 {
    return false
  }
  true
}

///|
fn wire_rule_698(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "type" || key == "nullable" || key == "resource_kind") {
      return false
    }
  }
  if !fields.contains("type") {
    return false
  }
  if !fields.contains("nullable") {
    return false
  }
  if !fields.contains("resource_kind") {
    return false
  }
  if fields.get("type") is Some(item) {
    if !wire_rule_699(item) {
      return false
    }
  }
  if fields.get("nullable") is Some(item) {
    if !wire_rule_390(item) {
      return false
    }
  }
  if fields.get("resource_kind") is Some(item) {
    if !wire_rule_701(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_703(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "content_ref") {
    return false
  }
  true
}

///|
fn wire_rule_702(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "type" || key == "nullable" || key == "media_type") {
      return false
    }
  }
  if !fields.contains("type") {
    return false
  }
  if !fields.contains("nullable") {
    return false
  }
  if fields.get("type") is Some(item) {
    if !wire_rule_703(item) {
      return false
    }
  }
  if fields.get("nullable") is Some(item) {
    if !wire_rule_390(item) {
      return false
    }
  }
  if fields.get("media_type") is Some(item) {
    if !wire_rule_701(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_435(value : Json) -> Bool {
  if [
      wire_rule_436(value),
      wire_rule_669(value),
      wire_rule_677(value),
      wire_rule_680(value),
      wire_rule_685(value),
      wire_rule_693(value),
      wire_rule_698(value),
      wire_rule_702(value),
    ]
    .filter(fn(ok) { ok })
    .length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_rule_434(value : Json) -> Bool {
  if !wire_rule_435(value) {
    return false
  }
  true
}

///|
fn wire_rule_706(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "caller") {
    return false
  }
  true
}

///|
fn wire_rule_710(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "numeric") {
    return false
  }
  true
}

///|
fn wire_rule_714(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "field") {
    return false
  }
  true
}

///|
fn wire_rule_713(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "kind" || key == "name") {
      return false
    }
  }
  if !fields.contains("kind") {
    return false
  }
  if !fields.contains("name") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_714(item) {
      return false
    }
  }
  if fields.get("name") is Some(item) {
    if !wire_rule_376(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_717(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "items") {
    return false
  }
  true
}

///|
fn wire_rule_716(value : Json) -> Bool {
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
    if !wire_rule_717(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_712(value : Json) -> Bool {
  if [wire_rule_713(value), wire_rule_716(value)].filter(fn(ok) { ok }).length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_rule_711(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  if items.length() > 64 {
    return false
  }
  for item in items {
    if !wire_rule_712(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_719(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) {
    return false
  }
  true
}

///|
fn wire_rule_709(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "kind" ||
      key == "path" ||
      key == "integer" ||
      key == "minimum" ||
      key == "maximum") {
      return false
    }
  }
  if !fields.contains("kind") {
    return false
  }
  if !fields.contains("path") {
    return false
  }
  if !fields.contains("integer") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_710(item) {
      return false
    }
  }
  if fields.get("path") is Some(item) {
    if !wire_rule_711(item) {
      return false
    }
  }
  if fields.get("integer") is Some(item) {
    if !wire_rule_390(item) {
      return false
    }
  }
  if fields.get("minimum") is Some(item) {
    if !wire_rule_719(item) {
      return false
    }
  }
  if fields.get("maximum") is Some(item) {
    if !wire_rule_719(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_722(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "duration") {
    return false
  }
  true
}

///|
fn wire_rule_721(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "kind" || key == "path") {
      return false
    }
  }
  if !fields.contains("kind") {
    return false
  }
  if !fields.contains("path") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_722(item) {
      return false
    }
  }
  if fields.get("path") is Some(item) {
    if !wire_rule_711(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_725(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "array_length") {
    return false
  }
  true
}

///|
fn wire_rule_727(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) ||
    number != number.floor() ||
    number < -9007199254740991.0 ||
    number > 9007199254740991.0 {
    return false
  }
  if number < 1.0 {
    return false
  }
  if number > 9007199254740991.0 {
    return false
  }
  true
}

///|
fn wire_rule_724(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "kind" || key == "path" || key == "length") {
      return false
    }
  }
  if !fields.contains("kind") {
    return false
  }
  if !fields.contains("path") {
    return false
  }
  if !fields.contains("length") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_725(item) {
      return false
    }
  }
  if fields.get("path") is Some(item) {
    if !wire_rule_711(item) {
      return false
    }
  }
  if fields.get("length") is Some(item) {
    if !wire_rule_727(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_708(value : Json) -> Bool {
  if [wire_rule_709(value), wire_rule_721(value), wire_rule_724(value)]
    .filter(fn(ok) { ok })
    .length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_rule_707(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  if items.length() > 8192 {
    return false
  }
  for item in items {
    if !wire_rule_708(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_431(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "contract_schema_cid" ||
      key == "kind" ||
      key == "contract" ||
      key == "supplier" ||
      key == "constraints") {
      return false
    }
  }
  if !fields.contains("kind") {
    return false
  }
  if !fields.contains("contract_schema_cid") {
    return false
  }
  if !fields.contains("contract") {
    return false
  }
  if !fields.contains("constraints") {
    return false
  }
  if !fields.contains("supplier") {
    return false
  }
  if fields.get("contract_schema_cid") is Some(item) {
    if !wire_rule_432(item) {
      return false
    }
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_433(item) {
      return false
    }
  }
  if fields.get("contract") is Some(item) {
    if !wire_rule_434(item) {
      return false
    }
  }
  if fields.get("supplier") is Some(item) {
    if !wire_rule_706(item) {
      return false
    }
  }
  if fields.get("constraints") is Some(item) {
    if !wire_rule_707(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_428(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "parameter" || key == "expected_type" || key == "admission") {
      return false
    }
  }
  if !fields.contains("parameter") {
    return false
  }
  if !fields.contains("expected_type") {
    return false
  }
  if fields.get("parameter") is Some(item) {
    if !wire_rule_294(item) {
      return false
    }
  }
  if fields.get("expected_type") is Some(item) {
    if !wire_rule_426(item) {
      return false
    }
  }
  if fields.get("admission") is Some(item) {
    if !wire_rule_431(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_730(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "numeric" ||
    text == "duration" ||
    text == "array_length" ||
    text == "array_size") {
    return false
  }
  true
}

///|
fn wire_rule_728(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "parameter" || key == "constraint") {
      return false
    }
  }
  if !fields.contains("parameter") {
    return false
  }
  if !fields.contains("constraint") {
    return false
  }
  if fields.get("parameter") is Some(item) {
    if !wire_rule_294(item) {
      return false
    }
  }
  if fields.get("constraint") is Some(item) {
    if !wire_rule_730(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_734(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "positive_safe_integer" ||
    text == "nonnegative_safe_integer" ||
    text == "unit_fraction" ||
    text == "finite_number" ||
    text == "duration" ||
    text == "positive_milliseconds" ||
    text == "signed_milliseconds" ||
    text == "timestamp") {
    return false
  }
  true
}

///|
fn wire_rule_732(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "parameter" || key == "domain") {
      return false
    }
  }
  if !fields.contains("parameter") {
    return false
  }
  if !fields.contains("domain") {
    return false
  }
  if fields.get("parameter") is Some(item) {
    if !wire_rule_294(item) {
      return false
    }
  }
  if fields.get("domain") is Some(item) {
    if !wire_rule_734(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_736(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "components") {
    return false
  }
  true
}

///|
fn wire_rule_737(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "invalid_kind" || text == "invalid_output_rows") {
    return false
  }
  true
}

///|
fn wire_rule_735(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "operation" || key == "issue") {
      return false
    }
  }
  if !fields.contains("operation") {
    return false
  }
  if !fields.contains("issue") {
    return false
  }
  if fields.get("operation") is Some(item) {
    if !wire_rule_736(item) {
      return false
    }
  }
  if fields.get("issue") is Some(item) {
    if !wire_rule_737(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_739(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "subgraph") {
    return false
  }
  true
}

///|
fn wire_rule_740(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "invalid_node_selector") {
    return false
  }
  true
}

///|
fn wire_rule_738(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "operation" || key == "issue") {
      return false
    }
  }
  if !fields.contains("operation") {
    return false
  }
  if !fields.contains("issue") {
    return false
  }
  if fields.get("operation") is Some(item) {
    if !wire_rule_739(item) {
      return false
    }
  }
  if fields.get("issue") is Some(item) {
    if !wire_rule_740(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_743(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "unexpected_end" ||
    text == "unexpected_token" ||
    text == "invalid_escape" ||
    text == "invalid_scalar" ||
    text == "empty_identifier" ||
    text == "unterminated_comment" ||
    text == "invalid_number" ||
    text == "invalid_parameter" ||
    text == "unknown_reference" ||
    text == "invalid_arguments" ||
    text == "expected_boolean" ||
    text == "invalid_bounds" ||
    text == "function_lowering_unresolved" ||
    text == "missing_field" ||
    text == "wrong_type" ||
    text == "unexpected_null" ||
    text == "invalid_structure") {
    return false
  }
  true
}

///|
fn wire_rule_742(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "issue") {
      return false
    }
  }
  if !fields.contains("issue") {
    return false
  }
  if fields.get("issue") is Some(item) {
    if !wire_rule_743(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_422(value : Json) -> Bool {
  if [
      wire_rule_293(value),
      wire_rule_424(value),
      wire_rule_428(value),
      wire_rule_728(value),
      wire_rule_305(value),
      wire_rule_732(value),
      wire_rule_735(value),
      wire_rule_738(value),
      wire_rule_334(value),
      wire_rule_742(value),
      wire_rule_203(value),
      wire_rule_186(value),
      wire_rule_374(value),
      wire_rule_385(value),
    ]
    .filter(fn(ok) { ok })
    .length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_rule_167(value : Json) -> Bool {
  if !wire_rule_168(value) {
    return false
  }
  if !wire_rule_178(value) {
    return false
  }
  if !wire_rule_190(value) {
    return false
  }
  if !wire_rule_197(value) {
    return false
  }
  if !wire_rule_209(value) {
    return false
  }
  if !wire_rule_216(value) {
    return false
  }
  if !wire_rule_225(value) {
    return false
  }
  if !wire_rule_232(value) {
    return false
  }
  if !wire_rule_241(value) {
    return false
  }
  if !wire_rule_248(value) {
    return false
  }
  if !wire_rule_255(value) {
    return false
  }
  if !wire_rule_262(value) {
    return false
  }
  if !wire_rule_267(value) {
    return false
  }
  if !wire_rule_273(value) {
    return false
  }
  if !wire_rule_284(value) {
    return false
  }
  if !wire_rule_289(value) {
    return false
  }
  if !wire_rule_296(value) {
    return false
  }
  if !wire_rule_301(value) {
    return false
  }
  if !wire_rule_308(value) {
    return false
  }
  if !wire_rule_316(value) {
    return false
  }
  if !wire_rule_339(value) {
    return false
  }
  if !wire_rule_347(value) {
    return false
  }
  if !wire_rule_354(value) {
    return false
  }
  if !wire_rule_361(value) {
    return false
  }
  if !wire_rule_369(value) {
    return false
  }
  if !wire_rule_380(value) {
    return false
  }
  if !wire_rule_392(value) {
    return false
  }
  if !wire_rule_398(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "code" || key == "location" || key == "fixes" || key == "facts") {
      return false
    }
  }
  if !fields.contains("code") {
    return false
  }
  if fields.get("code") is Some(item) {
    if !wire_rule_130(item) {
      return false
    }
  }
  if fields.get("location") is Some(item) {
    if !wire_rule_402(item) {
      return false
    }
  }
  if fields.get("fixes") is Some(item) {
    if !wire_rule_409(item) {
      return false
    }
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_422(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_166(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  if items.length() > 1024 {
    return false
  }
  for item in items {
    if !wire_rule_167(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_749(value : Json) -> Bool {
  if !wire_rule_168(value) {
    return false
  }
  if !wire_rule_178(value) {
    return false
  }
  if !wire_rule_190(value) {
    return false
  }
  if !wire_rule_197(value) {
    return false
  }
  if !wire_rule_209(value) {
    return false
  }
  if !wire_rule_216(value) {
    return false
  }
  if !wire_rule_225(value) {
    return false
  }
  if !wire_rule_232(value) {
    return false
  }
  if !wire_rule_241(value) {
    return false
  }
  if !wire_rule_248(value) {
    return false
  }
  if !wire_rule_255(value) {
    return false
  }
  if !wire_rule_262(value) {
    return false
  }
  if !wire_rule_267(value) {
    return false
  }
  if !wire_rule_273(value) {
    return false
  }
  if !wire_rule_284(value) {
    return false
  }
  if !wire_rule_289(value) {
    return false
  }
  if !wire_rule_296(value) {
    return false
  }
  if !wire_rule_301(value) {
    return false
  }
  if !wire_rule_308(value) {
    return false
  }
  if !wire_rule_316(value) {
    return false
  }
  if !wire_rule_339(value) {
    return false
  }
  if !wire_rule_347(value) {
    return false
  }
  if !wire_rule_354(value) {
    return false
  }
  if !wire_rule_361(value) {
    return false
  }
  if !wire_rule_369(value) {
    return false
  }
  if !wire_rule_380(value) {
    return false
  }
  if !wire_rule_392(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "code" || key == "location" || key == "fixes" || key == "facts") {
      return false
    }
  }
  if !fields.contains("code") {
    return false
  }
  if !fields.contains("facts") {
    return false
  }
  if fields.get("code") is Some(item) {
    if !wire_rule_400(item) {
      return false
    }
  }
  if fields.get("location") is Some(item) {
    if !wire_rule_402(item) {
      return false
    }
  }
  if fields.get("fixes") is Some(item) {
    if !wire_rule_409(item) {
      return false
    }
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_422(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_748(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  if items.length() > 1024 {
    return false
  }
  for item in items {
    if !wire_rule_749(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_782(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "template_only" || text == "bound_input") {
    return false
  }
  true
}

///|
fn wire_rule_781(value : Json) -> Bool {
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
    if !wire_rule_782(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_783(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "invalid" || text == "undetermined" || text == "verified") {
    return false
  }
  true
}

///|
fn wire_rule_68(value : Json) -> Bool {
  if !wire_rule_69(value) {
    return false
  }
  if !wire_rule_75(value) {
    return false
  }
  if !wire_rule_79(value) {
    return false
  }
  if !wire_rule_104(value) {
    return false
  }
  if !wire_rule_109(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "runnable" ||
      key == "context_ref" ||
      key == "omissions" ||
      key == "inputs" ||
      key == "coverage" ||
      key == "reasons" ||
      key == "requirements" ||
      key == "scope" ||
      key == "verdict") {
      return false
    }
  }
  if !fields.contains("context_ref") {
    return false
  }
  if !fields.contains("coverage") {
    return false
  }
  if !fields.contains("inputs") {
    return false
  }
  if !fields.contains("reasons") {
    return false
  }
  if !fields.contains("requirements") {
    return false
  }
  if !fields.contains("runnable") {
    return false
  }
  if !fields.contains("scope") {
    return false
  }
  if !fields.contains("verdict") {
    return false
  }
  if fields.get("runnable") is Some(item) {
    if !wire_rule_115(item) {
      return false
    }
  }
  if fields.get("context_ref") is Some(item) {
    if !wire_rule_131(item) {
      return false
    }
  }
  if fields.get("omissions") is Some(item) {
    if !wire_rule_132(item) {
      return false
    }
  }
  if fields.get("inputs") is Some(item) {
    if !wire_rule_134(item) {
      return false
    }
  }
  if fields.get("coverage") is Some(item) {
    if !wire_rule_140(item) {
      return false
    }
  }
  if fields.get("reasons") is Some(item) {
    if !wire_rule_166(item) {
      return false
    }
  }
  if fields.get("requirements") is Some(item) {
    if !wire_rule_748(item) {
      return false
    }
  }
  if fields.get("scope") is Some(item) {
    if !wire_rule_781(item) {
      return false
    }
  }
  if fields.get("verdict") is Some(item) {
    if !wire_rule_783(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_784(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if text.length() != 71 || !text.has_prefix("sha256:") {
    return false
  }
  for character in text[7:] {
    if !((character >= '0' && character <= '9') ||
      (character >= 'a' && character <= 'f')) {
      return false
    }
  }
  true
}

///|
fn wire_rule_785(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text ==
    "sha256:b68ddf82e07cefaf18e98e652f5763661371bf5ffa626134967c6c17bb2fd20e") {
    return false
  }
  true
}

///|
fn wire_rule_786(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "actql-check-outcome/0.1") {
    return false
  }
  true
}

///|
fn wire_rule_66(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "outcome" ||
      key == "report" ||
      key == "outcome_schema_cid" ||
      key == "reason_schema_cid" ||
      key == "version") {
      return false
    }
  }
  if !fields.contains("outcome") {
    return false
  }
  if !fields.contains("report") {
    return false
  }
  if !fields.contains("version") {
    return false
  }
  if !fields.contains("reason_schema_cid") {
    return false
  }
  if !fields.contains("outcome_schema_cid") {
    return false
  }
  if fields.get("outcome") is Some(item) {
    if !wire_rule_67(item) {
      return false
    }
  }
  if fields.get("report") is Some(item) {
    if !wire_rule_68(item) {
      return false
    }
  }
  if fields.get("outcome_schema_cid") is Some(item) {
    if !wire_rule_784(item) {
      return false
    }
  }
  if fields.get("reason_schema_cid") is Some(item) {
    if !wire_rule_785(item) {
      return false
    }
  }
  if fields.get("version") is Some(item) {
    if !wire_rule_786(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_788(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "failed") {
    return false
  }
  true
}

///|
fn wire_rule_803(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "invalid" || text == "undetermined") {
    return false
  }
  true
}

///|
fn wire_rule_789(value : Json) -> Bool {
  if !wire_rule_69(value) {
    return false
  }
  if !wire_rule_75(value) {
    return false
  }
  if !wire_rule_79(value) {
    return false
  }
  if !wire_rule_104(value) {
    return false
  }
  if !wire_rule_109(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "runnable" ||
      key == "context_ref" ||
      key == "omissions" ||
      key == "inputs" ||
      key == "coverage" ||
      key == "reasons" ||
      key == "requirements" ||
      key == "scope" ||
      key == "verdict") {
      return false
    }
  }
  if !fields.contains("context_ref") {
    return false
  }
  if !fields.contains("coverage") {
    return false
  }
  if !fields.contains("inputs") {
    return false
  }
  if !fields.contains("reasons") {
    return false
  }
  if !fields.contains("requirements") {
    return false
  }
  if !fields.contains("runnable") {
    return false
  }
  if !fields.contains("scope") {
    return false
  }
  if !fields.contains("verdict") {
    return false
  }
  if fields.get("runnable") is Some(item) {
    if !wire_rule_115(item) {
      return false
    }
  }
  if fields.get("context_ref") is Some(item) {
    if !wire_rule_131(item) {
      return false
    }
  }
  if fields.get("omissions") is Some(item) {
    if !wire_rule_132(item) {
      return false
    }
  }
  if fields.get("inputs") is Some(item) {
    if !wire_rule_134(item) {
      return false
    }
  }
  if fields.get("coverage") is Some(item) {
    if !wire_rule_140(item) {
      return false
    }
  }
  if fields.get("reasons") is Some(item) {
    if !wire_rule_166(item) {
      return false
    }
  }
  if fields.get("requirements") is Some(item) {
    if !wire_rule_748(item) {
      return false
    }
  }
  if fields.get("scope") is Some(item) {
    if !wire_rule_781(item) {
      return false
    }
  }
  if fields.get("verdict") is Some(item) {
    if !wire_rule_803(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_787(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "outcome" ||
      key == "partial_report" ||
      key == "problem" ||
      key == "correlation_ref" ||
      key == "outcome_schema_cid" ||
      key == "reason_schema_cid" ||
      key == "version") {
      return false
    }
  }
  if !fields.contains("outcome") {
    return false
  }
  if !fields.contains("problem") {
    return false
  }
  if !fields.contains("version") {
    return false
  }
  if !fields.contains("reason_schema_cid") {
    return false
  }
  if !fields.contains("outcome_schema_cid") {
    return false
  }
  if !fields.contains("correlation_ref") {
    return false
  }
  if fields.get("outcome") is Some(item) {
    if !wire_rule_788(item) {
      return false
    }
  }
  if fields.get("partial_report") is Some(item) {
    if !wire_rule_789(item) {
      return false
    }
  }
  if fields.get("problem") is Some(item) {
    if !wire_rule_129(item) {
      return false
    }
  }
  if fields.get("correlation_ref") is Some(item) {
    if !wire_rule_131(item) {
      return false
    }
  }
  if fields.get("outcome_schema_cid") is Some(item) {
    if !wire_rule_784(item) {
      return false
    }
  }
  if fields.get("reason_schema_cid") is Some(item) {
    if !wire_rule_785(item) {
      return false
    }
  }
  if fields.get("version") is Some(item) {
    if !wire_rule_786(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_811(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "unavailable") {
    return false
  }
  true
}

///|
fn wire_rule_809(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "correlation_ref" ||
      key == "outcome" ||
      key == "problem" ||
      key == "outcome_schema_cid" ||
      key == "reason_schema_cid" ||
      key == "version") {
      return false
    }
  }
  if !fields.contains("correlation_ref") {
    return false
  }
  if !fields.contains("outcome") {
    return false
  }
  if !fields.contains("problem") {
    return false
  }
  if !fields.contains("version") {
    return false
  }
  if !fields.contains("reason_schema_cid") {
    return false
  }
  if !fields.contains("outcome_schema_cid") {
    return false
  }
  if fields.get("correlation_ref") is Some(item) {
    if !wire_rule_131(item) {
      return false
    }
  }
  if fields.get("outcome") is Some(item) {
    if !wire_rule_811(item) {
      return false
    }
  }
  if fields.get("problem") is Some(item) {
    if !wire_rule_129(item) {
      return false
    }
  }
  if fields.get("outcome_schema_cid") is Some(item) {
    if !wire_rule_784(item) {
      return false
    }
  }
  if fields.get("reason_schema_cid") is Some(item) {
    if !wire_rule_785(item) {
      return false
    }
  }
  if fields.get("version") is Some(item) {
    if !wire_rule_786(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_65(value : Json) -> Bool {
  if [wire_rule_66(value), wire_rule_787(value), wire_rule_809(value)]
    .filter(fn(ok) { ok })
    .length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_rule_64(value : Json) -> Bool {
  if !wire_rule_65(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  if fields.get("reason_schema_cid") !=
    Some(
      Json::string(
        "sha256:b68ddf82e07cefaf18e98e652f5763661371bf5ffa626134967c6c17bb2fd20e",
      ),
    ) {
    return false
  }
  if fields.get("outcome_schema_cid") !=
    Some(
      Json::string(
        "sha256:988a8893ede0e64a351f077f28c7b7c82a9b2988467b8eb8a02755ad3530ca7b",
      ),
    ) {
    return false
  }
  if !wire_check_report_contract(value) {
    return false
  }
  true
}

///|
fn wire_rule_819(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "bound_input") {
    return false
  }
  true
}

///|
fn wire_rule_818(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("kind") is Some(item) {
    if !wire_rule_819(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_817(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scope") is Some(item) {
    if !wire_rule_818(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_816(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("report") is Some(item) {
    if !wire_rule_817(item) {
      return false
    }
  }
  if fields.get("partial_report") is Some(item) {
    if !wire_rule_817(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_63(value : Json) -> Bool {
  if !wire_rule_64(value) {
    return false
  }
  if !wire_rule_816(value) {
    return false
  }
  true
}

///|
fn wire_rule_823(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "invalid_input" ||
    text == "requirements" ||
    text == "implementation_limit" ||
    text == "authorization" ||
    text == "operation_failed") {
    return false
  }
  true
}

///|
fn wire_rule_821(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "code" || key == "classification") {
      return false
    }
  }
  if !fields.contains("code") {
    return false
  }
  if !fields.contains("classification") {
    return false
  }
  if fields.get("code") is Some(item) {
    if !wire_rule_7(item) {
      return false
    }
  }
  if fields.get("classification") is Some(item) {
    if !wire_rule_823(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_59(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "kind" ||
      key == "submissionRef" ||
      key == "intentCid" ||
      key == "checkObservation" ||
      key == "problem" ||
      key == "unresolvedHistory") {
      return false
    }
  }
  if !fields.contains("kind") {
    return false
  }
  if !fields.contains("submissionRef") {
    return false
  }
  if !fields.contains("intentCid") {
    return false
  }
  if !fields.contains("problem") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_60(item) {
      return false
    }
  }
  if fields.get("submissionRef") is Some(item) {
    if !wire_submission_ref_shape(item) {
      return false
    }
  }
  if fields.get("intentCid") is Some(item) {
    if !wire_rule_1(item) {
      return false
    }
  }
  if fields.get("checkObservation") is Some(item) {
    if !wire_rule_63(item) {
      return false
    }
  }
  if fields.get("problem") is Some(item) {
    if !wire_rule_821(item) {
      return false
    }
  }
  if fields.get("unresolvedHistory") is Some(item) {
    if !wire_rule_19(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_826(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "preparation_failed") {
    return false
  }
  true
}

///|
fn wire_rule_825(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "kind" ||
      key == "submissionRef" ||
      key == "intentCid" ||
      key == "checkObservation" ||
      key == "problem" ||
      key == "unresolvedHistory") {
      return false
    }
  }
  if !fields.contains("kind") {
    return false
  }
  if !fields.contains("submissionRef") {
    return false
  }
  if !fields.contains("intentCid") {
    return false
  }
  if !fields.contains("problem") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_826(item) {
      return false
    }
  }
  if fields.get("submissionRef") is Some(item) {
    if !wire_submission_ref_shape(item) {
      return false
    }
  }
  if fields.get("intentCid") is Some(item) {
    if !wire_rule_1(item) {
      return false
    }
  }
  if fields.get("checkObservation") is Some(item) {
    if !wire_rule_63(item) {
      return false
    }
  }
  if fields.get("problem") is Some(item) {
    if !wire_rule_821(item) {
      return false
    }
  }
  if fields.get("unresolvedHistory") is Some(item) {
    if !wire_rule_19(item) {
      return false
    }
  }
  true
}

///|
fn wire_submission_outcome_shape(value : Json) -> Bool {
  if [
      wire_rule_8(value),
      wire_rule_22(value),
      wire_rule_54(value),
      wire_rule_59(value),
      wire_rule_825(value),
    ]
    .filter(fn(ok) { ok })
    .length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_rule_835(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "kind" ||
      key == "submissionRef" ||
      key == "intentCid" ||
      key == "problem" ||
      key == "unresolvedHistory") {
      return false
    }
  }
  if !fields.contains("kind") {
    return false
  }
  if !fields.contains("submissionRef") {
    return false
  }
  if !fields.contains("intentCid") {
    return false
  }
  if !fields.contains("problem") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_60(item) {
      return false
    }
  }
  if fields.get("submissionRef") is Some(item) {
    if !wire_submission_ref_shape(item) {
      return false
    }
  }
  if fields.get("intentCid") is Some(item) {
    if !wire_rule_1(item) {
      return false
    }
  }
  if fields.get("problem") is Some(item) {
    if !wire_rule_821(item) {
      return false
    }
  }
  if fields.get("unresolvedHistory") is Some(item) {
    if !wire_rule_19(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_841(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "kind" ||
      key == "submissionRef" ||
      key == "intentCid" ||
      key == "problem" ||
      key == "unresolvedHistory") {
      return false
    }
  }
  if !fields.contains("kind") {
    return false
  }
  if !fields.contains("submissionRef") {
    return false
  }
  if !fields.contains("intentCid") {
    return false
  }
  if !fields.contains("problem") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_826(item) {
      return false
    }
  }
  if fields.get("submissionRef") is Some(item) {
    if !wire_submission_ref_shape(item) {
      return false
    }
  }
  if fields.get("intentCid") is Some(item) {
    if !wire_rule_1(item) {
      return false
    }
  }
  if fields.get("problem") is Some(item) {
    if !wire_rule_821(item) {
      return false
    }
  }
  if fields.get("unresolvedHistory") is Some(item) {
    if !wire_rule_19(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_848(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "unresolvable") {
    return false
  }
  true
}

///|
fn wire_rule_850(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "code") {
      return false
    }
  }
  if !fields.contains("code") {
    return false
  }
  if fields.get("code") is Some(item) {
    if !wire_rule_7(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_847(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "kind" ||
      key == "submissionRef" ||
      key == "problem" ||
      key == "unresolvedHistory") {
      return false
    }
  }
  if !fields.contains("kind") {
    return false
  }
  if !fields.contains("submissionRef") {
    return false
  }
  if !fields.contains("problem") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_848(item) {
      return false
    }
  }
  if fields.get("submissionRef") is Some(item) {
    if !wire_submission_ref_shape(item) {
      return false
    }
  }
  if fields.get("problem") is Some(item) {
    if !wire_rule_850(item) {
      return false
    }
  }
  if fields.get("unresolvedHistory") is Some(item) {
    if !wire_rule_19(item) {
      return false
    }
  }
  true
}

///|
fn wire_submission_lookup_shape(value : Json) -> Bool {
  if [
      wire_rule_8(value),
      wire_rule_22(value),
      wire_rule_54(value),
      wire_rule_835(value),
      wire_rule_841(value),
      wire_rule_847(value),
    ]
    .filter(fn(ok) { ok })
    .length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_submission_restart_shape(value : Json) -> Bool {
  wire_rule_19(value)
}

///|
fn wire_rule_856(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "already_satisfied") {
    return false
  }
  true
}

///|
fn wire_rule_855(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("kind") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_856(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_859(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("kind") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_55(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_858(value : Json) -> Bool {
  if wire_rule_859(value) {
    return false
  }
  true
}

///|
fn wire_rule_857(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("outcome") {
    return false
  }
  if fields.get("outcome") is Some(item) {
    if !wire_rule_858(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_854(value : Json) -> Bool {
  if wire_rule_855(value) && !wire_rule_857(value) {
    return false
  }
  true
}

///|
fn wire_rule_861(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "recorded" || text == "already_satisfied") {
    return false
  }
  true
}

///|
fn wire_rule_863(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "submit") {
    return false
  }
  true
}

///|
fn wire_rule_862(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "operation" || key == "attemptId") {
      return false
    }
  }
  if !fields.contains("operation") {
    return false
  }
  if !fields.contains("attemptId") {
    return false
  }
  if fields.get("operation") is Some(item) {
    if !wire_rule_863(item) {
      return false
    }
  }
  if fields.get("attemptId") is Some(item) {
    if !wire_rule_7(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_853(value : Json) -> Bool {
  if !wire_rule_854(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "kind" || key == "attemptRef" || key == "outcome") {
      return false
    }
  }
  if !fields.contains("kind") {
    return false
  }
  if !fields.contains("attemptRef") {
    return false
  }
  if !fields.contains("outcome") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_861(item) {
      return false
    }
  }
  if fields.get("attemptRef") is Some(item) {
    if !wire_rule_862(item) {
      return false
    }
  }
  if fields.get("outcome") is Some(item) {
    if !wire_submission_outcome_shape(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_867(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "refused") {
    return false
  }
  true
}

///|
fn wire_rule_869(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "attempt_uncommitted_unconsumed") {
    return false
  }
  true
}

///|
fn wire_rule_870(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "authorization") {
    return false
  }
  true
}

///|
fn wire_rule_866(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "kind" ||
      key == "attemptRef" ||
      key == "guarantee" ||
      key == "reason") {
      return false
    }
  }
  if !fields.contains("kind") {
    return false
  }
  if !fields.contains("attemptRef") {
    return false
  }
  if !fields.contains("guarantee") {
    return false
  }
  if !fields.contains("reason") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_867(item) {
      return false
    }
  }
  if fields.get("attemptRef") is Some(item) {
    if !wire_rule_862(item) {
      return false
    }
  }
  if fields.get("guarantee") is Some(item) {
    if !wire_rule_869(item) {
      return false
    }
  }
  if fields.get("reason") is Some(item) {
    if !wire_rule_870(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_877(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "admission_capacity" ||
    text == "epoch_expired" ||
    text == "epoch_not_yet_valid") {
    return false
  }
  true
}

///|
fn wire_rule_871(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "kind" ||
      key == "attemptRef" ||
      key == "submissionRef" ||
      key == "intentCid" ||
      key == "guarantee" ||
      key == "reason") {
      return false
    }
  }
  if !fields.contains("kind") {
    return false
  }
  if !fields.contains("attemptRef") {
    return false
  }
  if !fields.contains("submissionRef") {
    return false
  }
  if !fields.contains("intentCid") {
    return false
  }
  if !fields.contains("guarantee") {
    return false
  }
  if !fields.contains("reason") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_867(item) {
      return false
    }
  }
  if fields.get("attemptRef") is Some(item) {
    if !wire_rule_862(item) {
      return false
    }
  }
  if fields.get("submissionRef") is Some(item) {
    if !wire_submission_ref_shape(item) {
      return false
    }
  }
  if fields.get("intentCid") is Some(item) {
    if !wire_rule_1(item) {
      return false
    }
  }
  if fields.get("guarantee") is Some(item) {
    if !wire_rule_869(item) {
      return false
    }
  }
  if fields.get("reason") is Some(item) {
    if !wire_rule_877(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_879(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "conflict") {
    return false
  }
  true
}

///|
fn wire_rule_883(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "intent" || text == "restart_decision") {
    return false
  }
  true
}

///|
fn wire_rule_878(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "kind" ||
      key == "attemptRef" ||
      key == "submissionRef" ||
      key == "intentCid" ||
      key == "reason") {
      return false
    }
  }
  if !fields.contains("kind") {
    return false
  }
  if !fields.contains("attemptRef") {
    return false
  }
  if !fields.contains("submissionRef") {
    return false
  }
  if !fields.contains("intentCid") {
    return false
  }
  if !fields.contains("reason") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_879(item) {
      return false
    }
  }
  if fields.get("attemptRef") is Some(item) {
    if !wire_rule_862(item) {
      return false
    }
  }
  if fields.get("submissionRef") is Some(item) {
    if !wire_submission_ref_shape(item) {
      return false
    }
  }
  if fields.get("intentCid") is Some(item) {
    if !wire_rule_1(item) {
      return false
    }
  }
  if fields.get("reason") is Some(item) {
    if !wire_rule_883(item) {
      return false
    }
  }
  true
}

///|
fn wire_submission_attempt_shape(value : Json) -> Bool {
  if [
      wire_rule_853(value),
      wire_rule_866(value),
      wire_rule_871(value),
      wire_rule_878(value),
    ]
    .filter(fn(ok) { ok })
    .length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_rule_887(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("movementPolicyRef") {
    return false
  }
  true
}

///|
fn wire_rule_886(value : Json) -> Bool {
  if wire_rule_887(value) {
    return false
  }
  true
}

///|
fn wire_rule_889(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("cloudConnectionRef") {
    return false
  }
  true
}

///|
fn wire_rule_888(value : Json) -> Bool {
  if wire_rule_889(value) {
    return false
  }
  true
}

///|
fn wire_rule_890(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "remote") {
    return false
  }
  true
}

///|
fn wire_rule_892(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  if items.length() > 0 {
    return false
  }
  for item in items {
    if !wire_rule_7(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_885(value : Json) -> Bool {
  if !wire_rule_886(value) {
    return false
  }
  if !wire_rule_888(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  if fields.get("mode") is Some(item) {
    if !wire_rule_890(item) {
      return false
    }
  }
  if fields.get("owner") is Some(item) {
    if !wire_rule_890(item) {
      return false
    }
  }
  if fields.get("runners") is Some(item) {
    if !wire_rule_892(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_897(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "local") {
    return false
  }
  true
}

///|
fn wire_rule_894(value : Json) -> Bool {
  if !wire_rule_886(value) {
    return false
  }
  if !wire_rule_888(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  if fields.get("mode") is Some(item) {
    if !wire_rule_897(item) {
      return false
    }
  }
  if fields.get("owner") is Some(item) {
    if !wire_rule_897(item) {
      return false
    }
  }
  if fields.get("runners") is Some(item) {
    if !wire_rule_892(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_901(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "hybrid") {
    return false
  }
  true
}

///|
fn wire_rule_900(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("movementPolicyRef") {
    return false
  }
  if !fields.contains("cloudConnectionRef") {
    return false
  }
  if fields.get("mode") is Some(item) {
    if !wire_rule_901(item) {
      return false
    }
  }
  if fields.get("owner") is Some(item) {
    if !wire_rule_897(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_906(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "cloud") {
    return false
  }
  true
}

///|
fn wire_rule_907(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  if items.length() < 1 {
    return false
  }
  for item in items {
    if !wire_rule_7(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_903(value : Json) -> Bool {
  if wire_rule_889(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  if !fields.contains("movementPolicyRef") {
    return false
  }
  if fields.get("mode") is Some(item) {
    if !wire_rule_901(item) {
      return false
    }
  }
  if fields.get("owner") is Some(item) {
    if !wire_rule_906(item) {
      return false
    }
  }
  if fields.get("runners") is Some(item) {
    if !wire_rule_907(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_884(value : Json) -> Bool {
  if [
      wire_rule_885(value),
      wire_rule_894(value),
      wire_rule_900(value),
      wire_rule_903(value),
    ]
    .filter(fn(ok) { ok })
    .length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_rule_909(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "local" || text == "remote" || text == "hybrid") {
    return false
  }
  true
}

///|
fn wire_rule_910(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "local" || text == "remote" || text == "cloud") {
    return false
  }
  true
}

///|
fn wire_rule_912(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  for item in items {
    if !wire_rule_7(item) {
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
fn wire_connection_shape(value : Json) -> Bool {
  if !wire_rule_884(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "mode" ||
      key == "owner" ||
      key == "workspaceId" ||
      key == "consentRefs" ||
      key == "runners" ||
      key == "durability" ||
      key == "movementPolicyRef" ||
      key == "cloudConnectionRef") {
      return false
    }
  }
  if !fields.contains("mode") {
    return false
  }
  if !fields.contains("owner") {
    return false
  }
  if !fields.contains("consentRefs") {
    return false
  }
  if !fields.contains("runners") {
    return false
  }
  if fields.get("mode") is Some(item) {
    if !wire_rule_909(item) {
      return false
    }
  }
  if fields.get("owner") is Some(item) {
    if !wire_rule_910(item) {
      return false
    }
  }
  if fields.get("workspaceId") is Some(item) {
    if !wire_rule_7(item) {
      return false
    }
  }
  if fields.get("consentRefs") is Some(item) {
    if !wire_rule_912(item) {
      return false
    }
  }
  if fields.get("runners") is Some(item) {
    if !wire_rule_912(item) {
      return false
    }
  }
  if fields.get("durability") is Some(item) {
    if !wire_rule_17(item) {
      return false
    }
  }
  if fields.get("movementPolicyRef") is Some(item) {
    if !wire_rule_7(item) {
      return false
    }
  }
  if fields.get("cloudConnectionRef") is Some(item) {
    if !wire_rule_7(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_918(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "actql-client-host/0.1") {
    return false
  }
  true
}

///|
fn wire_rule_925(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  for item in items {
    if !wire_rule_7(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_928(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) ||
    number != number.floor() ||
    number < -9007199254740991.0 ||
    number > 9007199254740991.0 {
    return false
  }
  if number < 1.0 {
    return false
  }
  true
}

///|
fn wire_rule_927(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "maxReadWireBytes" ||
      key == "maxRowWireBytes" ||
      key == "maxRowRetainedValueBytes" ||
      key == "maxRetainedValueBytes" ||
      key == "maxRows" ||
      key == "maxBatchRows" ||
      key == "maxBatchRetainedValueBytes") {
      return false
    }
  }
  if !fields.contains("maxReadWireBytes") {
    return false
  }
  if !fields.contains("maxRowWireBytes") {
    return false
  }
  if !fields.contains("maxRowRetainedValueBytes") {
    return false
  }
  if !fields.contains("maxRetainedValueBytes") {
    return false
  }
  if !fields.contains("maxRows") {
    return false
  }
  if !fields.contains("maxBatchRows") {
    return false
  }
  if !fields.contains("maxBatchRetainedValueBytes") {
    return false
  }
  if fields.get("maxReadWireBytes") is Some(item) {
    if !wire_rule_928(item) {
      return false
    }
  }
  if fields.get("maxRowWireBytes") is Some(item) {
    if !wire_rule_928(item) {
      return false
    }
  }
  if fields.get("maxRowRetainedValueBytes") is Some(item) {
    if !wire_rule_928(item) {
      return false
    }
  }
  if fields.get("maxRetainedValueBytes") is Some(item) {
    if !wire_rule_928(item) {
      return false
    }
  }
  if fields.get("maxRows") is Some(item) {
    if !wire_rule_928(item) {
      return false
    }
  }
  if fields.get("maxBatchRows") is Some(item) {
    if !wire_rule_928(item) {
      return false
    }
  }
  if fields.get("maxBatchRetainedValueBytes") is Some(item) {
    if !wire_rule_928(item) {
      return false
    }
  }
  true
}

///|
fn wire_profile_shape(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "version" ||
      key == "mode" ||
      key == "owner" ||
      key == "durability" ||
      key == "submissionEpoch" ||
      key == "scopeRef" ||
      key == "workspaceId" ||
      key == "capabilities" ||
      key == "limits") {
      return false
    }
  }
  if !fields.contains("version") {
    return false
  }
  if !fields.contains("mode") {
    return false
  }
  if !fields.contains("owner") {
    return false
  }
  if !fields.contains("durability") {
    return false
  }
  if !fields.contains("scopeRef") {
    return false
  }
  if !fields.contains("capabilities") {
    return false
  }
  if !fields.contains("limits") {
    return false
  }
  if fields.get("version") is Some(item) {
    if !wire_rule_918(item) {
      return false
    }
  }
  if fields.get("mode") is Some(item) {
    if !wire_rule_909(item) {
      return false
    }
  }
  if fields.get("owner") is Some(item) {
    if !wire_rule_910(item) {
      return false
    }
  }
  if fields.get("durability") is Some(item) {
    if !wire_rule_17(item) {
      return false
    }
  }
  if fields.get("submissionEpoch") is Some(item) {
    if !wire_submission_epoch_shape(item) {
      return false
    }
  }
  if fields.get("scopeRef") is Some(item) {
    if !wire_rule_7(item) {
      return false
    }
  }
  if fields.get("workspaceId") is Some(item) {
    if !wire_rule_7(item) {
      return false
    }
  }
  if fields.get("capabilities") is Some(item) {
    if !wire_rule_925(item) {
      return false
    }
  }
  if fields.get("limits") is Some(item) {
    if !wire_rule_927(item) {
      return false
    }
  }
  true
}

///|
fn wire_admission_shape(value : Json) -> Bool {
  wire_rule_12(value)
}

///|
fn wire_run_ref_shape(value : Json) -> Bool {
  wire_rule_13(value)
}

///|
fn wire_rule_935(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "found") {
    return false
  }
  true
}

///|
fn wire_lookup_found_shape(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "kind" ||
      key == "requestId" ||
      key == "ref" ||
      key == "durability" ||
      key == "lookupExpiresAt") {
      return false
    }
  }
  if !fields.contains("kind") {
    return false
  }
  if !fields.contains("requestId") {
    return false
  }
  if !fields.contains("ref") {
    return false
  }
  if !fields.contains("durability") {
    return false
  }
  if !fields.contains("lookupExpiresAt") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_935(item) {
      return false
    }
  }
  if fields.get("requestId") is Some(item) {
    if !wire_rule_7(item) {
      return false
    }
  }
  if fields.get("ref") is Some(item) {
    if !wire_rule_13(item) {
      return false
    }
  }
  if fields.get("durability") is Some(item) {
    if !wire_rule_17(item) {
      return false
    }
  }
  if fields.get("lookupExpiresAt") is Some(item) {
    if !wire_rule_7(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_940(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "not_found") {
    return false
  }
  true
}

///|
fn wire_lookup_not_found_shape(value : Json) -> Bool {
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
    if !wire_rule_940(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_941(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "unknown") {
    return false
  }
  true
}

///|
fn wire_lookup_unknown_shape(value : Json) -> Bool {
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
    if !wire_rule_941(item) {
      return false
    }
  }
  if fields.get("reason") is Some(item) {
    if !wire_rule_7(item) {
      return false
    }
  }
  true
}

///|
fn wire_held_shape(value : Json) -> Bool {
  wire_rule_26(value)
}

///|
fn wire_rule_947(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !wire_finite_number(number) ||
    number != number.floor() ||
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
fn wire_cancellation_ref_shape(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "namespaceId" ||
      key == "authorityScopeCid" ||
      key == "runDefinitionCid" ||
      key == "cancelId" ||
      key == "expectedRevision") {
      return false
    }
  }
  if !fields.contains("namespaceId") {
    return false
  }
  if !fields.contains("authorityScopeCid") {
    return false
  }
  if !fields.contains("runDefinitionCid") {
    return false
  }
  if !fields.contains("cancelId") {
    return false
  }
  if !fields.contains("expectedRevision") {
    return false
  }
  if fields.get("namespaceId") is Some(item) {
    if !wire_rule_7(item) {
      return false
    }
  }
  if fields.get("authorityScopeCid") is Some(item) {
    if !wire_rule_1(item) {
      return false
    }
  }
  if fields.get("runDefinitionCid") is Some(item) {
    if !wire_rule_1(item) {
      return false
    }
  }
  if fields.get("cancelId") is Some(item) {
    if !wire_rule_7(item) {
      return false
    }
  }
  if fields.get("expectedRevision") is Some(item) {
    if !wire_rule_947(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_949(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "accepted" ||
    text == "already_requested" ||
    text == "already_terminal") {
    return false
  }
  true
}

///|
fn wire_cancellation_shape(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "ref" ||
      key == "kind" ||
      key == "revision" ||
      key == "cancelRef") {
      return false
    }
  }
  if !fields.contains("ref") {
    return false
  }
  if !fields.contains("kind") {
    return false
  }
  if !fields.contains("revision") {
    return false
  }
  if !fields.contains("cancelRef") {
    return false
  }
  if fields.get("ref") is Some(item) {
    if !wire_rule_13(item) {
      return false
    }
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_949(item) {
      return false
    }
  }
  if fields.get("revision") is Some(item) {
    if !wire_rule_947(item) {
      return false
    }
  }
  if fields.get("cancelRef") is Some(item) {
    if !wire_cancellation_ref_shape(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_952(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "kind" || key == "cancellation") {
      return false
    }
  }
  if !fields.contains("kind") {
    return false
  }
  if !fields.contains("cancellation") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_935(item) {
      return false
    }
  }
  if fields.get("cancellation") is Some(item) {
    if !wire_cancellation_shape(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_955(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "kind" || key == "cancelRef") {
      return false
    }
  }
  if !fields.contains("kind") {
    return false
  }
  if !fields.contains("cancelRef") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_941(item) {
      return false
    }
  }
  if fields.get("cancelRef") is Some(item) {
    if !wire_cancellation_ref_shape(item) {
      return false
    }
  }
  true
}

///|
fn wire_cancellation_lookup_shape(value : Json) -> Bool {
  if [wire_rule_952(value), wire_rule_955(value)].filter(fn(ok) { ok }).length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_rule_958(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "submit" || text == "cancel") {
    return false
  }
  true
}

///|
fn wire_operation_attempt_ref_shape(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "operation" || key == "attemptId") {
      return false
    }
  }
  if !fields.contains("operation") {
    return false
  }
  if !fields.contains("attemptId") {
    return false
  }
  if fields.get("operation") is Some(item) {
    if !wire_rule_958(item) {
      return false
    }
  }
  if fields.get("attemptId") is Some(item) {
    if !wire_rule_7(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_961(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "accepted") {
    return false
  }
  true
}

///|
fn wire_rule_963(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "cancel") {
    return false
  }
  true
}

///|
fn wire_rule_962(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "operation" || key == "attemptId") {
      return false
    }
  }
  if !fields.contains("operation") {
    return false
  }
  if !fields.contains("attemptId") {
    return false
  }
  if fields.get("operation") is Some(item) {
    if !wire_rule_963(item) {
      return false
    }
  }
  if fields.get("attemptId") is Some(item) {
    if !wire_rule_7(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_965(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "ref" ||
      key == "kind" ||
      key == "revision" ||
      key == "cancelRef") {
      return false
    }
  }
  if !fields.contains("ref") {
    return false
  }
  if !fields.contains("kind") {
    return false
  }
  if !fields.contains("revision") {
    return false
  }
  if !fields.contains("cancelRef") {
    return false
  }
  if fields.get("ref") is Some(item) {
    if !wire_rule_13(item) {
      return false
    }
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_961(item) {
      return false
    }
  }
  if fields.get("revision") is Some(item) {
    if !wire_rule_947(item) {
      return false
    }
  }
  if fields.get("cancelRef") is Some(item) {
    if !wire_cancellation_ref_shape(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_960(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "kind" || key == "attemptRef" || key == "cancellation") {
      return false
    }
  }
  if !fields.contains("kind") {
    return false
  }
  if !fields.contains("attemptRef") {
    return false
  }
  if !fields.contains("cancellation") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_961(item) {
      return false
    }
  }
  if fields.get("attemptRef") is Some(item) {
    if !wire_rule_962(item) {
      return false
    }
  }
  if fields.get("cancellation") is Some(item) {
    if !wire_rule_965(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_975(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "already_requested" || text == "already_terminal") {
    return false
  }
  true
}

///|
fn wire_rule_973(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "ref" ||
      key == "kind" ||
      key == "revision" ||
      key == "cancelRef") {
      return false
    }
  }
  if !fields.contains("ref") {
    return false
  }
  if !fields.contains("kind") {
    return false
  }
  if !fields.contains("revision") {
    return false
  }
  if !fields.contains("cancelRef") {
    return false
  }
  if fields.get("ref") is Some(item) {
    if !wire_rule_13(item) {
      return false
    }
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_975(item) {
      return false
    }
  }
  if fields.get("revision") is Some(item) {
    if !wire_rule_947(item) {
      return false
    }
  }
  if fields.get("cancelRef") is Some(item) {
    if !wire_cancellation_ref_shape(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_970(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "kind" || key == "attemptRef" || key == "cancellation") {
      return false
    }
  }
  if !fields.contains("kind") {
    return false
  }
  if !fields.contains("attemptRef") {
    return false
  }
  if !fields.contains("cancellation") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_856(item) {
      return false
    }
  }
  if fields.get("attemptRef") is Some(item) {
    if !wire_rule_962(item) {
      return false
    }
  }
  if fields.get("cancellation") is Some(item) {
    if !wire_rule_973(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_982(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "authorization" || text == "admission_capacity") {
    return false
  }
  true
}

///|
fn wire_rule_978(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "kind" ||
      key == "attemptRef" ||
      key == "guarantee" ||
      key == "reason" ||
      key == "cancelRef") {
      return false
    }
  }
  if !fields.contains("kind") {
    return false
  }
  if !fields.contains("attemptRef") {
    return false
  }
  if !fields.contains("guarantee") {
    return false
  }
  if !fields.contains("reason") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_867(item) {
      return false
    }
  }
  if fields.get("attemptRef") is Some(item) {
    if !wire_rule_962(item) {
      return false
    }
  }
  if fields.get("guarantee") is Some(item) {
    if !wire_rule_869(item) {
      return false
    }
  }
  if fields.get("reason") is Some(item) {
    if !wire_rule_982(item) {
      return false
    }
  }
  if fields.get("cancelRef") is Some(item) {
    if !wire_cancellation_ref_shape(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_987(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "intent" || text == "control_revision") {
    return false
  }
  true
}

///|
fn wire_rule_984(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "kind" ||
      key == "attemptRef" ||
      key == "reason" ||
      key == "cancelRef") {
      return false
    }
  }
  if !fields.contains("kind") {
    return false
  }
  if !fields.contains("attemptRef") {
    return false
  }
  if !fields.contains("reason") {
    return false
  }
  if !fields.contains("cancelRef") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_879(item) {
      return false
    }
  }
  if fields.get("attemptRef") is Some(item) {
    if !wire_rule_962(item) {
      return false
    }
  }
  if fields.get("reason") is Some(item) {
    if !wire_rule_987(item) {
      return false
    }
  }
  if fields.get("cancelRef") is Some(item) {
    if !wire_cancellation_ref_shape(item) {
      return false
    }
  }
  true
}

///|
fn wire_cancellation_attempt_shape(value : Json) -> Bool {
  if [
      wire_rule_960(value),
      wire_rule_970(value),
      wire_rule_978(value),
      wire_rule_984(value),
    ]
    .filter(fn(ok) { ok })
    .length() !=
    1 {
    return false
  }
  true
}

///|
enum WireResponseIssue {
  InvalidShape
  ConnectionMismatch
  RequestedValueUnavailable
}

///|
fn wire_profile_issue(value : Json, selected : Json) -> WireResponseIssue? {
  if !wire_connection_shape(selected) || !wire_profile_shape(value) {
    return Some(InvalidShape)
  }
  guard value is Object(fields) else { return Some(InvalidShape) }
  guard selected is Object(connection) else { return Some(InvalidShape) }
  if fields.get("mode") != connection.get("mode") {
    return Some(ConnectionMismatch)
  }
  if fields.get("owner") != connection.get("owner") {
    return Some(ConnectionMismatch)
  }
  if fields.get("workspaceId") != connection.get("workspaceId") {
    return Some(ConnectionMismatch)
  }
  if connection.get("durability") == Some(Json::string("durable")) &&
    fields.get("durability") != Some(Json::string("durable")) {
    return Some(RequestedValueUnavailable)
  }
  None
}

///|
fn wire_admission_issue(value : Json, selected : Json) -> WireResponseIssue? {
  if !wire_connection_shape(selected) || !wire_admission_shape(value) {
    return Some(InvalidShape)
  }
  guard value is Object(fields) else { return Some(InvalidShape) }
  guard selected is Object(connection) else { return Some(InvalidShape) }
  if connection.get("durability") == Some(Json::string("durable")) &&
    fields.get("durability") != Some(Json::string("durable")) {
    return Some(RequestedValueUnavailable)
  }
  None
}

///|
fn wire_admission(value : Json, selected : Json) -> Bool {
  wire_admission_issue(value, selected) is None
}

///|
fn wire_held(value : Json, expected : String) -> Bool {
  if !wire_rule_7(Json::string(expected)) {
    return false
  }
  guard value is Object(fields) else { return false }
  wire_held_shape(value) &&
  fields.get("requestId") == Some(Json::string(expected))
}

///|
fn wire_request_lookup(value : Json, expected : String) -> Bool {
  if !wire_rule_7(Json::string(expected)) {
    return false
  }
  guard value is Object(fields) else { return false }
  (
    wire_lookup_found_shape(value) &&
    fields.get("requestId") == Some(Json::string(expected))
  ) ||
  wire_lookup_not_found_shape(value) ||
  wire_lookup_unknown_shape(value) ||
  (
    wire_held_shape(value) &&
    fields.get("requestId") == Some(Json::string(expected))
  )
}

///|
fn wire_check_report_contract(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  let report = match fields.get("report") {
    Some(report) => Some(report)
    None => fields.get("partial_report")
  }
  guard report is Some(report) else { return true }
  guard report is Object(report_fields) &&
    report_fields.get("inputs") is Some(Array(inputs)) &&
    report_fields.get("reasons") is Some(Array(reasons)) &&
    report_fields.get("requirements") is Some(Array(requirements)) &&
    report_fields.get("coverage") is Some(Object(coverage)) &&
    coverage.get("limits") is Some(Array(limits)) else {
    return false
  }
  let documents : Map[String, Json] = Map([])
  for input in inputs {
    guard input is Object(fields) &&
      fields.get("document_id") is Some(String(id)) else {
      return false
    }
    documents[id] = input
  }
  let occurrences = reasons.copy()
  for reason in requirements {
    occurrences.push(reason)
  }
  for reason in limits {
    occurrences.push(reason)
  }
  if documents.length() != inputs.length() {
    return false
  }
  if documents.get("program") is Some(program) {
    guard program is Object(fields) &&
      fields.get("kind") == Some(Json::string("structured")) &&
      !documents.contains("source") &&
      !documents.contains("parameter_declarations") else {
      return false
    }
  } else {
    guard documents.get("source") is Some(Object(source)) &&
      source.get("kind") == Some(Json::string("text")) else {
      return false
    }
  }
  for id, input in documents {
    guard input is Object(fields) else { return false }
    if id != "source" && fields.get("kind") != Some(Json::string("structured")) {
      return false
    }
  }
  for reason in occurrences {
    guard reason is Object(fields) else { return false }
    if fields.get("location") is Some(location) {
      guard location is Object(location_fields) &&
        location_fields.get("document_id") is Some(String(id)) &&
        documents.get(id) is Some(Object(input)) &&
        input.get("revision") == location_fields.get("revision") &&
        input.get("kind") == location_fields.get("kind") else {
        return false
      }
      if location_fields.get("kind") == Some(Json::string("text")) {
        guard location_fields.get("start_byte") is Some(Number(start, ..)) &&
          location_fields.get("end_byte") is Some(Number(end, ..)) &&
          input.get("byte_length") is Some(Number(bytes, ..)) else {
          return false
        }
        if start > end || end > bytes {
          return false
        }
      }
    }
  }
  for reason in occurrences {
    guard reason is Object(fields) else { return false }
    if fields.get("fixes") is Some(fixes) {
      guard fixes is Array(fixes) else { return false }
      for fix in fixes {
        guard fix is Object(fix_fields) &&
          fix_fields.get("target") is Some(Object(target)) &&
          target.get("document_id") is Some(String(id)) &&
          documents.get(id) is Some(Object(input)) &&
          input.get("kind") == Some(Json::string("text")) &&
          input.get("revision") == target.get("revision") &&
          input.get("byte_length") is Some(Number(bytes, ..)) &&
          fix_fields.get("edits") is Some(Array(edits)) else {
          return false
        }
        for edit in edits {
          guard edit is Object(edit_fields) &&
            edit_fields.get("start_byte") is Some(Number(start, ..)) &&
            edit_fields.get("end_byte") is Some(Number(end, ..)) else {
            return false
          }
          if start != bytes || end != bytes {
            return false
          }
        }
      }
    }
  }
  true
}
