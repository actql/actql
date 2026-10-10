///|
/// Physical custody only. These bytes have not been projected as an Effect
/// success; current evidence-view permission is the caller's responsibility.
pub(all) struct NativeEffectSavedResponse {
  credential_use_cid : String
  status_code : Int
  body : Bytes
}

///|
/// Original Store-owned row facts. These confer no send or cleanup permission.
/// Only the Native journal can construct custody. Other targets retain the
/// read-only interface and return UnsupportedTarget rather than fabricate it.
#warnings("-struct_never_constructed")
pub struct NativeEffectRowCustody {
  head : @effect.EffectLedgerEntry
  dispatching : @effect.EffectLedgerEntry?
  response : NativeEffectSavedResponse?
}

///|
/// The stored response metadata hashes exact bytes on every target. Physical
/// journal access remains target-specific.
pub fn effect_response_body_digest(body : Bytes) -> String {
  @sha.hex(body)
}
