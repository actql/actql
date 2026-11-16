///|
// A newly admitted nested contract owns its Canonical tree, complete wire and
// measured-usage Some/tuple. Its input is borrowed from the captured context.
// Keep normalization in this packet: data-key capture is not a proof that a
// later semantic contract parser will preserve every original String spelling.
fn publication_local_source_contract_inventory(
  geometry : @encode.EncodingConstructionGeometry,
) -> (
  EffectPreviewIdentityConstructionInventory,
  EffectPreviewIdentityConstructionInventory,
)? {
  let { bytes, nodes, depth, fields, objects, arrays, .. } = geometry
  guard @source.json_shaped_construction_extent(
      bytes,
      nodes,
      depth,
      fields,
      objects + arrays,
      objects,
      geometry.largest_object,
      geometry.strings,
      normalize_keys=false,
    )
    is Some(literal) &&
    @source.json_shaped_construction_extent(
      bytes,
      nodes,
      depth,
      fields,
      objects + arrays,
      objects,
      geometry.largest_object,
      geometry.strings,
      normalize_keys=true,
    )
    is Some(normalized) &&
    @canonical.nfc_lf_retained_output_units(bytes.to_int64())
    is Some(source_text) &&
    source_text <= 2147483647L &&
    @json.source_conversion_construction_extent(
      nodes,
      fields,
      objects,
      arrays,
      depth,
      source_text.to_int(),
    )
    is Some(canonical) &&
    @json.source_conversion_construction_extent(
      nodes, fields, objects, arrays, depth, 0,
    )
    is Some(literal_canonical) else {
    return None
  }
  // Six JSON escape characters per normalized UTF-16 unit also cover the
  // UTF-8 alternative. Retain the original punctuation beside that bound.
  let text = canonical.retained_utf16_units
  guard text <= (2147483647L - bytes.to_int64()) / 6L else { return None }
  let wire = bytes.to_int64() + 6L * text
  guard protocol_wire_codec_construction_inventory(
      wire.to_int(),
      nodes,
      depth,
      geometry=Some(geometry),
      live_keys=Some(0),
    )
    is Some(codec) &&
    normalized.record_headers >= literal.record_headers &&
    normalized.reference_slots >= literal.reference_slots &&
    normalized.scalar_words >= literal.scalar_words &&
    normalized.owned_utf16_units >= literal.owned_utf16_units &&
    canonical.scratch.record_headers >= literal_canonical.scratch.record_headers &&
    canonical.scratch.reference_slots >=
    literal_canonical.scratch.reference_slots &&
    canonical.scratch.scalar_words >= literal_canonical.scratch.scalar_words &&
    canonical.scratch_utf16_units >= literal_canonical.scratch_utf16_units &&
    @shape.collection_construction_extent({
      // PublicationContract has six references; usage adds Some + Int tuple.
      records: 3L,
      record_references: 7L,
      record_words: 3L,
      reference_arrays: 0L,
      reference_items: 0L,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(contract) else {
    return None
  }
  let output : EffectPreviewIdentityConstructionInventory = {
    record_headers: canonical.retained.record_headers + contract.record_headers,
    reference_slots: canonical.retained.reference_slots +
    contract.reference_slots,
    scalar_words: canonical.retained.scalar_words + contract.scalar_words,
    owned_utf16_units: wire + text + 71L,
    owned_wire_bytes: 0L,
  }
  let normalization : EffectPreviewIdentityConstructionInventory = {
    record_headers: normalized.record_headers -
    literal.record_headers +
    canonical.scratch.record_headers -
    literal_canonical.scratch.record_headers,
    reference_slots: normalized.reference_slots -
    literal.reference_slots +
    canonical.scratch.reference_slots -
    literal_canonical.scratch.reference_slots,
    scalar_words: normalized.scalar_words -
    literal.scalar_words +
    canonical.scratch.scalar_words -
    literal_canonical.scratch.scalar_words,
    owned_utf16_units: normalized.owned_utf16_units -
    literal.owned_utf16_units +
    canonical.scratch_utf16_units -
    literal_canonical.scratch_utf16_units +
    2L * text,
    owned_wire_bytes: 0L,
  }
  guard publication_inventory_add(codec, normalization) is Some(peak) else {
    return None
  }
  Some((output, peak))
}

///|
fn publication_local_source_identity_inventory(
  fields : Int,
  depth : Int,
) -> EffectPreviewIdentityConstructionInventory? {
  guard fields >= 0 &&
    depth > 0 &&
    @shape.collection_construction_extent({
      // Preimage Object/FrozenArray/Some and the later ordering evidence,
      // ArtifactCheck, its Some/tuple and provenance continuation. These
      // phases are sequential; keeping their sum also covers refused prefixes.
      records: 8L,
      record_references: 13L,
      record_words: 2L,
      // Root seven-field copy/literal inventory; the exact local_value metadata
      // field lists, detached fields and preimage, plus both Manifest maps.
      reference_arrays: 6L,
      reference_items: 21L + 3L * fields.to_int64(),
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(control) &&
    // The five-key physical holding hash is the only unordered writer here;
    // local_value Canonical identity emitters use fewer simultaneously live keys.
    @encode.hash_writer_live_key_inventory(5, Int::max(2, depth)) is Some(hash) else {
    return None
  }
  Some({
    record_headers: control.record_headers + hash.record_headers,
    reference_slots: control.reference_slots + hash.reference_slots,
    scalar_words: control.scalar_words + hash.scalar_words,
    owned_utf16_units: hash.owned_utf16_units + 135L,
    owned_wire_bytes: hash.owned_wire_bytes,
  })
}

///|
// Workspace of the existing strict local_value Source admission only. Outer name
// inventories belong to the caller. One member's physical Source and four
// semantic contracts coexist; their parser/validator/hash packets are a
// sequential maximum. Nothing from this check escapes to the next member.
fn publication_local_source_construction_inventory(
  context : @json.CanonicalValue,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  work? : ((Int) -> Bool)? = None,
) -> EffectPreviewIdentityConstructionInventory? {
  let zero : EffectPreviewIdentityConstructionInventory = {
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  guard max_bytes > 0 &&
    max_nodes > 0 &&
    max_depth > 0 &&
    @json.object_field(context, "effect_source_artifacts")
    is Some(@json.Object(sources)) &&
    @json.object_field(context, "effect_source_local_inventory") is Some(locals) &&
    locals is @json.Object(_) else {
    return None
  }
  let mut peak = zero
  for index in 0..<@json.array_count(sources) {
    if work is Some(charge) && !charge(1) {
      return None
    }
    let (name, physical) = @json.array_at(sources, index).unwrap()
    guard @json.object_field(locals, name) is Some(local_value) &&
      @json.object_field_count(local_value) == Some(7) &&
      publication_canonical_construction_geometry(
        physical,
        max_bytes,
        max_nodes,
        max_depth,
        work~,
      )
      is Some(geometry) &&
      publication_local_source_contract_inventory(geometry)
      is Some((retained, active)) else {
      return None
    }
    let mut retained = retained
    let mut active = active
    let mut identity = zero
    for field in ["definition", "invocation", "manifest"] {
      if work is Some(charge) && !charge(1) {
        return None
      }
      guard @json.object_field(local_value, field) is Some(value) &&
        publication_canonical_construction_geometry(
          value,
          max_bytes,
          max_nodes,
          max_depth,
          work~,
        )
        is Some(geometry) &&
        publication_local_source_identity_inventory(
          geometry.fields,
          geometry.depth,
        )
        is Some(value) else {
        return None
      }
      identity = publication_inventory_max(identity, value)
    }
    for field in ["artifact", "derivation", "ordering", "retention"] {
      if work is Some(charge) && !charge(1) {
        return None
      }
      guard @json.object_field(local_value, field) is Some(value) &&
        publication_canonical_construction_geometry(
          value,
          max_bytes,
          max_nodes,
          max_depth,
          work~,
        )
        is Some(geometry) &&
        publication_local_source_contract_inventory(geometry)
        is Some((output, codec)) &&
        publication_inventory_add(retained, output) is Some(next) else {
        return None
      }
      retained = next
      active = publication_inventory_max(active, codec)
    }
    guard publication_inventory_add(retained, active) is Some(member_peak) &&
      publication_inventory_add(member_peak, identity) is Some(member_peak) else {
      return None
    }
    peak = publication_inventory_max(peak, member_peak)
  }
  Some(peak)
}
