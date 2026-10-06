// Generated from spec/contracts/actql-client-host.json.
// Run: node scripts/generate-client-host-wire.mjs --write

///|
fn wire_rule_3(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("movementPolicyRef") {
    return false
  }
  true
}

///|
fn wire_rule_2(value : Json) -> Bool {
  if wire_rule_3(value) {
    return false
  }
  true
}

///|
fn wire_rule_5(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("cloudConnectionRef") {
    return false
  }
  true
}

///|
fn wire_rule_4(value : Json) -> Bool {
  if wire_rule_5(value) {
    return false
  }
  true
}

///|
fn wire_rule_6(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "remote") {
    return false
  }
  true
}

///|
fn wire_rule_7(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "remote") {
    return false
  }
  true
}

///|
fn wire_rule_9(value : Json) -> Bool {
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
fn wire_rule_8(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  if items.length() > 0 {
    return false
  }
  for item in items {
    if !wire_rule_9(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_1(value : Json) -> Bool {
  if !wire_rule_2(value) {
    return false
  }
  if !wire_rule_4(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  if fields.get("mode") is Some(item) {
    if !wire_rule_6(item) {
      return false
    }
  }
  if fields.get("owner") is Some(item) {
    if !wire_rule_7(item) {
      return false
    }
  }
  if fields.get("runners") is Some(item) {
    if !wire_rule_8(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_12(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("movementPolicyRef") {
    return false
  }
  true
}

///|
fn wire_rule_11(value : Json) -> Bool {
  if wire_rule_12(value) {
    return false
  }
  true
}

///|
fn wire_rule_14(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("cloudConnectionRef") {
    return false
  }
  true
}

///|
fn wire_rule_13(value : Json) -> Bool {
  if wire_rule_14(value) {
    return false
  }
  true
}

///|
fn wire_rule_15(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "local") {
    return false
  }
  true
}

///|
fn wire_rule_16(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "local") {
    return false
  }
  true
}

///|
fn wire_rule_18(value : Json) -> Bool {
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
fn wire_rule_17(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  if items.length() > 0 {
    return false
  }
  for item in items {
    if !wire_rule_18(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_10(value : Json) -> Bool {
  if !wire_rule_11(value) {
    return false
  }
  if !wire_rule_13(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  if fields.get("mode") is Some(item) {
    if !wire_rule_15(item) {
      return false
    }
  }
  if fields.get("owner") is Some(item) {
    if !wire_rule_16(item) {
      return false
    }
  }
  if fields.get("runners") is Some(item) {
    if !wire_rule_17(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_20(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "hybrid") {
    return false
  }
  true
}

///|
fn wire_rule_21(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "local") {
    return false
  }
  true
}

///|
fn wire_rule_19(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("movementPolicyRef") {
    return false
  }
  if !fields.contains("cloudConnectionRef") {
    return false
  }
  if fields.get("mode") is Some(item) {
    if !wire_rule_20(item) {
      return false
    }
  }
  if fields.get("owner") is Some(item) {
    if !wire_rule_21(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_23(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("cloudConnectionRef") {
    return false
  }
  true
}

///|
fn wire_rule_24(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "hybrid") {
    return false
  }
  true
}

///|
fn wire_rule_25(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "cloud") {
    return false
  }
  true
}

///|
fn wire_rule_27(value : Json) -> Bool {
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
fn wire_rule_26(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  if items.length() < 1 {
    return false
  }
  for item in items {
    if !wire_rule_27(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_22(value : Json) -> Bool {
  if wire_rule_23(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  if !fields.contains("movementPolicyRef") {
    return false
  }
  if fields.get("mode") is Some(item) {
    if !wire_rule_24(item) {
      return false
    }
  }
  if fields.get("owner") is Some(item) {
    if !wire_rule_25(item) {
      return false
    }
  }
  if fields.get("runners") is Some(item) {
    if !wire_rule_26(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_0(value : Json) -> Bool {
  if [
      wire_rule_1(value),
      wire_rule_10(value),
      wire_rule_19(value),
      wire_rule_22(value),
    ]
    .filter(fn(ok) { ok })
    .length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_rule_28(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "local" || text == "remote" || text == "hybrid") {
    return false
  }
  true
}

///|
fn wire_rule_29(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "local" || text == "remote" || text == "cloud") {
    return false
  }
  true
}

///|
fn wire_rule_31(value : Json) -> Bool {
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
fn wire_rule_30(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  for item in items {
    if !wire_rule_31(item) {
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
fn wire_rule_33(value : Json) -> Bool {
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
fn wire_rule_32(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  for item in items {
    if !wire_rule_33(item) {
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
fn wire_rule_34(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "volatile" || text == "durable") {
    return false
  }
  true
}

///|
fn wire_rule_35(value : Json) -> Bool {
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
fn wire_rule_36(value : Json) -> Bool {
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
  if !wire_rule_0(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  for key, _ in fields {
    if !(key == "mode" ||
      key == "owner" ||
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
    if !wire_rule_28(item) {
      return false
    }
  }
  if fields.get("owner") is Some(item) {
    if !wire_rule_29(item) {
      return false
    }
  }
  if fields.get("consentRefs") is Some(item) {
    if !wire_rule_30(item) {
      return false
    }
  }
  if fields.get("runners") is Some(item) {
    if !wire_rule_32(item) {
      return false
    }
  }
  if fields.get("durability") is Some(item) {
    if !wire_rule_34(item) {
      return false
    }
  }
  if fields.get("movementPolicyRef") is Some(item) {
    if !wire_rule_35(item) {
      return false
    }
  }
  if fields.get("cloudConnectionRef") is Some(item) {
    if !wire_rule_36(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_37(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "actql-client-host/0.1") {
    return false
  }
  true
}

///|
fn wire_rule_38(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "local" || text == "remote" || text == "hybrid") {
    return false
  }
  true
}

///|
fn wire_rule_39(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "local" || text == "remote" || text == "cloud") {
    return false
  }
  true
}

///|
fn wire_rule_40(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "volatile" || text == "durable") {
    return false
  }
  true
}

///|
fn wire_rule_41(value : Json) -> Bool {
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
fn wire_rule_43(value : Json) -> Bool {
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
fn wire_rule_42(value : Json) -> Bool {
  guard value is Array(items) else { return false }
  for item in items {
    if !wire_rule_43(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_45(value : Json) -> Bool {
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
fn wire_rule_46(value : Json) -> Bool {
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
fn wire_rule_47(value : Json) -> Bool {
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
fn wire_rule_48(value : Json) -> Bool {
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
fn wire_rule_49(value : Json) -> Bool {
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
fn wire_rule_50(value : Json) -> Bool {
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
fn wire_rule_51(value : Json) -> Bool {
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
fn wire_rule_44(value : Json) -> Bool {
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
    if !wire_rule_45(item) {
      return false
    }
  }
  if fields.get("maxRowWireBytes") is Some(item) {
    if !wire_rule_46(item) {
      return false
    }
  }
  if fields.get("maxRowRetainedValueBytes") is Some(item) {
    if !wire_rule_47(item) {
      return false
    }
  }
  if fields.get("maxRetainedValueBytes") is Some(item) {
    if !wire_rule_48(item) {
      return false
    }
  }
  if fields.get("maxRows") is Some(item) {
    if !wire_rule_49(item) {
      return false
    }
  }
  if fields.get("maxBatchRows") is Some(item) {
    if !wire_rule_50(item) {
      return false
    }
  }
  if fields.get("maxBatchRetainedValueBytes") is Some(item) {
    if !wire_rule_51(item) {
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
      key == "scopeRef" ||
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
    if !wire_rule_37(item) {
      return false
    }
  }
  if fields.get("mode") is Some(item) {
    if !wire_rule_38(item) {
      return false
    }
  }
  if fields.get("owner") is Some(item) {
    if !wire_rule_39(item) {
      return false
    }
  }
  if fields.get("durability") is Some(item) {
    if !wire_rule_40(item) {
      return false
    }
  }
  if fields.get("scopeRef") is Some(item) {
    if !wire_rule_41(item) {
      return false
    }
  }
  if fields.get("capabilities") is Some(item) {
    if !wire_rule_42(item) {
      return false
    }
  }
  if fields.get("limits") is Some(item) {
    if !wire_rule_44(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_53(value : Json) -> Bool {
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
fn wire_rule_54(value : Json) -> Bool {
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
fn wire_rule_52(value : Json) -> Bool {
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
    if !wire_rule_53(item) {
      return false
    }
  }
  if fields.get("authorityScopeCid") is Some(item) {
    if !wire_rule_54(item) {
      return false
    }
  }
  if fields.get("runDefinitionCid") is Some(item) {
    if !wire_rule_55(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_56(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "volatile" || text == "durable") {
    return false
  }
  true
}

///|
fn wire_rule_57(value : Json) -> Bool {
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
    if !wire_rule_52(item) {
      return false
    }
  }
  if fields.get("durability") is Some(item) {
    if !wire_rule_56(item) {
      return false
    }
  }
  if fields.get("revision") is Some(item) {
    if !wire_rule_57(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_58(value : Json) -> Bool {
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
fn wire_rule_59(value : Json) -> Bool {
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
    if !wire_rule_58(item) {
      return false
    }
  }
  if fields.get("authorityScopeCid") is Some(item) {
    if !wire_rule_59(item) {
      return false
    }
  }
  if fields.get("runDefinitionCid") is Some(item) {
    if !wire_rule_60(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_61(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "found") {
    return false
  }
  true
}

///|
fn wire_rule_62(value : Json) -> Bool {
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
fn wire_rule_64(value : Json) -> Bool {
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
fn wire_rule_65(value : Json) -> Bool {
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
fn wire_rule_66(value : Json) -> Bool {
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
fn wire_rule_63(value : Json) -> Bool {
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
    if !wire_rule_64(item) {
      return false
    }
  }
  if fields.get("authorityScopeCid") is Some(item) {
    if !wire_rule_65(item) {
      return false
    }
  }
  if fields.get("runDefinitionCid") is Some(item) {
    if !wire_rule_66(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_67(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "volatile" || text == "durable") {
    return false
  }
  true
}

///|
fn wire_rule_68(value : Json) -> Bool {
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
    if !wire_rule_61(item) {
      return false
    }
  }
  if fields.get("requestId") is Some(item) {
    if !wire_rule_62(item) {
      return false
    }
  }
  if fields.get("ref") is Some(item) {
    if !wire_rule_63(item) {
      return false
    }
  }
  if fields.get("durability") is Some(item) {
    if !wire_rule_67(item) {
      return false
    }
  }
  if fields.get("lookupExpiresAt") is Some(item) {
    if !wire_rule_68(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_69(value : Json) -> Bool {
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
    if !wire_rule_69(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_70(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "unknown") {
    return false
  }
  true
}

///|
fn wire_rule_71(value : Json) -> Bool {
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
    if !wire_rule_70(item) {
      return false
    }
  }
  if fields.get("reason") is Some(item) {
    if !wire_rule_71(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_75(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("endReason") {
    return false
  }
  true
}

///|
fn wire_rule_74(value : Json) -> Bool {
  if wire_rule_75(value) {
    return false
  }
  true
}

///|
fn wire_rule_77(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("terminalErrorCode") {
    return false
  }
  true
}

///|
fn wire_rule_76(value : Json) -> Bool {
  if wire_rule_77(value) {
    return false
  }
  true
}

///|
fn wire_rule_78(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "waiting_checkpoint") {
    return false
  }
  true
}

///|
fn wire_rule_73(value : Json) -> Bool {
  if !wire_rule_74(value) {
    return false
  }
  if !wire_rule_76(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  if !fields.contains("checkpoint") {
    return false
  }
  if fields.get("state") is Some(item) {
    if !wire_rule_78(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_81(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("endReason") {
    return false
  }
  true
}

///|
fn wire_rule_80(value : Json) -> Bool {
  if wire_rule_81(value) {
    return false
  }
  true
}

///|
fn wire_rule_83(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("terminalErrorCode") {
    return false
  }
  true
}

///|
fn wire_rule_82(value : Json) -> Bool {
  if wire_rule_83(value) {
    return false
  }
  true
}

///|
fn wire_rule_84(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "resuming") {
    return false
  }
  true
}

///|
fn wire_rule_79(value : Json) -> Bool {
  if !wire_rule_80(value) {
    return false
  }
  if !wire_rule_82(value) {
    return false
  }
  guard value is Object(fields) else { return false }
  if fields.get("state") is Some(item) {
    if !wire_rule_84(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_86(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "ended") {
    return false
  }
  true
}

///|
fn wire_rule_85(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  if !fields.contains("endReason") {
    return false
  }
  if fields.get("state") is Some(item) {
    if !wire_rule_86(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_72(value : Json) -> Bool {
  if [wire_rule_73(value), wire_rule_79(value), wire_rule_85(value)]
    .filter(fn(ok) { ok })
    .length() !=
    1 {
    return false
  }
  true
}

///|
fn wire_rule_87(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "held") {
    return false
  }
  true
}

///|
fn wire_rule_88(value : Json) -> Bool {
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
fn wire_rule_89(value : Json) -> Bool {
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
fn wire_rule_90(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "waiting_checkpoint" || text == "resuming" || text == "ended") {
    return false
  }
  true
}

///|
fn wire_rule_91(value : Json) -> Bool {
  guard value is String(text) else { return false }
  if !(text == "durable") {
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
fn wire_rule_95(value : Json) -> Bool {
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
fn wire_rule_96(value : Json) -> Bool {
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
fn wire_rule_97(value : Json) -> Bool {
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
fn wire_rule_93(value : Json) -> Bool {
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
    if !wire_rule_94(item) {
      return false
    }
  }
  if fields.get("checkpointCid") is Some(item) {
    if !wire_rule_95(item) {
      return false
    }
  }
  if fields.get("kind") is Some(item) {
    if !wire_rule_96(item) {
      return false
    }
  }
  if fields.get("expiresAt") is Some(item) {
    if !wire_rule_97(item) {
      return false
    }
  }
  true
}

///|
fn wire_rule_98(value : Json) -> Bool {
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
fn wire_rule_99(value : Json) -> Bool {
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
  if !wire_rule_72(value) {
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
    if !wire_rule_87(item) {
      return false
    }
  }
  if fields.get("requestId") is Some(item) {
    if !wire_rule_88(item) {
      return false
    }
  }
  if fields.get("prepareAttemptId") is Some(item) {
    if !wire_rule_89(item) {
      return false
    }
  }
  if fields.get("state") is Some(item) {
    if !wire_rule_90(item) {
      return false
    }
  }
  if fields.get("durability") is Some(item) {
    if !wire_rule_91(item) {
      return false
    }
  }
  if fields.get("lookupExpiresAt") is Some(item) {
    if !wire_rule_92(item) {
      return false
    }
  }
  if fields.get("checkpoint") is Some(item) {
    if !wire_rule_93(item) {
      return false
    }
  }
  if fields.get("endReason") is Some(item) {
    if !wire_rule_98(item) {
      return false
    }
  }
  if fields.get("terminalErrorCode") is Some(item) {
    if !wire_rule_99(item) {
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
fn wire_rule_100(value : Json) -> Bool {
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
  if !wire_rule_100(Json::string(expected)) {
    return false
  }
  guard value is Object(fields) else { return false }
  wire_held_shape(value) &&
  fields.get("requestId") == Some(Json::string(expected))
}

///|
fn wire_rule_101(value : Json) -> Bool {
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
  if !wire_rule_101(Json::string(expected)) {
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
