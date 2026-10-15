///|
pub(all) enum ClientPrivateContinuationRetentionIssue {
  InvalidLedger
  EntriesLimit
}

///|
fn private_retention_text(object : @decode.ObjectView, key : String) -> String? {
  @decode.lookup(object, key).bind(value => @decode.text(value).to_option())
}

///|
fn private_retention_cid(value : String?) -> Bool {
  guard value is Some(text) && text.length() == 71 && text.has_prefix("sha256:") else {
    return false
  }
  for i in 7..<71 {
    let unit = text[i].to_int()
    if !((unit >= 48 && unit <= 57) || (unit >= 97 && unit <= 102)) {
      return false
    }
  }
  true
}

///|
/// Private retention shape ONLY, not original resource admission or custody.
/// The original READ envelope funds input/UTF-8 decoding, Source parser keys,
/// frames and error scratch, Source/decode trees and Node materialization.
/// Neither entry count nor the limits below are a heap price or a byte grant.
/// Preserving parsing rejects duplicate keys without normalizing data or wire.
pub fn check_client_private_continuation_retention(
  bytes : Bytes,
  prepare_attempt_id : String,
  max_wire_bytes : Int,
  max_entries : Int,
) -> Result[Unit, ClientPrivateContinuationRetentionIssue] {
  if max_wire_bytes <= 0 ||
    max_wire_bytes >= 2147483647 ||
    max_entries < 0 ||
    prepare_attempt_id.length() == 0 ||
    prepare_attempt_id.length() > 128 {
    return Err(InvalidLedger)
  }
  for i in 0..<prepare_attempt_id.length() {
    let ch = prepare_attempt_id[i].to_int()
    if !((ch >= 48 && ch <= 57) ||
      (ch >= 65 && ch <= 90) ||
      (ch >= 97 && ch <= 122) ||
      ch == 46 ||
      ch == 95 ||
      ch == 58 ||
      ch == 45) {
      return Err(InvalidLedger)
    }
  }
  // Valid root: <=7 nodes. Each entry: <=7. Admit one extra complete entry
  // for the distinct entry-limit diagnosis. Larger malformed trees still
  // fail before any native JSON.parse materialization. Int64 avoids overflow.
  let nodes = (14L + 7L * max_entries.to_int64())
    .min(max_wire_bytes.to_int64())
    .to_int()
  guard @source.parse_json_bytes_preserving(bytes, {
      max_input_bytes: max_wire_bytes,
      max_nodes: nodes,
      max_depth: 3,
    })
    is Ok(source) &&
    @decode.admit(source, {
      max_nodes: nodes,
      max_depth: 3,
      max_string_bytes: max_wire_bytes,
      max_total_string_bytes: max_wire_bytes,
    })
    is Ok(cursor) &&
    @decode.closed_object(cursor, [
      "version", "prepare_attempt_id", "request_cid", "key_id", "holdings", "abandoned",
    ])
    is Ok(root) &&
    private_retention_text(root, "version") ==
    Some("actql-local-continuation-retention/0.1") &&
    private_retention_text(root, "prepare_attempt_id") ==
    Some(prepare_attempt_id) &&
    private_retention_cid(private_retention_text(root, "request_cid")) &&
    private_retention_cid(private_retention_text(root, "key_id")) &&
    @decode.lookup(root, "holdings") is Some(holdings) &&
    @decode.array_length(holdings) is Some(length) else {
    return Err(InvalidLedger)
  }
  match @decode.field(root, "abandoned") {
    Missing => ()
    Present(value) =>
      if @decode.boolean(value) is Err(_) {
        return Err(InvalidLedger)
      }
    ExplicitNull => return Err(InvalidLedger)
  }
  if length > max_entries {
    return Err(EntriesLimit)
  }
  for i in 0..<length {
    guard @decode.element_at(holdings, i) is Some(entry) &&
      @decode.closed_object(entry, [
        "name", "semantic_cid", "holding_cid", "key_id", "state", "cleanup_error",
      ])
      is Ok(object) &&
      private_retention_text(object, "name") is Some(name) &&
      name.length() > 0 &&
      name.length() <= 128 &&
      private_retention_cid(private_retention_text(object, "semantic_cid")) &&
      private_retention_cid(private_retention_text(object, "holding_cid")) &&
      private_retention_cid(private_retention_text(object, "key_id")) &&
      private_retention_text(object, "state") is Some(state) &&
      (state == "held" || state == "retiring" || state == "retired") else {
      return Err(InvalidLedger)
    }
    match @decode.field(object, "cleanup_error") {
      Missing => ()
      Present(value) =>
        if @decode.text(value) is Err(_) {
          return Err(InvalidLedger)
        }
      ExplicitNull => return Err(InvalidLedger)
    }
  }
  Ok(())
}
