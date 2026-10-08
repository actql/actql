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
fn wire_rule_66(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "completed") {
    return false
  }
  true
}

///|
fn wire_rule_70(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "verified") {
    return false
  }
  true
}

///|
fn wire_rule_69(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("verdict") is Some(item) {
    if !wire_rule_70(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_72(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("omissions") {
    return false
  }
  true
}

///|
fn wire_rule_74(_value : Json) -> Bool {
  true
}

///|
fn wire_rule_73(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  if items.length() > 0 {
    return false
  }
  for item in items {
    if !wire_rule_74(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_76(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("limits") is Some(item) {
    if !wire_rule_73(item) {
      return false
    }
  }
  if fields.get("unresolved") is Some(item) {
    if !wire_rule_73(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_71(value : Json) -> Bool {
  if wire_rule_72(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  if fields.get("reasons") is Some(item) {
    if !wire_rule_73(item) {
      return false
    }
  }
  if fields.get("requirements") is Some(item) {
    if !wire_rule_73(item) {
      return false
    }
  }
  if fields.get("coverage") is Some(item) {
    if !wire_rule_76(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_68(value : Json) -> Bool {
  if wire_rule_69(value) && !wire_rule_71(value) {
    return false
  }
  true
}

///|
fn wire_rule_81(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "invalid") {
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
fn wire_rule_83(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  if items.length() < 1 {
    return false
  }
  for item in items {
    if !wire_rule_74(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_82(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("reasons") is Some(item) {
    if !wire_rule_83(item) {
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
fn wire_rule_87(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "undetermined") {
    return false
  }
  true
}

///|
fn wire_rule_86(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("verdict") is Some(item) {
    if !wire_rule_87(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_90(value : Json) -> Bool {
  if wire_rule_76(value) {
    return false
  }
  true
}

///|
fn wire_rule_88(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("reasons") is Some(item) {
    if !wire_rule_73(item) {
      return false
    }
  }
  if fields.get("coverage") is Some(item) {
    if !wire_rule_90(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_85(value : Json) -> Bool {
  if wire_rule_86(value) && !wire_rule_88(value) {
    return false
  }
  true
}

///|
fn wire_rule_92(value : Json) -> Bool {
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
fn wire_rule_94(value : Json) -> Bool {
  if !(value is True || value is False) {
    return false
  }
  if !(value is True) {
    return false
  }
  true
}

///|
fn wire_rule_93(value : Json) -> Bool {
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
    if !wire_rule_94(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_97(value : Json) -> Bool {
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
fn wire_rule_98(value : Json) -> Bool {
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
fn wire_rule_99(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "text" || text == "structured") {
    return false
  }
  true
}

///|
fn wire_rule_100(value : Json) -> Bool {
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
fn wire_rule_96(value : Json) -> Bool {
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
    if !wire_rule_97(item) {
      return false
    }
  }
  if fields.get("revision") is Some(item) {
    if !wire_rule_98(item) {
      return false
    }
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_99(item) {
      return false
    }
  }
  if fields.get("byte_length") is Some(item) {
    if !wire_rule_100(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_95(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  if items.length() < 1 {
    return false
  }
  if items.length() > 3 {
    return false
  }
  for item in items {
    if !wire_rule_96(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_105(value : Json) -> Bool {
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
fn wire_rule_104(value : Json) -> Bool {
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
    if !wire_rule_105(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_107(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "implementation_limit" || text == "analysis_budget_exhausted") {
    return false
  }
  true
}

///|
fn wire_rule_109(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "structured") {
    return false
  }
  true
}

///|
fn wire_rule_110(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "program") {
    return false
  }
  true
}

///|
fn wire_rule_112(value : Json) -> Bool {
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
fn wire_rule_108(value : Json) -> Bool {
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
    if !wire_rule_109(item) {
      return false
    }
  }
  if fields.get("document_id") is Some(item) {
    if !wire_rule_110(item) {
      return false
    }
  }
  if fields.get("revision") is Some(item) {
    if !wire_rule_98(item) {
      return false
    }
  }
  if fields.get("pointer") is Some(item) {
    if !wire_rule_112(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_106(value : Json) -> Bool {
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
    if !wire_rule_107(item) {
      return false
    }
  }
  if fields.get("location") is Some(item) {
    if !wire_rule_108(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_114(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "implementation_limit") {
    return false
  }
  true
}

///|
fn wire_rule_116(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "function_lowering_unresolved") {
    return false
  }
  true
}

///|
fn wire_rule_115(value : Json) -> Bool {
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
    if !wire_rule_116(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_118(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "text") {
    return false
  }
  true
}

///|
fn wire_rule_119(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "source") {
    return false
  }
  true
}

///|
fn wire_rule_121(value : Json) -> Bool {
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
fn wire_rule_123(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "exact" || text == "approximate") {
    return false
  }
  true
}

///|
fn wire_rule_117(value : Json) -> Bool {
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
    if !wire_rule_118(item) {
      return false
    }
  }
  if fields.get("document_id") is Some(item) {
    if !wire_rule_119(item) {
      return false
    }
  }
  if fields.get("revision") is Some(item) {
    if !wire_rule_98(item) {
      return false
    }
  }
  if fields.get("start_byte") is Some(item) {
    if !wire_rule_121(item) {
      return false
    }
  }
  if fields.get("end_byte") is Some(item) {
    if !wire_rule_121(item) {
      return false
    }
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_123(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_113(value : Json) -> Bool {
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
    if !wire_rule_114(item) {
      return false
    }
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_115(item) {
      return false
    }
  }
  if fields.get("location") is Some(item) {
    if !wire_rule_117(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_103(value : Json) -> Bool {
  if [wire_rule_104(value), wire_rule_106(value), wire_rule_113(value)]
    .filter(fn(ok) { ok })
    .length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_rule_102(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  for item in items {
    if !wire_rule_103(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_127(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "unresolved_protected") {
    return false
  }
  true
}

///|
fn wire_rule_125(value : Json) -> Bool {
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
    if !wire_rule_105(item) {
      return false
    }
  }
  if fields.get("reason") is Some(item) {
    if !wire_rule_127(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_124(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  for item in items {
    if !wire_rule_125(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_101(value : Json) -> Bool {
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
    if !wire_rule_102(item) {
      return false
    }
  }
  if fields.get("unresolved") is Some(item) {
    if !wire_rule_124(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_132(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "program_structure_invalid") {
    return false
  }
  true
}

///|
fn wire_rule_131(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_132(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_134(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("fixes") {
    return false
  }
  true
}

///|
fn wire_rule_136(value : Json) -> Bool {
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
fn wire_rule_135(value : Json) -> Bool {
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
    if !wire_rule_136(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_137(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("kind") is Some(item) {
    if !wire_rule_109(item) {
      return false
    }
  }
  if fields.get("document_id") is Some(item) {
    if !wire_rule_110(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_133(value : Json) -> Bool {
  if wire_rule_134(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  if !fields.contains("facts") {
    return false
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_135(item) {
      return false
    }
  }
  if fields.get("location") is Some(item) {
    if !wire_rule_137(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_130(value : Json) -> Bool {
  if wire_rule_131(value) && !wire_rule_133(value) {
    return false
  }
  true
}

///|
fn wire_rule_142(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "numeric_reduction_profile_required") {
    return false
  }
  true
}

///|
fn wire_rule_141(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_142(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_145(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("location") {
    return false
  }
  true
}

///|
fn wire_rule_144(value : Json) -> Bool {
  if wire_rule_145(value) {
    return false
  }
  true
}

///|
fn wire_rule_146(value : Json) -> Bool {
  if wire_rule_134(value) {
    return false
  }
  true
}

///|
fn wire_rule_149(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text ==
    "sha256:d771391b2e4f3e52a3cf48810571a09c6c272df64fbb77c245dfabcf456be5df") {
    return false
  }
  true
}

///|
fn wire_rule_150(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "checking_context_owner") {
    return false
  }
  true
}

///|
fn wire_rule_151(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "checking") {
    return false
  }
  true
}

///|
fn wire_rule_148(value : Json) -> Bool {
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
    if !wire_rule_149(item) {
      return false
    }
  }
  if fields.get("supplier") is Some(item) {
    if !wire_rule_150(item) {
      return false
    }
  }
  if fields.get("stage") is Some(item) {
    if !wire_rule_151(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_143(value : Json) -> Bool {
  if !wire_rule_144(value) {
    return false
  }
  if !wire_rule_146(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  if !fields.contains("facts") {
    return false
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_148(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_140(value : Json) -> Bool {
  if wire_rule_141(value) && !wire_rule_143(value) {
    return false
  }
  true
}

///|
fn wire_rule_154(value : Json) -> Bool {
  if wire_rule_142(value) {
    return false
  }
  true
}

///|
fn wire_rule_153(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_154(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_158(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("profile_cid") {
    return false
  }
  true
}

///|
fn wire_rule_157(value : Json) -> Bool {
  if wire_rule_158(value) {
    return false
  }
  true
}

///|
fn wire_rule_156(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("facts") is Some(item) {
    if !wire_rule_157(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_152(value : Json) -> Bool {
  if wire_rule_153(value) && !wire_rule_156(value) {
    return false
  }
  true
}

///|
fn wire_rule_161(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "host_capacity_policy_required") {
    return false
  }
  true
}

///|
fn wire_rule_160(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_161(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_166(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text ==
    "sha256:5de69acac624586723a7efad500d0caf13c21ad2ed6e2252df0aaacf32dfc164") {
    return false
  }
  true
}

///|
fn wire_rule_167(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text ==
    "sha256:f23dbd7096c73975276d79dc163c8b3ae7dbae662ade242a3f1789cf07b854f3") {
    return false
  }
  true
}

///|
fn wire_rule_168(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "/schema") {
    return false
  }
  true
}

///|
fn wire_rule_165(value : Json) -> Bool {
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
    if !wire_rule_166(item) {
      return false
    }
  }
  if fields.get("schema_cid") is Some(item) {
    if !wire_rule_167(item) {
      return false
    }
  }
  if fields.get("schema_pointer") is Some(item) {
    if !wire_rule_168(item) {
      return false
    }
  }
  if fields.get("supplier") is Some(item) {
    if !wire_rule_150(item) {
      return false
    }
  }
  if fields.get("stage") is Some(item) {
    if !wire_rule_151(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_162(value : Json) -> Bool {
  if !wire_rule_144(value) {
    return false
  }
  if !wire_rule_146(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  if !fields.contains("facts") {
    return false
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_165(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_159(value : Json) -> Bool {
  if wire_rule_160(value) && !wire_rule_162(value) {
    return false
  }
  true
}

///|
fn wire_rule_173(value : Json) -> Bool {
  if wire_rule_161(value) {
    return false
  }
  true
}

///|
fn wire_rule_172(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_173(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_177(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("schema_pointer") {
    return false
  }
  true
}

///|
fn wire_rule_176(value : Json) -> Bool {
  if wire_rule_177(value) {
    return false
  }
  true
}

///|
fn wire_rule_175(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("facts") is Some(item) {
    if !wire_rule_176(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_171(value : Json) -> Bool {
  if wire_rule_172(value) && !wire_rule_175(value) {
    return false
  }
  true
}

///|
fn wire_rule_179(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_114(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_182(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("issue") {
    return false
  }
  if fields.get("issue") is Some(item) {
    if !wire_rule_116(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_186(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "source" || text == "program") {
    return false
  }
  true
}

///|
fn wire_rule_184(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("kind") is Some(item) {
    if !wire_rule_99(item) {
      return false
    }
  }
  if fields.get("document_id") is Some(item) {
    if !wire_rule_186(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_181(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("facts") is Some(item) {
    if !wire_rule_182(item) {
      return false
    }
  }
  if fields.get("location") is Some(item) {
    if !wire_rule_184(item) {
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
fn wire_rule_190(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "parameter_value_required") {
    return false
  }
  true
}

///|
fn wire_rule_189(value : Json) -> Bool {
  if wire_rule_190(value) {
    return false
  }
  true
}

///|
fn wire_rule_188(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_189(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_193(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("admission") {
    return false
  }
  true
}

///|
fn wire_rule_192(value : Json) -> Bool {
  if wire_rule_193(value) {
    return false
  }
  true
}

///|
fn wire_rule_191(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("facts") is Some(item) {
    if !wire_rule_192(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_187(value : Json) -> Bool {
  if wire_rule_188(value) && !wire_rule_191(value) {
    return false
  }
  true
}

///|
fn wire_rule_197(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "query_lexical_invalid") {
    return false
  }
  true
}

///|
fn wire_rule_199(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "unterminated_comment") {
    return false
  }
  true
}

///|
fn wire_rule_198(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("issue") is Some(item) {
    if !wire_rule_199(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_202(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "exact") {
    return false
  }
  true
}

///|
fn wire_rule_200(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("kind") is Some(item) {
    if !wire_rule_118(item) {
      return false
    }
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_202(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_196(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("facts") {
    return false
  }
  if !fields.contains("location") {
    return false
  }
  if fields.get("code") is Some(item) {
    if !wire_rule_197(item) {
      return false
    }
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_198(item) {
      return false
    }
  }
  if fields.get("location") is Some(item) {
    if !wire_rule_200(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_194(value : Json) -> Bool {
  if wire_rule_134(value) && !wire_rule_196(value) {
    return false
  }
  true
}

///|
fn wire_rule_205(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "query_syntax_invalid" || text == "parameter_undeclared") {
    return false
  }
  true
}

///|
fn wire_rule_204(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_205(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_207(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("kind") is Some(item) {
    if !wire_rule_118(item) {
      return false
    }
  }
  if fields.get("document_id") is Some(item) {
    if !wire_rule_119(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_206(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("location") is Some(item) {
    if !wire_rule_207(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_203(value : Json) -> Bool {
  if wire_rule_204(value) && !wire_rule_206(value) {
    return false
  }
  true
}

///|
fn wire_rule_212(value : Json) -> Bool {
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
fn wire_rule_211(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_212(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_216(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "parameters") {
    return false
  }
  true
}

///|
fn wire_rule_214(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("kind") is Some(item) {
    if !wire_rule_109(item) {
      return false
    }
  }
  if fields.get("document_id") is Some(item) {
    if !wire_rule_216(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_213(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("location") is Some(item) {
    if !wire_rule_214(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_210(value : Json) -> Bool {
  if wire_rule_211(value) && !wire_rule_213(value) {
    return false
  }
  true
}

///|
fn wire_rule_219(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "parameter_declarations_invalid" ||
    text == "parameter_value_required") {
    return false
  }
  true
}

///|
fn wire_rule_218(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_219(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_223(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "parameter_declarations" || text == "program") {
    return false
  }
  true
}

///|
fn wire_rule_221(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("kind") is Some(item) {
    if !wire_rule_109(item) {
      return false
    }
  }
  if fields.get("document_id") is Some(item) {
    if !wire_rule_223(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_220(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("location") is Some(item) {
    if !wire_rule_221(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_217(value : Json) -> Bool {
  if wire_rule_218(value) && !wire_rule_220(value) {
    return false
  }
  true
}

///|
fn wire_rule_226(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "supplied_value_type_mismatch") {
    return false
  }
  true
}

///|
fn wire_rule_225(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_226(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_228(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("actual_type") {
    return false
  }
  true
}

///|
fn wire_rule_227(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("facts") {
    return false
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_228(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_224(value : Json) -> Bool {
  if wire_rule_225(value) && !wire_rule_227(value) {
    return false
  }
  true
}

///|
fn wire_rule_231(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "parameter_default_type_mismatch") {
    return false
  }
  true
}

///|
fn wire_rule_230(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_231(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_232(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("facts") {
    return false
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_228(item) {
      return false
    }
  }
  if fields.get("location") is Some(item) {
    if !wire_rule_221(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_229(value : Json) -> Bool {
  if wire_rule_230(value) && !wire_rule_232(value) {
    return false
  }
  true
}

///|
fn wire_rule_237(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "parameter_undeclared") {
    return false
  }
  true
}

///|
fn wire_rule_236(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_237(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_241(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("expected_type") {
    return false
  }
  true
}

///|
fn wire_rule_240(value : Json) -> Bool {
  if wire_rule_241(value) {
    return false
  }
  true
}

///|
fn wire_rule_243(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("constraint") {
    return false
  }
  true
}

///|
fn wire_rule_242(value : Json) -> Bool {
  if wire_rule_243(value) {
    return false
  }
  true
}

///|
fn wire_rule_245(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("domain") {
    return false
  }
  true
}

///|
fn wire_rule_244(value : Json) -> Bool {
  if wire_rule_245(value) {
    return false
  }
  true
}

///|
fn wire_rule_239(value : Json) -> Bool {
  if !wire_rule_240(value) {
    return false
  }
  if !wire_rule_242(value) {
    return false
  }
  if !wire_rule_244(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  if !fields.contains("parameter") {
    return false
  }
  true
}

///|
fn wire_rule_238(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("facts") {
    return false
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_239(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_235(value : Json) -> Bool {
  if wire_rule_236(value) && !wire_rule_238(value) {
    return false
  }
  true
}

///|
fn wire_rule_247(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_190(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_250(value : Json) -> Bool {
  if wire_rule_228(value) {
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
fn wire_rule_249(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("facts") {
    return false
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_250(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_246(value : Json) -> Bool {
  if wire_rule_247(value) && !wire_rule_249(value) {
    return false
  }
  true
}

///|
fn wire_rule_254(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "parameter_unused") {
    return false
  }
  true
}

///|
fn wire_rule_253(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_254(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_257(value : Json) -> Bool {
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
fn wire_rule_256(value : Json) -> Bool {
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
    if !wire_rule_257(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_255(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("facts") {
    return false
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_256(item) {
      return false
    }
  }
  if fields.get("location") is Some(item) {
    if !wire_rule_221(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_252(value : Json) -> Bool {
  if wire_rule_253(value) && !wire_rule_255(value) {
    return false
  }
  true
}

///|
fn wire_rule_261(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "supplied_value_constraint_violation") {
    return false
  }
  true
}

///|
fn wire_rule_260(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_261(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_262(value : Json) -> Bool {
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
fn wire_rule_259(value : Json) -> Bool {
  if wire_rule_260(value) && !wire_rule_262(value) {
    return false
  }
  true
}

///|
fn wire_rule_266(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "expression_type_mismatch") {
    return false
  }
  true
}

///|
fn wire_rule_265(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_266(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_269(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "number" || text == "boolean" || text == "string") {
    return false
  }
  true
}

///|
fn wire_rule_268(value : Json) -> Bool {
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
    if !wire_rule_269(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_267(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("facts") {
    return false
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_268(item) {
      return false
    }
  }
  if fields.get("location") is Some(item) {
    if !wire_rule_184(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_264(value : Json) -> Bool {
  if wire_rule_265(value) && !wire_rule_267(value) {
    return false
  }
  true
}

///|
fn wire_rule_273(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "operation_parameter_invalid") {
    return false
  }
  true
}

///|
fn wire_rule_272(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_273(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_278(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "parameters" || text == "parameter_declarations") {
    return false
  }
  true
}

///|
fn wire_rule_276(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("kind") is Some(item) {
    if !wire_rule_109(item) {
      return false
    }
  }
  if fields.get("document_id") is Some(item) {
    if !wire_rule_278(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_274(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("facts") {
    return false
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_245(item) {
      return false
    }
  }
  if fields.get("location") is Some(item) {
    if !wire_rule_276(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_271(value : Json) -> Bool {
  if wire_rule_272(value) && !wire_rule_274(value) {
    return false
  }
  true
}

///|
fn wire_rule_281(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "binding_json_invalid") {
    return false
  }
  true
}

///|
fn wire_rule_280(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_281(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_285(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("document") is Some(item) {
    if !wire_rule_216(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_284(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("facts") is Some(item) {
    if !wire_rule_285(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_288(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("document_id") is Some(item) {
    if !wire_rule_216(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_287(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("location") is Some(item) {
    if !wire_rule_288(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_283(value : Json) -> Bool {
  if wire_rule_284(value) && !wire_rule_287(value) {
    return false
  }
  true
}

///|
fn wire_rule_293(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "parameter_declarations") {
    return false
  }
  true
}

///|
fn wire_rule_292(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("document") is Some(item) {
    if !wire_rule_293(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_291(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("facts") is Some(item) {
    if !wire_rule_292(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_295(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("document_id") is Some(item) {
    if !wire_rule_293(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_294(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("location") is Some(item) {
    if !wire_rule_295(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_290(value : Json) -> Bool {
  if wire_rule_291(value) && !wire_rule_294(value) {
    return false
  }
  true
}

///|
fn wire_rule_299(value : Json) -> Bool {
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
fn wire_rule_297(value : Json) -> Bool {
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
    if !wire_rule_278(item) {
      return false
    }
  }
  if fields.get("issue") is Some(item) {
    if !wire_rule_299(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_300(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("kind") is Some(item) {
    if !wire_rule_109(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_282(value : Json) -> Bool {
  if !wire_rule_283(value) {
    return false
  }
  if !wire_rule_290(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  if !fields.contains("facts") {
    return false
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_297(item) {
      return false
    }
  }
  if fields.get("location") is Some(item) {
    if !wire_rule_300(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_279(value : Json) -> Bool {
  if wire_rule_280(value) && !wire_rule_282(value) {
    return false
  }
  true
}

///|
fn wire_rule_303(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_197(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_307(value : Json) -> Bool {
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
fn wire_rule_306(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("issue") {
    return false
  }
  if fields.get("issue") is Some(item) {
    if !wire_rule_307(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_308(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("kind") is Some(item) {
    if !wire_rule_118(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_305(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("facts") {
    return false
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_306(item) {
      return false
    }
  }
  if fields.get("location") is Some(item) {
    if !wire_rule_308(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_302(value : Json) -> Bool {
  if wire_rule_303(value) && !wire_rule_305(value) {
    return false
  }
  true
}

///|
fn wire_rule_312(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "query_expression_invalid") {
    return false
  }
  true
}

///|
fn wire_rule_311(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_312(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_315(value : Json) -> Bool {
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
fn wire_rule_314(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("issue") {
    return false
  }
  if fields.get("issue") is Some(item) {
    if !wire_rule_315(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_313(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("facts") {
    return false
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_314(item) {
      return false
    }
  }
  if fields.get("location") is Some(item) {
    if !wire_rule_184(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_310(value : Json) -> Bool {
  if wire_rule_311(value) && !wire_rule_313(value) {
    return false
  }
  true
}

///|
fn wire_rule_319(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "query_frame_invalid") {
    return false
  }
  true
}

///|
fn wire_rule_318(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_319(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_322(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "invalid_bounds") {
    return false
  }
  true
}

///|
fn wire_rule_321(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("issue") {
    return false
  }
  if fields.get("issue") is Some(item) {
    if !wire_rule_322(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_320(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("facts") {
    return false
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_321(item) {
      return false
    }
  }
  if fields.get("location") is Some(item) {
    if !wire_rule_184(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_317(value : Json) -> Bool {
  if wire_rule_318(value) && !wire_rule_320(value) {
    return false
  }
  true
}

///|
fn wire_rule_326(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "graph_operation_invalid") {
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
  if !(text == "components" || text == "subgraph") {
    return false
  }
  true
}

///|
fn wire_rule_330(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "invalid_kind" ||
    text == "invalid_output_rows" ||
    text == "invalid_node_selector") {
    return false
  }
  true
}

///|
fn wire_rule_328(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("operation") {
    return false
  }
  if !fields.contains("issue") {
    return false
  }
  if fields.get("operation") is Some(item) {
    if !wire_rule_329(item) {
      return false
    }
  }
  if fields.get("issue") is Some(item) {
    if !wire_rule_330(item) {
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
    if !wire_rule_184(item) {
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
fn wire_rule_335(value : Json) -> Bool {
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
    text == "program_structure_invalid") {
    return false
  }
  true
}

///|
fn wire_rule_334(value : Json) -> Bool {
  if wire_rule_335(value) {
    return false
  }
  true
}

///|
fn wire_rule_333(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("code") is Some(item) {
    if !wire_rule_334(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_337(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("facts") {
    return false
  }
  true
}

///|
fn wire_rule_336(value : Json) -> Bool {
  if wire_rule_337(value) {
    return false
  }
  true
}

///|
fn wire_rule_332(value : Json) -> Bool {
  if wire_rule_333(value) && !wire_rule_336(value) {
    return false
  }
  true
}

///|
fn wire_rule_340(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "parameter_value_required" ||
    text == "host_capacity_policy_required" ||
    text == "numeric_reduction_profile_required") {
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
fn wire_rule_338(value : Json) -> Bool {
  if wire_rule_339(value) {
    return false
  }
  true
}

///|
fn wire_rule_346(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "program" ||
    text == "parameter_declarations" ||
    text == "parameters") {
    return false
  }
  true
}

///|
fn wire_rule_344(value : Json) -> Bool {
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
    if !wire_rule_109(item) {
      return false
    }
  }
  if fields.get("document_id") is Some(item) {
    if !wire_rule_346(item) {
      return false
    }
  }
  if fields.get("revision") is Some(item) {
    if !wire_rule_98(item) {
      return false
    }
  }
  if fields.get("pointer") is Some(item) {
    if !wire_rule_112(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_342(value : Json) -> Bool {
  if [wire_rule_117(value), wire_rule_344(value)].filter(fn(ok) { ok }).length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_rule_351(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "close_block_comment") {
    return false
  }
  true
}

///|
fn wire_rule_352(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "requires_review") {
    return false
  }
  true
}

///|
fn wire_rule_353(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "syntax_structure") {
    return false
  }
  true
}

///|
fn wire_rule_354(value : Json) -> Bool {
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
    if !wire_rule_119(item) {
      return false
    }
  }
  if fields.get("revision") is Some(item) {
    if !wire_rule_98(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_361(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "*/") {
    return false
  }
  true
}

///|
fn wire_rule_358(value : Json) -> Bool {
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
    if !wire_rule_121(item) {
      return false
    }
  }
  if fields.get("end_byte") is Some(item) {
    if !wire_rule_121(item) {
      return false
    }
  }
  if fields.get("replacement") is Some(item) {
    if !wire_rule_361(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_357(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  if items.length() < 1 {
    return false
  }
  if items.length() > 1 {
    return false
  }
  for item in items {
    if !wire_rule_358(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_350(value : Json) -> Bool {
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
    if !wire_rule_351(item) {
      return false
    }
  }
  if fields.get("applicability") is Some(item) {
    if !wire_rule_352(item) {
      return false
    }
  }
  if fields.get("risk") is Some(item) {
    if !wire_rule_353(item) {
      return false
    }
  }
  if fields.get("target") is Some(item) {
    if !wire_rule_354(item) {
      return false
    }
  }
  if fields.get("edits") is Some(item) {
    if !wire_rule_357(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_349(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  if items.length() < 1 {
    return false
  }
  if items.length() > 1 {
    return false
  }
  for item in items {
    if !wire_rule_350(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_366(value : Json) -> Bool {
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
fn wire_rule_364(value : Json) -> Bool {
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
    if !wire_rule_257(item) {
      return false
    }
  }
  if fields.get("expected_type") is Some(item) {
    if !wire_rule_366(item) {
      return false
    }
  }
  if fields.get("actual_type") is Some(item) {
    if !wire_rule_366(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_372(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text ==
    "sha256:02859499357530af0ae58e4f2958d1c8fa48f957b86b0a2976dad43bed99b551") {
    return false
  }
  true
}

///|
fn wire_rule_373(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "parameter_declaration") {
    return false
  }
  true
}

///|
fn wire_rule_379(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !(number == 1.0) {
    return false
  }
  true
}

///|
fn wire_rule_378(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_379(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_382(value : Json) -> Bool {
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
fn wire_rule_381(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_382(value)
  }
  true
}

///|
fn wire_rule_380(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_381(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_377(value : Json) -> Bool {
  if wire_rule_378(value) && !wire_rule_380(value) {
    return false
  }
  true
}

///|
fn wire_rule_385(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !(number == 2.0) {
    return false
  }
  true
}

///|
fn wire_rule_384(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_385(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_388(value : Json) -> Bool {
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
fn wire_rule_387(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_388(value)
  }
  true
}

///|
fn wire_rule_386(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_387(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_383(value : Json) -> Bool {
  if wire_rule_384(value) && !wire_rule_386(value) {
    return false
  }
  true
}

///|
fn wire_rule_391(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !(number == 3.0) {
    return false
  }
  true
}

///|
fn wire_rule_390(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_391(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_394(value : Json) -> Bool {
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
fn wire_rule_393(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_394(value)
  }
  true
}

///|
fn wire_rule_392(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_393(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_389(value : Json) -> Bool {
  if wire_rule_390(value) && !wire_rule_392(value) {
    return false
  }
  true
}

///|
fn wire_rule_397(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !(number == 4.0) {
    return false
  }
  true
}

///|
fn wire_rule_396(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_397(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_400(value : Json) -> Bool {
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
fn wire_rule_399(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_400(value)
  }
  true
}

///|
fn wire_rule_398(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_399(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_395(value : Json) -> Bool {
  if wire_rule_396(value) && !wire_rule_398(value) {
    return false
  }
  true
}

///|
fn wire_rule_403(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !(number == 5.0) {
    return false
  }
  true
}

///|
fn wire_rule_402(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_403(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_406(value : Json) -> Bool {
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
fn wire_rule_405(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_406(value)
  }
  true
}

///|
fn wire_rule_404(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_405(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_401(value : Json) -> Bool {
  if wire_rule_402(value) && !wire_rule_404(value) {
    return false
  }
  true
}

///|
fn wire_rule_409(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !(number == 6.0) {
    return false
  }
  true
}

///|
fn wire_rule_408(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_409(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_412(value : Json) -> Bool {
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
fn wire_rule_411(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_412(value)
  }
  true
}

///|
fn wire_rule_410(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_411(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_407(value : Json) -> Bool {
  if wire_rule_408(value) && !wire_rule_410(value) {
    return false
  }
  true
}

///|
fn wire_rule_415(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !(number == 7.0) {
    return false
  }
  true
}

///|
fn wire_rule_414(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_415(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_418(value : Json) -> Bool {
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
fn wire_rule_417(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_418(value)
  }
  true
}

///|
fn wire_rule_416(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_417(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_413(value : Json) -> Bool {
  if wire_rule_414(value) && !wire_rule_416(value) {
    return false
  }
  true
}

///|
fn wire_rule_421(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !(number == 8.0) {
    return false
  }
  true
}

///|
fn wire_rule_420(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_421(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_424(value : Json) -> Bool {
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
fn wire_rule_423(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_424(value)
  }
  true
}

///|
fn wire_rule_422(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_423(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_419(value : Json) -> Bool {
  if wire_rule_420(value) && !wire_rule_422(value) {
    return false
  }
  true
}

///|
fn wire_rule_427(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !(number == 9.0) {
    return false
  }
  true
}

///|
fn wire_rule_426(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_427(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_430(value : Json) -> Bool {
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
fn wire_rule_429(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_430(value)
  }
  true
}

///|
fn wire_rule_428(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_429(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_425(value : Json) -> Bool {
  if wire_rule_426(value) && !wire_rule_428(value) {
    return false
  }
  true
}

///|
fn wire_rule_433(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !(number == 10.0) {
    return false
  }
  true
}

///|
fn wire_rule_432(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("precision") {
    return false
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_433(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_436(value : Json) -> Bool {
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
fn wire_rule_435(value : Json) -> Bool {
  if value is Number(_, ..) {
    return wire_rule_436(value)
  }
  true
}

///|
fn wire_rule_434(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if fields.get("scale") is Some(item) {
    if !wire_rule_435(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_431(value : Json) -> Bool {
  if wire_rule_432(value) && !wire_rule_434(value) {
    return false
  }
  true
}

///|
fn wire_rule_439(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if !(number == 11.0) {
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
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 11.0 {
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
  if !(number == 12.0) {
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
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 12.0 {
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
  if !(number == 13.0) {
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
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 13.0 {
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
  if !(number == 14.0) {
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
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 14.0 {
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
  if !(number == 15.0) {
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
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 15.0 {
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
  if !(number == 16.0) {
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
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 16.0 {
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
  if !(number == 17.0) {
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
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 17.0 {
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
  if !(number == 18.0) {
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
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 18.0 {
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
  if !(number == 19.0) {
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
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 19.0 {
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
  if !(number == 20.0) {
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
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 20.0 {
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
  if !(number == 21.0) {
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
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 21.0 {
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
  if !(number == 22.0) {
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
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 22.0 {
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
  if !(number == 23.0) {
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
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 23.0 {
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
  if !(number == 24.0) {
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
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 24.0 {
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
  if !(number == 25.0) {
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
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 25.0 {
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
  if !(number == 26.0) {
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
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 26.0 {
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
  if !(number == 27.0) {
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
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 27.0 {
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
  if !(number == 28.0) {
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
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 28.0 {
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
  if !(number == 29.0) {
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
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 29.0 {
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
  if !(number == 30.0) {
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
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 30.0 {
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
  if !(number == 31.0) {
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
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 31.0 {
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
  if !(number == 32.0) {
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
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 32.0 {
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
  if !(number == 33.0) {
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
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 33.0 {
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
  if !(number == 34.0) {
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
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 34.0 {
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
  if !(number == 35.0) {
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
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 35.0 {
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
  if !(number == 36.0) {
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
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 36.0 {
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
  if !(number == 37.0) {
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
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 37.0 {
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
  if !(number == 38.0) {
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
  if number.is_nan() || number.is_inf() {
    return false
  }
  if number > 38.0 {
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
fn wire_rule_605(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "decimal") {
    return false
  }
  true
}

///|
fn wire_rule_606(value : Json) -> Bool {
  if !(value is True || value is False) {
    return false
  }
  true
}

///|
fn wire_rule_607(value : Json) -> Bool {
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
fn wire_rule_608(value : Json) -> Bool {
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
fn wire_rule_376(value : Json) -> Bool {
  if !wire_rule_377(value) {
    return false
  }
  if !wire_rule_383(value) {
    return false
  }
  if !wire_rule_389(value) {
    return false
  }
  if !wire_rule_395(value) {
    return false
  }
  if !wire_rule_401(value) {
    return false
  }
  if !wire_rule_407(value) {
    return false
  }
  if !wire_rule_413(value) {
    return false
  }
  if !wire_rule_419(value) {
    return false
  }
  if !wire_rule_425(value) {
    return false
  }
  if !wire_rule_431(value) {
    return false
  }
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
    if !wire_rule_605(item) {
      return false
    }
  }
  if fields.get("nullable") is Some(item) {
    if !wire_rule_606(item) {
      return false
    }
  }
  if fields.get("precision") is Some(item) {
    if !wire_rule_607(item) {
      return false
    }
  }
  if fields.get("scale") is Some(item) {
    if !wire_rule_608(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_610(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "string") {
    return false
  }
  true
}

///|
fn wire_rule_612(value : Json) -> Bool {
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
fn wire_rule_609(value : Json) -> Bool {
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
    if !wire_rule_610(item) {
      return false
    }
  }
  if fields.get("nullable") is Some(item) {
    if !wire_rule_606(item) {
      return false
    }
  }
  if fields.get("min_length") is Some(item) {
    if !wire_rule_612(item) {
      return false
    }
  }
  if fields.get("max_codepoints") is Some(item) {
    if !wire_rule_612(item) {
      return false
    }
  }
  if fields.get("max_utf8_bytes") is Some(item) {
    if !wire_rule_612(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_616(value : Json) -> Bool {
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
fn wire_rule_615(value : Json) -> Bool {
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
    if !wire_rule_616(item) {
      return false
    }
  }
  if fields.get("nullable") is Some(item) {
    if !wire_rule_606(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_619(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "array") {
    return false
  }
  true
}

///|
fn wire_rule_618(value : Json) -> Bool {
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
    if !wire_rule_619(item) {
      return false
    }
  }
  if fields.get("nullable") is Some(item) {
    if !wire_rule_606(item) {
      return false
    }
  }
  if fields.get("items") is Some(item) {
    if !wire_rule_374(item) {
      return false
    }
  }
  if fields.get("max_items") is Some(item) {
    if !wire_rule_612(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_624(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "object") {
    return false
  }
  true
}

///|
fn wire_rule_626(value : Json) -> Bool {
  if !(value is True || value is False) {
    return false
  }
  if !(value is False) {
    return false
  }
  true
}

///|
fn wire_rule_630(value : Json) -> Bool {
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
fn wire_rule_629(value : Json) -> Bool {
  if value is String(_) {
    return wire_rule_630(value)
  }
  true
}

///|
fn wire_rule_627(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  for _key, item in fields {
    if !false && !wire_rule_374(item) {
      return false
    }
  }
  for key, _ in fields {
    if !wire_rule_629(Json::string(key)) {
      return false
    }
  }
  true
}

///|
fn wire_rule_623(value : Json) -> Bool {
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
    if !wire_rule_624(item) {
      return false
    }
  }
  if fields.get("nullable") is Some(item) {
    if !wire_rule_606(item) {
      return false
    }
  }
  if fields.get("additional_properties") is Some(item) {
    if !wire_rule_626(item) {
      return false
    }
  }
  if fields.get("fields") is Some(item) {
    if !wire_rule_627(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_632(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "vector") {
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
  if number < 1.0 {
    return false
  }
  true
}

///|
fn wire_rule_635(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "f32") {
    return false
  }
  true
}

///|
fn wire_rule_631(value : Json) -> Bool {
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
    if !wire_rule_632(item) {
      return false
    }
  }
  if fields.get("nullable") is Some(item) {
    if !wire_rule_606(item) {
      return false
    }
  }
  if fields.get("dimensions") is Some(item) {
    if !wire_rule_634(item) {
      return false
    }
  }
  if fields.get("element_type") is Some(item) {
    if !wire_rule_635(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_637(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "resource_ref") {
    return false
  }
  true
}

///|
fn wire_rule_639(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if text.iter().count() < 1 {
    return false
  }
  true
}

///|
fn wire_rule_636(value : Json) -> Bool {
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
    if !wire_rule_637(item) {
      return false
    }
  }
  if fields.get("nullable") is Some(item) {
    if !wire_rule_606(item) {
      return false
    }
  }
  if fields.get("resource_kind") is Some(item) {
    if !wire_rule_639(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_641(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "artifact_ref") {
    return false
  }
  true
}

///|
fn wire_rule_640(value : Json) -> Bool {
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
    if !wire_rule_641(item) {
      return false
    }
  }
  if fields.get("nullable") is Some(item) {
    if !wire_rule_606(item) {
      return false
    }
  }
  if fields.get("media_type") is Some(item) {
    if !wire_rule_639(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_375(value : Json) -> Bool {
  if [
      wire_rule_376(value),
      wire_rule_609(value),
      wire_rule_615(value),
      wire_rule_618(value),
      wire_rule_623(value),
      wire_rule_631(value),
      wire_rule_636(value),
      wire_rule_640(value),
    ]
    .filter(fn(ok) { ok })
    .length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_rule_374(value : Json) -> Bool {
  if !wire_rule_375(value) {
    return false
  }
  true
}

///|
fn wire_rule_644(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "caller") {
    return false
  }
  true
}

///|
fn wire_rule_648(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "numeric") {
    return false
  }
  true
}

///|
fn wire_rule_652(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "field") {
    return false
  }
  true
}

///|
fn wire_rule_653(value : Json) -> Bool {
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
fn wire_rule_651(value : Json) -> Bool {
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
    if !wire_rule_652(item) {
      return false
    }
  }
  if fields.get("name") is Some(item) {
    if !wire_rule_653(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_655(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "items") {
    return false
  }
  true
}

///|
fn wire_rule_654(value : Json) -> Bool {
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
    if !wire_rule_655(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_650(value : Json) -> Bool {
  if [wire_rule_651(value), wire_rule_654(value)].filter(fn(ok) { ok }).length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_rule_649(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  if items.length() > 64 {
    return false
  }
  for item in items {
    if !wire_rule_650(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_657(value : Json) -> Bool {
  guard value is Number(number, ..) else { return false }
  if number.is_nan() || number.is_inf() {
    return false
  }
  true
}

///|
fn wire_rule_647(value : Json) -> Bool {
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
    if !wire_rule_648(item) {
      return false
    }
  }
  if fields.get("path") is Some(item) {
    if !wire_rule_649(item) {
      return false
    }
  }
  if fields.get("integer") is Some(item) {
    if !wire_rule_606(item) {
      return false
    }
  }
  if fields.get("minimum") is Some(item) {
    if !wire_rule_657(item) {
      return false
    }
  }
  if fields.get("maximum") is Some(item) {
    if !wire_rule_657(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_660(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "duration") {
    return false
  }
  true
}

///|
fn wire_rule_659(value : Json) -> Bool {
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
    if !wire_rule_660(item) {
      return false
    }
  }
  if fields.get("path") is Some(item) {
    if !wire_rule_649(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_663(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "array_length") {
    return false
  }
  true
}

///|
fn wire_rule_665(value : Json) -> Bool {
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
fn wire_rule_662(value : Json) -> Bool {
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
    if !wire_rule_663(item) {
      return false
    }
  }
  if fields.get("path") is Some(item) {
    if !wire_rule_649(item) {
      return false
    }
  }
  if fields.get("length") is Some(item) {
    if !wire_rule_665(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_646(value : Json) -> Bool {
  if [wire_rule_647(value), wire_rule_659(value), wire_rule_662(value)]
    .filter(fn(ok) { ok })
    .length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_rule_645(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  if items.length() > 8192 {
    return false
  }
  for item in items {
    if !wire_rule_646(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_371(value : Json) -> Bool {
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
    if !wire_rule_372(item) {
      return false
    }
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_373(item) {
      return false
    }
  }
  if fields.get("contract") is Some(item) {
    if !wire_rule_374(item) {
      return false
    }
  }
  if fields.get("supplier") is Some(item) {
    if !wire_rule_644(item) {
      return false
    }
  }
  if fields.get("constraints") is Some(item) {
    if !wire_rule_645(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_368(value : Json) -> Bool {
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
    if !wire_rule_257(item) {
      return false
    }
  }
  if fields.get("expected_type") is Some(item) {
    if !wire_rule_366(item) {
      return false
    }
  }
  if fields.get("admission") is Some(item) {
    if !wire_rule_371(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_668(value : Json) -> Bool {
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
fn wire_rule_666(value : Json) -> Bool {
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
    if !wire_rule_257(item) {
      return false
    }
  }
  if fields.get("constraint") is Some(item) {
    if !wire_rule_668(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_672(value : Json) -> Bool {
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
fn wire_rule_670(value : Json) -> Bool {
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
    if !wire_rule_257(item) {
      return false
    }
  }
  if fields.get("domain") is Some(item) {
    if !wire_rule_672(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_674(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "components") {
    return false
  }
  true
}

///|
fn wire_rule_675(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "invalid_kind" || text == "invalid_output_rows") {
    return false
  }
  true
}

///|
fn wire_rule_673(value : Json) -> Bool {
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
    if !wire_rule_674(item) {
      return false
    }
  }
  if fields.get("issue") is Some(item) {
    if !wire_rule_675(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_677(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "subgraph") {
    return false
  }
  true
}

///|
fn wire_rule_678(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "invalid_node_selector") {
    return false
  }
  true
}

///|
fn wire_rule_676(value : Json) -> Bool {
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
    if !wire_rule_677(item) {
      return false
    }
  }
  if fields.get("issue") is Some(item) {
    if !wire_rule_678(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_681(value : Json) -> Bool {
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
fn wire_rule_680(value : Json) -> Bool {
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
    if !wire_rule_681(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_362(value : Json) -> Bool {
  if [
      wire_rule_256(value),
      wire_rule_364(value),
      wire_rule_368(value),
      wire_rule_666(value),
      wire_rule_268(value),
      wire_rule_670(value),
      wire_rule_673(value),
      wire_rule_676(value),
      wire_rule_297(value),
      wire_rule_680(value),
      wire_rule_165(value),
      wire_rule_148(value),
    ]
    .filter(fn(ok) { ok })
    .length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_rule_129(value : Json) -> Bool {
  if !wire_rule_130(value) {
    return false
  }
  if !wire_rule_140(value) {
    return false
  }
  if !wire_rule_152(value) {
    return false
  }
  if !wire_rule_159(value) {
    return false
  }
  if !wire_rule_171(value) {
    return false
  }
  if !wire_rule_178(value) {
    return false
  }
  if !wire_rule_187(value) {
    return false
  }
  if !wire_rule_194(value) {
    return false
  }
  if !wire_rule_203(value) {
    return false
  }
  if !wire_rule_210(value) {
    return false
  }
  if !wire_rule_217(value) {
    return false
  }
  if !wire_rule_224(value) {
    return false
  }
  if !wire_rule_229(value) {
    return false
  }
  if !wire_rule_235(value) {
    return false
  }
  if !wire_rule_246(value) {
    return false
  }
  if !wire_rule_252(value) {
    return false
  }
  if !wire_rule_259(value) {
    return false
  }
  if !wire_rule_264(value) {
    return false
  }
  if !wire_rule_271(value) {
    return false
  }
  if !wire_rule_279(value) {
    return false
  }
  if !wire_rule_302(value) {
    return false
  }
  if !wire_rule_310(value) {
    return false
  }
  if !wire_rule_317(value) {
    return false
  }
  if !wire_rule_324(value) {
    return false
  }
  if !wire_rule_332(value) {
    return false
  }
  if !wire_rule_338(value) {
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
    if !wire_rule_105(item) {
      return false
    }
  }
  if fields.get("location") is Some(item) {
    if !wire_rule_342(item) {
      return false
    }
  }
  if fields.get("fixes") is Some(item) {
    if !wire_rule_349(item) {
      return false
    }
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_362(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_128(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  if items.length() > 1024 {
    return false
  }
  for item in items {
    if !wire_rule_129(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_685(value : Json) -> Bool {
  if !wire_rule_130(value) {
    return false
  }
  if !wire_rule_140(value) {
    return false
  }
  if !wire_rule_152(value) {
    return false
  }
  if !wire_rule_159(value) {
    return false
  }
  if !wire_rule_171(value) {
    return false
  }
  if !wire_rule_178(value) {
    return false
  }
  if !wire_rule_187(value) {
    return false
  }
  if !wire_rule_194(value) {
    return false
  }
  if !wire_rule_203(value) {
    return false
  }
  if !wire_rule_210(value) {
    return false
  }
  if !wire_rule_217(value) {
    return false
  }
  if !wire_rule_224(value) {
    return false
  }
  if !wire_rule_229(value) {
    return false
  }
  if !wire_rule_235(value) {
    return false
  }
  if !wire_rule_246(value) {
    return false
  }
  if !wire_rule_252(value) {
    return false
  }
  if !wire_rule_259(value) {
    return false
  }
  if !wire_rule_264(value) {
    return false
  }
  if !wire_rule_271(value) {
    return false
  }
  if !wire_rule_279(value) {
    return false
  }
  if !wire_rule_302(value) {
    return false
  }
  if !wire_rule_310(value) {
    return false
  }
  if !wire_rule_317(value) {
    return false
  }
  if !wire_rule_324(value) {
    return false
  }
  if !wire_rule_332(value) {
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
    if !wire_rule_340(item) {
      return false
    }
  }
  if fields.get("location") is Some(item) {
    if !wire_rule_342(item) {
      return false
    }
  }
  if fields.get("fixes") is Some(item) {
    if !wire_rule_349(item) {
      return false
    }
  }
  if fields.get("facts") is Some(item) {
    if !wire_rule_362(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_684(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  if items.length() > 1024 {
    return false
  }
  for item in items {
    if !wire_rule_685(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_716(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "bound_input") {
    return false
  }
  true
}

///|
fn wire_rule_715(value : Json) -> Bool {
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
    if !wire_rule_716(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_717(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "invalid" || text == "undetermined" || text == "verified") {
    return false
  }
  true
}

///|
fn wire_rule_67(value : Json) -> Bool {
  if !wire_rule_68(value) {
    return false
  }
  if !wire_rule_79(value) {
    return false
  }
  if !wire_rule_85(value) {
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
    if !wire_rule_92(item) {
      return false
    }
  }
  if fields.get("omissions") is Some(item) {
    if !wire_rule_93(item) {
      return false
    }
  }
  if fields.get("inputs") is Some(item) {
    if !wire_rule_95(item) {
      return false
    }
  }
  if fields.get("coverage") is Some(item) {
    if !wire_rule_101(item) {
      return false
    }
  }
  if fields.get("reasons") is Some(item) {
    if !wire_rule_128(item) {
      return false
    }
  }
  if fields.get("requirements") is Some(item) {
    if !wire_rule_684(item) {
      return false
    }
  }
  if fields.get("scope") is Some(item) {
    if !wire_rule_715(item) {
      return false
    }
  }
  if fields.get("verdict") is Some(item) {
    if !wire_rule_717(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_718(value : Json) -> Bool {
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
fn wire_rule_719(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text ==
    "sha256:3d0c78252f42ea8b2edc7a8bbea8d7ccf27ee4d2980b5889c9c191d5f0f3476a") {
    return false
  }
  true
}

///|
fn wire_rule_720(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "actql-check-outcome/0.1") {
    return false
  }
  true
}

///|
fn wire_rule_65(value : Json) -> Bool {
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
    if !wire_rule_66(item) {
      return false
    }
  }
  if fields.get("report") is Some(item) {
    if !wire_rule_67(item) {
      return false
    }
  }
  if fields.get("outcome_schema_cid") is Some(item) {
    if !wire_rule_718(item) {
      return false
    }
  }
  if fields.get("reason_schema_cid") is Some(item) {
    if !wire_rule_719(item) {
      return false
    }
  }
  if fields.get("version") is Some(item) {
    if !wire_rule_720(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_722(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "failed") {
    return false
  }
  true
}

///|
fn wire_rule_734(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "invalid" || text == "undetermined") {
    return false
  }
  true
}

///|
fn wire_rule_723(value : Json) -> Bool {
  if !wire_rule_68(value) {
    return false
  }
  if !wire_rule_79(value) {
    return false
  }
  if !wire_rule_85(value) {
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
    if !wire_rule_92(item) {
      return false
    }
  }
  if fields.get("omissions") is Some(item) {
    if !wire_rule_93(item) {
      return false
    }
  }
  if fields.get("inputs") is Some(item) {
    if !wire_rule_95(item) {
      return false
    }
  }
  if fields.get("coverage") is Some(item) {
    if !wire_rule_101(item) {
      return false
    }
  }
  if fields.get("reasons") is Some(item) {
    if !wire_rule_128(item) {
      return false
    }
  }
  if fields.get("requirements") is Some(item) {
    if !wire_rule_684(item) {
      return false
    }
  }
  if fields.get("scope") is Some(item) {
    if !wire_rule_715(item) {
      return false
    }
  }
  if fields.get("verdict") is Some(item) {
    if !wire_rule_734(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_721(value : Json) -> Bool {
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
    if !wire_rule_722(item) {
      return false
    }
  }
  if fields.get("partial_report") is Some(item) {
    if !wire_rule_723(item) {
      return false
    }
  }
  if fields.get("problem") is Some(item) {
    if !wire_rule_104(item) {
      return false
    }
  }
  if fields.get("correlation_ref") is Some(item) {
    if !wire_rule_92(item) {
      return false
    }
  }
  if fields.get("outcome_schema_cid") is Some(item) {
    if !wire_rule_718(item) {
      return false
    }
  }
  if fields.get("reason_schema_cid") is Some(item) {
    if !wire_rule_719(item) {
      return false
    }
  }
  if fields.get("version") is Some(item) {
    if !wire_rule_720(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_742(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "unavailable") {
    return false
  }
  true
}

///|
fn wire_rule_740(value : Json) -> Bool {
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
    if !wire_rule_92(item) {
      return false
    }
  }
  if fields.get("outcome") is Some(item) {
    if !wire_rule_742(item) {
      return false
    }
  }
  if fields.get("problem") is Some(item) {
    if !wire_rule_104(item) {
      return false
    }
  }
  if fields.get("outcome_schema_cid") is Some(item) {
    if !wire_rule_718(item) {
      return false
    }
  }
  if fields.get("reason_schema_cid") is Some(item) {
    if !wire_rule_719(item) {
      return false
    }
  }
  if fields.get("version") is Some(item) {
    if !wire_rule_720(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_64(value : Json) -> Bool {
  if [wire_rule_65(value), wire_rule_721(value), wire_rule_740(value)]
    .filter(fn(ok) { ok })
    .length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_rule_63(value : Json) -> Bool {
  if !wire_rule_64(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  if fields.get("reason_schema_cid") !=
    Some(
      Json::string(
        "sha256:3d0c78252f42ea8b2edc7a8bbea8d7ccf27ee4d2980b5889c9c191d5f0f3476a",
      ),
    ) {
    return false
  }
  if fields.get("outcome_schema_cid") !=
    Some(
      Json::string(
        "sha256:c7e11c497b3d0ab58adc69c1ec04e4a44e6420aed7f0981e8e9741d2c3af8b5f",
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
fn wire_rule_749(value : Json) -> Bool {
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
fn wire_rule_747(value : Json) -> Bool {
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
    if !wire_rule_749(item) {
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
    if !wire_rule_747(item) {
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
fn wire_rule_752(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "preparation_failed") {
    return false
  }
  true
}

///|
fn wire_rule_751(value : Json) -> Bool {
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
    if !wire_rule_752(item) {
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
    if !wire_rule_747(item) {
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
      wire_rule_751(value),
    ]
    .filter(fn(ok) { ok })
    .length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_rule_761(value : Json) -> Bool {
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
    if !wire_rule_747(item) {
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
fn wire_rule_767(value : Json) -> Bool {
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
    if !wire_rule_752(item) {
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
    if !wire_rule_747(item) {
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
fn wire_rule_774(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "unresolvable") {
    return false
  }
  true
}

///|
fn wire_rule_776(value : Json) -> Bool {
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
fn wire_rule_773(value : Json) -> Bool {
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
    if !wire_rule_774(item) {
      return false
    }
  }
  if fields.get("submissionRef") is Some(item) {
    if !wire_submission_ref_shape(item) {
      return false
    }
  }
  if fields.get("problem") is Some(item) {
    if !wire_rule_776(item) {
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
      wire_rule_761(value),
      wire_rule_767(value),
      wire_rule_773(value),
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
fn wire_rule_782(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("movementPolicyRef") {
    return false
  }
  true
}

///|
fn wire_rule_781(value : Json) -> Bool {
  if wire_rule_782(value) {
    return false
  }
  true
}

///|
fn wire_rule_784(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("cloudConnectionRef") {
    return false
  }
  true
}

///|
fn wire_rule_783(value : Json) -> Bool {
  if wire_rule_784(value) {
    return false
  }
  true
}

///|
fn wire_rule_785(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "remote") {
    return false
  }
  true
}

///|
fn wire_rule_787(value : Json) -> Bool {
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
fn wire_rule_780(value : Json) -> Bool {
  if !wire_rule_781(value) {
    return false
  }
  if !wire_rule_783(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  if fields.get("mode") is Some(item) {
    if !wire_rule_785(item) {
      return false
    }
  }
  if fields.get("owner") is Some(item) {
    if !wire_rule_785(item) {
      return false
    }
  }
  if fields.get("runners") is Some(item) {
    if !wire_rule_787(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_792(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "local") {
    return false
  }
  true
}

///|
fn wire_rule_789(value : Json) -> Bool {
  if !wire_rule_781(value) {
    return false
  }
  if !wire_rule_783(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  if fields.get("mode") is Some(item) {
    if !wire_rule_792(item) {
      return false
    }
  }
  if fields.get("owner") is Some(item) {
    if !wire_rule_792(item) {
      return false
    }
  }
  if fields.get("runners") is Some(item) {
    if !wire_rule_787(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_796(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "hybrid") {
    return false
  }
  true
}

///|
fn wire_rule_795(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("movementPolicyRef") {
    return false
  }
  if !fields.contains("cloudConnectionRef") {
    return false
  }
  if fields.get("mode") is Some(item) {
    if !wire_rule_796(item) {
      return false
    }
  }
  if fields.get("owner") is Some(item) {
    if !wire_rule_792(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_801(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "cloud") {
    return false
  }
  true
}

///|
fn wire_rule_802(value : Json) -> Bool {
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
fn wire_rule_798(value : Json) -> Bool {
  if wire_rule_784(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  if !fields.contains("movementPolicyRef") {
    return false
  }
  if fields.get("mode") is Some(item) {
    if !wire_rule_796(item) {
      return false
    }
  }
  if fields.get("owner") is Some(item) {
    if !wire_rule_801(item) {
      return false
    }
  }
  if fields.get("runners") is Some(item) {
    if !wire_rule_802(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_779(value : Json) -> Bool {
  if [
      wire_rule_780(value),
      wire_rule_789(value),
      wire_rule_795(value),
      wire_rule_798(value),
    ]
    .filter(fn(ok) { ok })
    .length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_rule_804(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "local" || text == "remote" || text == "hybrid") {
    return false
  }
  true
}

///|
fn wire_rule_805(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "local" || text == "remote" || text == "cloud") {
    return false
  }
  true
}

///|
fn wire_rule_807(value : Json) -> Bool {
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
  if !wire_rule_779(value) {
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
    if !wire_rule_804(item) {
      return false
    }
  }
  if fields.get("owner") is Some(item) {
    if !wire_rule_805(item) {
      return false
    }
  }
  if fields.get("workspaceId") is Some(item) {
    if !wire_rule_7(item) {
      return false
    }
  }
  if fields.get("consentRefs") is Some(item) {
    if !wire_rule_807(item) {
      return false
    }
  }
  if fields.get("runners") is Some(item) {
    if !wire_rule_807(item) {
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
fn wire_rule_813(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "actql-client-host/0.1") {
    return false
  }
  true
}

///|
fn wire_rule_820(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  for item in items {
    if !wire_rule_7(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_823(value : Json) -> Bool {
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
fn wire_rule_822(value : Json) -> Bool {
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
    if !wire_rule_823(item) {
      return false
    }
  }
  if fields.get("maxRowWireBytes") is Some(item) {
    if !wire_rule_823(item) {
      return false
    }
  }
  if fields.get("maxRowRetainedValueBytes") is Some(item) {
    if !wire_rule_823(item) {
      return false
    }
  }
  if fields.get("maxRetainedValueBytes") is Some(item) {
    if !wire_rule_823(item) {
      return false
    }
  }
  if fields.get("maxRows") is Some(item) {
    if !wire_rule_823(item) {
      return false
    }
  }
  if fields.get("maxBatchRows") is Some(item) {
    if !wire_rule_823(item) {
      return false
    }
  }
  if fields.get("maxBatchRetainedValueBytes") is Some(item) {
    if !wire_rule_823(item) {
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
    if !wire_rule_813(item) {
      return false
    }
  }
  if fields.get("mode") is Some(item) {
    if !wire_rule_804(item) {
      return false
    }
  }
  if fields.get("owner") is Some(item) {
    if !wire_rule_805(item) {
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
    if !wire_rule_820(item) {
      return false
    }
  }
  if fields.get("limits") is Some(item) {
    if !wire_rule_822(item) {
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
fn wire_rule_830(value : Json) -> Bool {
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
    if !wire_rule_830(item) {
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
fn wire_rule_835(value : Json) -> Bool {
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
    if !wire_rule_835(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_836(value : Json) -> Bool {
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
    if !wire_rule_836(item) {
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
fn wire_rule_842(value : Json) -> Bool {
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
    if !wire_rule_842(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_844(value : Json) -> Bool {
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
    if !wire_rule_844(item) {
      return false
    }
  }
  if fields.get("revision") is Some(item) {
    if !wire_rule_842(item) {
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
fn wire_rule_847(value : Json) -> Bool {
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
    if !wire_rule_830(item) {
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
fn wire_rule_850(value : Json) -> Bool {
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
    if !wire_rule_836(item) {
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
  if [wire_rule_847(value), wire_rule_850(value)].filter(fn(ok) { ok }).length() !=
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
  if documents.size() != inputs.length() {
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
