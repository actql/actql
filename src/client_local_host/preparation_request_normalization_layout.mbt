///|
/// Same measured original journal shape through its existing sealer: two
/// canonical roots may coexist with body/complete text; parser/index/sort and
/// writer/hash scratch are sequential constructor material. No codec maximum
/// or guessed text-as-node quantity is used as a construction allocation.
fn request_normalization_publication_extents(
  value : @publication_host.ClientLocalNormalizationConstruction,
) -> (Int64, Int64)? {
  request_evidence_publication_extents(value.complete)
}

///|
// Shared original evidence sealer layout. Domain callers retain their own
// constructor/proof/current/failed-child lifetimes; this projects DATA only.
fn request_evidence_publication_extents(
  shape : @encode.EncodingConstructionGeometry,
) -> (Int64, Int64)? {
  let usage = @encode.construction_geometry_usage(shape)
  guard program_artifact_parse_layout(usage, structure=Some(shape))
    is Some(parse) &&
    @encode.text_writer_construction_inventory(
      shape.bytes,
      shape.nodes,
      shape.depth,
    )
    is Some(writer) &&
    @encode.hash_writer_construction_inventory(shape.nodes, shape.depth)
    is Some(hash) &&
    compilation_canonical_emitter_layout(shape.depth) is Some(emitter) else {
    return None
  }
  // Body and completed wire own immutable text; the final evidence borrows
  // the same canonical descendants. Counting two full values is conservative.
  let wires : @execution.PreparationRepresentationUnits = {
    record_headers: 4L,
    reference_slots: 6L,
    scalar_words: 8L,
    owned_utf16_units: shape.bytes.to_int64() * 2L,
    owned_wire_bytes: 0L,
  }
  let writer : @execution.PreparationRepresentationUnits = {
    record_headers: writer.record_headers,
    reference_slots: writer.reference_slots,
    scalar_words: writer.scalar_words,
    owned_utf16_units: writer.owned_utf16_units,
    owned_wire_bytes: 0L,
  }
  let hash : @execution.PreparationRepresentationUnits = {
    record_headers: hash.record_headers,
    reference_slots: hash.reference_slots,
    scalar_words: hash.scalar_words,
    owned_utf16_units: hash.owned_utf16_units,
    owned_wire_bytes: hash.owned_wire_bytes,
  }
  guard @execution.compose_preparation_representation([
      parse.value,
      parse.value,
      wires,
    ])
    is Some(output) &&
    @execution.compose_preparation_representation([
      parse.temporary,
      parse.temporary,
      writer,
      writer,
      hash,
      emitter,
    ])
    is Some(scratch) &&
    @execution.preparation_representation_cost(output) is Some(output) &&
    @execution.preparation_representation_cost(scratch) is Some(scratch) else {
    return None
  }
  Some((output, scratch))
}
