///|
/// Actual membership and secret/key-generation custody belong to the installed
/// Credential supplier. An external reference is not independently an issuer.
#external
type OriginalCredentialAuthenticationMaterial

///|
#export_name("strategyCredentialAuthenticationRequest")
pub fn strategy_credential_authentication_request(
  parent : @credential.RemoteCredentialUse,
  grant : @credential.RemoteCredentialGrant,
  material : OriginalCredentialAuthenticationMaterial,
  method : String,
  path : String,
  media_type : String,
  body : Bytes,
  max_body_bytes : Int,
  deadline_unix_ms : Int64,
) -> @credential.CredentialAuthenticationRequest[
  OriginalCredentialAuthenticationMaterial,
] raise NodeHostFailure {
  match
    @credential.prepare_credential_authentication_request(
      parent, grant, material, method, path, media_type, body, max_body_bytes,
      deadline_unix_ms,
    ) {
    Ok(value) => value
    Err(issue) => raise RemoteCredential(issue)
  }
}

///|
#export_name("strategyCredentialAuthenticationUseBind")
pub fn strategy_credential_authentication_use_bind(
  request : @credential.CredentialAuthenticationRequest[
    OriginalCredentialAuthenticationMaterial,
  ],
  parent : @credential.RemoteCredentialUse,
  credential_use : @credential.RemoteCredentialUse,
  material : OriginalCredentialAuthenticationMaterial,
  method : String,
  path : String,
  media_type : String,
  body : Bytes,
  trusted_now_ms : Int64,
) -> @credential.CredentialAuthenticationOperation[
  OriginalCredentialAuthenticationMaterial,
] raise NodeHostFailure {
  match
    @credential.bind_credential_authentication_use(
      request, parent, credential_use, material, method, path, media_type, body,
      trusted_now_ms,
    ) {
    Ok(value) => value
    Err(issue) => raise RemoteCredential(issue)
  }
}

///|
#export_name("strategyCredentialAuthenticationOperationCheck")
pub fn strategy_credential_authentication_operation_check(
  operation : @credential.CredentialAuthenticationOperation[
    OriginalCredentialAuthenticationMaterial,
  ],
  request : @credential.CredentialAuthenticationRequest[
    OriginalCredentialAuthenticationMaterial,
  ],
  parent : @credential.RemoteCredentialUse,
  credential_use : @credential.RemoteCredentialUse,
  material : OriginalCredentialAuthenticationMaterial,
  method : String,
  path : String,
  media_type : String,
  body : Bytes,
  trusted_now_ms : Int64,
) -> Unit raise NodeHostFailure {
  match
    @credential.check_credential_authentication_operation(
      operation, request, parent, credential_use, material, method, path,
      media_type, body, trusted_now_ms,
    ) {
    Ok(_) => ()
    Err(issue) => raise RemoteCredential(issue)
  }
}
