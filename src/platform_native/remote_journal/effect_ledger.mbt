///|
/// Physical custody only. These bytes have not been projected as an Effect
/// success; current evidence-view permission is the caller's responsibility.
pub(all) struct NativeEffectSavedResponse {
  credential_use_cid : String
  status_code : Int
  body : Bytes
}

///|
/// Digest of the exact saved Provider response bytes, without interpretation
/// or normalization. This does not establish Effect success or read authority.
pub fn NativeEffectSavedResponse::body_digest(
  self : NativeEffectSavedResponse,
) -> String {
  @sha.hex(self.body)
}
