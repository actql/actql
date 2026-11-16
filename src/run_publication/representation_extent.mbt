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

///|
/// Retained representation of the SAME admitted dependency after its decoder
/// returns: canonical tree, body/node/reference controls and original Strings.
/// The tuple separates canonical facts, pinned retained controls and UTF-16;
/// no wire is encoded, identity issued, authority checked or lifetime moved.
pub fn captured_effect_dependency_body_representation_extent(
  body : CapturedEffectDependencyBody,
  max_nodes : Int,
  max_depth : Int,
  max_utf16_units : Int,
) -> Result[
  (
    @json.CanonicalRepresentationExtent,
    @shape.CollectionConstructionExtent,
    Int64,
  ),
  PublicationContractIssue,
] {
  if max_nodes < 1 || max_depth < 0 || max_utf16_units < 0 {
    return Err(InvalidLimits)
  }
  let references = body.node.references
  let count = references.length().to_int64()
  let mut text = body.wire.length().to_int64() +
    body.node.kind.length().to_int64() +
    body.node.identity.length().to_int64()
  for reference in references {
    text += reference.kind.length().to_int64() +
      reference.identity.length().to_int64()
  }
  if text > max_utf16_units.to_int64() {
    return Err(Encoding)
  }
  let canonical = match
    @json.representation_extent(
      body.value,
      max_nodes,
      max_depth,
      max_utf16_units - text.to_int(),
    ) {
    Ok(value) => value
    Err(_) => return Err(Encoding)
  }
  guard @shape.reference_array_retained_extent(
      1L,
      references.capacity().to_int64(),
    )
    is Some(array) else {
    return Err(Encoding)
  }
  let measured = body.wire_usage is Some(_)
  // Body H1/R4; node H1/R3/W1; each reference H1/R2; every original
  // String header. A payload Some and its three-word tuple add H2/R1/W4.
  // None is the borrowed inline alternative in the body's existing slot.
  let controls : @shape.CollectionConstructionExtent = {
    record_headers: array.record_headers +
    2L +
    count +
    3L +
    2L * count +
    (if measured { 2L } else { 0L }),
    reference_slots: array.reference_slots +
    7L +
    2L * count +
    (if measured { 1L } else { 0L }),
    scalar_words: array.scalar_words + 1L + (if measured { 4L } else { 0L }),
  }
  Ok((canonical, controls, text))
}
