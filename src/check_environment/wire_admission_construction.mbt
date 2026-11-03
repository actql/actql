///|
/// Geometry of the SAME complete, immutable JSON input selected by the Host.
/// This DATA is observed by its already-funded input owner, before read. It is
/// neither wire admission nor a policy ceiling. No body is parsed here.
pub(all) struct WireAdmissionConstructionGeometry {
  bytes : Int
  nodes : Int
  depth : Int
  fields : Int
  objects : Int
  arrays : Int
  root_fields : Int
  max_fields : Int
  key_utf16_units : Int
  max_key_utf16_units : Int
  members : Int
  snapshots : Int
  catalogs : Int
  manifest_entries : Int
} derive(Eq, Debug)

///|
fn wire_admission_geometry_valid(g : WireAdmissionConstructionGeometry) -> Bool {
  g.bytes > 0 && g.nodes > 0 && g.depth > 0 && g.fields >= 0 &&
  g.objects >= 0 && g.arrays >= 0 && g.root_fields >= 0 &&
  g.max_fields >= g.root_fields && g.max_fields <= g.fields &&
  g.fields < g.nodes && g.objects <= g.nodes && g.arrays <= g.nodes &&
  g.objects.to_int64() + g.arrays.to_int64() <= g.nodes.to_int64() &&
  g.key_utf16_units >= 0 && g.max_key_utf16_units >= 0 &&
  g.max_key_utf16_units <= g.key_utf16_units &&
  g.members >= 0 && g.members <= g.nodes && g.snapshots >= 0 &&
  g.snapshots <= g.members && g.catalogs >= 0 && g.catalogs <= g.members &&
  g.manifest_entries >= 0 && g.manifest_entries <= g.nodes
}

///|
fn wire_admission_units(
  value : @shape.CollectionConstructionExtent,
) -> RegistryConstructionExtent {
  {
    record_headers: value.record_headers,
    reference_slots: value.reference_slots,
    scalar_words: value.scalar_words,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
}

///|
fn wire_admission_add(
  left : RegistryConstructionExtent,
  right : RegistryConstructionExtent,
) -> RegistryConstructionExtent {
  // All input counts are Int-bounded and each original linear family fits
  // Int64. The capacity owner still checks the final tariff conversion.
  {
    record_headers: left.record_headers + right.record_headers,
    reference_slots: left.reference_slots + right.reference_slots,
    scalar_words: left.scalar_words + right.scalar_words,
    owned_utf16_units: left.owned_utf16_units + right.owned_utf16_units,
    owned_wire_bytes: left.owned_wire_bytes + right.owned_wire_bytes,
  }
}

///|
fn wire_admission_envelope_retained(
  g : WireAdmissionConstructionGeometry,
) -> RegistryConstructionExtent {
  let m = g.members.to_int64()
  // WireEnvironment, root CID, policy Cursor and optional manifest Cursor/
  // Some. Each member retains Entry(2R3W), Cursor(2R1W) and its new CID String.
  // Eight section arrays and their outer array retain exactly these entries.
  let value = @shape.collection_construction_extent({
    records: 5L + 3L * m,
    record_references: 11L + 4L * m,
    record_words: 6L + 4L * m,
    reference_arrays: 9L,
    reference_items: 8L + m,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  }).unwrap()
  {
    ..wire_admission_units(value),
    owned_utf16_units: 71L * (m + 1L),
  }
}

///|
fn wire_admission_manifest_scratch(
  g : WireAdmissionConstructionGeometry,
) -> RegistryConstructionExtent {
  let e = g.manifest_entries.to_int64()
  let c = g.catalogs.to_int64()
  let child = @decode.indexed_child_construction_extent()
  let access = member_access_construction_extent()
  // The manifest result is discarded by read. All entries and both selector
  // Maps coexist until that call returns. One catalog/entry ObjectView is
  // reconstructed at a time; it borrows original names and member trees.
  let output = @shape.collection_construction_extent({
    records: 9L + 2L * e + access.record_headers + 8L * child.record_headers,
    record_references: 9L + 4L * e + access.reference_slots +
    8L * child.reference_slots,
    record_words: 10L + access.scalar_words + 8L * child.scalar_words,
    reference_arrays: 3L,
    reference_items: e + 5L,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 2L,
    map_entries: c + e,
  }).unwrap()
  let outer = @decode.closed_object_field_construction_extent(
    Some(g.max_fields), 2, 1L,
  ).unwrap()
  let entry = @decode.closed_object_field_construction_extent(
    Some(g.max_fields), 3, 3L,
  ).unwrap()
  let catalog = @decode.open_object_construction_extent(g.max_fields).unwrap()
  let result = wire_admission_add(
    wire_admission_units(output),
    wire_admission_add(
      wire_admission_units(outer),
      wire_admission_add(wire_admission_units(entry), wire_admission_units(catalog)),
    ),
  )
  { ..result, owned_utf16_units: 71L * e, }
}

///|
/// Existing UTF8 encode, normalized byte-JSON parser, immutable decode index,
/// envelope/member hashes and optional manifest validator. One hash workspace
/// serves successive full/member/manifest calls; it is not multiplied by the
/// number of members. The source input String is borrowed by this constructor.
pub fn wire_admission_construction_extent(
  g : WireAdmissionConstructionGeometry,
) -> RegistryConstructionExtent? {
  if !wire_admission_geometry_valid(g) {
    return None
  }
  guard @source.json_construction_extent(
      g.bytes, g.nodes, g.depth, normalize_keys=false,
    ) is Some(parser) &&
    @unicode.nfc_lf_construction_extent(g.max_key_utf16_units) is Some(normalization) &&
    @unicode.nfc_lf_retained_output_units(g.key_utf16_units.to_int64())
    is Some(normalized_keys) &&
    @decode.admission_construction_inventory(
      g.nodes, g.fields, g.objects, g.arrays, g.depth,
    ) is Some(index) else {
    return None
  }
  // This is the same normalized parser family: its literal construction plus
  // the actual largest key's normalization workspace, all returned key Strings
  // and their cumulative output bound. No key is assumed already normalized.
  let parsed : RegistryConstructionExtent = {
    record_headers: parser.record_headers + normalization.record_headers +
    g.fields.to_int64() + 10L,
    reference_slots: parser.reference_slots + normalization.reference_slots + 16L,
    scalar_words: parser.scalar_words + normalization.scalar_words + 24L,
    // Strict UTF8 decode owns its input String beside parser-owned literals.
    owned_utf16_units: parser.owned_utf16_units + normalization.owned_utf16_units +
    normalized_keys + g.bytes.to_int64(),
    owned_wire_bytes: g.bytes.to_int64(),
  }
  let decoded : RegistryConstructionExtent = {
    record_headers: index.indexed.record_headers + index.keys.record_headers +
    index.ancestry.record_headers + index.controls.record_headers,
    reference_slots: index.indexed.reference_slots + index.keys.reference_slots +
    index.ancestry.reference_slots + index.controls.reference_slots,
    scalar_words: index.indexed.scalar_words + index.keys.scalar_words +
    index.ancestry.scalar_words + index.controls.scalar_words,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  let root = @decode.closed_object_field_construction_extent(
    Some(g.root_fields), 12, 0L,
  ).unwrap()
  let snapshot = @decode.open_object_construction_extent(g.max_fields).unwrap()
  let child = @decode.indexed_child_construction_extent()
  // Limits/Stop/Result/hash-usage controls, six original live lookup roles,
  // allowed root fields and section tags, and original snapshot uniqueness Map.
  // Member depth Ref/Some is allocated once, never one per Entry.
  let controls = @shape.collection_construction_extent({
    records: 18L + 6L * child.record_headers,
    record_references: 18L + 6L * child.reference_slots,
    record_words: 24L + 6L * child.scalar_words,
    reference_arrays: 2L,
    reference_items: 20L,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 1L,
    map_entries: g.snapshots.to_int64(),
  }).unwrap()
  let envelope = wire_admission_add(
    wire_admission_envelope_retained(g),
    wire_admission_add(
      wire_admission_units(controls),
      wire_admission_add(
        wire_admission_units(root),
        wire_admission_add(
          wire_admission_units(snapshot),
          wire_admission_units(member_depth_capture_extent()),
        ),
      ),
    ),
  )
  let hash = wire_hash_construction_extent(g.nodes).unwrap()
  // Raw input SHA has no emitter/tree, but can coexist with the preceding
  // full CID. Reuse the hash owner's zero-node sink/finalization inventory.
  let raw = @encode.hash_writer_construction_inventory(0, 0).unwrap()
  let hashes : RegistryConstructionExtent = {
    record_headers: hash.record_headers + raw.record_headers + 3L,
    reference_slots: hash.reference_slots + raw.reference_slots,
    scalar_words: hash.scalar_words + raw.scalar_words,
    owned_utf16_units: hash.owned_utf16_units + raw.owned_utf16_units + 213L,
    owned_wire_bytes: hash.owned_wire_bytes + raw.owned_wire_bytes,
  }
  Some(wire_admission_add(
    parsed,
    wire_admission_add(
      decoded,
      wire_admission_add(
        envelope,
        wire_admission_add(hashes, wire_admission_manifest_scratch(g)),
      ),
    ),
  ))
}

///|
/// Successful read retains its immutable index, original Source Spans/Strings,
/// canonical member CIDs and section arrays. Parser/normalization/hash/manifest
/// frames are absent only after the SAME synchronous read actually returned.
/// This DATA is not permission to release a failed or running constructor.
pub fn wire_admission_retained_extent(
  g : WireAdmissionConstructionGeometry,
) -> RegistryConstructionExtent? {
  if !wire_admission_geometry_valid(g) {
    return None
  }
  guard @decode.admission_construction_inventory(
      g.nodes, g.fields, g.objects, g.arrays, g.depth,
    ) is Some(index) &&
    @unicode.nfc_lf_retained_output_units(g.key_utf16_units.to_int64())
    is Some(normalized_keys) else {
    return None
  }
  let spans = g.nodes.to_int64() + g.fields.to_int64()
  // Each original Span owns six coordinates and borrows its source-path.
  // A String header per node/field overbounds retained textual leaves/keys.
  // Keep index growth backing conservatively; its temporary ancestry is small
  // and is not used as evidence of a physical allocator/GC release.
  let decoded : RegistryConstructionExtent = {
    record_headers: index.indexed.record_headers + index.ancestry.record_headers +
    2L * spans,
    reference_slots: index.indexed.reference_slots + index.ancestry.reference_slots + spans,
    scalar_words: index.indexed.scalar_words + index.ancestry.scalar_words + 6L * spans,
    owned_utf16_units: g.bytes.to_int64() + normalized_keys,
    owned_wire_bytes: 0L,
  }
  Some(wire_admission_add(decoded, wire_admission_envelope_retained(g)))
}
