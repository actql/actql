///|
/// Physical custody only. These bytes have not been projected as an Effect
/// success; current evidence-view permission is the caller's responsibility.
pub(all) struct NativeEffectSavedResponse {
  credential_use_cid : String
  status_code : Int
  body : Bytes
}
