///|
// Shared canonical record writer for the existing credential use Owner. The
// caller supplies its closed domain; Remote's historical preimage is unchanged.
fn credential_use_record_body(
  grant_cid : String,
  use_id : String,
  use_ordinal : Int,
  version : String,
) -> Result[String, RemoteCredentialIssue] {
  let writer = @encode.writer(4096, 12, 2) catch {
    _ => return Err(InvalidCredentialGrant)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "grant_cid")
    @encode.string_value(writer, grant_cid)
    @encode.key(writer, "use_id")
    @encode.string_value(writer, use_id)
    @encode.key(writer, "use_ordinal")
    @encode.number_value(writer, use_ordinal.to_double())
    @encode.key(writer, "version")
    @encode.string_value(writer, version)
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(InvalidCredentialGrant)
  }
}
