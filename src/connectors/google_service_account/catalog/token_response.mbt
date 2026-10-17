///|
pub(all) struct TokenResponseLimits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_token_bytes : Int
  max_lifetime_seconds : Int
  max_scopes : Int
  max_scope_bytes : Int
}

///|
pub(all) enum TokenResponseIssue {
  InvalidLimits
  BudgetExceeded
  InvalidStatus
  InvalidResponse
  ProviderRejected
  InvalidToken
  InvalidTokenType
  InvalidLifetime
  InvalidScopes
} derive(Eq, Debug)

///|
/// Private Credential material, not a grant, current authorization, journal
/// outcome, cleanup receipt or permission to retry. The physical owner retains
/// the original response and transport custody independently of this projection.
pub struct TokenResponse {
  priv token : String
  priv lifetime_seconds : Int
  priv scopes : Array[String]?
}

///|
fn valid_limits(limits : TokenResponseLimits) -> Bool {
  limits.max_bytes > 0 &&
  limits.max_nodes > 0 &&
  limits.max_depth > 0 &&
  limits.max_token_bytes > 0 &&
  limits.max_lifetime_seconds > 0 &&
  limits.max_scopes > 0 &&
  limits.max_scope_bytes > 0
}

///|
// RFC 6750 b64token; padding is trailing only. Native header construction must
// never receive whitespace, Unicode or control bytes from a token response.
fn bearer_token(value : String) -> Bool {
  if value.is_empty() {
    return false
  }
  let mut padding = false
  let mut content = false
  for unit in value.iter() {
    if unit == '=' {
      padding = true
    } else {
      if padding ||
        !((unit >= 'A' && unit <= 'Z') ||
        (unit >= 'a' && unit <= 'z') ||
        (unit >= '0' && unit <= '9') ||
        unit == '-' ||
        unit == '.' ||
        unit == '_' ||
        unit == '~' ||
        unit == '+' ||
        unit == '/') {
        return false
      }
      content = true
    }
  }
  content
}

///|
fn response_scopes(
  value : String,
  limits : TokenResponseLimits,
) -> Result[Array[String], TokenResponseIssue] {
  if value.is_empty() {
    return Err(InvalidScopes)
  }
  if @utf8.encode(value).length() > limits.max_scope_bytes {
    return Err(BudgetExceeded)
  }
  let mut count = 1
  for unit in value.iter() {
    if unit == ' ' {
      count += 1
      if count > limits.max_scopes {
        return Err(BudgetExceeded)
      }
    } else if unit < '!' || unit > '~' || unit == '"' || unit == '\\' {
      return Err(InvalidScopes)
    }
  }
  let scopes = []
  for scope in value.split(" ") {
    let scope = scope.to_owned()
    if scope.is_empty() {
      return Err(InvalidScopes)
    }
    scopes.push(scope)
  }
  Ok(scopes)
}

///|
/// The existing strict source parser bounds the complete response, including
/// ignored extension members, before materializing private token fields. No
/// second JSON parser, native last-wins fallback or provider error text escapes.
pub fn read_service_account_token_response(
  status : Int,
  bytes : Bytes,
  limits : TokenResponseLimits,
) -> Result[TokenResponse, TokenResponseIssue] {
  if !valid_limits(limits) {
    return Err(InvalidLimits)
  }
  if bytes.length() > limits.max_bytes {
    return Err(BudgetExceeded)
  }
  if status != 200 {
    return Err(InvalidStatus)
  }
  let parsed = match
    @source.parse_json_bytes(bytes, {
      max_input_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(value) => value
    Err(issue) =>
      return Err(
        match issue.issue {
          InputLimit | NodeLimit | DepthLimit => BudgetExceeded
          _ => InvalidResponse
        },
      )
  }
  let cursor = match
    @decode.admit(parsed, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_bytes,
      max_total_string_bytes: limits.max_bytes,
    }) {
    Ok(value) => value
    Err(_) => return Err(BudgetExceeded)
  }
  guard @decode.open_object(cursor) is Ok(root) else {
    return Err(InvalidResponse)
  }
  match @decode.field(root, "error") {
    Missing => ()
    _ => return Err(ProviderRejected)
  }
  guard @decode.lookup(root, "access_token") is Some(token) &&
    @decode.text(token) is Ok(token) &&
    bearer_token(token) else {
    return Err(InvalidToken)
  }
  if @utf8.encode(token).length() > limits.max_token_bytes {
    return Err(BudgetExceeded)
  }
  guard @decode.lookup(root, "token_type") is Some(kind) &&
    @decode.text(kind) is Ok(kind) else {
    return Err(InvalidTokenType)
  }
  // OAuth token_type is case insensitive; do not accept a different scheme.
  if kind.to_lower() != "bearer" {
    return Err(InvalidTokenType)
  }
  guard @decode.lookup(root, "expires_in") is Some(lifetime) &&
    @decode.int32(lifetime) is Ok(lifetime) &&
    lifetime > 0 else {
    return Err(InvalidLifetime)
  }
  if lifetime > limits.max_lifetime_seconds {
    return Err(BudgetExceeded)
  }
  let scopes = match @decode.field(root, "scope") {
    Missing => None
    ExplicitNull => return Err(InvalidScopes)
    Present(value) => {
      guard @decode.text(value) is Ok(text) else { return Err(InvalidScopes) }
      match response_scopes(text, limits) {
        Ok(scopes) => Some(scopes)
        Err(issue) => return Err(issue)
      }
    }
  }
  // OAuth extension members are ignored semantically, but have already paid
  // the same whole-response bytes/nodes/depth/string admission above.
  Ok({ token, lifetime_seconds: lifetime, scopes, })
}

///|
pub fn token_response_access_token(response : TokenResponse) -> String {
  response.token
}

///|
pub fn token_response_lifetime_seconds(response : TokenResponse) -> Int {
  response.lifetime_seconds
}

///|
/// Absence stays absent: requested scopes or an API permission are never
/// synthesized from token success. The Credential issuer checks correspondence.
pub fn token_response_scopes(response : TokenResponse) -> Array[String]? {
  response.scopes.map(scopes => scopes.copy())
}
