///|
// Use the same journal metadata accumulator as the other original readers.
// Each phase adds only its escaping material to the next phase's baseline.
fn fund_native_model_http_configuration(
  operations : NativeClientJournalOperationAccess,
  retained : @execution.PreparationRepresentationUnits,
  working : @execution.PreparationRepresentationUnits,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  let (header, unit, terminator, array_header, pointer) = @bootstrap.native_managed_value_layout()
  guard header > 0L &&
    array_header >= header &&
    unit == 2L &&
    terminator == unit &&
    pointer > 0L &&
    @execution.preparation_representation_cost(retained) is Some(r) &&
    @execution.preparation_representation_cost(working) is Some(e) &&
    operations.reads.before_metadata_construction is Some(prepare) else {
    return Err(ConfigurationLimit)
  }
  // Each allocation contains a subset of the phase's backing. Reference
  // and scalar slots can share a record, while String and Bytes own their
  // backing separately. The inventories above include builder growth.
  let raw = Int64::max(
    array_header + working.reference_slots * pointer + working.scalar_words * 8L,
    header +
    Int64::max(
      working.owned_utf16_units * unit + terminator,
      working.owned_wire_bytes + 1L,
    ),
  )
  prepare(r, Int64::max(r, e), raw).map_err(_ => ConfigurationLimit)
}

///|
fn native_model_http_configuration_parse(
  body : Bytes,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  normalize_keys? : Bool = false,
) -> @execution.PreparationRepresentationUnits? {
  let bytes = body.length()
  if bytes <= 0 || bytes > max_bytes || max_nodes < 1 || max_depth < 1 {
    return None
  }
  // Every JSON node consumes at least one byte from the same input.
  let nodes = Int::min(max_nodes, bytes)
  let depth = Int::min(max_depth, nodes)
  guard @decode.preserving_json_admission_construction_inventory(
      bytes, nodes, depth,
    )
    is Some(parse) &&
    @source.json_construction_extent(bytes, nodes, depth, normalize_keys~)
    is Some(source) &&
    @source.json_literal_construction_extent(bytes, nodes, depth)
    is Some(literal) else {
    return None
  }
  Some({
    record_headers: parse.record_headers +
    source.record_headers -
    literal.record_headers +
    24L,
    reference_slots: parse.reference_slots +
    source.reference_slots -
    literal.reference_slots +
    40L,
    scalar_words: parse.scalar_words +
    source.scalar_words -
    literal.scalar_words +
    24L,
    // Also back the native UTF8 destination array before it becomes a String.
    owned_utf16_units: parse.owned_utf16_units +
    source.owned_utf16_units -
    literal.owned_utf16_units +
    bytes.to_int64(),
    owned_wire_bytes: 0L,
  })
}

///|
fn native_model_http_utf8_configuration_working(
  provider : Bytes,
  revision : Bytes,
  contract : Bytes,
) -> @execution.PreparationRepresentationUnits {
  let p = provider.length().to_int64()
  let r = revision.length().to_int64()
  let c = contract.length().to_int64()
  {
    record_headers: 12L,
    reference_slots: 12L,
    scalar_words: 12L,
    owned_utf16_units: Int64::max(
      2L * p,
      Int64::max(p + 2L * r, p + r + 2L * c),
    ),
    owned_wire_bytes: 0L,
  }
}

///|
fn native_model_http_metadata_units(
  extent : @environment.RegistryConstructionExtent,
) -> @execution.PreparationRepresentationUnits {
  {
    record_headers: extent.record_headers,
    reference_slots: extent.reference_slots,
    scalar_words: extent.scalar_words,
    owned_utf16_units: extent.owned_utf16_units,
    owned_wire_bytes: extent.owned_wire_bytes,
  }
}

///|
fn native_model_http_profile_construction(
  body : Bytes,
  limits : @environment.Limits,
) -> (
  @execution.PreparationRepresentationUnits,
  @execution.PreparationRepresentationUnits,
)? {
  let nodes = Int::min(body.length(), limits.max_nodes)
  guard native_model_http_configuration_parse(
      body,
      limits.max_bytes,
      nodes,
      limits.max_depth,
      normalize_keys=true,
    )
    is Some(parser) &&
    @environment.wire_hash_construction_extent(nodes) is Some(hashing) else {
    return None
  }
  // Only the typed profile, its installation/limits, at most eight
  // observation references and their projected strings escape this phase.
  let retained : @execution.PreparationRepresentationUnits = {
    record_headers: 48L,
    reference_slots: 72L,
    scalar_words: 48L,
    owned_utf16_units: body.length().to_int64(),
    owned_wire_bytes: 0L,
  }
  // Hash and hash-with-self-CID-omitted use the existing same emitter.
  // The indexed tree stays live while checking each closed record and
  // comparing the two bounded hash results. No parser result is retained.
  let fields = nodes.to_int64()
  guard @execution.compose_preparation_representation([
      parser,
      native_model_http_metadata_units(hashing),
      retained,
      {
        record_headers: 24L + 12L * fields,
        reference_slots: 68L + 24L * fields,
        scalar_words: 48L + 18L * fields,
        owned_utf16_units: 3L * 71L,
        owned_wire_bytes: 512L,
      },
    ])
    is Some(working) else {
    return None
  }
  Some((retained, working))
}

///|
fn native_model_http_capability_construction(
  binding : @publication.RunEvidenceValue,
  configuration : String,
) -> @execution.PreparationRepresentationUnits? {
  let mut peak : @execution.PreparationRepresentationUnits = {
    record_headers: 32L,
    reference_slots: 57L,
    scalar_words: 32L,
    owned_utf16_units: 71L + 133L,
    owned_wire_bytes: 512L,
  }
  // Both original-configuration observations are synchronous and return
  // before the next read. Each parses the binding and configuration with
  // the same canonical reader; the credential reference borrows its text.
  for
    (wire, max_bytes, max_nodes, max_depth) in [
      (@publication.run_evidence_value_json(binding), 16384, 256, 8),
      (configuration, 65536, 4096, 32),
    ] {
    guard @scalar.admit_utf8_length(wire, max_bytes) is Ok(bytes) else {
      return None
    }
    let nodes = Int::min(max_nodes, bytes)
    let depth = Int::min(max_depth, nodes)
    guard @decode.preserving_json_parser_construction_inventory(
        bytes, nodes, depth,
      )
      is Some(parse) &&
      @canonical.source_conversion_construction_extent(
        nodes, nodes, nodes, nodes, depth, bytes,
      )
      is Some(canonical) &&
      @execution.compose_preparation_representation([
        peak,
        {
          record_headers: parse.record_headers +
          canonical.retained.record_headers +
          canonical.scratch.record_headers +
          8L,
          reference_slots: parse.reference_slots +
          canonical.retained.reference_slots +
          canonical.scratch.reference_slots +
          12L,
          scalar_words: parse.scalar_words +
          canonical.retained.scalar_words +
          canonical.scratch.scalar_words +
          8L,
          owned_utf16_units: parse.owned_utf16_units +
          canonical.retained_utf16_units +
          canonical.scratch_utf16_units +
          bytes.to_int64(),
          owned_wire_bytes: 2L * bytes.to_int64(),
        },
      ])
      is Some(total) else {
      return None
    }
    peak = total
  }
  Some(peak)
}
