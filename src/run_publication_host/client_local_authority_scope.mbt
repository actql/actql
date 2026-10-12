///|
pub(all) enum ClientLocalAuthorityScopeIssue {
  InvalidInput
  Encoding
} derive(Eq, Debug)

///|
/// Encode the existing Local scope preimage from the original admitted Account.
/// The Host must already hold and revalidate its genuine adoption/current binding.
/// A body or its digest does not adopt a Host, authorize a caller, or repair custody.
pub fn client_local_authority_scope_body(
  account : @authorization.AdmittedAccountConfiguration,
  adoption_cid : String,
  principal : String,
  connection : String,
) -> Result[Bytes, ClientLocalAuthorityScopeIssue] {
  if principal.is_empty() ||
    principal.length() > 512 ||
    connection.is_empty() ||
    connection.length() > 512 {
    return Err(InvalidInput)
  }
  // Preserve the original field order, domain and raw text; no NFC conversion.
  let writer = @encode.writer(8192, 64, 4) catch { _ => return Err(Encoding) }
  try {
    @encode.begin_object(writer)
    for
      (key, text) in [
        ("account_configuration_cid", account.configuration_cid()),
        ("adoption_cid", adoption_cid),
        ("connection", connection),
        ("principal", principal),
        ("version", "actql-native-local-authority-scope/0.1"),
      ] {
      @encode.key(writer, key)
      @encode.string_value(writer, text)
    }
    @encode.end_object(writer)
    Ok(@utf8.encode(@encode.finish(writer)))
  } catch {
    _ => Err(Encoding)
  }
}
