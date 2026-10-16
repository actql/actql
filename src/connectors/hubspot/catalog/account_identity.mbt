///|
pub(all) enum AccountIdentityIssue {
  InvalidLimits
  BudgetExceeded
  InvalidResponse
  ForeignAccount
} derive(Eq, Debug)

///|
/// A projection of the account-details response, not a credential, Account
/// authorization, policy classification, or admitted installed Catalog.
pub struct AccountIdentity {
  portal_id : Int
  response_sha256 : String
}

///|
/// Project the documented int32 portalId through the existing Source/Decode
/// Owners. Other account details remain bounded input, not policy facts.
pub fn project_account_identity(
  bytes : Bytes,
  limits : @source.ParseLimits,
) -> Result[AccountIdentity, AccountIdentityIssue] {
  if limits.max_input_bytes <= 0 ||
    limits.max_input_bytes >= 2147483647 ||
    limits.max_nodes <= 0 ||
    limits.max_depth <= 0 {
    return Err(InvalidLimits)
  }
  let parsed = match @source.parse_json_bytes_preserving(bytes, limits) {
    Ok(value) => value
    Err(issue) =>
      return Err(
        match issue.issue {
          InputLimit | NodeLimit | DepthLimit => BudgetExceeded
          _ => InvalidResponse
        },
      )
  }
  let root = match
    @decode.admit(parsed, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_input_bytes,
      max_total_string_bytes: limits.max_input_bytes,
    }) {
    Ok(value) => value
    Err(issue) =>
      return Err(
        if issue.kind == @decode.BudgetExceeded {
          BudgetExceeded
        } else {
          InvalidResponse
        },
      )
  }
  guard @decode.open_object(root) is Ok(object) &&
    @decode.lookup(object, "portalId") is Some(cursor) &&
    @decode.int32(cursor) is Ok(portal_id) else {
    return Err(InvalidResponse)
  }
  // int32 admission alone sees binary64. Check its original numeric token
  // through Common's exact source-text conversion so a tiny nonzero fraction
  // cannot round into another account's integer identifier.
  let span = @decode.cursor_span(cursor)
  guard span.start_byte >= 0 &&
    span.end_byte > span.start_byte &&
    span.end_byte <= bytes.length() else {
    return Err(InvalidResponse)
  }
  let lexeme = @utf8.decode(bytes[span.start_byte:span.end_byte]) catch {
    _ => return Err(InvalidResponse)
  }
  guard @admitted.normalize_decimal_text(lexeme, 10, 0, limits.max_input_bytes)
    is Ok(exact) &&
    exact == portal_id.to_string() else {
    return Err(InvalidResponse)
  }
  Ok({ portal_id, response_sha256: @sha.hex(bytes), })
}

///|
/// Compare with the original observation's canonical account identifier.
/// Equality does not replace the Credential Owner's same-acquisition binding
/// or any current permission, generation, lifetime, request or use check.
pub fn recheck_account_identity(
  identity : AccountIdentity,
  original_portal_id : String,
) -> Result[Unit, AccountIdentityIssue] {
  if identity.portal_id.to_string() == original_portal_id {
    Ok(())
  } else {
    Err(ForeignAccount)
  }
}
