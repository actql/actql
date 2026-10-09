// Generated from spec/contracts/actql-client-host.json.
// Run: node scripts/generate-client-host-wire.mjs --write

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
  if number != number.floor() ||
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
  if number != number.floor() ||
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
  if number != number.floor() ||
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
  if !(text == "verified") {
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
fn wire_rule_76(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "bound_input") {
    return false
  }
  true
}

///|
fn wire_rule_75(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("kind") is Some(item) {
    if !wire_rule_76(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_74(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scope") is Some(item) {
    if !wire_rule_75(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_79(_value : Json) -> Bool {
  true
}

///|
fn wire_rule_78(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  if items.length() > 0 {
    return false
  }
  for item in items {
    if !wire_rule_79(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_77(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("requirements") is Some(item) {
    if !wire_rule_78(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_73(value : Json) -> Bool {
  if wire_rule_74(value) && !wire_rule_77(value) {
    return false
  }
  true
}

///|
fn wire_rule_83(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "template_only") {
    return false
  }
  true
}

///|
fn wire_rule_82(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("kind") is Some(item) {
    if !wire_rule_83(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_81(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scope") is Some(item) {
    if !wire_rule_82(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_88(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "parameter_value_required") {
    return false
  }
  true
}

///|
fn wire_rule_87(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_88(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_86(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  for item in items {
    if !wire_rule_87(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_85(value : Json) -> Bool {
  if value is Array(_) {
    return wire_rule_86(value)
  }
  true
}

///|
fn wire_rule_84(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("requirements") is Some(item) {
    if !wire_rule_85(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_80(value : Json) -> Bool {
  if wire_rule_81(value) && !wire_rule_84(value) {
    return false
  }
  true
}

///|
fn wire_rule_89(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("omissions") {
    return false
  }
  true
}

///|
fn wire_rule_91(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("limits") is Some(item) {
    if !wire_rule_78(item) {
      return false
    }
  }
  if fields.get("unresolved") is Some(item) {
    if !wire_rule_78(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_72(value : Json) -> Bool {
  if !wire_rule_73(value) {
    return false
  }
  if !wire_rule_80(value) {
    return false
  }
  if wire_rule_89(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  if fields.get("reasons") is Some(item) {
    if !wire_rule_78(item) {
      return false
    }
  }
  if fields.get("coverage") is Some(item) {
    if !wire_rule_91(item) {
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
fn wire_rule_96(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "invalid") {
    return false
  }
  true
}

///|
fn wire_rule_95(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("verdict") is Some(item) {
    if !wire_rule_96(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_98(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  if items.length() < 1 {
    return false
  }
  for item in items {
    if !wire_rule_79(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_97(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("reasons") is Some(item) {
    if !wire_rule_98(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_94(value : Json) -> Bool {
  if wire_rule_95(value) && !wire_rule_97(value) {
    return false
  }
  true
}

///|
fn wire_rule_102(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "undetermined") {
    return false
  }
  true
}

///|
fn wire_rule_101(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("verdict") is Some(item) {
    if !wire_rule_102(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_105(value : Json) -> Bool {
  if wire_rule_91(value) {
    return false
  }
  true
}

///|
fn wire_rule_103(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("reasons") is Some(item) {
    if !wire_rule_78(item) {
      return false
    }
  }
  if fields.get("coverage") is Some(item) {
    if !wire_rule_105(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_100(value : Json) -> Bool {
  if wire_rule_101(value) && !wire_rule_103(value) {
    return false
  }
  true
}

///|
fn wire_rule_107(value : Json) -> Bool {
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
fn wire_rule_109(value : Json) -> Bool {
  if !(value is True || value is False) {
    return false
  }
  if !(value is True) {
    return false
  }
  true
}

///|
fn wire_rule_108(value : Json) -> Bool {
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
    if !wire_rule_109(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_112(value : Json) -> Bool {
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
fn wire_rule_113(value : Json) -> Bool {
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
fn wire_rule_114(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "text" || text == "structured") {
    return false
  }
  true
}

///|
fn wire_rule_115(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if number != number.floor() ||
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
fn wire_rule_111(value : Json) -> Bool {
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
    if !wire_rule_112(item) {
      return false
    }
  }
  if fields.get("revision") is Some(item) {
    if !wire_rule_113(item) {
      return false
    }
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_114(item) {
      return false
    }
  }
  if fields.get("byte_length") is Some(item) {
    if !wire_rule_115(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_110(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  if items.length() < 1 {
    return false
  }
  if items.length() > 3 {
    return false
  }
  for item in items {
    if !wire_rule_111(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_120(value : Json) -> Bool {
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
fn wire_rule_119(value : Json) -> Bool {
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
    if !wire_rule_120(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_122(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "implementation_limit" || text == "analysis_budget_exhausted") {
    return false
  }
  true
}

///|
fn wire_rule_124(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "structured") {
    return false
  }
  true
}

///|
fn wire_rule_125(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "program") {
    return false
  }
  true
}

///|
fn wire_rule_127(value : Json) -> Bool {
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
fn wire_rule_123(value : Json) -> Bool {
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
    if !wire_rule_124(item) {
      return false
    }
  }
  if fields.get("document_id") is Some(item) {
    if !wire_rule_125(item) {
      return false
    }
  }
  if fields.get("revision") is Some(item) {
    if !wire_rule_113(item) {
      return false
    }
  }
  if fields.get("pointer") is Some(item) {
    if !wire_rule_127(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_121(value : Json) -> Bool {
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
    if !wire_rule_122(item) {
      return false
    }
  }
  if fields.get("location") is Some(item) {
    if !wire_rule_123(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_129(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "implementation_limit") {
    return false
  }
  true
}

///|
fn wire_rule_131(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "function_lowering_unresolved") {
    return false
  }
  true
}

///|
fn wire_rule_130(value : Json) -> Bool {
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
    if !wire_rule_131(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_133(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "text") {
    return false
  }
  true
}

///|
fn wire_rule_134(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "source") {
    return false
  }
  true
}

///|
fn wire_rule_136(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if number != number.floor() ||
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
fn wire_rule_138(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "exact" || text == "approximate") {
    return false
  }
  true
}

///|
fn wire_rule_132(value : Json) -> Bool {
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
    if !wire_rule_133(item) {
      return false
    }
  }
  if fields.get("document_id") is Some(item) {
    if !wire_rule_134(item) {
      return false
    }
  }
  if fields.get("revision") is Some(item) {
    if !wire_rule_113(item) {
      return false
    }
  }
  if fields.get("start_byte") is Some(item) {
    if !wire_rule_136(item) {
      return false
    }
  }
  if fields.get("end_byte") is Some(item) {
    if !wire_rule_136(item) {
      return false
    }
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_138(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_128(value : Json) -> Bool {
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
    if !wire_rule_129(item) {
      return false
    }
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_130(item) {
      return false
    }
  }
  if fields.get("location") is Some(item) {
    if !wire_rule_132(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_118(value : Json) -> Bool {
  if [wire_rule_119(value), wire_rule_121(value), wire_rule_128(value)]
    .filter(fn(ok) { ok })
    .length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_rule_117(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  for item in items {
    if !wire_rule_118(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_142(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "unresolved_protected") {
    return false
  }
  true
}

///|
fn wire_rule_140(value : Json) -> Bool {
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
    if !wire_rule_120(item) {
      return false
    }
  }
  if fields.get("reason") is Some(item) {
    if !wire_rule_142(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_139(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  for item in items {
    if !wire_rule_140(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_116(value : Json) -> Bool {
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
    if !wire_rule_117(item) {
      return false
    }
  }
  if fields.get("unresolved") is Some(item) {
    if !wire_rule_139(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_147(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "program_structure_invalid") {
    return false
  }
  true
}

///|
fn wire_rule_146(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_147(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_149(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("fixes") {
    return false
  }
  true
}

///|
fn wire_rule_151(value : Json) -> Bool {
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
fn wire_rule_150(value : Json) -> Bool {
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
    if !wire_rule_151(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_152(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("kind") is Some(item) {
    if !wire_rule_124(item) {
      return false
    }
  }
  if fields.get("document_id") is Some(item) {
    if !wire_rule_125(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_148(value : Json) -> Bool {
  if wire_rule_149(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  if !fields.contains("facts") {
    return false
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_150(item) {
      return false
    }
  }
  if fields.get("location") is Some(item) {
    if !wire_rule_152(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_145(value : Json) -> Bool {
  if wire_rule_146(value) && !wire_rule_148(value) {
    return false
  }
  true
}

///|
fn wire_rule_157(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "numeric_reduction_profile_required") {
    return false
  }
  true
}

///|
fn wire_rule_156(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_157(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_160(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("location") {
    return false
  }
  true
}

///|
fn wire_rule_159(value : Json) -> Bool {
  if wire_rule_160(value) {
    return false
  }
  true
}

///|
fn wire_rule_161(value : Json) -> Bool {
  if wire_rule_149(value) {
    return false
  }
  true
}

///|
fn wire_rule_164(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text ==
    "sha256:d771391b2e4f3e52a3cf48810571a09c6c272df64fbb77c245dfabcf456be5df") {
    return false
  }
  true
}

///|
fn wire_rule_165(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "checking_context_owner") {
    return false
  }
  true
}

///|
fn wire_rule_166(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "checking") {
    return false
  }
  true
}

///|
fn wire_rule_163(value : Json) -> Bool {
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
    if !wire_rule_164(item) {
      return false
    }
  }
  if fields.get("supplier") is Some(item) {
    if !wire_rule_165(item) {
      return false
    }
  }
  if fields.get("stage") is Some(item) {
    if !wire_rule_166(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_158(value : Json) -> Bool {
  if !wire_rule_159(value) {
    return false
  }
  if !wire_rule_161(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  if !fields.contains("facts") {
    return false
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_163(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_155(value : Json) -> Bool {
  if wire_rule_156(value) && !wire_rule_158(value) {
    return false
  }
  true
}

///|
fn wire_rule_169(value : Json) -> Bool {
  if wire_rule_157(value) {
    return false
  }
  true
}

///|
fn wire_rule_168(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_169(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_173(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("profile_cid") {
    return false
  }
  true
}

///|
fn wire_rule_172(value : Json) -> Bool {
  if wire_rule_173(value) {
    return false
  }
  true
}

///|
fn wire_rule_171(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("facts") is Some(item) {
    if !wire_rule_172(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_167(value : Json) -> Bool {
  if wire_rule_168(value) && !wire_rule_171(value) {
    return false
  }
  true
}

///|
fn wire_rule_176(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "host_capacity_policy_required") {
    return false
  }
  true
}

///|
fn wire_rule_175(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_176(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_181(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text ==
    "sha256:5de69acac624586723a7efad500d0caf13c21ad2ed6e2252df0aaacf32dfc164") {
    return false
  }
  true
}

///|
fn wire_rule_182(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text ==
    "sha256:f23dbd7096c73975276d79dc163c8b3ae7dbae662ade242a3f1789cf07b854f3") {
    return false
  }
  true
}

///|
fn wire_rule_183(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "/schema") {
    return false
  }
  true
}

///|
fn wire_rule_180(value : Json) -> Bool {
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
    if !wire_rule_181(item) {
      return false
    }
  }
  if fields.get("schema_cid") is Some(item) {
    if !wire_rule_182(item) {
      return false
    }
  }
  if fields.get("schema_pointer") is Some(item) {
    if !wire_rule_183(item) {
      return false
    }
  }
  if fields.get("supplier") is Some(item) {
    if !wire_rule_165(item) {
      return false
    }
  }
  if fields.get("stage") is Some(item) {
    if !wire_rule_166(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_177(value : Json) -> Bool {
  if !wire_rule_159(value) {
    return false
  }
  if !wire_rule_161(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  if !fields.contains("facts") {
    return false
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_180(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_174(value : Json) -> Bool {
  if wire_rule_175(value) && !wire_rule_177(value) {
    return false
  }
  true
}

///|
fn wire_rule_188(value : Json) -> Bool {
  if wire_rule_176(value) {
    return false
  }
  true
}

///|
fn wire_rule_187(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_188(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_192(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("schema_pointer") {
    return false
  }
  true
}

///|
fn wire_rule_191(value : Json) -> Bool {
  if wire_rule_192(value) {
    return false
  }
  true
}

///|
fn wire_rule_190(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("facts") is Some(item) {
    if !wire_rule_191(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_186(value : Json) -> Bool {
  if wire_rule_187(value) && !wire_rule_190(value) {
    return false
  }
  true
}

///|
fn wire_rule_194(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_129(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_197(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("issue") {
    return false
  }
  if fields.get("issue") is Some(item) {
    if !wire_rule_131(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_201(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "source" || text == "program") {
    return false
  }
  true
}

///|
fn wire_rule_199(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("kind") is Some(item) {
    if !wire_rule_114(item) {
      return false
    }
  }
  if fields.get("document_id") is Some(item) {
    if !wire_rule_201(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_196(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("facts") is Some(item) {
    if !wire_rule_197(item) {
      return false
    }
  }
  if fields.get("location") is Some(item) {
    if !wire_rule_199(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_193(value : Json) -> Bool {
  if wire_rule_194(value) && !wire_rule_196(value) {
    return false
  }
  true
}

///|
fn wire_rule_204(value : Json) -> Bool {
  if wire_rule_88(value) {
    return false
  }
  true
}

///|
fn wire_rule_203(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_204(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_208(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("admission") {
    return false
  }
  true
}

///|
fn wire_rule_207(value : Json) -> Bool {
  if wire_rule_208(value) {
    return false
  }
  true
}

///|
fn wire_rule_206(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("facts") is Some(item) {
    if !wire_rule_207(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_202(value : Json) -> Bool {
  if wire_rule_203(value) && !wire_rule_206(value) {
    return false
  }
  true
}

///|
fn wire_rule_212(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "query_lexical_invalid") {
    return false
  }
  true
}

///|
fn wire_rule_214(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "unterminated_comment") {
    return false
  }
  true
}

///|
fn wire_rule_213(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("issue") is Some(item) {
    if !wire_rule_214(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_217(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "exact") {
    return false
  }
  true
}

///|
fn wire_rule_215(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("kind") is Some(item) {
    if !wire_rule_133(item) {
      return false
    }
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_217(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_211(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("facts") {
    return false
  }
  if !fields.contains("location") {
    return false
  }
  if fields.get("code") is Some(item) {
    if !wire_rule_212(item) {
      return false
    }
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_213(item) {
      return false
    }
  }
  if fields.get("location") is Some(item) {
    if !wire_rule_215(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_209(value : Json) -> Bool {
  if wire_rule_149(value) && !wire_rule_211(value) {
    return false
  }
  true
}

///|
fn wire_rule_220(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "query_syntax_invalid" || text == "parameter_undeclared") {
    return false
  }
  true
}

///|
fn wire_rule_219(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_220(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_222(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("kind") is Some(item) {
    if !wire_rule_133(item) {
      return false
    }
  }
  if fields.get("document_id") is Some(item) {
    if !wire_rule_134(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_221(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("location") is Some(item) {
    if !wire_rule_222(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_218(value : Json) -> Bool {
  if wire_rule_219(value) && !wire_rule_221(value) {
    return false
  }
  true
}

///|
fn wire_rule_227(value : Json) -> Bool {
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
  guard value is String(text) else { return false }
  if !(text == "parameters") {
    return false
  }
  true
}

///|
fn wire_rule_229(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("kind") is Some(item) {
    if !wire_rule_124(item) {
      return false
    }
  }
  if fields.get("document_id") is Some(item) {
    if !wire_rule_231(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_228(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("location") is Some(item) {
    if !wire_rule_229(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_225(value : Json) -> Bool {
  if wire_rule_226(value) && !wire_rule_228(value) {
    return false
  }
  true
}

///|
fn wire_rule_234(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "parameter_declarations_invalid" ||
    text == "parameter_value_required") {
    return false
  }
  true
}

///|
fn wire_rule_233(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_234(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_238(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "parameter_declarations" || text == "program") {
    return false
  }
  true
}

///|
fn wire_rule_236(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("kind") is Some(item) {
    if !wire_rule_124(item) {
      return false
    }
  }
  if fields.get("document_id") is Some(item) {
    if !wire_rule_238(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_235(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("location") is Some(item) {
    if !wire_rule_236(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_232(value : Json) -> Bool {
  if wire_rule_233(value) && !wire_rule_235(value) {
    return false
  }
  true
}

///|
fn wire_rule_241(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "supplied_value_type_mismatch") {
    return false
  }
  true
}

///|
fn wire_rule_240(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_241(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_243(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("actual_type") {
    return false
  }
  true
}

///|
fn wire_rule_242(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("facts") {
    return false
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_243(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_239(value : Json) -> Bool {
  if wire_rule_240(value) && !wire_rule_242(value) {
    return false
  }
  true
}

///|
fn wire_rule_246(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "parameter_default_type_mismatch") {
    return false
  }
  true
}

///|
fn wire_rule_245(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_246(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_247(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("facts") {
    return false
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_243(item) {
      return false
    }
  }
  if fields.get("location") is Some(item) {
    if !wire_rule_236(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_244(value : Json) -> Bool {
  if wire_rule_245(value) && !wire_rule_247(value) {
    return false
  }
  true
}

///|
fn wire_rule_252(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "parameter_undeclared") {
    return false
  }
  true
}

///|
fn wire_rule_251(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_252(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_256(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("expected_type") {
    return false
  }
  true
}

///|
fn wire_rule_255(value : Json) -> Bool {
  if wire_rule_256(value) {
    return false
  }
  true
}

///|
fn wire_rule_258(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("constraint") {
    return false
  }
  true
}

///|
fn wire_rule_257(value : Json) -> Bool {
  if wire_rule_258(value) {
    return false
  }
  true
}

///|
fn wire_rule_260(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("domain") {
    return false
  }
  true
}

///|
fn wire_rule_259(value : Json) -> Bool {
  if wire_rule_260(value) {
    return false
  }
  true
}

///|
fn wire_rule_254(value : Json) -> Bool {
  if !wire_rule_255(value) {
    return false
  }
  if !wire_rule_257(value) {
    return false
  }
  if !wire_rule_259(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  if !fields.contains("parameter") {
    return false
  }
  true
}

///|
fn wire_rule_253(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("facts") {
    return false
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_254(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_250(value : Json) -> Bool {
  if wire_rule_251(value) && !wire_rule_253(value) {
    return false
  }
  true
}

///|
fn wire_rule_264(value : Json) -> Bool {
  if wire_rule_243(value) {
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
fn wire_rule_263(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("facts") {
    return false
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_264(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_261(value : Json) -> Bool {
  if wire_rule_87(value) && !wire_rule_263(value) {
    return false
  }
  true
}

///|
fn wire_rule_268(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "parameter_unused") {
    return false
  }
  true
}

///|
fn wire_rule_267(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_268(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_271(value : Json) -> Bool {
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
fn wire_rule_270(value : Json) -> Bool {
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
    if !wire_rule_271(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_269(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("facts") {
    return false
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_270(item) {
      return false
    }
  }
  if fields.get("location") is Some(item) {
    if !wire_rule_236(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_266(value : Json) -> Bool {
  if wire_rule_267(value) && !wire_rule_269(value) {
    return false
  }
  true
}

///|
fn wire_rule_275(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "supplied_value_constraint_violation") {
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
fn wire_rule_276(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("facts") {
    return false
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_258(item) {
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
fn wire_rule_280(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "expression_type_mismatch") {
    return false
  }
  true
}

///|
fn wire_rule_279(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_280(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_283(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "number" || text == "boolean" || text == "string") {
    return false
  }
  true
}

///|
fn wire_rule_282(value : Json) -> Bool {
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
    if !wire_rule_283(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_281(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("facts") {
    return false
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_282(item) {
      return false
    }
  }
  if fields.get("location") is Some(item) {
    if !wire_rule_199(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_278(value : Json) -> Bool {
  if wire_rule_279(value) && !wire_rule_281(value) {
    return false
  }
  true
}

///|
fn wire_rule_287(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "operation_parameter_invalid") {
    return false
  }
  true
}

///|
fn wire_rule_286(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_287(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_292(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "parameters" || text == "parameter_declarations") {
    return false
  }
  true
}

///|
fn wire_rule_290(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("kind") is Some(item) {
    if !wire_rule_124(item) {
      return false
    }
  }
  if fields.get("document_id") is Some(item) {
    if !wire_rule_292(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_288(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("facts") {
    return false
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_260(item) {
      return false
    }
  }
  if fields.get("location") is Some(item) {
    if !wire_rule_290(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_285(value : Json) -> Bool {
  if wire_rule_286(value) && !wire_rule_288(value) {
    return false
  }
  true
}

///|
fn wire_rule_295(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "binding_json_invalid") {
    return false
  }
  true
}

///|
fn wire_rule_294(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_295(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_299(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("document") is Some(item) {
    if !wire_rule_231(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_298(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("facts") is Some(item) {
    if !wire_rule_299(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_302(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("document_id") is Some(item) {
    if !wire_rule_231(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_301(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("location") is Some(item) {
    if !wire_rule_302(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_297(value : Json) -> Bool {
  if wire_rule_298(value) && !wire_rule_301(value) {
    return false
  }
  true
}

///|
fn wire_rule_307(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "parameter_declarations") {
    return false
  }
  true
}

///|
fn wire_rule_306(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("document") is Some(item) {
    if !wire_rule_307(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_305(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("facts") is Some(item) {
    if !wire_rule_306(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_309(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("document_id") is Some(item) {
    if !wire_rule_307(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_308(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("location") is Some(item) {
    if !wire_rule_309(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_304(value : Json) -> Bool {
  if wire_rule_305(value) && !wire_rule_308(value) {
    return false
  }
  true
}

///|
fn wire_rule_313(value : Json) -> Bool {
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
fn wire_rule_311(value : Json) -> Bool {
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
    if !wire_rule_292(item) {
      return false
    }
  }
  if fields.get("issue") is Some(item) {
    if !wire_rule_313(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_314(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("kind") is Some(item) {
    if !wire_rule_124(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_296(value : Json) -> Bool {
  if !wire_rule_297(value) {
    return false
  }
  if !wire_rule_304(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  if !fields.contains("facts") {
    return false
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_311(item) {
      return false
    }
  }
  if fields.get("location") is Some(item) {
    if !wire_rule_314(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_293(value : Json) -> Bool {
  if wire_rule_294(value) && !wire_rule_296(value) {
    return false
  }
  true
}

///|
fn wire_rule_317(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_212(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_321(value : Json) -> Bool {
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
fn wire_rule_320(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("issue") {
    return false
  }
  if fields.get("issue") is Some(item) {
    if !wire_rule_321(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_322(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("kind") is Some(item) {
    if !wire_rule_133(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_319(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("facts") {
    return false
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_320(item) {
      return false
    }
  }
  if fields.get("location") is Some(item) {
    if !wire_rule_322(item) {
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
fn wire_rule_326(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "query_expression_invalid") {
    return false
  }
  true
}

///|
fn wire_rule_325(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_326(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_329(value : Json) -> Bool {
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
fn wire_rule_328(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("issue") {
    return false
  }
  if fields.get("issue") is Some(item) {
    if !wire_rule_329(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_327(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("facts") {
    return false
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_328(item) {
      return false
    }
  }
  if fields.get("location") is Some(item) {
    if !wire_rule_199(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_324(value : Json) -> Bool {
  if wire_rule_325(value) && !wire_rule_327(value) {
    return false
  }
  true
}

///|
fn wire_rule_333(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "query_frame_invalid") {
    return false
  }
  true
}

///|
fn wire_rule_332(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_333(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_336(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "invalid_bounds") {
    return false
  }
  true
}

///|
fn wire_rule_335(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("issue") {
    return false
  }
  if fields.get("issue") is Some(item) {
    if !wire_rule_336(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_334(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("facts") {
    return false
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_335(item) {
      return false
    }
  }
  if fields.get("location") is Some(item) {
    if !wire_rule_199(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_331(value : Json) -> Bool {
  if wire_rule_332(value) && !wire_rule_334(value) {
    return false
  }
  true
}

///|
fn wire_rule_340(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "graph_operation_invalid") {
    return false
  }
  true
}

///|
fn wire_rule_339(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_340(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_343(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "components" || text == "subgraph") {
    return false
  }
  true
}

///|
fn wire_rule_344(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "invalid_kind" ||
    text == "invalid_output_rows" ||
    text == "invalid_node_selector") {
    return false
  }
  true
}

///|
fn wire_rule_342(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("operation") {
    return false
  }
  if !fields.contains("issue") {
    return false
  }
  if fields.get("operation") is Some(item) {
    if !wire_rule_343(item) {
      return false
    }
  }
  if fields.get("issue") is Some(item) {
    if !wire_rule_344(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_341(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("facts") {
    return false
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_342(item) {
      return false
    }
  }
  if fields.get("location") is Some(item) {
    if !wire_rule_199(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_338(value : Json) -> Bool {
  if wire_rule_339(value) && !wire_rule_341(value) {
    return false
  }
  true
}

///|
fn wire_rule_348(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "query_alias_absent") {
    return false
  }
  true
}

///|
fn wire_rule_347(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_348(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_355(value : Json) -> Bool {
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
fn wire_rule_356(value : Json) -> Bool {
  if !(value is True || value is False) {
    return false
  }
  true
}

///|
fn wire_rule_354(value : Json) -> Bool {
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
    if !wire_rule_355(item) {
      return false
    }
  }
  if fields.get("quoted") is Some(item) {
    if !wire_rule_356(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_353(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  if items.length() < 1 {
    return false
  }
  if items.length() > 8192 {
    return false
  }
  for item in items {
    if !wire_rule_354(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_351(value : Json) -> Bool {
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
    if !wire_rule_271(item) {
      return false
    }
  }
  if fields.get("reference") is Some(item) {
    if !wire_rule_353(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_349(value : Json) -> Bool {
  if wire_rule_149(value) {
    return false
  }
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
fn wire_rule_346(value : Json) -> Bool {
  if wire_rule_347(value) && !wire_rule_349(value) {
    return false
  }
  true
}

///|
fn wire_rule_361(value : Json) -> Bool {
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
    text == "query_alias_absent") {
    return false
  }
  true
}

///|
fn wire_rule_360(value : Json) -> Bool {
  if wire_rule_361(value) {
    return false
  }
  true
}

///|
fn wire_rule_359(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_360(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_363(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("facts") {
    return false
  }
  true
}

///|
fn wire_rule_362(value : Json) -> Bool {
  if wire_rule_363(value) {
    return false
  }
  true
}

///|
fn wire_rule_358(value : Json) -> Bool {
  if wire_rule_359(value) && !wire_rule_362(value) {
    return false
  }
  true
}

///|
fn wire_rule_366(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "parameter_value_required" ||
    text == "host_capacity_policy_required" ||
    text == "numeric_reduction_profile_required") {
    return false
  }
  true
}

///|
fn wire_rule_365(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_366(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_364(value : Json) -> Bool {
  if wire_rule_365(value) {
    return false
  }
  true
}

///|
fn wire_rule_372(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "program" ||
    text == "parameter_declarations" ||
    text == "parameters") {
    return false
  }
  true
}

///|
fn wire_rule_370(value : Json) -> Bool {
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
    if !wire_rule_124(item) {
      return false
    }
  }
  if fields.get("document_id") is Some(item) {
    if !wire_rule_372(item) {
      return false
    }
  }
  if fields.get("revision") is Some(item) {
    if !wire_rule_113(item) {
      return false
    }
  }
  if fields.get("pointer") is Some(item) {
    if !wire_rule_127(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_368(value : Json) -> Bool {
  if [wire_rule_132(value), wire_rule_370(value)].filter(fn(ok) { ok }).length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_rule_377(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "close_block_comment") {
    return false
  }
  true
}

///|
fn wire_rule_378(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "requires_review") {
    return false
  }
  true
}

///|
fn wire_rule_379(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "syntax_structure") {
    return false
  }
  true
}

///|
fn wire_rule_380(value : Json) -> Bool {
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
    if !wire_rule_134(item) {
      return false
    }
  }
  if fields.get("revision") is Some(item) {
    if !wire_rule_113(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_387(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "*/") {
    return false
  }
  true
}

///|
fn wire_rule_384(value : Json) -> Bool {
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
    if !wire_rule_136(item) {
      return false
    }
  }
  if fields.get("end_byte") is Some(item) {
    if !wire_rule_136(item) {
      return false
    }
  }
  if fields.get("replacement") is Some(item) {
    if !wire_rule_387(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_383(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  if items.length() < 1 {
    return false
  }
  if items.length() > 1 {
    return false
  }
  for item in items {
    if !wire_rule_384(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_376(value : Json) -> Bool {
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
    if !wire_rule_377(item) {
      return false
    }
  }
  if fields.get("applicability") is Some(item) {
    if !wire_rule_378(item) {
      return false
    }
  }
  if fields.get("risk") is Some(item) {
    if !wire_rule_379(item) {
      return false
    }
  }
  if fields.get("target") is Some(item) {
    if !wire_rule_380(item) {
      return false
    }
  }
  if fields.get("edits") is Some(item) {
    if !wire_rule_383(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_375(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  if items.length() < 1 {
    return false
  }
  if items.length() > 1 {
    return false
  }
  for item in items {
    if !wire_rule_376(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_392(value : Json) -> Bool {
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
    text == "artifact_ref") {
    return false
  }
  true
}

///|
fn wire_rule_390(value : Json) -> Bool {
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
    if !wire_rule_271(item) {
      return false
    }
  }
  if fields.get("expected_type") is Some(item) {
    if !wire_rule_392(item) {
      return false
    }
  }
  if fields.get("actual_type") is Some(item) {
    if !wire_rule_392(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_398(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text ==
    "sha256:02859499357530af0ae58e4f2958d1c8fa48f957b86b0a2976dad43bed99b551") {
    return false
  }
  true
}

///|
fn wire_rule_399(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "parameter_declaration") {
    return false
  }
  true
}

///|
fn wire_rule_405(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !(number == 1.0) {
    return false
  }
  true
}

///|
fn wire_rule_404(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_405(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_408(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 1.0 {
    return false
  }
  true
}

///|
fn wire_rule_407(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_408(value)
  }
  true
}

///|
fn wire_rule_406(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_407(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_403(value : Json) -> Bool {
  if wire_rule_404(value) && !wire_rule_406(value) {
    return false
  }
  true
}

///|
fn wire_rule_411(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !(number == 2.0) {
    return false
  }
  true
}

///|
fn wire_rule_410(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_411(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_414(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 2.0 {
    return false
  }
  true
}

///|
fn wire_rule_413(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_414(value)
  }
  true
}

///|
fn wire_rule_412(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_413(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_409(value : Json) -> Bool {
  if wire_rule_410(value) && !wire_rule_412(value) {
    return false
  }
  true
}

///|
fn wire_rule_417(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !(number == 3.0) {
    return false
  }
  true
}

///|
fn wire_rule_416(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_417(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_420(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 3.0 {
    return false
  }
  true
}

///|
fn wire_rule_419(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_420(value)
  }
  true
}

///|
fn wire_rule_418(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_419(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_415(value : Json) -> Bool {
  if wire_rule_416(value) && !wire_rule_418(value) {
    return false
  }
  true
}

///|
fn wire_rule_423(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !(number == 4.0) {
    return false
  }
  true
}

///|
fn wire_rule_422(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_423(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_426(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 4.0 {
    return false
  }
  true
}

///|
fn wire_rule_425(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_426(value)
  }
  true
}

///|
fn wire_rule_424(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_425(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_421(value : Json) -> Bool {
  if wire_rule_422(value) && !wire_rule_424(value) {
    return false
  }
  true
}

///|
fn wire_rule_429(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !(number == 5.0) {
    return false
  }
  true
}

///|
fn wire_rule_428(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_429(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_432(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 5.0 {
    return false
  }
  true
}

///|
fn wire_rule_431(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_432(value)
  }
  true
}

///|
fn wire_rule_430(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_431(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_427(value : Json) -> Bool {
  if wire_rule_428(value) && !wire_rule_430(value) {
    return false
  }
  true
}

///|
fn wire_rule_435(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !(number == 6.0) {
    return false
  }
  true
}

///|
fn wire_rule_434(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_435(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_438(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 6.0 {
    return false
  }
  true
}

///|
fn wire_rule_437(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_438(value)
  }
  true
}

///|
fn wire_rule_436(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_437(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_433(value : Json) -> Bool {
  if wire_rule_434(value) && !wire_rule_436(value) {
    return false
  }
  true
}

///|
fn wire_rule_441(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !(number == 7.0) {
    return false
  }
  true
}

///|
fn wire_rule_440(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_441(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_444(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 7.0 {
    return false
  }
  true
}

///|
fn wire_rule_443(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_444(value)
  }
  true
}

///|
fn wire_rule_442(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_443(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_439(value : Json) -> Bool {
  if wire_rule_440(value) && !wire_rule_442(value) {
    return false
  }
  true
}

///|
fn wire_rule_447(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !(number == 8.0) {
    return false
  }
  true
}

///|
fn wire_rule_446(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_447(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_450(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 8.0 {
    return false
  }
  true
}

///|
fn wire_rule_449(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_450(value)
  }
  true
}

///|
fn wire_rule_448(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_449(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_445(value : Json) -> Bool {
  if wire_rule_446(value) && !wire_rule_448(value) {
    return false
  }
  true
}

///|
fn wire_rule_453(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !(number == 9.0) {
    return false
  }
  true
}

///|
fn wire_rule_452(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_453(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_456(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 9.0 {
    return false
  }
  true
}

///|
fn wire_rule_455(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_456(value)
  }
  true
}

///|
fn wire_rule_454(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_455(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_451(value : Json) -> Bool {
  if wire_rule_452(value) && !wire_rule_454(value) {
    return false
  }
  true
}

///|
fn wire_rule_459(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !(number == 10.0) {
    return false
  }
  true
}

///|
fn wire_rule_458(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_459(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_462(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 10.0 {
    return false
  }
  true
}

///|
fn wire_rule_461(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_462(value)
  }
  true
}

///|
fn wire_rule_460(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_461(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_457(value : Json) -> Bool {
  if wire_rule_458(value) && !wire_rule_460(value) {
    return false
  }
  true
}

///|
fn wire_rule_465(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !(number == 11.0) {
    return false
  }
  true
}

///|
fn wire_rule_464(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_465(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_468(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 11.0 {
    return false
  }
  true
}

///|
fn wire_rule_467(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_468(value)
  }
  true
}

///|
fn wire_rule_466(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_467(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_463(value : Json) -> Bool {
  if wire_rule_464(value) && !wire_rule_466(value) {
    return false
  }
  true
}

///|
fn wire_rule_471(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !(number == 12.0) {
    return false
  }
  true
}

///|
fn wire_rule_470(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_471(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_474(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 12.0 {
    return false
  }
  true
}

///|
fn wire_rule_473(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_474(value)
  }
  true
}

///|
fn wire_rule_472(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_473(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_469(value : Json) -> Bool {
  if wire_rule_470(value) && !wire_rule_472(value) {
    return false
  }
  true
}

///|
fn wire_rule_477(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !(number == 13.0) {
    return false
  }
  true
}

///|
fn wire_rule_476(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_477(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_480(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 13.0 {
    return false
  }
  true
}

///|
fn wire_rule_479(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_480(value)
  }
  true
}

///|
fn wire_rule_478(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_479(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_475(value : Json) -> Bool {
  if wire_rule_476(value) && !wire_rule_478(value) {
    return false
  }
  true
}

///|
fn wire_rule_483(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !(number == 14.0) {
    return false
  }
  true
}

///|
fn wire_rule_482(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_483(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_486(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 14.0 {
    return false
  }
  true
}

///|
fn wire_rule_485(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_486(value)
  }
  true
}

///|
fn wire_rule_484(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_485(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_481(value : Json) -> Bool {
  if wire_rule_482(value) && !wire_rule_484(value) {
    return false
  }
  true
}

///|
fn wire_rule_489(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !(number == 15.0) {
    return false
  }
  true
}

///|
fn wire_rule_488(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_489(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_492(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 15.0 {
    return false
  }
  true
}

///|
fn wire_rule_491(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_492(value)
  }
  true
}

///|
fn wire_rule_490(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_491(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_487(value : Json) -> Bool {
  if wire_rule_488(value) && !wire_rule_490(value) {
    return false
  }
  true
}

///|
fn wire_rule_495(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !(number == 16.0) {
    return false
  }
  true
}

///|
fn wire_rule_494(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_495(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_498(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 16.0 {
    return false
  }
  true
}

///|
fn wire_rule_497(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_498(value)
  }
  true
}

///|
fn wire_rule_496(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_497(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_493(value : Json) -> Bool {
  if wire_rule_494(value) && !wire_rule_496(value) {
    return false
  }
  true
}

///|
fn wire_rule_501(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !(number == 17.0) {
    return false
  }
  true
}

///|
fn wire_rule_500(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_501(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_504(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 17.0 {
    return false
  }
  true
}

///|
fn wire_rule_503(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_504(value)
  }
  true
}

///|
fn wire_rule_502(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_503(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_499(value : Json) -> Bool {
  if wire_rule_500(value) && !wire_rule_502(value) {
    return false
  }
  true
}

///|
fn wire_rule_507(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !(number == 18.0) {
    return false
  }
  true
}

///|
fn wire_rule_506(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_507(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_510(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 18.0 {
    return false
  }
  true
}

///|
fn wire_rule_509(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_510(value)
  }
  true
}

///|
fn wire_rule_508(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_509(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_505(value : Json) -> Bool {
  if wire_rule_506(value) && !wire_rule_508(value) {
    return false
  }
  true
}

///|
fn wire_rule_513(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !(number == 19.0) {
    return false
  }
  true
}

///|
fn wire_rule_512(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_513(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_516(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 19.0 {
    return false
  }
  true
}

///|
fn wire_rule_515(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_516(value)
  }
  true
}

///|
fn wire_rule_514(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_515(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_511(value : Json) -> Bool {
  if wire_rule_512(value) && !wire_rule_514(value) {
    return false
  }
  true
}

///|
fn wire_rule_519(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !(number == 20.0) {
    return false
  }
  true
}

///|
fn wire_rule_518(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_519(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_522(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 20.0 {
    return false
  }
  true
}

///|
fn wire_rule_521(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_522(value)
  }
  true
}

///|
fn wire_rule_520(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_521(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_517(value : Json) -> Bool {
  if wire_rule_518(value) && !wire_rule_520(value) {
    return false
  }
  true
}

///|
fn wire_rule_525(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !(number == 21.0) {
    return false
  }
  true
}

///|
fn wire_rule_524(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_525(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_528(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 21.0 {
    return false
  }
  true
}

///|
fn wire_rule_527(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_528(value)
  }
  true
}

///|
fn wire_rule_526(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_527(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_523(value : Json) -> Bool {
  if wire_rule_524(value) && !wire_rule_526(value) {
    return false
  }
  true
}

///|
fn wire_rule_531(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !(number == 22.0) {
    return false
  }
  true
}

///|
fn wire_rule_530(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_531(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_534(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 22.0 {
    return false
  }
  true
}

///|
fn wire_rule_533(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_534(value)
  }
  true
}

///|
fn wire_rule_532(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_533(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_529(value : Json) -> Bool {
  if wire_rule_530(value) && !wire_rule_532(value) {
    return false
  }
  true
}

///|
fn wire_rule_537(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !(number == 23.0) {
    return false
  }
  true
}

///|
fn wire_rule_536(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_537(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_540(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 23.0 {
    return false
  }
  true
}

///|
fn wire_rule_539(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_540(value)
  }
  true
}

///|
fn wire_rule_538(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_539(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_535(value : Json) -> Bool {
  if wire_rule_536(value) && !wire_rule_538(value) {
    return false
  }
  true
}

///|
fn wire_rule_543(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !(number == 24.0) {
    return false
  }
  true
}

///|
fn wire_rule_542(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_543(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_546(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 24.0 {
    return false
  }
  true
}

///|
fn wire_rule_545(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_546(value)
  }
  true
}

///|
fn wire_rule_544(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_545(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_541(value : Json) -> Bool {
  if wire_rule_542(value) && !wire_rule_544(value) {
    return false
  }
  true
}

///|
fn wire_rule_549(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !(number == 25.0) {
    return false
  }
  true
}

///|
fn wire_rule_548(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_549(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_552(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 25.0 {
    return false
  }
  true
}

///|
fn wire_rule_551(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_552(value)
  }
  true
}

///|
fn wire_rule_550(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_551(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_547(value : Json) -> Bool {
  if wire_rule_548(value) && !wire_rule_550(value) {
    return false
  }
  true
}

///|
fn wire_rule_555(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !(number == 26.0) {
    return false
  }
  true
}

///|
fn wire_rule_554(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_555(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_558(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 26.0 {
    return false
  }
  true
}

///|
fn wire_rule_557(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_558(value)
  }
  true
}

///|
fn wire_rule_556(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_557(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_553(value : Json) -> Bool {
  if wire_rule_554(value) && !wire_rule_556(value) {
    return false
  }
  true
}

///|
fn wire_rule_561(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !(number == 27.0) {
    return false
  }
  true
}

///|
fn wire_rule_560(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_561(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_564(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 27.0 {
    return false
  }
  true
}

///|
fn wire_rule_563(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_564(value)
  }
  true
}

///|
fn wire_rule_562(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_563(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_559(value : Json) -> Bool {
  if wire_rule_560(value) && !wire_rule_562(value) {
    return false
  }
  true
}

///|
fn wire_rule_567(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !(number == 28.0) {
    return false
  }
  true
}

///|
fn wire_rule_566(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_567(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_570(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 28.0 {
    return false
  }
  true
}

///|
fn wire_rule_569(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_570(value)
  }
  true
}

///|
fn wire_rule_568(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_569(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_565(value : Json) -> Bool {
  if wire_rule_566(value) && !wire_rule_568(value) {
    return false
  }
  true
}

///|
fn wire_rule_573(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !(number == 29.0) {
    return false
  }
  true
}

///|
fn wire_rule_572(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_573(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_576(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 29.0 {
    return false
  }
  true
}

///|
fn wire_rule_575(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_576(value)
  }
  true
}

///|
fn wire_rule_574(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_575(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_571(value : Json) -> Bool {
  if wire_rule_572(value) && !wire_rule_574(value) {
    return false
  }
  true
}

///|
fn wire_rule_579(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !(number == 30.0) {
    return false
  }
  true
}

///|
fn wire_rule_578(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_579(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_582(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 30.0 {
    return false
  }
  true
}

///|
fn wire_rule_581(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_582(value)
  }
  true
}

///|
fn wire_rule_580(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_581(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_577(value : Json) -> Bool {
  if wire_rule_578(value) && !wire_rule_580(value) {
    return false
  }
  true
}

///|
fn wire_rule_585(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !(number == 31.0) {
    return false
  }
  true
}

///|
fn wire_rule_584(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_585(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_588(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 31.0 {
    return false
  }
  true
}

///|
fn wire_rule_587(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_588(value)
  }
  true
}

///|
fn wire_rule_586(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_587(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_583(value : Json) -> Bool {
  if wire_rule_584(value) && !wire_rule_586(value) {
    return false
  }
  true
}

///|
fn wire_rule_591(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !(number == 32.0) {
    return false
  }
  true
}

///|
fn wire_rule_590(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_591(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_594(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 32.0 {
    return false
  }
  true
}

///|
fn wire_rule_593(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_594(value)
  }
  true
}

///|
fn wire_rule_592(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_593(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_589(value : Json) -> Bool {
  if wire_rule_590(value) && !wire_rule_592(value) {
    return false
  }
  true
}

///|
fn wire_rule_597(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !(number == 33.0) {
    return false
  }
  true
}

///|
fn wire_rule_596(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_597(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_600(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 33.0 {
    return false
  }
  true
}

///|
fn wire_rule_599(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_600(value)
  }
  true
}

///|
fn wire_rule_598(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_599(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_595(value : Json) -> Bool {
  if wire_rule_596(value) && !wire_rule_598(value) {
    return false
  }
  true
}

///|
fn wire_rule_603(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !(number == 34.0) {
    return false
  }
  true
}

///|
fn wire_rule_602(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_603(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_606(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 34.0 {
    return false
  }
  true
}

///|
fn wire_rule_605(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_606(value)
  }
  true
}

///|
fn wire_rule_604(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_605(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_601(value : Json) -> Bool {
  if wire_rule_602(value) && !wire_rule_604(value) {
    return false
  }
  true
}

///|
fn wire_rule_609(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !(number == 35.0) {
    return false
  }
  true
}

///|
fn wire_rule_608(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_609(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_612(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 35.0 {
    return false
  }
  true
}

///|
fn wire_rule_611(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_612(value)
  }
  true
}

///|
fn wire_rule_610(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_611(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_607(value : Json) -> Bool {
  if wire_rule_608(value) && !wire_rule_610(value) {
    return false
  }
  true
}

///|
fn wire_rule_615(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !(number == 36.0) {
    return false
  }
  true
}

///|
fn wire_rule_614(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_615(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_618(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 36.0 {
    return false
  }
  true
}

///|
fn wire_rule_617(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_618(value)
  }
  true
}

///|
fn wire_rule_616(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_617(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_613(value : Json) -> Bool {
  if wire_rule_614(value) && !wire_rule_616(value) {
    return false
  }
  true
}

///|
fn wire_rule_621(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !(number == 37.0) {
    return false
  }
  true
}

///|
fn wire_rule_620(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_621(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_624(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 37.0 {
    return false
  }
  true
}

///|
fn wire_rule_623(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_624(value)
  }
  true
}

///|
fn wire_rule_622(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_623(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_619(value : Json) -> Bool {
  if wire_rule_620(value) && !wire_rule_622(value) {
    return false
  }
  true
}

///|
fn wire_rule_627(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !(number == 38.0) {
    return false
  }
  true
}

///|
fn wire_rule_626(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_627(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_630(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 38.0 {
    return false
  }
  true
}

///|
fn wire_rule_629(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_630(value)
  }
  true
}

///|
fn wire_rule_628(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_629(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_625(value : Json) -> Bool {
  if wire_rule_626(value) && !wire_rule_628(value) {
    return false
  }
  true
}

///|
fn wire_rule_631(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "decimal") {
    return false
  }
  true
}

///|
fn wire_rule_633(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if number != number.floor() ||
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
fn wire_rule_634(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if number != number.floor() ||
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
fn wire_rule_402(value : Json) -> Bool {
  if !wire_rule_403(value) {
    return false
  }
  if !wire_rule_409(value) {
    return false
  }
  if !wire_rule_415(value) {
    return false
  }
  if !wire_rule_421(value) {
    return false
  }
  if !wire_rule_427(value) {
    return false
  }
  if !wire_rule_433(value) {
    return false
  }
  if !wire_rule_439(value) {
    return false
  }
  if !wire_rule_445(value) {
    return false
  }
  if !wire_rule_451(value) {
    return false
  }
  if !wire_rule_457(value) {
    return false
  }
  if !wire_rule_463(value) {
    return false
  }
  if !wire_rule_469(value) {
    return false
  }
  if !wire_rule_475(value) {
    return false
  }
  if !wire_rule_481(value) {
    return false
  }
  if !wire_rule_487(value) {
    return false
  }
  if !wire_rule_493(value) {
    return false
  }
  if !wire_rule_499(value) {
    return false
  }
  if !wire_rule_505(value) {
    return false
  }
  if !wire_rule_511(value) {
    return false
  }
  if !wire_rule_517(value) {
    return false
  }
  if !wire_rule_523(value) {
    return false
  }
  if !wire_rule_529(value) {
    return false
  }
  if !wire_rule_535(value) {
    return false
  }
  if !wire_rule_541(value) {
    return false
  }
  if !wire_rule_547(value) {
    return false
  }
  if !wire_rule_553(value) {
    return false
  }
  if !wire_rule_559(value) {
    return false
  }
  if !wire_rule_565(value) {
    return false
  }
  if !wire_rule_571(value) {
    return false
  }
  if !wire_rule_577(value) {
    return false
  }
  if !wire_rule_583(value) {
    return false
  }
  if !wire_rule_589(value) {
    return false
  }
  if !wire_rule_595(value) {
    return false
  }
  if !wire_rule_601(value) {
    return false
  }
  if !wire_rule_607(value) {
    return false
  }
  if !wire_rule_613(value) {
    return false
  }
  if !wire_rule_619(value) {
    return false
  }
  if !wire_rule_625(value) {
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
    if !wire_rule_631(item) {
      return false
    }
  }
  if fields.get("nullable") is Some(item) {
    if !wire_rule_356(item) {
      return false
    }
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_633(item) {
      return false
    }
  }
  if fields.get("scale") is Some(item) {
    if !wire_rule_634(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_636(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "string") {
    return false
  }
  true
}

///|
fn wire_rule_638(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if number != number.floor() ||
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
fn wire_rule_635(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "type" ||
      key == "nullable" ||
      key == "min_length" ||
      key == "max_codepoints" ||
      key == "max_utf8_bytes") {
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
    if !wire_rule_636(item) {
      return false
    }
  }
  if fields.get("nullable") is Some(item) {
    if !wire_rule_356(item) {
      return false
    }
  }
  if fields.get("min_length") is Some(item) {
    if !wire_rule_638(item) {
      return false
    }
  }
  if fields.get("max_codepoints") is Some(item) {
    if !wire_rule_638(item) {
      return false
    }
  }
  if fields.get("max_utf8_bytes") is Some(item) {
    if !wire_rule_638(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_642(value : Json) -> Bool {
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
fn wire_rule_641(value : Json) -> Bool {
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
    if !wire_rule_642(item) {
      return false
    }
  }
  if fields.get("nullable") is Some(item) {
    if !wire_rule_356(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_645(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "array") {
    return false
  }
  true
}

///|
fn wire_rule_644(value : Json) -> Bool {
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
    if !wire_rule_645(item) {
      return false
    }
  }
  if fields.get("nullable") is Some(item) {
    if !wire_rule_356(item) {
      return false
    }
  }
  if fields.get("items") is Some(item) {
    if !wire_rule_400(item) {
      return false
    }
  }
  if fields.get("max_items") is Some(item) {
    if !wire_rule_638(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_650(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "object") {
    return false
  }
  true
}

///|
fn wire_rule_652(value : Json) -> Bool {
  if !(value is True || value is False) {
    return false
  }
  if !(value is False) {
    return false
  }
  true
}

///|
fn wire_rule_656(value : Json) -> Bool {
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
fn wire_rule_655(value : Json) -> Bool {
  if value is String(_) {
    return wire_rule_656(value)
  }
  true
}

///|
fn wire_rule_653(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for _key, item in fields {
    if !false && !wire_rule_400(item) {
      return false
    }
  }
  for key, _ in fields {
    if !wire_rule_655(Json::string(key)) {
      return false
    }
  }
  true
}

///|
fn wire_rule_649(value : Json) -> Bool {
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
    if !wire_rule_650(item) {
      return false
    }
  }
  if fields.get("nullable") is Some(item) {
    if !wire_rule_356(item) {
      return false
    }
  }
  if fields.get("additional_properties") is Some(item) {
    if !wire_rule_652(item) {
      return false
    }
  }
  if fields.get("fields") is Some(item) {
    if !wire_rule_653(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_658(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "vector") {
    return false
  }
  true
}

///|
fn wire_rule_660(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if number != number.floor() ||
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
fn wire_rule_661(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "f32") {
    return false
  }
  true
}

///|
fn wire_rule_657(value : Json) -> Bool {
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
    if !wire_rule_658(item) {
      return false
    }
  }
  if fields.get("nullable") is Some(item) {
    if !wire_rule_356(item) {
      return false
    }
  }
  if fields.get("dimensions") is Some(item) {
    if !wire_rule_660(item) {
      return false
    }
  }
  if fields.get("element_type") is Some(item) {
    if !wire_rule_661(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_663(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "resource_ref") {
    return false
  }
  true
}

///|
fn wire_rule_665(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if text.iter().count() < 1 {
    return false
  }
  true
}

///|
fn wire_rule_662(value : Json) -> Bool {
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
    if !wire_rule_663(item) {
      return false
    }
  }
  if fields.get("nullable") is Some(item) {
    if !wire_rule_356(item) {
      return false
    }
  }
  if fields.get("resource_kind") is Some(item) {
    if !wire_rule_665(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_667(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "artifact_ref") {
    return false
  }
  true
}

///|
fn wire_rule_666(value : Json) -> Bool {
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
    if !wire_rule_667(item) {
      return false
    }
  }
  if fields.get("nullable") is Some(item) {
    if !wire_rule_356(item) {
      return false
    }
  }
  if fields.get("media_type") is Some(item) {
    if !wire_rule_665(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_401(value : Json) -> Bool {
  if [
      wire_rule_402(value),
      wire_rule_635(value),
      wire_rule_641(value),
      wire_rule_644(value),
      wire_rule_649(value),
      wire_rule_657(value),
      wire_rule_662(value),
      wire_rule_666(value),
    ]
    .filter(fn(ok) { ok })
    .length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_rule_400(value : Json) -> Bool {
  if !wire_rule_401(value) {
    return false
  }
  true
}

///|
fn wire_rule_670(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "caller") {
    return false
  }
  true
}

///|
fn wire_rule_674(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "numeric") {
    return false
  }
  true
}

///|
fn wire_rule_678(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "field") {
    return false
  }
  true
}

///|
fn wire_rule_677(value : Json) -> Bool {
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
    if !wire_rule_678(item) {
      return false
    }
  }
  if fields.get("name") is Some(item) {
    if !wire_rule_355(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_681(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "items") {
    return false
  }
  true
}

///|
fn wire_rule_680(value : Json) -> Bool {
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
    if !wire_rule_681(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_676(value : Json) -> Bool {
  if [wire_rule_677(value), wire_rule_680(value)].filter(fn(ok) { ok }).length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_rule_675(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  if items.length() > 64 {
    return false
  }
  for item in items {
    if !wire_rule_676(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_683(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if number.is_nan() || number.is_inf() {
    return false
  }
  true
}

///|
fn wire_rule_673(value : Json) -> Bool {
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
    if !wire_rule_674(item) {
      return false
    }
  }
  if fields.get("path") is Some(item) {
    if !wire_rule_675(item) {
      return false
    }
  }
  if fields.get("integer") is Some(item) {
    if !wire_rule_356(item) {
      return false
    }
  }
  if fields.get("minimum") is Some(item) {
    if !wire_rule_683(item) {
      return false
    }
  }
  if fields.get("maximum") is Some(item) {
    if !wire_rule_683(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_686(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "duration") {
    return false
  }
  true
}

///|
fn wire_rule_685(value : Json) -> Bool {
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
    if !wire_rule_686(item) {
      return false
    }
  }
  if fields.get("path") is Some(item) {
    if !wire_rule_675(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_689(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "array_length") {
    return false
  }
  true
}

///|
fn wire_rule_691(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if number != number.floor() ||
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
fn wire_rule_688(value : Json) -> Bool {
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
    if !wire_rule_689(item) {
      return false
    }
  }
  if fields.get("path") is Some(item) {
    if !wire_rule_675(item) {
      return false
    }
  }
  if fields.get("length") is Some(item) {
    if !wire_rule_691(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_672(value : Json) -> Bool {
  if [wire_rule_673(value), wire_rule_685(value), wire_rule_688(value)]
    .filter(fn(ok) { ok })
    .length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_rule_671(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  if items.length() > 8192 {
    return false
  }
  for item in items {
    if !wire_rule_672(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_397(value : Json) -> Bool {
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
    if !wire_rule_398(item) {
      return false
    }
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_399(item) {
      return false
    }
  }
  if fields.get("contract") is Some(item) {
    if !wire_rule_400(item) {
      return false
    }
  }
  if fields.get("supplier") is Some(item) {
    if !wire_rule_670(item) {
      return false
    }
  }
  if fields.get("constraints") is Some(item) {
    if !wire_rule_671(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_394(value : Json) -> Bool {
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
    if !wire_rule_271(item) {
      return false
    }
  }
  if fields.get("expected_type") is Some(item) {
    if !wire_rule_392(item) {
      return false
    }
  }
  if fields.get("admission") is Some(item) {
    if !wire_rule_397(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_694(value : Json) -> Bool {
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
fn wire_rule_692(value : Json) -> Bool {
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
    if !wire_rule_271(item) {
      return false
    }
  }
  if fields.get("constraint") is Some(item) {
    if !wire_rule_694(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_698(value : Json) -> Bool {
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
fn wire_rule_696(value : Json) -> Bool {
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
    if !wire_rule_271(item) {
      return false
    }
  }
  if fields.get("domain") is Some(item) {
    if !wire_rule_698(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_700(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "components") {
    return false
  }
  true
}

///|
fn wire_rule_701(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "invalid_kind" || text == "invalid_output_rows") {
    return false
  }
  true
}

///|
fn wire_rule_699(value : Json) -> Bool {
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
    if !wire_rule_700(item) {
      return false
    }
  }
  if fields.get("issue") is Some(item) {
    if !wire_rule_701(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_703(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "subgraph") {
    return false
  }
  true
}

///|
fn wire_rule_704(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "invalid_node_selector") {
    return false
  }
  true
}

///|
fn wire_rule_702(value : Json) -> Bool {
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
    if !wire_rule_703(item) {
      return false
    }
  }
  if fields.get("issue") is Some(item) {
    if !wire_rule_704(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_707(value : Json) -> Bool {
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
fn wire_rule_706(value : Json) -> Bool {
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
    if !wire_rule_707(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_388(value : Json) -> Bool {
  if [
      wire_rule_270(value),
      wire_rule_390(value),
      wire_rule_394(value),
      wire_rule_692(value),
      wire_rule_282(value),
      wire_rule_696(value),
      wire_rule_699(value),
      wire_rule_702(value),
      wire_rule_311(value),
      wire_rule_706(value),
      wire_rule_180(value),
      wire_rule_163(value),
      wire_rule_351(value),
    ]
    .filter(fn(ok) { ok })
    .length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_rule_144(value : Json) -> Bool {
  if !wire_rule_145(value) {
    return false
  }
  if !wire_rule_155(value) {
    return false
  }
  if !wire_rule_167(value) {
    return false
  }
  if !wire_rule_174(value) {
    return false
  }
  if !wire_rule_186(value) {
    return false
  }
  if !wire_rule_193(value) {
    return false
  }
  if !wire_rule_202(value) {
    return false
  }
  if !wire_rule_209(value) {
    return false
  }
  if !wire_rule_218(value) {
    return false
  }
  if !wire_rule_225(value) {
    return false
  }
  if !wire_rule_232(value) {
    return false
  }
  if !wire_rule_239(value) {
    return false
  }
  if !wire_rule_244(value) {
    return false
  }
  if !wire_rule_250(value) {
    return false
  }
  if !wire_rule_261(value) {
    return false
  }
  if !wire_rule_266(value) {
    return false
  }
  if !wire_rule_273(value) {
    return false
  }
  if !wire_rule_278(value) {
    return false
  }
  if !wire_rule_285(value) {
    return false
  }
  if !wire_rule_293(value) {
    return false
  }
  if !wire_rule_316(value) {
    return false
  }
  if !wire_rule_324(value) {
    return false
  }
  if !wire_rule_331(value) {
    return false
  }
  if !wire_rule_338(value) {
    return false
  }
  if !wire_rule_346(value) {
    return false
  }
  if !wire_rule_358(value) {
    return false
  }
  if !wire_rule_364(value) {
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
    if !wire_rule_120(item) {
      return false
    }
  }
  if fields.get("location") is Some(item) {
    if !wire_rule_368(item) {
      return false
    }
  }
  if fields.get("fixes") is Some(item) {
    if !wire_rule_375(item) {
      return false
    }
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_388(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_143(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  if items.length() > 1024 {
    return false
  }
  for item in items {
    if !wire_rule_144(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_712(value : Json) -> Bool {
  if !wire_rule_145(value) {
    return false
  }
  if !wire_rule_155(value) {
    return false
  }
  if !wire_rule_167(value) {
    return false
  }
  if !wire_rule_174(value) {
    return false
  }
  if !wire_rule_186(value) {
    return false
  }
  if !wire_rule_193(value) {
    return false
  }
  if !wire_rule_202(value) {
    return false
  }
  if !wire_rule_209(value) {
    return false
  }
  if !wire_rule_218(value) {
    return false
  }
  if !wire_rule_225(value) {
    return false
  }
  if !wire_rule_232(value) {
    return false
  }
  if !wire_rule_239(value) {
    return false
  }
  if !wire_rule_244(value) {
    return false
  }
  if !wire_rule_250(value) {
    return false
  }
  if !wire_rule_261(value) {
    return false
  }
  if !wire_rule_266(value) {
    return false
  }
  if !wire_rule_273(value) {
    return false
  }
  if !wire_rule_278(value) {
    return false
  }
  if !wire_rule_285(value) {
    return false
  }
  if !wire_rule_293(value) {
    return false
  }
  if !wire_rule_316(value) {
    return false
  }
  if !wire_rule_324(value) {
    return false
  }
  if !wire_rule_331(value) {
    return false
  }
  if !wire_rule_338(value) {
    return false
  }
  if !wire_rule_346(value) {
    return false
  }
  if !wire_rule_358(value) {
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
    if !wire_rule_366(item) {
      return false
    }
  }
  if fields.get("location") is Some(item) {
    if !wire_rule_368(item) {
      return false
    }
  }
  if fields.get("fixes") is Some(item) {
    if !wire_rule_375(item) {
      return false
    }
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_388(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_711(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  if items.length() > 1024 {
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
fn wire_rule_744(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "template_only" || text == "bound_input") {
    return false
  }
  true
}

///|
fn wire_rule_743(value : Json) -> Bool {
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
    if !wire_rule_744(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_745(value : Json) -> Bool {
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
  if !wire_rule_94(value) {
    return false
  }
  if !wire_rule_100(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "context_ref" ||
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
  if !fields.contains("scope") {
    return false
  }
  if !fields.contains("verdict") {
    return false
  }
  if fields.get("context_ref") is Some(item) {
    if !wire_rule_107(item) {
      return false
    }
  }
  if fields.get("omissions") is Some(item) {
    if !wire_rule_108(item) {
      return false
    }
  }
  if fields.get("inputs") is Some(item) {
    if !wire_rule_110(item) {
      return false
    }
  }
  if fields.get("coverage") is Some(item) {
    if !wire_rule_116(item) {
      return false
    }
  }
  if fields.get("reasons") is Some(item) {
    if !wire_rule_143(item) {
      return false
    }
  }
  if fields.get("requirements") is Some(item) {
    if !wire_rule_711(item) {
      return false
    }
  }
  if fields.get("scope") is Some(item) {
    if !wire_rule_743(item) {
      return false
    }
  }
  if fields.get("verdict") is Some(item) {
    if !wire_rule_745(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_746(value : Json) -> Bool {
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
fn wire_rule_747(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text ==
    "sha256:332a61df6738e4e21d916345f31f2ae28aec30cd779cd614dba2a24044f061e6") {
    return false
  }
  true
}

///|
fn wire_rule_748(value : Json) -> Bool {
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
    if !wire_rule_746(item) {
      return false
    }
  }
  if fields.get("reason_schema_cid") is Some(item) {
    if !wire_rule_747(item) {
      return false
    }
  }
  if fields.get("version") is Some(item) {
    if !wire_rule_748(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_750(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "failed") {
    return false
  }
  true
}

///|
fn wire_rule_762(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "invalid" || text == "undetermined") {
    return false
  }
  true
}

///|
fn wire_rule_751(value : Json) -> Bool {
  if !wire_rule_69(value) {
    return false
  }
  if !wire_rule_94(value) {
    return false
  }
  if !wire_rule_100(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "context_ref" ||
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
  if !fields.contains("scope") {
    return false
  }
  if !fields.contains("verdict") {
    return false
  }
  if fields.get("context_ref") is Some(item) {
    if !wire_rule_107(item) {
      return false
    }
  }
  if fields.get("omissions") is Some(item) {
    if !wire_rule_108(item) {
      return false
    }
  }
  if fields.get("inputs") is Some(item) {
    if !wire_rule_110(item) {
      return false
    }
  }
  if fields.get("coverage") is Some(item) {
    if !wire_rule_116(item) {
      return false
    }
  }
  if fields.get("reasons") is Some(item) {
    if !wire_rule_143(item) {
      return false
    }
  }
  if fields.get("requirements") is Some(item) {
    if !wire_rule_711(item) {
      return false
    }
  }
  if fields.get("scope") is Some(item) {
    if !wire_rule_743(item) {
      return false
    }
  }
  if fields.get("verdict") is Some(item) {
    if !wire_rule_762(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_749(value : Json) -> Bool {
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
    if !wire_rule_750(item) {
      return false
    }
  }
  if fields.get("partial_report") is Some(item) {
    if !wire_rule_751(item) {
      return false
    }
  }
  if fields.get("problem") is Some(item) {
    if !wire_rule_119(item) {
      return false
    }
  }
  if fields.get("correlation_ref") is Some(item) {
    if !wire_rule_107(item) {
      return false
    }
  }
  if fields.get("outcome_schema_cid") is Some(item) {
    if !wire_rule_746(item) {
      return false
    }
  }
  if fields.get("reason_schema_cid") is Some(item) {
    if !wire_rule_747(item) {
      return false
    }
  }
  if fields.get("version") is Some(item) {
    if !wire_rule_748(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_770(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "unavailable") {
    return false
  }
  true
}

///|
fn wire_rule_768(value : Json) -> Bool {
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
    if !wire_rule_107(item) {
      return false
    }
  }
  if fields.get("outcome") is Some(item) {
    if !wire_rule_770(item) {
      return false
    }
  }
  if fields.get("problem") is Some(item) {
    if !wire_rule_119(item) {
      return false
    }
  }
  if fields.get("outcome_schema_cid") is Some(item) {
    if !wire_rule_746(item) {
      return false
    }
  }
  if fields.get("reason_schema_cid") is Some(item) {
    if !wire_rule_747(item) {
      return false
    }
  }
  if fields.get("version") is Some(item) {
    if !wire_rule_748(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_65(value : Json) -> Bool {
  if [wire_rule_66(value), wire_rule_749(value), wire_rule_768(value)]
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
        "sha256:332a61df6738e4e21d916345f31f2ae28aec30cd779cd614dba2a24044f061e6",
      ),
    ) {
    return false
  }
  if fields.get("outcome_schema_cid") !=
    Some(
      Json::string(
        "sha256:b1062306669a530f532faa3b7fc5d24e34bd72aeae712c177cee7557216ea464",
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
fn wire_rule_778(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "bound_input") {
    return false
  }
  true
}

///|
fn wire_rule_777(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("kind") is Some(item) {
    if !wire_rule_778(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_776(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scope") is Some(item) {
    if !wire_rule_777(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_775(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("report") is Some(item) {
    if !wire_rule_776(item) {
      return false
    }
  }
  if fields.get("partial_report") is Some(item) {
    if !wire_rule_776(item) {
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
  if !wire_rule_775(value) {
    return false
  }
  true
}

///|
fn wire_rule_782(value : Json) -> Bool {
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
fn wire_rule_780(value : Json) -> Bool {
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
    if !wire_rule_782(item) {
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
    if !wire_rule_780(item) {
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
fn wire_rule_785(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "preparation_failed") {
    return false
  }
  true
}

///|
fn wire_rule_784(value : Json) -> Bool {
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
    if !wire_rule_785(item) {
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
    if !wire_rule_780(item) {
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
      wire_rule_784(value),
    ]
    .filter(fn(ok) { ok })
    .length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_rule_794(value : Json) -> Bool {
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
    if !wire_rule_780(item) {
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
fn wire_rule_800(value : Json) -> Bool {
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
    if !wire_rule_785(item) {
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
    if !wire_rule_780(item) {
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
fn wire_rule_807(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "unresolvable") {
    return false
  }
  true
}

///|
fn wire_rule_809(value : Json) -> Bool {
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
fn wire_rule_806(value : Json) -> Bool {
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
    if !wire_rule_807(item) {
      return false
    }
  }
  if fields.get("submissionRef") is Some(item) {
    if !wire_submission_ref_shape(item) {
      return false
    }
  }
  if fields.get("problem") is Some(item) {
    if !wire_rule_809(item) {
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
      wire_rule_794(value),
      wire_rule_800(value),
      wire_rule_806(value),
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
fn wire_rule_815(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "already_satisfied") {
    return false
  }
  true
}

///|
fn wire_rule_814(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("kind") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_815(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_818(value : Json) -> Bool {
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
fn wire_rule_817(value : Json) -> Bool {
  if wire_rule_818(value) {
    return false
  }
  true
}

///|
fn wire_rule_816(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("outcome") {
    return false
  }
  if fields.get("outcome") is Some(item) {
    if !wire_rule_817(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_813(value : Json) -> Bool {
  if wire_rule_814(value) && !wire_rule_816(value) {
    return false
  }
  true
}

///|
fn wire_rule_820(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "recorded" || text == "already_satisfied") {
    return false
  }
  true
}

///|
fn wire_rule_822(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "submit") {
    return false
  }
  true
}

///|
fn wire_rule_821(value : Json) -> Bool {
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
    if !wire_rule_822(item) {
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
fn wire_rule_812(value : Json) -> Bool {
  if !wire_rule_813(value) {
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
    if !wire_rule_820(item) {
      return false
    }
  }
  if fields.get("attemptRef") is Some(item) {
    if !wire_rule_821(item) {
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
fn wire_rule_826(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "refused") {
    return false
  }
  true
}

///|
fn wire_rule_828(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "attempt_uncommitted_unconsumed") {
    return false
  }
  true
}

///|
fn wire_rule_829(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "authorization") {
    return false
  }
  true
}

///|
fn wire_rule_825(value : Json) -> Bool {
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
    if !wire_rule_826(item) {
      return false
    }
  }
  if fields.get("attemptRef") is Some(item) {
    if !wire_rule_821(item) {
      return false
    }
  }
  if fields.get("guarantee") is Some(item) {
    if !wire_rule_828(item) {
      return false
    }
  }
  if fields.get("reason") is Some(item) {
    if !wire_rule_829(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_836(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "admission_capacity" ||
    text == "epoch_expired" ||
    text == "epoch_not_yet_valid") {
    return false
  }
  true
}

///|
fn wire_rule_830(value : Json) -> Bool {
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
    if !wire_rule_826(item) {
      return false
    }
  }
  if fields.get("attemptRef") is Some(item) {
    if !wire_rule_821(item) {
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
    if !wire_rule_828(item) {
      return false
    }
  }
  if fields.get("reason") is Some(item) {
    if !wire_rule_836(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_838(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "conflict") {
    return false
  }
  true
}

///|
fn wire_rule_842(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "intent" || text == "restart_decision") {
    return false
  }
  true
}

///|
fn wire_rule_837(value : Json) -> Bool {
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
    if !wire_rule_838(item) {
      return false
    }
  }
  if fields.get("attemptRef") is Some(item) {
    if !wire_rule_821(item) {
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
    if !wire_rule_842(item) {
      return false
    }
  }
  true
}

///|
fn wire_submission_attempt_shape(value : Json) -> Bool {
  if [
      wire_rule_812(value),
      wire_rule_825(value),
      wire_rule_830(value),
      wire_rule_837(value),
    ]
    .filter(fn(ok) { ok })
    .length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_rule_846(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("movementPolicyRef") {
    return false
  }
  true
}

///|
fn wire_rule_845(value : Json) -> Bool {
  if wire_rule_846(value) {
    return false
  }
  true
}

///|
fn wire_rule_848(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("cloudConnectionRef") {
    return false
  }
  true
}

///|
fn wire_rule_847(value : Json) -> Bool {
  if wire_rule_848(value) {
    return false
  }
  true
}

///|
fn wire_rule_849(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "remote") {
    return false
  }
  true
}

///|
fn wire_rule_851(value : Json) -> Bool {
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
fn wire_rule_844(value : Json) -> Bool {
  if !wire_rule_845(value) {
    return false
  }
  if !wire_rule_847(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  if fields.get("mode") is Some(item) {
    if !wire_rule_849(item) {
      return false
    }
  }
  if fields.get("owner") is Some(item) {
    if !wire_rule_849(item) {
      return false
    }
  }
  if fields.get("runners") is Some(item) {
    if !wire_rule_851(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_856(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "local") {
    return false
  }
  true
}

///|
fn wire_rule_853(value : Json) -> Bool {
  if !wire_rule_845(value) {
    return false
  }
  if !wire_rule_847(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  if fields.get("mode") is Some(item) {
    if !wire_rule_856(item) {
      return false
    }
  }
  if fields.get("owner") is Some(item) {
    if !wire_rule_856(item) {
      return false
    }
  }
  if fields.get("runners") is Some(item) {
    if !wire_rule_851(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_860(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "hybrid") {
    return false
  }
  true
}

///|
fn wire_rule_859(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("movementPolicyRef") {
    return false
  }
  if !fields.contains("cloudConnectionRef") {
    return false
  }
  if fields.get("mode") is Some(item) {
    if !wire_rule_860(item) {
      return false
    }
  }
  if fields.get("owner") is Some(item) {
    if !wire_rule_856(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_865(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "cloud") {
    return false
  }
  true
}

///|
fn wire_rule_866(value : Json) -> Bool {
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
fn wire_rule_862(value : Json) -> Bool {
  if wire_rule_848(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  if !fields.contains("movementPolicyRef") {
    return false
  }
  if fields.get("mode") is Some(item) {
    if !wire_rule_860(item) {
      return false
    }
  }
  if fields.get("owner") is Some(item) {
    if !wire_rule_865(item) {
      return false
    }
  }
  if fields.get("runners") is Some(item) {
    if !wire_rule_866(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_843(value : Json) -> Bool {
  if [
      wire_rule_844(value),
      wire_rule_853(value),
      wire_rule_859(value),
      wire_rule_862(value),
    ]
    .filter(fn(ok) { ok })
    .length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_rule_868(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "local" || text == "remote" || text == "hybrid") {
    return false
  }
  true
}

///|
fn wire_rule_869(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "local" || text == "remote" || text == "cloud") {
    return false
  }
  true
}

///|
fn wire_rule_871(value : Json) -> Bool {
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
  if !wire_rule_843(value) {
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
    if !wire_rule_868(item) {
      return false
    }
  }
  if fields.get("owner") is Some(item) {
    if !wire_rule_869(item) {
      return false
    }
  }
  if fields.get("workspaceId") is Some(item) {
    if !wire_rule_7(item) {
      return false
    }
  }
  if fields.get("consentRefs") is Some(item) {
    if !wire_rule_871(item) {
      return false
    }
  }
  if fields.get("runners") is Some(item) {
    if !wire_rule_871(item) {
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
fn wire_rule_877(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "actql-client-host/0.1") {
    return false
  }
  true
}

///|
fn wire_rule_884(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  for item in items {
    if !wire_rule_7(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_887(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if number != number.floor() ||
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
fn wire_rule_886(value : Json) -> Bool {
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
    if !wire_rule_887(item) {
      return false
    }
  }
  if fields.get("maxRowWireBytes") is Some(item) {
    if !wire_rule_887(item) {
      return false
    }
  }
  if fields.get("maxRowRetainedValueBytes") is Some(item) {
    if !wire_rule_887(item) {
      return false
    }
  }
  if fields.get("maxRetainedValueBytes") is Some(item) {
    if !wire_rule_887(item) {
      return false
    }
  }
  if fields.get("maxRows") is Some(item) {
    if !wire_rule_887(item) {
      return false
    }
  }
  if fields.get("maxBatchRows") is Some(item) {
    if !wire_rule_887(item) {
      return false
    }
  }
  if fields.get("maxBatchRetainedValueBytes") is Some(item) {
    if !wire_rule_887(item) {
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
    if !wire_rule_877(item) {
      return false
    }
  }
  if fields.get("mode") is Some(item) {
    if !wire_rule_868(item) {
      return false
    }
  }
  if fields.get("owner") is Some(item) {
    if !wire_rule_869(item) {
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
    if !wire_rule_884(item) {
      return false
    }
  }
  if fields.get("limits") is Some(item) {
    if !wire_rule_886(item) {
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
fn wire_rule_894(value : Json) -> Bool {
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
    if !wire_rule_894(item) {
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
fn wire_rule_899(value : Json) -> Bool {
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
    if !wire_rule_899(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_900(value : Json) -> Bool {
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
    if !wire_rule_900(item) {
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
fn wire_rule_906(value : Json) -> Bool {
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
    if !wire_rule_906(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_908(value : Json) -> Bool {
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
    if !wire_rule_908(item) {
      return false
    }
  }
  if fields.get("revision") is Some(item) {
    if !wire_rule_906(item) {
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
fn wire_rule_911(value : Json) -> Bool {
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
    if !wire_rule_894(item) {
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
fn wire_rule_914(value : Json) -> Bool {
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
    if !wire_rule_900(item) {
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
  if [wire_rule_911(value), wire_rule_914(value)].filter(fn(ok) { ok }).length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_rule_917(value : Json) -> Bool {
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
    if !wire_rule_917(item) {
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
fn wire_rule_920(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "accepted") {
    return false
  }
  true
}

///|
fn wire_rule_922(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "cancel") {
    return false
  }
  true
}

///|
fn wire_rule_921(value : Json) -> Bool {
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
    if !wire_rule_922(item) {
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
fn wire_rule_924(value : Json) -> Bool {
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
    if !wire_rule_920(item) {
      return false
    }
  }
  if fields.get("revision") is Some(item) {
    if !wire_rule_906(item) {
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
fn wire_rule_919(value : Json) -> Bool {
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
    if !wire_rule_920(item) {
      return false
    }
  }
  if fields.get("attemptRef") is Some(item) {
    if !wire_rule_921(item) {
      return false
    }
  }
  if fields.get("cancellation") is Some(item) {
    if !wire_rule_924(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_934(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "already_requested" || text == "already_terminal") {
    return false
  }
  true
}

///|
fn wire_rule_932(value : Json) -> Bool {
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
    if !wire_rule_934(item) {
      return false
    }
  }
  if fields.get("revision") is Some(item) {
    if !wire_rule_906(item) {
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
fn wire_rule_929(value : Json) -> Bool {
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
    if !wire_rule_815(item) {
      return false
    }
  }
  if fields.get("attemptRef") is Some(item) {
    if !wire_rule_921(item) {
      return false
    }
  }
  if fields.get("cancellation") is Some(item) {
    if !wire_rule_932(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_941(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "authorization" || text == "admission_capacity") {
    return false
  }
  true
}

///|
fn wire_rule_937(value : Json) -> Bool {
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
    if !wire_rule_826(item) {
      return false
    }
  }
  if fields.get("attemptRef") is Some(item) {
    if !wire_rule_921(item) {
      return false
    }
  }
  if fields.get("guarantee") is Some(item) {
    if !wire_rule_828(item) {
      return false
    }
  }
  if fields.get("reason") is Some(item) {
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
fn wire_rule_946(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "intent" || text == "control_revision") {
    return false
  }
  true
}

///|
fn wire_rule_943(value : Json) -> Bool {
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
    if !wire_rule_838(item) {
      return false
    }
  }
  if fields.get("attemptRef") is Some(item) {
    if !wire_rule_921(item) {
      return false
    }
  }
  if fields.get("reason") is Some(item) {
    if !wire_rule_946(item) {
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
      wire_rule_919(value),
      wire_rule_929(value),
      wire_rule_937(value),
      wire_rule_943(value),
    ]
    .filter(fn(ok) { ok })
    .length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_rule_934(value : Json) -> Bool {
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
    if !wire_rule_934(item) {
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
fn wire_rule_938(value : Json) -> Bool {
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
    if !wire_rule_938(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_940(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "non_atomic") {
    return false
  }
  true
}

///|
fn wire_rule_941(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "owner_local") {
    return false
  }
  true
}

///|
fn wire_rule_946(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "unavailable") {
    return false
  }
  true
}

///|
fn wire_rule_948(value : Json) -> Bool {
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
fn wire_rule_947(value : Json) -> Bool {
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
    if !wire_rule_948(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_944(value : Json) -> Bool {
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
    if !wire_rule_934(item) {
      return false
    }
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_946(item) {
      return false
    }
  }
  if fields.get("problem") is Some(item) {
    if !wire_rule_947(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_950(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "run") {
    return false
  }
  true
}

///|
fn wire_rule_952(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "observed") {
    return false
  }
  true
}

///|
fn wire_rule_955(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "not_provided") {
    return false
  }
  true
}

///|
fn wire_rule_954(value : Json) -> Bool {
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
    if !wire_rule_955(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_957(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "retention_expired") {
    return false
  }
  true
}

///|
fn wire_rule_956(value : Json) -> Bool {
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
    if !wire_rule_957(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_959(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "history_unrecoverable") {
    return false
  }
  true
}

///|
fn wire_rule_958(value : Json) -> Bool {
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
    if !wire_rule_959(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_961(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "cursor_mismatch") {
    return false
  }
  true
}

///|
fn wire_rule_960(value : Json) -> Bool {
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
    if !wire_rule_961(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_963(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "cursor_expired") {
    return false
  }
  true
}

///|
fn wire_rule_962(value : Json) -> Bool {
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
    if !wire_rule_963(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_965(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "limit_exceeded") {
    return false
  }
  true
}

///|
fn wire_rule_964(value : Json) -> Bool {
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
    if !wire_rule_965(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_967(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "acquisition_failed") {
    return false
  }
  true
}

///|
fn wire_rule_966(value : Json) -> Bool {
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
    if !wire_rule_967(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_969(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "page") {
    return false
  }
  true
}

///|
fn wire_rule_974(value : Json) -> Bool {
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
fn wire_rule_971(value : Json) -> Bool {
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
    if !wire_rule_974(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_970(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  if items.length() > 1000 {
    return false
  }
  for item in items {
    if !wire_rule_971(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_968(value : Json) -> Bool {
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
    if !wire_rule_969(item) {
      return false
    }
  }
  if fields.get("entries") is Some(item) {
    if !wire_rule_970(item) {
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
fn wire_rule_953(value : Json) -> Bool {
  if [
      wire_rule_954(value),
      wire_rule_956(value),
      wire_rule_958(value),
      wire_rule_960(value),
      wire_rule_962(value),
      wire_rule_964(value),
      wire_rule_966(value),
      wire_rule_968(value),
    ]
    .filter(fn(ok) { ok })
    .length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_rule_982(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "waiting_checkpoint") {
    return false
  }
  true
}

///|
fn wire_rule_981(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("status") {
    return false
  }
  if fields.get("status") is Some(item) {
    if !wire_rule_982(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_985(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "resolve_checkpoint") {
    return false
  }
  true
}

///|
fn wire_rule_984(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("kind") {
    return false
  }
  if !fields.contains("checkpoint_id") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_985(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_983(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("checkpoint") {
    return false
  }
  if fields.get("next_action") is Some(item) {
    if !wire_rule_984(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_980(value : Json) -> Bool {
  if wire_rule_981(value) && !wire_rule_983(value) {
    return false
  }
  true
}

///|
fn wire_rule_988(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "needs_reconciliation") {
    return false
  }
  true
}

///|
fn wire_rule_987(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("status") {
    return false
  }
  if fields.get("status") is Some(item) {
    if !wire_rule_988(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_990(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("checkpoint") {
    return false
  }
  true
}

///|
fn wire_rule_993(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "reconcile") {
    return false
  }
  true
}

///|
fn wire_rule_994(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  if items.length() < 1 {
    return false
  }
  for item in items {
    if !wire_rule_653(item) {
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
fn wire_rule_992(value : Json) -> Bool {
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
    if !wire_rule_993(item) {
      return false
    }
  }
  if fields.get("effects") is Some(item) {
    if !wire_rule_994(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_997(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "reconcile_run") {
    return false
  }
  true
}

///|
fn wire_rule_998(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "execution_unknown") {
    return false
  }
  true
}

///|
fn wire_rule_996(value : Json) -> Bool {
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
    if !wire_rule_997(item) {
      return false
    }
  }
  if fields.get("reason") is Some(item) {
    if !wire_rule_998(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_991(value : Json) -> Bool {
  if [wire_rule_992(value), wire_rule_996(value)].filter(fn(ok) { ok }).length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_rule_989(value : Json) -> Bool {
  if wire_rule_990(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  if fields.get("next_action") is Some(item) {
    if !wire_rule_991(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_986(value : Json) -> Bool {
  if wire_rule_987(value) && !wire_rule_989(value) {
    return false
  }
  true
}

///|
fn wire_rule_1001(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "succeeded") {
    return false
  }
  true
}

///|
fn wire_rule_1000(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("status") {
    return false
  }
  if fields.get("status") is Some(item) {
    if !wire_rule_1001(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1005(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "read_result" || text == "refresh_availability" || text == "none") {
    return false
  }
  true
}

///|
fn wire_rule_1004(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("kind") {
    return false
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_1005(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1002(value : Json) -> Bool {
  if wire_rule_990(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  if fields.get("next_action") is Some(item) {
    if !wire_rule_1004(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_999(value : Json) -> Bool {
  if wire_rule_1000(value) && !wire_rule_1002(value) {
    return false
  }
  true
}

///|
fn wire_rule_1008(value : Json) -> Bool {
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
fn wire_rule_1007(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("status") {
    return false
  }
  if fields.get("status") is Some(item) {
    if !wire_rule_1008(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1012(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "none") {
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
  if fields.get("kind") is Some(item) {
    if !wire_rule_1012(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1009(value : Json) -> Bool {
  if wire_rule_990(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  if fields.get("next_action") is Some(item) {
    if !wire_rule_1011(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1006(value : Json) -> Bool {
  if wire_rule_1007(value) && !wire_rule_1009(value) {
    return false
  }
  true
}

///|
fn wire_rule_1015(_value : Json) -> Bool {
  true
}

///|
fn wire_rule_1014(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("result_availability") {
    return false
  }
  if fields.get("result_availability") is Some(item) {
    if !wire_rule_1015(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1019(value : Json) -> Bool {
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
fn wire_rule_1018(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("kind") is Some(item) {
    if !wire_rule_1019(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1016(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("result_available") is Some(item) {
    if !wire_rule_640(item) {
      return false
    }
  }
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
fn wire_rule_1020(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "actql-run-state/0.1") {
    return false
  }
  true
}

///|
fn wire_rule_1022(value : Json) -> Bool {
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
fn wire_rule_1023(value : Json) -> Bool {
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
fn wire_rule_1027(value : Json) -> Bool {
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
fn wire_rule_1024(value : Json) -> Bool {
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
    if !wire_rule_653(item) {
      return false
    }
  }
  if fields.get("checkpoint_cid") is Some(item) {
    if !wire_rule_732(item) {
      return false
    }
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_1027(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1029(value : Json) -> Bool {
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
    if !wire_rule_985(item) {
      return false
    }
  }
  if fields.get("checkpoint_id") is Some(item) {
    if !wire_rule_653(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1034(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "read_result") {
    return false
  }
  true
}

///|
fn wire_rule_1033(value : Json) -> Bool {
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
    if !wire_rule_1034(item) {
      return false
    }
  }
  if fields.get("results") is Some(item) {
    if !wire_rule_994(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1037(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "refresh_availability") {
    return false
  }
  true
}

///|
fn wire_rule_1036(value : Json) -> Bool {
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
    if !wire_rule_1037(item) {
      return false
    }
  }
  if fields.get("results") is Some(item) {
    if !wire_rule_994(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1039(value : Json) -> Bool {
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
    if !wire_rule_1012(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1028(value : Json) -> Bool {
  if [
      wire_rule_1029(value),
      wire_rule_992(value),
      wire_rule_1033(value),
      wire_rule_1036(value),
      wire_rule_1039(value),
      wire_rule_996(value),
    ]
    .filter(fn(ok) { ok })
    .length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_rule_1044(value : Json) -> Bool {
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
fn wire_rule_1043(value : Json) -> Bool {
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
    if !wire_rule_1044(item) {
      return false
    }
  }
  if fields.get("message") is Some(item) {
    if !wire_rule_653(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1050(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "available") {
    return false
  }
  true
}

///|
fn wire_rule_1049(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("state") {
    return false
  }
  if fields.get("state") is Some(item) {
    if !wire_rule_1050(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1052(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "confirmed_present") {
    return false
  }
  true
}

///|
fn wire_rule_1051(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("reason") is Some(item) {
    if !wire_rule_1052(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1048(value : Json) -> Bool {
  if wire_rule_1049(value) && !wire_rule_1051(value) {
    return false
  }
  true
}

///|
fn wire_rule_1054(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("state") {
    return false
  }
  if fields.get("state") is Some(item) {
    if !wire_rule_756(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1057(value : Json) -> Bool {
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
fn wire_rule_1056(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("reason") is Some(item) {
    if !wire_rule_1057(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1053(value : Json) -> Bool {
  if wire_rule_1054(value) && !wire_rule_1056(value) {
    return false
  }
  true
}

///|
fn wire_rule_1060(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "unknown") {
    return false
  }
  true
}

///|
fn wire_rule_1059(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("state") {
    return false
  }
  if fields.get("state") is Some(item) {
    if !wire_rule_1060(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1062(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "store_query_failed" ||
    text == "clock_uncertain" ||
    text == "verification_pending") {
    return false
  }
  true
}

///|
fn wire_rule_1061(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("reason") is Some(item) {
    if !wire_rule_1062(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1058(value : Json) -> Bool {
  if wire_rule_1059(value) && !wire_rule_1061(value) {
    return false
  }
  true
}

///|
fn wire_rule_1063(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "available" || text == "unavailable" || text == "unknown") {
    return false
  }
  true
}

///|
fn wire_rule_1065(value : Json) -> Bool {
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
fn wire_rule_1047(value : Json) -> Bool {
  if !wire_rule_1048(value) {
    return false
  }
  if !wire_rule_1053(value) {
    return false
  }
  if !wire_rule_1058(value) {
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
    if !wire_rule_1063(item) {
      return false
    }
  }
  if fields.get("observed_at") is Some(item) {
    if !wire_rule_1023(item) {
      return false
    }
  }
  if fields.get("reason") is Some(item) {
    if !wire_rule_1065(item) {
      return false
    }
  }
  if fields.get("cause_cid") is Some(item) {
    if !wire_rule_732(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1068(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if text.iter().count() < 1 {
    return false
  }
  true
}

///|
fn wire_rule_1067(value : Json) -> Bool {
  if value is String(_) {
    return wire_rule_1068(value)
  }
  true
}

///|
fn wire_rule_1046(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for _key, item in fields {
    if !false && !wire_rule_1047(item) {
      return false
    }
  }
  for key, _ in fields {
    if !wire_rule_1067(Json::string(key)) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1070(value : Json) -> Bool {
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
fn wire_rule_1072(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "unknown" || text == "confirmed") {
    return false
  }
  true
}

///|
fn wire_rule_1069(value : Json) -> Bool {
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
    if !wire_rule_1070(item) {
      return false
    }
  }
  if fields.get("cancellation_requested") is Some(item) {
    if !wire_rule_620(item) {
      return false
    }
  }
  if fields.get("physical_stop") is Some(item) {
    if !wire_rule_1072(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_979(value : Json) -> Bool {
  if !wire_rule_980(value) {
    return false
  }
  if !wire_rule_986(value) {
    return false
  }
  if !wire_rule_999(value) {
    return false
  }
  if !wire_rule_1006(value) {
    return false
  }
  if !wire_rule_1013(value) {
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
    if !wire_rule_1020(item) {
      return false
    }
  }
  if fields.get("run_id") is Some(item) {
    if !wire_rule_653(item) {
      return false
    }
  }
  if fields.get("status") is Some(item) {
    if !wire_rule_1022(item) {
      return false
    }
  }
  if fields.get("updated_at") is Some(item) {
    if !wire_rule_1023(item) {
      return false
    }
  }
  if fields.get("checkpoint") is Some(item) {
    if !wire_rule_1024(item) {
      return false
    }
  }
  if fields.get("next_action") is Some(item) {
    if !wire_rule_1028(item) {
      return false
    }
  }
  if fields.get("result_available") is Some(item) {
    if !wire_rule_620(item) {
      return false
    }
  }
  if fields.get("terminal_error") is Some(item) {
    if !wire_rule_1043(item) {
      return false
    }
  }
  if fields.get("result_availability") is Some(item) {
    if !wire_rule_1046(item) {
      return false
    }
  }
  if fields.get("control") is Some(item) {
    if !wire_rule_1069(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_978(value : Json) -> Bool {
  if !wire_rule_979(value) {
    return false
  }
  true
}

///|
fn wire_rule_976(value : Json) -> Bool {
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
    if !wire_rule_978(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_949(value : Json) -> Bool {
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
    if !wire_rule_950(item) {
      return false
    }
  }
  if fields.get("ownerRef") is Some(item) {
    if !wire_owner_ref_shape(item) {
      return false
    }
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_952(item) {
      return false
    }
  }
  if fields.get("history") is Some(item) {
    if !wire_rule_953(item) {
      return false
    }
  }
  if fields.get("snapshot") is Some(item) {
    if !wire_rule_976(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1079(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "limit_exceeded" || text == "acquisition_failed") {
    return false
  }
  true
}

///|
fn wire_rule_1078(value : Json) -> Bool {
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
    if !wire_rule_1079(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1073(value : Json) -> Bool {
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
    if !wire_rule_950(item) {
      return false
    }
  }
  if fields.get("ownerRef") is Some(item) {
    if !wire_owner_ref_shape(item) {
      return false
    }
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_952(item) {
      return false
    }
  }
  if fields.get("history") is Some(item) {
    if !wire_rule_953(item) {
      return false
    }
  }
  if fields.get("snapshotProblem") is Some(item) {
    if !wire_rule_1078(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1081(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "effect") {
    return false
  }
  true
}

///|
fn wire_rule_1087(value : Json) -> Bool {
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
    if !wire_rule_974(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1085(value : Json) -> Bool {
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
    if !wire_rule_1087(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1080(value : Json) -> Bool {
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
    if !wire_rule_1081(item) {
      return false
    }
  }
  if fields.get("ownerRef") is Some(item) {
    if !wire_owner_ref_shape(item) {
      return false
    }
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_952(item) {
      return false
    }
  }
  if fields.get("history") is Some(item) {
    if !wire_rule_953(item) {
      return false
    }
  }
  if fields.get("snapshot") is Some(item) {
    if !wire_rule_1085(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1089(value : Json) -> Bool {
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
    if !wire_rule_1081(item) {
      return false
    }
  }
  if fields.get("ownerRef") is Some(item) {
    if !wire_owner_ref_shape(item) {
      return false
    }
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_952(item) {
      return false
    }
  }
  if fields.get("history") is Some(item) {
    if !wire_rule_953(item) {
      return false
    }
  }
  if fields.get("snapshotProblem") is Some(item) {
    if !wire_rule_1078(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_943(value : Json) -> Bool {
  if [
      wire_rule_944(value),
      wire_rule_949(value),
      wire_rule_1073(value),
      wire_rule_1080(value),
      wire_rule_1089(value),
    ]
    .filter(fn(ok) { ok })
    .length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_rule_942(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  if items.length() > 5 {
    return false
  }
  for item in items {
    if !wire_rule_943(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1100(value : Json) -> Bool {
  guard value is Null else { return false }
  true
}

///|
fn wire_rule_1101(value : Json) -> Bool {
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
fn wire_rule_1099(value : Json) -> Bool {
  if [wire_rule_1100(value), wire_rule_1101(value)]
    .filter(fn(ok) { ok })
    .length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_rule_1096(value : Json) -> Bool {
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
    if !wire_rule_1099(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1095(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  if items.length() > 5 {
    return false
  }
  for item in items {
    if !wire_rule_1096(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1107(value : Json) -> Bool {
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
fn wire_rule_1106(value : Json) -> Bool {
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
    if !wire_rule_1107(item) {
      return false
    }
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_946(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1105(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  if items.length() > 5 {
    return false
  }
  for item in items {
    if !wire_rule_1106(item) {
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
    if !wire_rule_940(item) {
      return false
    }
  }
  if fields.get("ordering") is Some(item) {
    if !wire_rule_941(item) {
      return false
    }
  }
  if fields.get("owners") is Some(item) {
    if !wire_rule_942(item) {
      return false
    }
  }
  if fields.get("revisionVector") is Some(item) {
    if !wire_rule_1095(item) {
      return false
    }
  }
  if fields.get("unmatchedCursors") is Some(item) {
    if !wire_rule_1105(item) {
      return false
    }
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
