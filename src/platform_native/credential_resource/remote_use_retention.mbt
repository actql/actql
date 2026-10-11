///|
/// Connect original Remote use custody to the existing Resource Owner. The
/// callback receives its actual nominal use, not a proposed CID or raw wire.
/// It grants no permission and must retain responsibility on failed/uncertain
/// persistence. Local and Local-preparation custody remain separate domains.
pub fn install_native_credential_resource_service_with_use_retention(
  database : @sqlite.Database,
  client : @http.Client,
  operations : Array[NativeCredentialOperation],
  authorize : (NativeCredentialAuthorization) -> Bool,
  retain_use : (@credential.RemoteCredentialUse) -> Result[
    Unit,
    NativeCredentialResourceIssue,
  ],
) -> Result[NativeCredentialResourceService, NativeCredentialResourceIssue] {
  install_native_credential_resource_service_with_clock(
    database,
    client,
    operations,
    authorize,
    fn() { @env.now().reinterpret_as_int64() },
    retain_remote_use=Some(retain_use),
  )
}

///|
fn retain_remote_use_before_send(
  original : NativeOwnedCredentialUse,
  retain_remote_use : ((@credential.RemoteCredentialUse) -> Result[
    Unit,
    NativeCredentialResourceIssue,
  ])?,
) -> Result[Unit, NativeCredentialResourceIssue] {
  match (original, retain_remote_use) {
    (RemoteUse(original), Some(retain)) => retain(original)
    _ => Ok(())
  }
}
