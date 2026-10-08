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
fn wire_rule_5(value : Json) -> Bool {
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
    if !wire_rule_5(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_7(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "actql-submission-epoch/0.1") {
    return false
  }
  true
}

///|
fn wire_rule_8(value : Json) -> Bool {
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
fn wire_rule_9(value : Json) -> Bool {
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
fn wire_rule_10(value : Json) -> Bool {
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
fn wire_rule_11(value : Json) -> Bool {
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
fn wire_rule_12(value : Json) -> Bool {
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
fn wire_rule_6(value : Json) -> Bool {
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
    if !wire_rule_7(item) {
      return false
    }
  }
  if fields.get("authorityScopeCid") is Some(item) {
    if !wire_rule_8(item) {
      return false
    }
  }
  if fields.get("epochNonce") is Some(item) {
    if !wire_rule_9(item) {
      return false
    }
  }
  if fields.get("notBefore") is Some(item) {
    if !wire_rule_10(item) {
      return false
    }
  }
  if fields.get("expiresAt") is Some(item) {
    if !wire_rule_11(item) {
      return false
    }
  }
  if fields.get("authenticator") is Some(item) {
    if !wire_rule_12(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_13(value : Json) -> Bool {
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
    if !wire_rule_6(item) {
      return false
    }
  }
  if fields.get("nonce") is Some(item) {
    if !wire_rule_13(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_15(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "ready") {
    return false
  }
  true
}

///|
fn wire_rule_18(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "actql-submission-epoch/0.1") {
    return false
  }
  true
}

///|
fn wire_rule_19(value : Json) -> Bool {
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
fn wire_rule_20(value : Json) -> Bool {
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
fn wire_rule_21(value : Json) -> Bool {
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
fn wire_rule_22(value : Json) -> Bool {
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
fn wire_rule_23(value : Json) -> Bool {
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
fn wire_rule_17(value : Json) -> Bool {
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
    if !wire_rule_18(item) {
      return false
    }
  }
  if fields.get("authorityScopeCid") is Some(item) {
    if !wire_rule_19(item) {
      return false
    }
  }
  if fields.get("epochNonce") is Some(item) {
    if !wire_rule_20(item) {
      return false
    }
  }
  if fields.get("notBefore") is Some(item) {
    if !wire_rule_21(item) {
      return false
    }
  }
  if fields.get("expiresAt") is Some(item) {
    if !wire_rule_22(item) {
      return false
    }
  }
  if fields.get("authenticator") is Some(item) {
    if !wire_rule_23(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_24(value : Json) -> Bool {
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
fn wire_rule_16(value : Json) -> Bool {
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
    if !wire_rule_17(item) {
      return false
    }
  }
  if fields.get("nonce") is Some(item) {
    if !wire_rule_24(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_25(value : Json) -> Bool {
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
fn wire_rule_28(value : Json) -> Bool {
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
fn wire_rule_29(value : Json) -> Bool {
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
fn wire_rule_30(value : Json) -> Bool {
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
fn wire_rule_27(value : Json) -> Bool {
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
    if !wire_rule_28(item) {
      return false
    }
  }
  if fields.get("authorityScopeCid") is Some(item) {
    if !wire_rule_29(item) {
      return false
    }
  }
  if fields.get("runDefinitionCid") is Some(item) {
    if !wire_rule_30(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_31(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "volatile" || text == "durable") {
    return false
  }
  true
}

///|
fn wire_rule_32(value : Json) -> Bool {
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
fn wire_rule_26(value : Json) -> Bool {
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
    if !wire_rule_27(item) {
      return false
    }
  }
  if fields.get("durability") is Some(item) {
    if !wire_rule_31(item) {
      return false
    }
  }
  if fields.get("revision") is Some(item) {
    if !wire_rule_32(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_36(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "actql-submission-epoch/0.1") {
    return false
  }
  true
}

///|
fn wire_rule_37(value : Json) -> Bool {
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
fn wire_rule_38(value : Json) -> Bool {
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
fn wire_rule_39(value : Json) -> Bool {
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
fn wire_rule_40(value : Json) -> Bool {
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
fn wire_rule_41(value : Json) -> Bool {
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
fn wire_rule_35(value : Json) -> Bool {
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
    if !wire_rule_36(item) {
      return false
    }
  }
  if fields.get("authorityScopeCid") is Some(item) {
    if !wire_rule_37(item) {
      return false
    }
  }
  if fields.get("epochNonce") is Some(item) {
    if !wire_rule_38(item) {
      return false
    }
  }
  if fields.get("notBefore") is Some(item) {
    if !wire_rule_39(item) {
      return false
    }
  }
  if fields.get("expiresAt") is Some(item) {
    if !wire_rule_40(item) {
      return false
    }
  }
  if fields.get("authenticator") is Some(item) {
    if !wire_rule_41(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_42(value : Json) -> Bool {
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
fn wire_rule_34(value : Json) -> Bool {
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
    if !wire_rule_35(item) {
      return false
    }
  }
  if fields.get("nonce") is Some(item) {
    if !wire_rule_42(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_43(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "possible_prior_execution_and_effects") {
    return false
  }
  true
}

///|
fn wire_rule_33(value : Json) -> Bool {
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
    if !wire_rule_34(item) {
      return false
    }
  }
  if fields.get("acknowledgement") is Some(item) {
    if !wire_rule_43(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_14(value : Json) -> Bool {
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
    if !wire_rule_15(item) {
      return false
    }
  }
  if fields.get("submissionRef") is Some(item) {
    if !wire_rule_16(item) {
      return false
    }
  }
  if fields.get("intentCid") is Some(item) {
    if !wire_rule_25(item) {
      return false
    }
  }
  if fields.get("admission") is Some(item) {
    if !wire_rule_26(item) {
      return false
    }
  }
  if fields.get("unresolvedHistory") is Some(item) {
    if !wire_rule_33(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_45(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "held") {
    return false
  }
  true
}

///|
fn wire_rule_48(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "actql-submission-epoch/0.1") {
    return false
  }
  true
}

///|
fn wire_rule_49(value : Json) -> Bool {
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
fn wire_rule_50(value : Json) -> Bool {
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
fn wire_rule_51(value : Json) -> Bool {
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
fn wire_rule_52(value : Json) -> Bool {
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
fn wire_rule_53(value : Json) -> Bool {
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
fn wire_rule_47(value : Json) -> Bool {
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
    if !wire_rule_48(item) {
      return false
    }
  }
  if fields.get("authorityScopeCid") is Some(item) {
    if !wire_rule_49(item) {
      return false
    }
  }
  if fields.get("epochNonce") is Some(item) {
    if !wire_rule_50(item) {
      return false
    }
  }
  if fields.get("notBefore") is Some(item) {
    if !wire_rule_51(item) {
      return false
    }
  }
  if fields.get("expiresAt") is Some(item) {
    if !wire_rule_52(item) {
      return false
    }
  }
  if fields.get("authenticator") is Some(item) {
    if !wire_rule_53(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_54(value : Json) -> Bool {
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
fn wire_rule_46(value : Json) -> Bool {
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
    if !wire_rule_47(item) {
      return false
    }
  }
  if fields.get("nonce") is Some(item) {
    if !wire_rule_54(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_55(value : Json) -> Bool {
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
fn wire_rule_60(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("endReason") {
    return false
  }
  true
}

///|
fn wire_rule_59(value : Json) -> Bool {
  if wire_rule_60(value) {
    return false
  }
  true
}

///|
fn wire_rule_62(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("terminalErrorCode") {
    return false
  }
  true
}

///|
fn wire_rule_61(value : Json) -> Bool {
  if wire_rule_62(value) {
    return false
  }
  true
}

///|
fn wire_rule_63(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "waiting_checkpoint") {
    return false
  }
  true
}

///|
fn wire_rule_58(value : Json) -> Bool {
  if !wire_rule_59(value) {
    return false
  }
  if !wire_rule_61(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  if !fields.contains("checkpoint") {
    return false
  }
  if fields.get("state") is Some(item) {
    if !wire_rule_63(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_66(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("endReason") {
    return false
  }
  true
}

///|
fn wire_rule_65(value : Json) -> Bool {
  if wire_rule_66(value) {
    return false
  }
  true
}

///|
fn wire_rule_68(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("terminalErrorCode") {
    return false
  }
  true
}

///|
fn wire_rule_67(value : Json) -> Bool {
  if wire_rule_68(value) {
    return false
  }
  true
}

///|
fn wire_rule_69(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "resuming") {
    return false
  }
  true
}

///|
fn wire_rule_64(value : Json) -> Bool {
  if !wire_rule_65(value) {
    return false
  }
  if !wire_rule_67(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  if fields.get("state") is Some(item) {
    if !wire_rule_69(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_71(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "ended") {
    return false
  }
  true
}

///|
fn wire_rule_70(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("endReason") {
    return false
  }
  if fields.get("state") is Some(item) {
    if !wire_rule_71(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_57(value : Json) -> Bool {
  if [wire_rule_58(value), wire_rule_64(value), wire_rule_70(value)]
    .filter(fn(ok) { ok })
    .length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_rule_72(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "held") {
    return false
  }
  true
}

///|
fn wire_rule_73(value : Json) -> Bool {
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
fn wire_rule_74(value : Json) -> Bool {
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
fn wire_rule_75(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "waiting_checkpoint" || text == "resuming" || text == "ended") {
    return false
  }
  true
}

///|
fn wire_rule_76(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "durable") {
    return false
  }
  true
}

///|
fn wire_rule_77(value : Json) -> Bool {
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
fn wire_rule_79(value : Json) -> Bool {
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
fn wire_rule_80(value : Json) -> Bool {
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
fn wire_rule_81(value : Json) -> Bool {
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
fn wire_rule_82(value : Json) -> Bool {
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
fn wire_rule_78(value : Json) -> Bool {
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
    if !wire_rule_79(item) {
      return false
    }
  }
  if fields.get("checkpointCid") is Some(item) {
    if !wire_rule_80(item) {
      return false
    }
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_81(item) {
      return false
    }
  }
  if fields.get("expiresAt") is Some(item) {
    if !wire_rule_82(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_83(value : Json) -> Bool {
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
fn wire_rule_84(value : Json) -> Bool {
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
fn wire_rule_56(value : Json) -> Bool {
  if !wire_rule_57(value) {
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
    if !wire_rule_72(item) {
      return false
    }
  }
  if fields.get("requestId") is Some(item) {
    if !wire_rule_73(item) {
      return false
    }
  }
  if fields.get("prepareAttemptId") is Some(item) {
    if !wire_rule_74(item) {
      return false
    }
  }
  if fields.get("state") is Some(item) {
    if !wire_rule_75(item) {
      return false
    }
  }
  if fields.get("durability") is Some(item) {
    if !wire_rule_76(item) {
      return false
    }
  }
  if fields.get("lookupExpiresAt") is Some(item) {
    if !wire_rule_77(item) {
      return false
    }
  }
  if fields.get("checkpoint") is Some(item) {
    if !wire_rule_78(item) {
      return false
    }
  }
  if fields.get("endReason") is Some(item) {
    if !wire_rule_83(item) {
      return false
    }
  }
  if fields.get("terminalErrorCode") is Some(item) {
    if !wire_rule_84(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_88(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "actql-submission-epoch/0.1") {
    return false
  }
  true
}

///|
fn wire_rule_89(value : Json) -> Bool {
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
fn wire_rule_90(value : Json) -> Bool {
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
fn wire_rule_91(value : Json) -> Bool {
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
fn wire_rule_92(value : Json) -> Bool {
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
fn wire_rule_93(value : Json) -> Bool {
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
fn wire_rule_87(value : Json) -> Bool {
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
    if !wire_rule_88(item) {
      return false
    }
  }
  if fields.get("authorityScopeCid") is Some(item) {
    if !wire_rule_89(item) {
      return false
    }
  }
  if fields.get("epochNonce") is Some(item) {
    if !wire_rule_90(item) {
      return false
    }
  }
  if fields.get("notBefore") is Some(item) {
    if !wire_rule_91(item) {
      return false
    }
  }
  if fields.get("expiresAt") is Some(item) {
    if !wire_rule_92(item) {
      return false
    }
  }
  if fields.get("authenticator") is Some(item) {
    if !wire_rule_93(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_94(value : Json) -> Bool {
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
fn wire_rule_86(value : Json) -> Bool {
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
    if !wire_rule_87(item) {
      return false
    }
  }
  if fields.get("nonce") is Some(item) {
    if !wire_rule_94(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_95(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "possible_prior_execution_and_effects") {
    return false
  }
  true
}

///|
fn wire_rule_85(value : Json) -> Bool {
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
    if !wire_rule_86(item) {
      return false
    }
  }
  if fields.get("acknowledgement") is Some(item) {
    if !wire_rule_95(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_44(value : Json) -> Bool {
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
    if !wire_rule_45(item) {
      return false
    }
  }
  if fields.get("submissionRef") is Some(item) {
    if !wire_rule_46(item) {
      return false
    }
  }
  if fields.get("intentCid") is Some(item) {
    if !wire_rule_55(item) {
      return false
    }
  }
  if fields.get("held") is Some(item) {
    if !wire_rule_56(item) {
      return false
    }
  }
  if fields.get("unresolvedHistory") is Some(item) {
    if !wire_rule_85(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_97(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "preparing") {
    return false
  }
  true
}

///|
fn wire_rule_100(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "actql-submission-epoch/0.1") {
    return false
  }
  true
}

///|
fn wire_rule_101(value : Json) -> Bool {
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
fn wire_rule_102(value : Json) -> Bool {
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
fn wire_rule_103(value : Json) -> Bool {
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
fn wire_rule_104(value : Json) -> Bool {
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
fn wire_rule_105(value : Json) -> Bool {
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
fn wire_rule_99(value : Json) -> Bool {
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
    if !wire_rule_100(item) {
      return false
    }
  }
  if fields.get("authorityScopeCid") is Some(item) {
    if !wire_rule_101(item) {
      return false
    }
  }
  if fields.get("epochNonce") is Some(item) {
    if !wire_rule_102(item) {
      return false
    }
  }
  if fields.get("notBefore") is Some(item) {
    if !wire_rule_103(item) {
      return false
    }
  }
  if fields.get("expiresAt") is Some(item) {
    if !wire_rule_104(item) {
      return false
    }
  }
  if fields.get("authenticator") is Some(item) {
    if !wire_rule_105(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_106(value : Json) -> Bool {
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
fn wire_rule_98(value : Json) -> Bool {
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
    if !wire_rule_99(item) {
      return false
    }
  }
  if fields.get("nonce") is Some(item) {
    if !wire_rule_106(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_107(value : Json) -> Bool {
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
fn wire_rule_111(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "actql-submission-epoch/0.1") {
    return false
  }
  true
}

///|
fn wire_rule_112(value : Json) -> Bool {
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
fn wire_rule_113(value : Json) -> Bool {
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
fn wire_rule_114(value : Json) -> Bool {
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
fn wire_rule_115(value : Json) -> Bool {
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
fn wire_rule_116(value : Json) -> Bool {
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
fn wire_rule_110(value : Json) -> Bool {
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
    if !wire_rule_111(item) {
      return false
    }
  }
  if fields.get("authorityScopeCid") is Some(item) {
    if !wire_rule_112(item) {
      return false
    }
  }
  if fields.get("epochNonce") is Some(item) {
    if !wire_rule_113(item) {
      return false
    }
  }
  if fields.get("notBefore") is Some(item) {
    if !wire_rule_114(item) {
      return false
    }
  }
  if fields.get("expiresAt") is Some(item) {
    if !wire_rule_115(item) {
      return false
    }
  }
  if fields.get("authenticator") is Some(item) {
    if !wire_rule_116(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_117(value : Json) -> Bool {
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
fn wire_rule_109(value : Json) -> Bool {
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
    if !wire_rule_110(item) {
      return false
    }
  }
  if fields.get("nonce") is Some(item) {
    if !wire_rule_117(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_118(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "possible_prior_execution_and_effects") {
    return false
  }
  true
}

///|
fn wire_rule_108(value : Json) -> Bool {
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
    if !wire_rule_109(item) {
      return false
    }
  }
  if fields.get("acknowledgement") is Some(item) {
    if !wire_rule_118(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_96(value : Json) -> Bool {
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
    if !wire_rule_97(item) {
      return false
    }
  }
  if fields.get("submissionRef") is Some(item) {
    if !wire_rule_98(item) {
      return false
    }
  }
  if fields.get("intentCid") is Some(item) {
    if !wire_rule_107(item) {
      return false
    }
  }
  if fields.get("unresolvedHistory") is Some(item) {
    if !wire_rule_108(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_120(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "not_accepted") {
    return false
  }
  true
}

///|
fn wire_rule_123(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "actql-submission-epoch/0.1") {
    return false
  }
  true
}

///|
fn wire_rule_124(value : Json) -> Bool {
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
fn wire_rule_125(value : Json) -> Bool {
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
fn wire_rule_126(value : Json) -> Bool {
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
fn wire_rule_127(value : Json) -> Bool {
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
fn wire_rule_128(value : Json) -> Bool {
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
fn wire_rule_122(value : Json) -> Bool {
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
    if !wire_rule_123(item) {
      return false
    }
  }
  if fields.get("authorityScopeCid") is Some(item) {
    if !wire_rule_124(item) {
      return false
    }
  }
  if fields.get("epochNonce") is Some(item) {
    if !wire_rule_125(item) {
      return false
    }
  }
  if fields.get("notBefore") is Some(item) {
    if !wire_rule_126(item) {
      return false
    }
  }
  if fields.get("expiresAt") is Some(item) {
    if !wire_rule_127(item) {
      return false
    }
  }
  if fields.get("authenticator") is Some(item) {
    if !wire_rule_128(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_129(value : Json) -> Bool {
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
fn wire_rule_121(value : Json) -> Bool {
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
    if !wire_rule_122(item) {
      return false
    }
  }
  if fields.get("nonce") is Some(item) {
    if !wire_rule_129(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_130(value : Json) -> Bool {
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
fn wire_rule_132(value : Json) -> Bool {
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
fn wire_rule_133(value : Json) -> Bool {
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
fn wire_rule_131(value : Json) -> Bool {
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
    if !wire_rule_132(item) {
      return false
    }
  }
  if fields.get("classification") is Some(item) {
    if !wire_rule_133(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_137(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "actql-submission-epoch/0.1") {
    return false
  }
  true
}

///|
fn wire_rule_138(value : Json) -> Bool {
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
fn wire_rule_139(value : Json) -> Bool {
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
fn wire_rule_140(value : Json) -> Bool {
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
fn wire_rule_141(value : Json) -> Bool {
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
fn wire_rule_142(value : Json) -> Bool {
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
fn wire_rule_136(value : Json) -> Bool {
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
    if !wire_rule_137(item) {
      return false
    }
  }
  if fields.get("authorityScopeCid") is Some(item) {
    if !wire_rule_138(item) {
      return false
    }
  }
  if fields.get("epochNonce") is Some(item) {
    if !wire_rule_139(item) {
      return false
    }
  }
  if fields.get("notBefore") is Some(item) {
    if !wire_rule_140(item) {
      return false
    }
  }
  if fields.get("expiresAt") is Some(item) {
    if !wire_rule_141(item) {
      return false
    }
  }
  if fields.get("authenticator") is Some(item) {
    if !wire_rule_142(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_143(value : Json) -> Bool {
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
fn wire_rule_135(value : Json) -> Bool {
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
    if !wire_rule_136(item) {
      return false
    }
  }
  if fields.get("nonce") is Some(item) {
    if !wire_rule_143(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_144(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "possible_prior_execution_and_effects") {
    return false
  }
  true
}

///|
fn wire_rule_134(value : Json) -> Bool {
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
    if !wire_rule_135(item) {
      return false
    }
  }
  if fields.get("acknowledgement") is Some(item) {
    if !wire_rule_144(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_119(value : Json) -> Bool {
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
    if !wire_rule_120(item) {
      return false
    }
  }
  if fields.get("submissionRef") is Some(item) {
    if !wire_rule_121(item) {
      return false
    }
  }
  if fields.get("intentCid") is Some(item) {
    if !wire_rule_130(item) {
      return false
    }
  }
  if fields.get("problem") is Some(item) {
    if !wire_rule_131(item) {
      return false
    }
  }
  if fields.get("unresolvedHistory") is Some(item) {
    if !wire_rule_134(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_146(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "preparation_failed") {
    return false
  }
  true
}

///|
fn wire_rule_149(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "actql-submission-epoch/0.1") {
    return false
  }
  true
}

///|
fn wire_rule_150(value : Json) -> Bool {
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
fn wire_rule_151(value : Json) -> Bool {
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
fn wire_rule_152(value : Json) -> Bool {
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
fn wire_rule_153(value : Json) -> Bool {
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
fn wire_rule_154(value : Json) -> Bool {
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
fn wire_rule_148(value : Json) -> Bool {
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
    if !wire_rule_149(item) {
      return false
    }
  }
  if fields.get("authorityScopeCid") is Some(item) {
    if !wire_rule_150(item) {
      return false
    }
  }
  if fields.get("epochNonce") is Some(item) {
    if !wire_rule_151(item) {
      return false
    }
  }
  if fields.get("notBefore") is Some(item) {
    if !wire_rule_152(item) {
      return false
    }
  }
  if fields.get("expiresAt") is Some(item) {
    if !wire_rule_153(item) {
      return false
    }
  }
  if fields.get("authenticator") is Some(item) {
    if !wire_rule_154(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_155(value : Json) -> Bool {
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
fn wire_rule_147(value : Json) -> Bool {
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
    if !wire_rule_148(item) {
      return false
    }
  }
  if fields.get("nonce") is Some(item) {
    if !wire_rule_155(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_156(value : Json) -> Bool {
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
fn wire_rule_158(value : Json) -> Bool {
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
fn wire_rule_159(value : Json) -> Bool {
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
fn wire_rule_157(value : Json) -> Bool {
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
    if !wire_rule_158(item) {
      return false
    }
  }
  if fields.get("classification") is Some(item) {
    if !wire_rule_159(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_163(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "actql-submission-epoch/0.1") {
    return false
  }
  true
}

///|
fn wire_rule_164(value : Json) -> Bool {
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
fn wire_rule_165(value : Json) -> Bool {
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
fn wire_rule_166(value : Json) -> Bool {
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
fn wire_rule_167(value : Json) -> Bool {
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
fn wire_rule_168(value : Json) -> Bool {
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
fn wire_rule_162(value : Json) -> Bool {
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
    if !wire_rule_163(item) {
      return false
    }
  }
  if fields.get("authorityScopeCid") is Some(item) {
    if !wire_rule_164(item) {
      return false
    }
  }
  if fields.get("epochNonce") is Some(item) {
    if !wire_rule_165(item) {
      return false
    }
  }
  if fields.get("notBefore") is Some(item) {
    if !wire_rule_166(item) {
      return false
    }
  }
  if fields.get("expiresAt") is Some(item) {
    if !wire_rule_167(item) {
      return false
    }
  }
  if fields.get("authenticator") is Some(item) {
    if !wire_rule_168(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_169(value : Json) -> Bool {
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
fn wire_rule_161(value : Json) -> Bool {
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
    if !wire_rule_162(item) {
      return false
    }
  }
  if fields.get("nonce") is Some(item) {
    if !wire_rule_169(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_170(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "possible_prior_execution_and_effects") {
    return false
  }
  true
}

///|
fn wire_rule_160(value : Json) -> Bool {
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
    if !wire_rule_161(item) {
      return false
    }
  }
  if fields.get("acknowledgement") is Some(item) {
    if !wire_rule_170(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_145(value : Json) -> Bool {
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
    if !wire_rule_146(item) {
      return false
    }
  }
  if fields.get("submissionRef") is Some(item) {
    if !wire_rule_147(item) {
      return false
    }
  }
  if fields.get("intentCid") is Some(item) {
    if !wire_rule_156(item) {
      return false
    }
  }
  if fields.get("problem") is Some(item) {
    if !wire_rule_157(item) {
      return false
    }
  }
  if fields.get("unresolvedHistory") is Some(item) {
    if !wire_rule_160(item) {
      return false
    }
  }
  true
}

///|
fn wire_submission_outcome_shape(value : Json) -> Bool {
  if [
      wire_rule_14(value),
      wire_rule_44(value),
      wire_rule_96(value),
      wire_rule_119(value),
      wire_rule_145(value),
    ]
    .filter(fn(ok) { ok })
    .length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_rule_172(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "ready") {
    return false
  }
  true
}

///|
fn wire_rule_175(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "actql-submission-epoch/0.1") {
    return false
  }
  true
}

///|
fn wire_rule_176(value : Json) -> Bool {
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
fn wire_rule_177(value : Json) -> Bool {
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
fn wire_rule_178(value : Json) -> Bool {
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
fn wire_rule_179(value : Json) -> Bool {
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
fn wire_rule_180(value : Json) -> Bool {
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
fn wire_rule_174(value : Json) -> Bool {
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
    if !wire_rule_175(item) {
      return false
    }
  }
  if fields.get("authorityScopeCid") is Some(item) {
    if !wire_rule_176(item) {
      return false
    }
  }
  if fields.get("epochNonce") is Some(item) {
    if !wire_rule_177(item) {
      return false
    }
  }
  if fields.get("notBefore") is Some(item) {
    if !wire_rule_178(item) {
      return false
    }
  }
  if fields.get("expiresAt") is Some(item) {
    if !wire_rule_179(item) {
      return false
    }
  }
  if fields.get("authenticator") is Some(item) {
    if !wire_rule_180(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_181(value : Json) -> Bool {
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
fn wire_rule_173(value : Json) -> Bool {
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
    if !wire_rule_174(item) {
      return false
    }
  }
  if fields.get("nonce") is Some(item) {
    if !wire_rule_181(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_182(value : Json) -> Bool {
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
fn wire_rule_185(value : Json) -> Bool {
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
fn wire_rule_186(value : Json) -> Bool {
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
fn wire_rule_187(value : Json) -> Bool {
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
fn wire_rule_184(value : Json) -> Bool {
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
    if !wire_rule_185(item) {
      return false
    }
  }
  if fields.get("authorityScopeCid") is Some(item) {
    if !wire_rule_186(item) {
      return false
    }
  }
  if fields.get("runDefinitionCid") is Some(item) {
    if !wire_rule_187(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_188(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "volatile" || text == "durable") {
    return false
  }
  true
}

///|
fn wire_rule_189(value : Json) -> Bool {
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
fn wire_rule_183(value : Json) -> Bool {
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
    if !wire_rule_184(item) {
      return false
    }
  }
  if fields.get("durability") is Some(item) {
    if !wire_rule_188(item) {
      return false
    }
  }
  if fields.get("revision") is Some(item) {
    if !wire_rule_189(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_193(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "actql-submission-epoch/0.1") {
    return false
  }
  true
}

///|
fn wire_rule_194(value : Json) -> Bool {
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
fn wire_rule_195(value : Json) -> Bool {
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
fn wire_rule_196(value : Json) -> Bool {
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
fn wire_rule_197(value : Json) -> Bool {
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
fn wire_rule_198(value : Json) -> Bool {
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
fn wire_rule_192(value : Json) -> Bool {
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
    if !wire_rule_193(item) {
      return false
    }
  }
  if fields.get("authorityScopeCid") is Some(item) {
    if !wire_rule_194(item) {
      return false
    }
  }
  if fields.get("epochNonce") is Some(item) {
    if !wire_rule_195(item) {
      return false
    }
  }
  if fields.get("notBefore") is Some(item) {
    if !wire_rule_196(item) {
      return false
    }
  }
  if fields.get("expiresAt") is Some(item) {
    if !wire_rule_197(item) {
      return false
    }
  }
  if fields.get("authenticator") is Some(item) {
    if !wire_rule_198(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_199(value : Json) -> Bool {
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
fn wire_rule_191(value : Json) -> Bool {
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
    if !wire_rule_192(item) {
      return false
    }
  }
  if fields.get("nonce") is Some(item) {
    if !wire_rule_199(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_200(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "possible_prior_execution_and_effects") {
    return false
  }
  true
}

///|
fn wire_rule_190(value : Json) -> Bool {
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
    if !wire_rule_191(item) {
      return false
    }
  }
  if fields.get("acknowledgement") is Some(item) {
    if !wire_rule_200(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_171(value : Json) -> Bool {
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
    if !wire_rule_172(item) {
      return false
    }
  }
  if fields.get("submissionRef") is Some(item) {
    if !wire_rule_173(item) {
      return false
    }
  }
  if fields.get("intentCid") is Some(item) {
    if !wire_rule_182(item) {
      return false
    }
  }
  if fields.get("admission") is Some(item) {
    if !wire_rule_183(item) {
      return false
    }
  }
  if fields.get("unresolvedHistory") is Some(item) {
    if !wire_rule_190(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_202(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "held") {
    return false
  }
  true
}

///|
fn wire_rule_205(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "actql-submission-epoch/0.1") {
    return false
  }
  true
}

///|
fn wire_rule_206(value : Json) -> Bool {
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
fn wire_rule_207(value : Json) -> Bool {
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
fn wire_rule_208(value : Json) -> Bool {
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
fn wire_rule_209(value : Json) -> Bool {
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
fn wire_rule_210(value : Json) -> Bool {
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
fn wire_rule_204(value : Json) -> Bool {
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
    if !wire_rule_205(item) {
      return false
    }
  }
  if fields.get("authorityScopeCid") is Some(item) {
    if !wire_rule_206(item) {
      return false
    }
  }
  if fields.get("epochNonce") is Some(item) {
    if !wire_rule_207(item) {
      return false
    }
  }
  if fields.get("notBefore") is Some(item) {
    if !wire_rule_208(item) {
      return false
    }
  }
  if fields.get("expiresAt") is Some(item) {
    if !wire_rule_209(item) {
      return false
    }
  }
  if fields.get("authenticator") is Some(item) {
    if !wire_rule_210(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_211(value : Json) -> Bool {
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
fn wire_rule_203(value : Json) -> Bool {
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
    if !wire_rule_204(item) {
      return false
    }
  }
  if fields.get("nonce") is Some(item) {
    if !wire_rule_211(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_212(value : Json) -> Bool {
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
fn wire_rule_217(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("endReason") {
    return false
  }
  true
}

///|
fn wire_rule_216(value : Json) -> Bool {
  if wire_rule_217(value) {
    return false
  }
  true
}

///|
fn wire_rule_219(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("terminalErrorCode") {
    return false
  }
  true
}

///|
fn wire_rule_218(value : Json) -> Bool {
  if wire_rule_219(value) {
    return false
  }
  true
}

///|
fn wire_rule_220(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "waiting_checkpoint") {
    return false
  }
  true
}

///|
fn wire_rule_215(value : Json) -> Bool {
  if !wire_rule_216(value) {
    return false
  }
  if !wire_rule_218(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  if !fields.contains("checkpoint") {
    return false
  }
  if fields.get("state") is Some(item) {
    if !wire_rule_220(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_223(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("endReason") {
    return false
  }
  true
}

///|
fn wire_rule_222(value : Json) -> Bool {
  if wire_rule_223(value) {
    return false
  }
  true
}

///|
fn wire_rule_225(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("terminalErrorCode") {
    return false
  }
  true
}

///|
fn wire_rule_224(value : Json) -> Bool {
  if wire_rule_225(value) {
    return false
  }
  true
}

///|
fn wire_rule_226(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "resuming") {
    return false
  }
  true
}

///|
fn wire_rule_221(value : Json) -> Bool {
  if !wire_rule_222(value) {
    return false
  }
  if !wire_rule_224(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  if fields.get("state") is Some(item) {
    if !wire_rule_226(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_228(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "ended") {
    return false
  }
  true
}

///|
fn wire_rule_227(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("endReason") {
    return false
  }
  if fields.get("state") is Some(item) {
    if !wire_rule_228(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_214(value : Json) -> Bool {
  if [wire_rule_215(value), wire_rule_221(value), wire_rule_227(value)]
    .filter(fn(ok) { ok })
    .length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_rule_229(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "held") {
    return false
  }
  true
}

///|
fn wire_rule_230(value : Json) -> Bool {
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
fn wire_rule_231(value : Json) -> Bool {
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
fn wire_rule_232(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "waiting_checkpoint" || text == "resuming" || text == "ended") {
    return false
  }
  true
}

///|
fn wire_rule_233(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "durable") {
    return false
  }
  true
}

///|
fn wire_rule_234(value : Json) -> Bool {
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
fn wire_rule_236(value : Json) -> Bool {
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
fn wire_rule_237(value : Json) -> Bool {
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
fn wire_rule_238(value : Json) -> Bool {
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
fn wire_rule_239(value : Json) -> Bool {
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
fn wire_rule_235(value : Json) -> Bool {
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
    if !wire_rule_236(item) {
      return false
    }
  }
  if fields.get("checkpointCid") is Some(item) {
    if !wire_rule_237(item) {
      return false
    }
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_238(item) {
      return false
    }
  }
  if fields.get("expiresAt") is Some(item) {
    if !wire_rule_239(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_240(value : Json) -> Bool {
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
fn wire_rule_241(value : Json) -> Bool {
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
fn wire_rule_213(value : Json) -> Bool {
  if !wire_rule_214(value) {
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
    if !wire_rule_229(item) {
      return false
    }
  }
  if fields.get("requestId") is Some(item) {
    if !wire_rule_230(item) {
      return false
    }
  }
  if fields.get("prepareAttemptId") is Some(item) {
    if !wire_rule_231(item) {
      return false
    }
  }
  if fields.get("state") is Some(item) {
    if !wire_rule_232(item) {
      return false
    }
  }
  if fields.get("durability") is Some(item) {
    if !wire_rule_233(item) {
      return false
    }
  }
  if fields.get("lookupExpiresAt") is Some(item) {
    if !wire_rule_234(item) {
      return false
    }
  }
  if fields.get("checkpoint") is Some(item) {
    if !wire_rule_235(item) {
      return false
    }
  }
  if fields.get("endReason") is Some(item) {
    if !wire_rule_240(item) {
      return false
    }
  }
  if fields.get("terminalErrorCode") is Some(item) {
    if !wire_rule_241(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_245(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "actql-submission-epoch/0.1") {
    return false
  }
  true
}

///|
fn wire_rule_246(value : Json) -> Bool {
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
fn wire_rule_247(value : Json) -> Bool {
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
fn wire_rule_248(value : Json) -> Bool {
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
fn wire_rule_249(value : Json) -> Bool {
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
fn wire_rule_250(value : Json) -> Bool {
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
fn wire_rule_244(value : Json) -> Bool {
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
    if !wire_rule_245(item) {
      return false
    }
  }
  if fields.get("authorityScopeCid") is Some(item) {
    if !wire_rule_246(item) {
      return false
    }
  }
  if fields.get("epochNonce") is Some(item) {
    if !wire_rule_247(item) {
      return false
    }
  }
  if fields.get("notBefore") is Some(item) {
    if !wire_rule_248(item) {
      return false
    }
  }
  if fields.get("expiresAt") is Some(item) {
    if !wire_rule_249(item) {
      return false
    }
  }
  if fields.get("authenticator") is Some(item) {
    if !wire_rule_250(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_251(value : Json) -> Bool {
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
fn wire_rule_243(value : Json) -> Bool {
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
    if !wire_rule_244(item) {
      return false
    }
  }
  if fields.get("nonce") is Some(item) {
    if !wire_rule_251(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_252(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "possible_prior_execution_and_effects") {
    return false
  }
  true
}

///|
fn wire_rule_242(value : Json) -> Bool {
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
    if !wire_rule_243(item) {
      return false
    }
  }
  if fields.get("acknowledgement") is Some(item) {
    if !wire_rule_252(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_201(value : Json) -> Bool {
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
    if !wire_rule_202(item) {
      return false
    }
  }
  if fields.get("submissionRef") is Some(item) {
    if !wire_rule_203(item) {
      return false
    }
  }
  if fields.get("intentCid") is Some(item) {
    if !wire_rule_212(item) {
      return false
    }
  }
  if fields.get("held") is Some(item) {
    if !wire_rule_213(item) {
      return false
    }
  }
  if fields.get("unresolvedHistory") is Some(item) {
    if !wire_rule_242(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_254(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "preparing") {
    return false
  }
  true
}

///|
fn wire_rule_257(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "actql-submission-epoch/0.1") {
    return false
  }
  true
}

///|
fn wire_rule_258(value : Json) -> Bool {
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
fn wire_rule_259(value : Json) -> Bool {
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
fn wire_rule_260(value : Json) -> Bool {
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
fn wire_rule_261(value : Json) -> Bool {
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
fn wire_rule_262(value : Json) -> Bool {
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
fn wire_rule_256(value : Json) -> Bool {
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
    if !wire_rule_257(item) {
      return false
    }
  }
  if fields.get("authorityScopeCid") is Some(item) {
    if !wire_rule_258(item) {
      return false
    }
  }
  if fields.get("epochNonce") is Some(item) {
    if !wire_rule_259(item) {
      return false
    }
  }
  if fields.get("notBefore") is Some(item) {
    if !wire_rule_260(item) {
      return false
    }
  }
  if fields.get("expiresAt") is Some(item) {
    if !wire_rule_261(item) {
      return false
    }
  }
  if fields.get("authenticator") is Some(item) {
    if !wire_rule_262(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_263(value : Json) -> Bool {
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
fn wire_rule_255(value : Json) -> Bool {
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
    if !wire_rule_256(item) {
      return false
    }
  }
  if fields.get("nonce") is Some(item) {
    if !wire_rule_263(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_264(value : Json) -> Bool {
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
fn wire_rule_268(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "actql-submission-epoch/0.1") {
    return false
  }
  true
}

///|
fn wire_rule_269(value : Json) -> Bool {
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
fn wire_rule_270(value : Json) -> Bool {
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
fn wire_rule_271(value : Json) -> Bool {
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
fn wire_rule_272(value : Json) -> Bool {
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
fn wire_rule_273(value : Json) -> Bool {
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
fn wire_rule_267(value : Json) -> Bool {
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
    if !wire_rule_268(item) {
      return false
    }
  }
  if fields.get("authorityScopeCid") is Some(item) {
    if !wire_rule_269(item) {
      return false
    }
  }
  if fields.get("epochNonce") is Some(item) {
    if !wire_rule_270(item) {
      return false
    }
  }
  if fields.get("notBefore") is Some(item) {
    if !wire_rule_271(item) {
      return false
    }
  }
  if fields.get("expiresAt") is Some(item) {
    if !wire_rule_272(item) {
      return false
    }
  }
  if fields.get("authenticator") is Some(item) {
    if !wire_rule_273(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_274(value : Json) -> Bool {
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
fn wire_rule_266(value : Json) -> Bool {
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
    if !wire_rule_267(item) {
      return false
    }
  }
  if fields.get("nonce") is Some(item) {
    if !wire_rule_274(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_275(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "possible_prior_execution_and_effects") {
    return false
  }
  true
}

///|
fn wire_rule_265(value : Json) -> Bool {
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
    if !wire_rule_266(item) {
      return false
    }
  }
  if fields.get("acknowledgement") is Some(item) {
    if !wire_rule_275(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_253(value : Json) -> Bool {
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
    if !wire_rule_254(item) {
      return false
    }
  }
  if fields.get("submissionRef") is Some(item) {
    if !wire_rule_255(item) {
      return false
    }
  }
  if fields.get("intentCid") is Some(item) {
    if !wire_rule_264(item) {
      return false
    }
  }
  if fields.get("unresolvedHistory") is Some(item) {
    if !wire_rule_265(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_277(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "not_accepted") {
    return false
  }
  true
}

///|
fn wire_rule_280(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "actql-submission-epoch/0.1") {
    return false
  }
  true
}

///|
fn wire_rule_281(value : Json) -> Bool {
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
fn wire_rule_282(value : Json) -> Bool {
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
fn wire_rule_283(value : Json) -> Bool {
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
fn wire_rule_284(value : Json) -> Bool {
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
fn wire_rule_285(value : Json) -> Bool {
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
fn wire_rule_279(value : Json) -> Bool {
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
    if !wire_rule_280(item) {
      return false
    }
  }
  if fields.get("authorityScopeCid") is Some(item) {
    if !wire_rule_281(item) {
      return false
    }
  }
  if fields.get("epochNonce") is Some(item) {
    if !wire_rule_282(item) {
      return false
    }
  }
  if fields.get("notBefore") is Some(item) {
    if !wire_rule_283(item) {
      return false
    }
  }
  if fields.get("expiresAt") is Some(item) {
    if !wire_rule_284(item) {
      return false
    }
  }
  if fields.get("authenticator") is Some(item) {
    if !wire_rule_285(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_286(value : Json) -> Bool {
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
fn wire_rule_278(value : Json) -> Bool {
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
    if !wire_rule_279(item) {
      return false
    }
  }
  if fields.get("nonce") is Some(item) {
    if !wire_rule_286(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_287(value : Json) -> Bool {
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
fn wire_rule_289(value : Json) -> Bool {
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
fn wire_rule_290(value : Json) -> Bool {
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
fn wire_rule_288(value : Json) -> Bool {
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
    if !wire_rule_289(item) {
      return false
    }
  }
  if fields.get("classification") is Some(item) {
    if !wire_rule_290(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_294(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "actql-submission-epoch/0.1") {
    return false
  }
  true
}

///|
fn wire_rule_295(value : Json) -> Bool {
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
fn wire_rule_296(value : Json) -> Bool {
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
fn wire_rule_297(value : Json) -> Bool {
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
fn wire_rule_298(value : Json) -> Bool {
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
fn wire_rule_299(value : Json) -> Bool {
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
fn wire_rule_293(value : Json) -> Bool {
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
    if !wire_rule_294(item) {
      return false
    }
  }
  if fields.get("authorityScopeCid") is Some(item) {
    if !wire_rule_295(item) {
      return false
    }
  }
  if fields.get("epochNonce") is Some(item) {
    if !wire_rule_296(item) {
      return false
    }
  }
  if fields.get("notBefore") is Some(item) {
    if !wire_rule_297(item) {
      return false
    }
  }
  if fields.get("expiresAt") is Some(item) {
    if !wire_rule_298(item) {
      return false
    }
  }
  if fields.get("authenticator") is Some(item) {
    if !wire_rule_299(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_300(value : Json) -> Bool {
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
fn wire_rule_292(value : Json) -> Bool {
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
    if !wire_rule_293(item) {
      return false
    }
  }
  if fields.get("nonce") is Some(item) {
    if !wire_rule_300(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_301(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "possible_prior_execution_and_effects") {
    return false
  }
  true
}

///|
fn wire_rule_291(value : Json) -> Bool {
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
    if !wire_rule_292(item) {
      return false
    }
  }
  if fields.get("acknowledgement") is Some(item) {
    if !wire_rule_301(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_276(value : Json) -> Bool {
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
    if !wire_rule_277(item) {
      return false
    }
  }
  if fields.get("submissionRef") is Some(item) {
    if !wire_rule_278(item) {
      return false
    }
  }
  if fields.get("intentCid") is Some(item) {
    if !wire_rule_287(item) {
      return false
    }
  }
  if fields.get("problem") is Some(item) {
    if !wire_rule_288(item) {
      return false
    }
  }
  if fields.get("unresolvedHistory") is Some(item) {
    if !wire_rule_291(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_303(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "preparation_failed") {
    return false
  }
  true
}

///|
fn wire_rule_306(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "actql-submission-epoch/0.1") {
    return false
  }
  true
}

///|
fn wire_rule_307(value : Json) -> Bool {
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
fn wire_rule_308(value : Json) -> Bool {
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
fn wire_rule_309(value : Json) -> Bool {
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
fn wire_rule_310(value : Json) -> Bool {
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
fn wire_rule_311(value : Json) -> Bool {
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
fn wire_rule_305(value : Json) -> Bool {
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
    if !wire_rule_306(item) {
      return false
    }
  }
  if fields.get("authorityScopeCid") is Some(item) {
    if !wire_rule_307(item) {
      return false
    }
  }
  if fields.get("epochNonce") is Some(item) {
    if !wire_rule_308(item) {
      return false
    }
  }
  if fields.get("notBefore") is Some(item) {
    if !wire_rule_309(item) {
      return false
    }
  }
  if fields.get("expiresAt") is Some(item) {
    if !wire_rule_310(item) {
      return false
    }
  }
  if fields.get("authenticator") is Some(item) {
    if !wire_rule_311(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_312(value : Json) -> Bool {
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
fn wire_rule_304(value : Json) -> Bool {
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
    if !wire_rule_305(item) {
      return false
    }
  }
  if fields.get("nonce") is Some(item) {
    if !wire_rule_312(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_313(value : Json) -> Bool {
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
fn wire_rule_315(value : Json) -> Bool {
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
fn wire_rule_316(value : Json) -> Bool {
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
fn wire_rule_314(value : Json) -> Bool {
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
    if !wire_rule_315(item) {
      return false
    }
  }
  if fields.get("classification") is Some(item) {
    if !wire_rule_316(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_320(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "actql-submission-epoch/0.1") {
    return false
  }
  true
}

///|
fn wire_rule_321(value : Json) -> Bool {
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
fn wire_rule_322(value : Json) -> Bool {
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
fn wire_rule_323(value : Json) -> Bool {
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
fn wire_rule_324(value : Json) -> Bool {
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
fn wire_rule_325(value : Json) -> Bool {
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
fn wire_rule_319(value : Json) -> Bool {
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
    if !wire_rule_320(item) {
      return false
    }
  }
  if fields.get("authorityScopeCid") is Some(item) {
    if !wire_rule_321(item) {
      return false
    }
  }
  if fields.get("epochNonce") is Some(item) {
    if !wire_rule_322(item) {
      return false
    }
  }
  if fields.get("notBefore") is Some(item) {
    if !wire_rule_323(item) {
      return false
    }
  }
  if fields.get("expiresAt") is Some(item) {
    if !wire_rule_324(item) {
      return false
    }
  }
  if fields.get("authenticator") is Some(item) {
    if !wire_rule_325(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_326(value : Json) -> Bool {
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
fn wire_rule_318(value : Json) -> Bool {
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
    if !wire_rule_319(item) {
      return false
    }
  }
  if fields.get("nonce") is Some(item) {
    if !wire_rule_326(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_327(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "possible_prior_execution_and_effects") {
    return false
  }
  true
}

///|
fn wire_rule_317(value : Json) -> Bool {
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
    if !wire_rule_318(item) {
      return false
    }
  }
  if fields.get("acknowledgement") is Some(item) {
    if !wire_rule_327(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_302(value : Json) -> Bool {
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
    if !wire_rule_303(item) {
      return false
    }
  }
  if fields.get("submissionRef") is Some(item) {
    if !wire_rule_304(item) {
      return false
    }
  }
  if fields.get("intentCid") is Some(item) {
    if !wire_rule_313(item) {
      return false
    }
  }
  if fields.get("problem") is Some(item) {
    if !wire_rule_314(item) {
      return false
    }
  }
  if fields.get("unresolvedHistory") is Some(item) {
    if !wire_rule_317(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_329(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "unresolvable") {
    return false
  }
  true
}

///|
fn wire_rule_332(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "actql-submission-epoch/0.1") {
    return false
  }
  true
}

///|
fn wire_rule_333(value : Json) -> Bool {
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
fn wire_rule_334(value : Json) -> Bool {
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
fn wire_rule_335(value : Json) -> Bool {
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
fn wire_rule_336(value : Json) -> Bool {
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
fn wire_rule_337(value : Json) -> Bool {
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
fn wire_rule_331(value : Json) -> Bool {
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
    if !wire_rule_332(item) {
      return false
    }
  }
  if fields.get("authorityScopeCid") is Some(item) {
    if !wire_rule_333(item) {
      return false
    }
  }
  if fields.get("epochNonce") is Some(item) {
    if !wire_rule_334(item) {
      return false
    }
  }
  if fields.get("notBefore") is Some(item) {
    if !wire_rule_335(item) {
      return false
    }
  }
  if fields.get("expiresAt") is Some(item) {
    if !wire_rule_336(item) {
      return false
    }
  }
  if fields.get("authenticator") is Some(item) {
    if !wire_rule_337(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_338(value : Json) -> Bool {
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
fn wire_rule_330(value : Json) -> Bool {
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
    if !wire_rule_331(item) {
      return false
    }
  }
  if fields.get("nonce") is Some(item) {
    if !wire_rule_338(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_340(value : Json) -> Bool {
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
fn wire_rule_339(value : Json) -> Bool {
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
    if !wire_rule_340(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_344(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "actql-submission-epoch/0.1") {
    return false
  }
  true
}

///|
fn wire_rule_345(value : Json) -> Bool {
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
fn wire_rule_346(value : Json) -> Bool {
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
fn wire_rule_347(value : Json) -> Bool {
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
fn wire_rule_348(value : Json) -> Bool {
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
fn wire_rule_349(value : Json) -> Bool {
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
fn wire_rule_343(value : Json) -> Bool {
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
    if !wire_rule_344(item) {
      return false
    }
  }
  if fields.get("authorityScopeCid") is Some(item) {
    if !wire_rule_345(item) {
      return false
    }
  }
  if fields.get("epochNonce") is Some(item) {
    if !wire_rule_346(item) {
      return false
    }
  }
  if fields.get("notBefore") is Some(item) {
    if !wire_rule_347(item) {
      return false
    }
  }
  if fields.get("expiresAt") is Some(item) {
    if !wire_rule_348(item) {
      return false
    }
  }
  if fields.get("authenticator") is Some(item) {
    if !wire_rule_349(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_350(value : Json) -> Bool {
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
fn wire_rule_342(value : Json) -> Bool {
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
    if !wire_rule_343(item) {
      return false
    }
  }
  if fields.get("nonce") is Some(item) {
    if !wire_rule_350(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_351(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "possible_prior_execution_and_effects") {
    return false
  }
  true
}

///|
fn wire_rule_341(value : Json) -> Bool {
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
    if !wire_rule_342(item) {
      return false
    }
  }
  if fields.get("acknowledgement") is Some(item) {
    if !wire_rule_351(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_328(value : Json) -> Bool {
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
    if !wire_rule_329(item) {
      return false
    }
  }
  if fields.get("submissionRef") is Some(item) {
    if !wire_rule_330(item) {
      return false
    }
  }
  if fields.get("problem") is Some(item) {
    if !wire_rule_339(item) {
      return false
    }
  }
  if fields.get("unresolvedHistory") is Some(item) {
    if !wire_rule_341(item) {
      return false
    }
  }
  true
}

///|
fn wire_submission_lookup_shape(value : Json) -> Bool {
  if [
      wire_rule_171(value),
      wire_rule_201(value),
      wire_rule_253(value),
      wire_rule_276(value),
      wire_rule_302(value),
      wire_rule_328(value),
    ]
    .filter(fn(ok) { ok })
    .length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_rule_354(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "actql-submission-epoch/0.1") {
    return false
  }
  true
}

///|
fn wire_rule_355(value : Json) -> Bool {
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
fn wire_rule_356(value : Json) -> Bool {
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
fn wire_rule_357(value : Json) -> Bool {
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
fn wire_rule_358(value : Json) -> Bool {
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
fn wire_rule_359(value : Json) -> Bool {
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
fn wire_rule_353(value : Json) -> Bool {
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
    if !wire_rule_354(item) {
      return false
    }
  }
  if fields.get("authorityScopeCid") is Some(item) {
    if !wire_rule_355(item) {
      return false
    }
  }
  if fields.get("epochNonce") is Some(item) {
    if !wire_rule_356(item) {
      return false
    }
  }
  if fields.get("notBefore") is Some(item) {
    if !wire_rule_357(item) {
      return false
    }
  }
  if fields.get("expiresAt") is Some(item) {
    if !wire_rule_358(item) {
      return false
    }
  }
  if fields.get("authenticator") is Some(item) {
    if !wire_rule_359(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_360(value : Json) -> Bool {
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
fn wire_rule_352(value : Json) -> Bool {
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
    if !wire_rule_353(item) {
      return false
    }
  }
  if fields.get("nonce") is Some(item) {
    if !wire_rule_360(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_361(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "possible_prior_execution_and_effects") {
    return false
  }
  true
}

///|
fn wire_submission_restart_shape(value : Json) -> Bool {
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
    if !wire_rule_352(item) {
      return false
    }
  }
  if fields.get("acknowledgement") is Some(item) {
    if !wire_rule_361(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_365(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("movementPolicyRef") {
    return false
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
fn wire_rule_367(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("cloudConnectionRef") {
    return false
  }
  true
}

///|
fn wire_rule_366(value : Json) -> Bool {
  if wire_rule_367(value) {
    return false
  }
  true
}

///|
fn wire_rule_368(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "remote") {
    return false
  }
  true
}

///|
fn wire_rule_369(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "remote") {
    return false
  }
  true
}

///|
fn wire_rule_371(value : Json) -> Bool {
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
fn wire_rule_370(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  if items.length() > 0 {
    return false
  }
  for item in items {
    if !wire_rule_371(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_363(value : Json) -> Bool {
  if !wire_rule_364(value) {
    return false
  }
  if !wire_rule_366(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  if fields.get("mode") is Some(item) {
    if !wire_rule_368(item) {
      return false
    }
  }
  if fields.get("owner") is Some(item) {
    if !wire_rule_369(item) {
      return false
    }
  }
  if fields.get("runners") is Some(item) {
    if !wire_rule_370(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_374(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("movementPolicyRef") {
    return false
  }
  true
}

///|
fn wire_rule_373(value : Json) -> Bool {
  if wire_rule_374(value) {
    return false
  }
  true
}

///|
fn wire_rule_376(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("cloudConnectionRef") {
    return false
  }
  true
}

///|
fn wire_rule_375(value : Json) -> Bool {
  if wire_rule_376(value) {
    return false
  }
  true
}

///|
fn wire_rule_377(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "local") {
    return false
  }
  true
}

///|
fn wire_rule_378(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "local") {
    return false
  }
  true
}

///|
fn wire_rule_380(value : Json) -> Bool {
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
fn wire_rule_379(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  if items.length() > 0 {
    return false
  }
  for item in items {
    if !wire_rule_380(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_372(value : Json) -> Bool {
  if !wire_rule_373(value) {
    return false
  }
  if !wire_rule_375(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  if fields.get("mode") is Some(item) {
    if !wire_rule_377(item) {
      return false
    }
  }
  if fields.get("owner") is Some(item) {
    if !wire_rule_378(item) {
      return false
    }
  }
  if fields.get("runners") is Some(item) {
    if !wire_rule_379(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_382(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "hybrid") {
    return false
  }
  true
}

///|
fn wire_rule_383(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "local") {
    return false
  }
  true
}

///|
fn wire_rule_381(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("movementPolicyRef") {
    return false
  }
  if !fields.contains("cloudConnectionRef") {
    return false
  }
  if fields.get("mode") is Some(item) {
    if !wire_rule_382(item) {
      return false
    }
  }
  if fields.get("owner") is Some(item) {
    if !wire_rule_383(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_385(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("cloudConnectionRef") {
    return false
  }
  true
}

///|
fn wire_rule_386(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "hybrid") {
    return false
  }
  true
}

///|
fn wire_rule_387(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "cloud") {
    return false
  }
  true
}

///|
fn wire_rule_389(value : Json) -> Bool {
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
fn wire_rule_388(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  if items.length() < 1 {
    return false
  }
  for item in items {
    if !wire_rule_389(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_384(value : Json) -> Bool {
  if wire_rule_385(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  if !fields.contains("movementPolicyRef") {
    return false
  }
  if fields.get("mode") is Some(item) {
    if !wire_rule_386(item) {
      return false
    }
  }
  if fields.get("owner") is Some(item) {
    if !wire_rule_387(item) {
      return false
    }
  }
  if fields.get("runners") is Some(item) {
    if !wire_rule_388(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_362(value : Json) -> Bool {
  if [
      wire_rule_363(value),
      wire_rule_372(value),
      wire_rule_381(value),
      wire_rule_384(value),
    ]
    .filter(fn(ok) { ok })
    .length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_rule_390(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "local" || text == "remote" || text == "hybrid") {
    return false
  }
  true
}

///|
fn wire_rule_391(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "local" || text == "remote" || text == "cloud") {
    return false
  }
  true
}

///|
fn wire_rule_392(value : Json) -> Bool {
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
fn wire_rule_394(value : Json) -> Bool {
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
fn wire_rule_393(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  for item in items {
    if !wire_rule_394(item) {
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
fn wire_rule_396(value : Json) -> Bool {
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
fn wire_rule_395(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  for item in items {
    if !wire_rule_396(item) {
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
fn wire_rule_397(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "volatile" || text == "durable") {
    return false
  }
  true
}

///|
fn wire_rule_398(value : Json) -> Bool {
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
fn wire_rule_399(value : Json) -> Bool {
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
fn wire_connection_shape(value : Json) -> Bool {
  if !wire_rule_362(value) {
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
    if !wire_rule_390(item) {
      return false
    }
  }
  if fields.get("owner") is Some(item) {
    if !wire_rule_391(item) {
      return false
    }
  }
  if fields.get("workspaceId") is Some(item) {
    if !wire_rule_392(item) {
      return false
    }
  }
  if fields.get("consentRefs") is Some(item) {
    if !wire_rule_393(item) {
      return false
    }
  }
  if fields.get("runners") is Some(item) {
    if !wire_rule_395(item) {
      return false
    }
  }
  if fields.get("durability") is Some(item) {
    if !wire_rule_397(item) {
      return false
    }
  }
  if fields.get("movementPolicyRef") is Some(item) {
    if !wire_rule_398(item) {
      return false
    }
  }
  if fields.get("cloudConnectionRef") is Some(item) {
    if !wire_rule_399(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_400(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "actql-client-host/0.1") {
    return false
  }
  true
}

///|
fn wire_rule_401(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "local" || text == "remote" || text == "hybrid") {
    return false
  }
  true
}

///|
fn wire_rule_402(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "local" || text == "remote" || text == "cloud") {
    return false
  }
  true
}

///|
fn wire_rule_403(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "volatile" || text == "durable") {
    return false
  }
  true
}

///|
fn wire_rule_405(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "actql-submission-epoch/0.1") {
    return false
  }
  true
}

///|
fn wire_rule_406(value : Json) -> Bool {
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
fn wire_rule_407(value : Json) -> Bool {
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
fn wire_rule_408(value : Json) -> Bool {
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
fn wire_rule_409(value : Json) -> Bool {
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
fn wire_rule_410(value : Json) -> Bool {
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
fn wire_rule_404(value : Json) -> Bool {
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
    if !wire_rule_405(item) {
      return false
    }
  }
  if fields.get("authorityScopeCid") is Some(item) {
    if !wire_rule_406(item) {
      return false
    }
  }
  if fields.get("epochNonce") is Some(item) {
    if !wire_rule_407(item) {
      return false
    }
  }
  if fields.get("notBefore") is Some(item) {
    if !wire_rule_408(item) {
      return false
    }
  }
  if fields.get("expiresAt") is Some(item) {
    if !wire_rule_409(item) {
      return false
    }
  }
  if fields.get("authenticator") is Some(item) {
    if !wire_rule_410(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_411(value : Json) -> Bool {
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
fn wire_rule_412(value : Json) -> Bool {
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
fn wire_rule_414(value : Json) -> Bool {
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
fn wire_rule_413(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  for item in items {
    if !wire_rule_414(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_416(value : Json) -> Bool {
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
fn wire_rule_417(value : Json) -> Bool {
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
fn wire_rule_418(value : Json) -> Bool {
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
fn wire_rule_419(value : Json) -> Bool {
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
fn wire_rule_420(value : Json) -> Bool {
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
fn wire_rule_421(value : Json) -> Bool {
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
fn wire_rule_422(value : Json) -> Bool {
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
fn wire_rule_415(value : Json) -> Bool {
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
    if !wire_rule_416(item) {
      return false
    }
  }
  if fields.get("maxRowWireBytes") is Some(item) {
    if !wire_rule_417(item) {
      return false
    }
  }
  if fields.get("maxRowRetainedValueBytes") is Some(item) {
    if !wire_rule_418(item) {
      return false
    }
  }
  if fields.get("maxRetainedValueBytes") is Some(item) {
    if !wire_rule_419(item) {
      return false
    }
  }
  if fields.get("maxRows") is Some(item) {
    if !wire_rule_420(item) {
      return false
    }
  }
  if fields.get("maxBatchRows") is Some(item) {
    if !wire_rule_421(item) {
      return false
    }
  }
  if fields.get("maxBatchRetainedValueBytes") is Some(item) {
    if !wire_rule_422(item) {
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
    if !wire_rule_400(item) {
      return false
    }
  }
  if fields.get("mode") is Some(item) {
    if !wire_rule_401(item) {
      return false
    }
  }
  if fields.get("owner") is Some(item) {
    if !wire_rule_402(item) {
      return false
    }
  }
  if fields.get("durability") is Some(item) {
    if !wire_rule_403(item) {
      return false
    }
  }
  if fields.get("submissionEpoch") is Some(item) {
    if !wire_rule_404(item) {
      return false
    }
  }
  if fields.get("scopeRef") is Some(item) {
    if !wire_rule_411(item) {
      return false
    }
  }
  if fields.get("workspaceId") is Some(item) {
    if !wire_rule_412(item) {
      return false
    }
  }
  if fields.get("capabilities") is Some(item) {
    if !wire_rule_413(item) {
      return false
    }
  }
  if fields.get("limits") is Some(item) {
    if !wire_rule_415(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_424(value : Json) -> Bool {
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
fn wire_rule_425(value : Json) -> Bool {
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
fn wire_rule_426(value : Json) -> Bool {
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
fn wire_rule_423(value : Json) -> Bool {
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
    if !wire_rule_424(item) {
      return false
    }
  }
  if fields.get("authorityScopeCid") is Some(item) {
    if !wire_rule_425(item) {
      return false
    }
  }
  if fields.get("runDefinitionCid") is Some(item) {
    if !wire_rule_426(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_427(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "volatile" || text == "durable") {
    return false
  }
  true
}

///|
fn wire_rule_428(value : Json) -> Bool {
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
fn wire_admission_shape(value : Json) -> Bool {
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
    if !wire_rule_423(item) {
      return false
    }
  }
  if fields.get("durability") is Some(item) {
    if !wire_rule_427(item) {
      return false
    }
  }
  if fields.get("revision") is Some(item) {
    if !wire_rule_428(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_429(value : Json) -> Bool {
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
fn wire_rule_430(value : Json) -> Bool {
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
fn wire_rule_431(value : Json) -> Bool {
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
fn wire_run_ref_shape(value : Json) -> Bool {
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
    if !wire_rule_429(item) {
      return false
    }
  }
  if fields.get("authorityScopeCid") is Some(item) {
    if !wire_rule_430(item) {
      return false
    }
  }
  if fields.get("runDefinitionCid") is Some(item) {
    if !wire_rule_431(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_432(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "found") {
    return false
  }
  true
}

///|
fn wire_rule_433(value : Json) -> Bool {
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
fn wire_rule_435(value : Json) -> Bool {
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
fn wire_rule_436(value : Json) -> Bool {
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
fn wire_rule_437(value : Json) -> Bool {
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
fn wire_rule_434(value : Json) -> Bool {
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
    if !wire_rule_435(item) {
      return false
    }
  }
  if fields.get("authorityScopeCid") is Some(item) {
    if !wire_rule_436(item) {
      return false
    }
  }
  if fields.get("runDefinitionCid") is Some(item) {
    if !wire_rule_437(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_438(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "volatile" || text == "durable") {
    return false
  }
  true
}

///|
fn wire_rule_439(value : Json) -> Bool {
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
    if !wire_rule_432(item) {
      return false
    }
  }
  if fields.get("requestId") is Some(item) {
    if !wire_rule_433(item) {
      return false
    }
  }
  if fields.get("ref") is Some(item) {
    if !wire_rule_434(item) {
      return false
    }
  }
  if fields.get("durability") is Some(item) {
    if !wire_rule_438(item) {
      return false
    }
  }
  if fields.get("lookupExpiresAt") is Some(item) {
    if !wire_rule_439(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_440(value : Json) -> Bool {
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
    if !wire_rule_440(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_441(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "unknown") {
    return false
  }
  true
}

///|
fn wire_rule_442(value : Json) -> Bool {
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
    if !wire_rule_441(item) {
      return false
    }
  }
  if fields.get("reason") is Some(item) {
    if !wire_rule_442(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_446(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("endReason") {
    return false
  }
  true
}

///|
fn wire_rule_445(value : Json) -> Bool {
  if wire_rule_446(value) {
    return false
  }
  true
}

///|
fn wire_rule_448(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("terminalErrorCode") {
    return false
  }
  true
}

///|
fn wire_rule_447(value : Json) -> Bool {
  if wire_rule_448(value) {
    return false
  }
  true
}

///|
fn wire_rule_449(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "waiting_checkpoint") {
    return false
  }
  true
}

///|
fn wire_rule_444(value : Json) -> Bool {
  if !wire_rule_445(value) {
    return false
  }
  if !wire_rule_447(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  if !fields.contains("checkpoint") {
    return false
  }
  if fields.get("state") is Some(item) {
    if !wire_rule_449(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_452(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("endReason") {
    return false
  }
  true
}

///|
fn wire_rule_451(value : Json) -> Bool {
  if wire_rule_452(value) {
    return false
  }
  true
}

///|
fn wire_rule_454(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("terminalErrorCode") {
    return false
  }
  true
}

///|
fn wire_rule_453(value : Json) -> Bool {
  if wire_rule_454(value) {
    return false
  }
  true
}

///|
fn wire_rule_455(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "resuming") {
    return false
  }
  true
}

///|
fn wire_rule_450(value : Json) -> Bool {
  if !wire_rule_451(value) {
    return false
  }
  if !wire_rule_453(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  if fields.get("state") is Some(item) {
    if !wire_rule_455(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_457(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "ended") {
    return false
  }
  true
}

///|
fn wire_rule_456(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("endReason") {
    return false
  }
  if fields.get("state") is Some(item) {
    if !wire_rule_457(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_443(value : Json) -> Bool {
  if [wire_rule_444(value), wire_rule_450(value), wire_rule_456(value)]
    .filter(fn(ok) { ok })
    .length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_rule_458(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "held") {
    return false
  }
  true
}

///|
fn wire_rule_459(value : Json) -> Bool {
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
fn wire_rule_460(value : Json) -> Bool {
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
fn wire_rule_461(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "waiting_checkpoint" || text == "resuming" || text == "ended") {
    return false
  }
  true
}

///|
fn wire_rule_462(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "durable") {
    return false
  }
  true
}

///|
fn wire_rule_463(value : Json) -> Bool {
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
fn wire_rule_465(value : Json) -> Bool {
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
fn wire_rule_466(value : Json) -> Bool {
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
fn wire_rule_467(value : Json) -> Bool {
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
fn wire_rule_468(value : Json) -> Bool {
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
fn wire_rule_464(value : Json) -> Bool {
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
    if !wire_rule_465(item) {
      return false
    }
  }
  if fields.get("checkpointCid") is Some(item) {
    if !wire_rule_466(item) {
      return false
    }
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_467(item) {
      return false
    }
  }
  if fields.get("expiresAt") is Some(item) {
    if !wire_rule_468(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_469(value : Json) -> Bool {
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
fn wire_rule_470(value : Json) -> Bool {
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
fn wire_held_shape(value : Json) -> Bool {
  if !wire_rule_443(value) {
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
    if !wire_rule_458(item) {
      return false
    }
  }
  if fields.get("requestId") is Some(item) {
    if !wire_rule_459(item) {
      return false
    }
  }
  if fields.get("prepareAttemptId") is Some(item) {
    if !wire_rule_460(item) {
      return false
    }
  }
  if fields.get("state") is Some(item) {
    if !wire_rule_461(item) {
      return false
    }
  }
  if fields.get("durability") is Some(item) {
    if !wire_rule_462(item) {
      return false
    }
  }
  if fields.get("lookupExpiresAt") is Some(item) {
    if !wire_rule_463(item) {
      return false
    }
  }
  if fields.get("checkpoint") is Some(item) {
    if !wire_rule_464(item) {
      return false
    }
  }
  if fields.get("endReason") is Some(item) {
    if !wire_rule_469(item) {
      return false
    }
  }
  if fields.get("terminalErrorCode") is Some(item) {
    if !wire_rule_470(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_471(value : Json) -> Bool {
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
fn wire_rule_472(value : Json) -> Bool {
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
fn wire_rule_473(value : Json) -> Bool {
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
fn wire_rule_474(value : Json) -> Bool {
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
fn wire_rule_475(value : Json) -> Bool {
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
    if !wire_rule_471(item) {
      return false
    }
  }
  if fields.get("authorityScopeCid") is Some(item) {
    if !wire_rule_472(item) {
      return false
    }
  }
  if fields.get("runDefinitionCid") is Some(item) {
    if !wire_rule_473(item) {
      return false
    }
  }
  if fields.get("cancelId") is Some(item) {
    if !wire_rule_474(item) {
      return false
    }
  }
  if fields.get("expectedRevision") is Some(item) {
    if !wire_rule_475(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_477(value : Json) -> Bool {
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
fn wire_rule_478(value : Json) -> Bool {
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
fn wire_rule_479(value : Json) -> Bool {
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
fn wire_rule_476(value : Json) -> Bool {
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
    if !wire_rule_477(item) {
      return false
    }
  }
  if fields.get("authorityScopeCid") is Some(item) {
    if !wire_rule_478(item) {
      return false
    }
  }
  if fields.get("runDefinitionCid") is Some(item) {
    if !wire_rule_479(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_480(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "accepted" ||
    text == "already_requested" ||
    text == "already_terminal") {
    return false
  }
  true
}

///|
fn wire_rule_481(value : Json) -> Bool {
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
fn wire_rule_483(value : Json) -> Bool {
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
fn wire_rule_484(value : Json) -> Bool {
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
fn wire_rule_485(value : Json) -> Bool {
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
fn wire_rule_486(value : Json) -> Bool {
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
fn wire_rule_487(value : Json) -> Bool {
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
fn wire_rule_482(value : Json) -> Bool {
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
    if !wire_rule_483(item) {
      return false
    }
  }
  if fields.get("authorityScopeCid") is Some(item) {
    if !wire_rule_484(item) {
      return false
    }
  }
  if fields.get("runDefinitionCid") is Some(item) {
    if !wire_rule_485(item) {
      return false
    }
  }
  if fields.get("cancelId") is Some(item) {
    if !wire_rule_486(item) {
      return false
    }
  }
  if fields.get("expectedRevision") is Some(item) {
    if !wire_rule_487(item) {
      return false
    }
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
    if !wire_rule_476(item) {
      return false
    }
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_480(item) {
      return false
    }
  }
  if fields.get("revision") is Some(item) {
    if !wire_rule_481(item) {
      return false
    }
  }
  if fields.get("cancelRef") is Some(item) {
    if !wire_rule_482(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_489(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "found") {
    return false
  }
  true
}

///|
fn wire_rule_492(value : Json) -> Bool {
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
fn wire_rule_493(value : Json) -> Bool {
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
fn wire_rule_494(value : Json) -> Bool {
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
fn wire_rule_491(value : Json) -> Bool {
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
    if !wire_rule_492(item) {
      return false
    }
  }
  if fields.get("authorityScopeCid") is Some(item) {
    if !wire_rule_493(item) {
      return false
    }
  }
  if fields.get("runDefinitionCid") is Some(item) {
    if !wire_rule_494(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_495(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "accepted" ||
    text == "already_requested" ||
    text == "already_terminal") {
    return false
  }
  true
}

///|
fn wire_rule_496(value : Json) -> Bool {
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
fn wire_rule_498(value : Json) -> Bool {
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
fn wire_rule_499(value : Json) -> Bool {
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
fn wire_rule_500(value : Json) -> Bool {
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
fn wire_rule_501(value : Json) -> Bool {
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
fn wire_rule_502(value : Json) -> Bool {
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
fn wire_rule_497(value : Json) -> Bool {
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
    if !wire_rule_498(item) {
      return false
    }
  }
  if fields.get("authorityScopeCid") is Some(item) {
    if !wire_rule_499(item) {
      return false
    }
  }
  if fields.get("runDefinitionCid") is Some(item) {
    if !wire_rule_500(item) {
      return false
    }
  }
  if fields.get("cancelId") is Some(item) {
    if !wire_rule_501(item) {
      return false
    }
  }
  if fields.get("expectedRevision") is Some(item) {
    if !wire_rule_502(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_490(value : Json) -> Bool {
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
    if !wire_rule_491(item) {
      return false
    }
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_495(item) {
      return false
    }
  }
  if fields.get("revision") is Some(item) {
    if !wire_rule_496(item) {
      return false
    }
  }
  if fields.get("cancelRef") is Some(item) {
    if !wire_rule_497(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_488(value : Json) -> Bool {
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
    if !wire_rule_489(item) {
      return false
    }
  }
  if fields.get("cancellation") is Some(item) {
    if !wire_rule_490(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_504(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "unknown") {
    return false
  }
  true
}

///|
fn wire_rule_506(value : Json) -> Bool {
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
fn wire_rule_507(value : Json) -> Bool {
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
fn wire_rule_508(value : Json) -> Bool {
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
fn wire_rule_509(value : Json) -> Bool {
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
fn wire_rule_510(value : Json) -> Bool {
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
fn wire_rule_505(value : Json) -> Bool {
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
    if !wire_rule_506(item) {
      return false
    }
  }
  if fields.get("authorityScopeCid") is Some(item) {
    if !wire_rule_507(item) {
      return false
    }
  }
  if fields.get("runDefinitionCid") is Some(item) {
    if !wire_rule_508(item) {
      return false
    }
  }
  if fields.get("cancelId") is Some(item) {
    if !wire_rule_509(item) {
      return false
    }
  }
  if fields.get("expectedRevision") is Some(item) {
    if !wire_rule_510(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_503(value : Json) -> Bool {
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
    if !wire_rule_504(item) {
      return false
    }
  }
  if fields.get("cancelRef") is Some(item) {
    if !wire_rule_505(item) {
      return false
    }
  }
  true
}

///|
fn wire_cancellation_lookup_shape(value : Json) -> Bool {
  if [wire_rule_488(value), wire_rule_503(value)].filter(fn(ok) { ok }).length() !=
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
fn wire_rule_511(value : Json) -> Bool {
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
fn wire_held(value : Json, expected : String) -> Bool {
  if !wire_rule_511(Json::string(expected)) {
    return false
  }
  guard value is Object(fields) else { return false }
  wire_held_shape(value) &&
  fields.get("requestId") == Some(Json::string(expected))
}

///|
fn wire_rule_512(value : Json) -> Bool {
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
fn wire_request_lookup(value : Json, expected : String) -> Bool {
  if !wire_rule_512(Json::string(expected)) {
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
