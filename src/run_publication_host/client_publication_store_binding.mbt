///|
pub(all) enum ClientPublicationStoreBindingIssue {
  Encoding
} derive(Eq, Debug)

///|
/// Pure existing Native physical binding bytes, not a grant or publication ACK.
/// Only the trusted Host supplies namespace/authority and actual original Store
/// file identity. Admission/current and the original Run journal remain separate.
pub fn client_publication_store_binding_body(
  namespace_id : String,
  authority : String,
  device : UInt64,
  inode : UInt64,
) -> Result[String, ClientPublicationStoreBindingIssue] {
  try {
    let writer = @encode.writer(4096, 8, 2)
    @encode.begin_array(writer)
    for
      value in [namespace_id, authority, device.to_string(), inode.to_string()] {
      @encode.string_value(writer, value)
    }
    @encode.end_array(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(Encoding)
  }
}
