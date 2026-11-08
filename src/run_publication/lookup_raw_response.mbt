///|
/// Borrow the byte identity from this already admitted closed raw envelope.
/// This is metadata only: the Source supplies original authority and retention;
/// the existing Store must persist and verify those exact bytes separately.
pub fn lookup_raw_response_content(
  original : PublicationContract,
) -> (String, Int64)? {
  guard original.name == "native_file_lookup_raw_response" &&
    contract_string(original, "content_cid") is Some(cid) &&
    contract_count(original, "size_bytes") is Some(count) else {
    return None
  }
  Some((cid, count))
}
