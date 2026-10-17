///|
#export_name("googleServiceAccountReadTokenResponse")
pub fn google_service_account_read_token_response(
  status : Int,
  body : Bytes,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_token_bytes : Int,
  max_lifetime_seconds : Int,
  max_scopes : Int,
  max_scope_bytes : Int,
) -> Result[@catalog.TokenResponse, @catalog.TokenResponseIssue] {
  @catalog.read_service_account_token_response(status, body, {
    max_bytes,
    max_nodes,
    max_depth,
    max_token_bytes,
    max_lifetime_seconds,
    max_scopes,
    max_scope_bytes,
  })
}

///|
#export_name("googleServiceAccountTokenResponseAccessToken")
pub fn google_service_account_token_response_access_token(
  response : @catalog.TokenResponse,
) -> String {
  @catalog.token_response_access_token(response)
}

///|
#export_name("googleServiceAccountTokenResponseLifetimeSeconds")
pub fn google_service_account_token_response_lifetime_seconds(
  response : @catalog.TokenResponse,
) -> Int {
  @catalog.token_response_lifetime_seconds(response)
}

///|
#export_name("googleServiceAccountTokenResponseScopes")
pub fn google_service_account_token_response_scopes(
  response : @catalog.TokenResponse,
) -> Array[String]? {
  @catalog.token_response_scopes(response)
}
