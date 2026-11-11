///|
/// Read-only facts of the same admitted contract. These are not heap bytes,
/// serialization size, a lifetime transfer or authority. A Host funds its
/// adopted representation before retaining the contract beyond its producer.
pub(all) struct PublicationRepresentationExtent {
  contract_records : Int64
  contract_strings : Int64
  contract_text_utf16_units : Int64
  canonical : @json.CanonicalRepresentationExtent
} derive(Eq, Debug)

///|
/// Include all four contract strings and the original canonical backing tree.
/// Do not reconstruct a contract or adopt a candidate wire to measure it.
pub fn publication_contract_representation_extent(
  contract : PublicationContract,
  max_nodes : Int,
  max_depth : Int,
  max_utf16_units : Int,
) -> Result[PublicationRepresentationExtent, PublicationContractIssue] {
  if max_nodes < 1 || max_depth < 0 || max_utf16_units < 0 {
    return Err(InvalidLimits)
  }
  let text = contract.name.length().to_int64() +
    contract.identity_field.length().to_int64() +
    contract.identity.length().to_int64() +
    contract.wire.length().to_int64()
  if text > max_utf16_units.to_int64() {
    return Err(Encoding)
  }
  let canonical = match
    @json.representation_extent(
      contract.value,
      max_nodes,
      max_depth,
      max_utf16_units - text.to_int(),
    ) {
    Ok(value) => value
    Err(_) => return Err(Encoding)
  }
  Ok({
    contract_records: 1L,
    contract_strings: 4L,
    contract_text_utf16_units: text,
    canonical,
  })
}

///|
/// Same immutable representation facts for an already admitted evidence value.
/// No encoding, admission, hashing or authority observation is repeated.
pub fn run_evidence_value_representation_extent(
  original : RunEvidenceValue,
  max_nodes : Int,
  max_depth : Int,
  max_utf16_units : Int,
) -> Result[PublicationRepresentationExtent, PublicationContractIssue] {
  if max_nodes < 1 || max_depth < 0 || max_utf16_units < 0 {
    return Err(InvalidLimits)
  }
  let text = original.name.length().to_int64() +
    original.identity.length().to_int64() +
    original.wire.length().to_int64()
  if text > max_utf16_units.to_int64() {
    return Err(Encoding)
  }
  let canonical = match
    @json.representation_extent(
      original.value,
      max_nodes,
      max_depth,
      max_utf16_units - text.to_int(),
    ) {
    Ok(value) => value
    Err(_) => return Err(Encoding)
  }
  Ok({
    contract_records: 1L,
    contract_strings: 3L,
    contract_text_utf16_units: text,
    canonical,
  })
}
