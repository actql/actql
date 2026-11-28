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

///|
pub(all) enum ClientLocalPrivateEvidenceKeyPurpose {
  ModelEvidenceKey
  EffectReviewKey
}

///|
/// Shared by the existing Host reservation and this preimage encoder.
pub fn client_local_private_evidence_key_codec_limits() -> (Int, Int, Int) {
  (8192, 64, 4)
}

///|
/// Exact preimage for the selected Local Store evidence key. Its callers
/// supply the adopted Host and physical binding in the original Read.
/// The epoch key and physical HMAC remain with the Host.
pub fn client_local_private_evidence_key_preimage(
  adoption_cid : String,
  store_binding : String,
  purpose : ClientLocalPrivateEvidenceKeyPurpose,
) -> Result[Bytes, ClientPublicationStoreBindingIssue] {
  let domain = match purpose {
    ModelEvidenceKey => "actql-native-local-model-evidence-key/0.1"
    EffectReviewKey => "actql-native-local-effect-review-key/0.1"
  }
  try {
    let (bytes, nodes, depth) = client_local_private_evidence_key_codec_limits()
    let writer = @encode.writer(bytes, nodes, depth)
    @encode.begin_object(writer)
    @encode.key(writer, "adoption_cid")
    @encode.string_value(writer, adoption_cid)
    @encode.key(writer, "domain")
    @encode.string_value(writer, domain)
    @encode.key(writer, "store_binding")
    @encode.string_value(writer, store_binding)
    @encode.end_object(writer)
    Ok(@utf8.encode(@encode.finish(writer)))
  } catch {
    _ => Err(Encoding)
  }
}
