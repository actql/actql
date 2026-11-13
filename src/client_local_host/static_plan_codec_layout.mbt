///|
/// One artifact's codec-construction DATA, not the complete static-plan issuer
/// and not a funding receipt. The caller must add its other live artifacts,
/// step/port maps, arrays, concatenations and physical controls. `scratch`
/// conservatively includes sequential constructor alternatives and their
/// output-tree overlap; add `retained` when selecting an execution footprint.
pub(all) struct ClientStaticPlanCodecLayout {
  retained : @execution.PreparationRepresentationUnits
  scratch : @execution.PreparationRepresentationUnits
  // Variable Native constructor endpoints, not logical R/E converted to raw.
  // The installed caller's fixed constructor basis remains independently live.
  string_utf16_units : Int64
  builder_utf16_bound : Int64
  wire_bytes : Int64
  reference_array_slots : Int64
  scalar_array_items : Int64
  map_bucket_slots : Int64
} derive(Eq)

///|
/// Parse/canonicalize, seal/hash and read back ONE complete bounded artifact.
/// Geometry includes the self-identity field where applicable. The validator
/// contribution is mandatory: no missing schema recipe becomes zero funding.
/// These arguments are sizing data only; the original owners still validate
/// shape, identity, policy, currentness and resource admission independently.
pub fn client_static_plan_codec_layout(
  geometry : (Int, Int, Int),
  validator : @execution.PreparationRepresentationUnits,
  validator_string_utf16_units : Int64,
  validator_reference_array_slots : Int64,
  validator_scalar_array_items : Int64,
) -> ClientStaticPlanCodecLayout? {
  let (bytes, nodes, depth) = geometry
  if bytes < 1 ||
    nodes < 2 ||
    depth < 1 ||
    validator_string_utf16_units < 0L ||
    validator_reference_array_slots < 0L ||
    validator_scalar_array_items < 0L {
    return None
  }
  guard @execution.preparation_representation_cost(validator) is Some(_) &&
    program_artifact_parse_layout(geometry) is Some(parse) &&
    compilation_canonical_emitter_layout(depth) is Some(emitter) &&
    @encode.hash_writer_construction_inventory(nodes, depth) is Some(hash) &&
    @encode.text_writer_construction_inventory(bytes, nodes, depth)
    is Some(text) &&
    closed_values_sort_scratch_layout(nodes) is Some(sort) &&
    @shape.collection_construction_extent({
      // object_with_string_field: new scalar variant, field tuple, Object and
      // FrozenArray; children and the identity String borrow their owners.
      records: 4L,
      record_references: 5L,
      record_words: 0L,
      reference_arrays: 1L,
      reference_items: nodes.to_int64(),
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(root) else {
    return None
  }
  let root_copy : @execution.PreparationRepresentationUnits = {
    record_headers: root.record_headers,
    reference_slots: root.reference_slots,
    scalar_words: root.scalar_words,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  // The complete wire and concatenated `sha256:` identity are separate from
  // decoded source strings in parse.value. Hash finish owns its digest/hex
  // scratch through its authoritative recipe; aliases are not new Strings.
  let strings : @execution.PreparationRepresentationUnits = {
    record_headers: 2L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: bytes.to_int64() + 71L,
    owned_wire_bytes: 0L,
  }
  // Returned RunEvidenceValue(name,identity,wire,value,wire_usage), the
  // wire-usage Some and three-word tuple, and the Result success carrier.
  let result_carrier : @execution.PreparationRepresentationUnits = {
    record_headers: 4L,
    reference_slots: 7L,
    scalar_words: 3L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  let hash_units : @execution.PreparationRepresentationUnits = {
    record_headers: hash.record_headers,
    reference_slots: hash.reference_slots,
    scalar_words: hash.scalar_words,
    owned_utf16_units: hash.owned_utf16_units,
    owned_wire_bytes: hash.owned_wire_bytes,
  }
  let text_units : @execution.PreparationRepresentationUnits = {
    record_headers: text.record_headers,
    reference_slots: text.reference_slots,
    scalar_words: text.scalar_words,
    owned_utf16_units: text.owned_utf16_units,
    owned_wire_bytes: 0L,
  }
  guard @execution.compose_preparation_representation([
      parse.value,
      root_copy,
      strings,
      result_carrier,
    ])
    is Some(retained) &&
    @execution.compose_preparation_representation([
      parse.temporary,
      emitter,
      hash_units,
      text_units,
      root_copy,
      sort,
      validator,
    ])
    is Some(scratch) else {
    return None
  }
  // Pinned linked Map starts at eight buckets and doubles when inserting past
  // floor(capacity*13/16). Any parser/canonical/writer map has <=nodes keys.
  let buckets = client_static_plan_map_bucket_slots(nodes).unwrap()
  // Pinned grow-only reference Array backing has <=12+3N slots including
  // old/new growth. This also bounds either individual contiguous allocation.
  let arrays = 12L + 3L * nodes.to_int64()
  Some({
    retained,
    scratch,
    string_utf16_units: Int64::max(
      Int64::max(bytes.to_int64(), 71L),
      validator_string_utf16_units,
    ),
    builder_utf16_bound: Int64::max(
      bytes.to_int64(),
      validator_string_utf16_units,
    ),
    wire_bytes: bytes.to_int64(),
    reference_array_slots: Int64::max(arrays, validator_reference_array_slots),
    // SHA hash owner has 8-word state, 64-word schedule and 64-byte block.
    // The latter is conservatively covered by 64 actual Int32 slots too.
    scalar_array_items: Int64::max(64L, validator_scalar_array_items),
    map_bucket_slots: buckets,
  })
}

///|
/// Canonical-value traversal plus one text writer, including returned String.
/// Borrowed tree/input text and any unique-array seen strings are excluded and
/// must remain with their original validator owner. This quotes no parser.
pub fn client_static_plan_canonical_emission_layout(
  geometry : (Int, Int, Int),
) -> @execution.PreparationRepresentationUnits? {
  let (bytes, nodes, depth) = geometry
  guard compilation_canonical_emitter_layout(depth) is Some(emitter) &&
    @encode.text_writer_construction_inventory(bytes, nodes, depth)
    is Some(text) else {
    return None
  }
  @execution.compose_preparation_representation([
    emitter,
    {
      record_headers: text.record_headers,
      reference_slots: text.reference_slots,
      scalar_words: text.scalar_words,
      owned_utf16_units: text.owned_utf16_units,
      owned_wire_bytes: 0L,
    },
  ])
}

///|
/// Pinned Array.sort_by's synchronous recursion/control recipe, using actual
/// element count. Empty arrays keep a conservative one-element control basis.
/// Input/output element storage and opaque runtime stack remain separate.
pub fn client_static_plan_array_sort_layout(
  items : Int,
) -> @execution.PreparationRepresentationUnits? {
  if items < 0 {
    None
  } else {
    closed_values_sort_scratch_layout(Int::max(1, items))
  }
}

///|
/// Largest bucket array of the pinned growing linked Map. Input is actual
/// maximum simultaneously present entries, not a resource policy or byte fee.
pub fn client_static_plan_map_bucket_slots(entries : Int) -> Int64? {
  if entries < 0 {
    return None
  }
  let mut buckets = 8L
  while entries.to_int64() > buckets * 13L / 16L {
    buckets *= 2L
  }
  Some(buckets)
}
