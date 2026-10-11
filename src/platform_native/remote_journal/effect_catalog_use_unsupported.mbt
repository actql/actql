///|
pub fn Journal::effect_catalog_use(
  _self : Journal,
  _request : @remote.DispatchRequest,
  _original_grant : @credential.RemoteCredentialGrant,
  _original_use_id : String,
) -> Result[@credential.RemoteCredentialUse, NativeRemoteJournalIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Journal::retain_effect_catalog_use(
  _self : Journal,
  _request : @remote.DispatchRequest,
  _original_grant : @credential.RemoteCredentialGrant,
  _credential_use : @credential.RemoteCredentialUse,
) -> Result[Unit, NativeRemoteJournalIssue] {
  Err(UnsupportedTarget)
}
