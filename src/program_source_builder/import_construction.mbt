///|
/// Logical construction for one original cursor import and its admitted Source
/// snapshot. Original Cursor, document, origin, Spans and value Strings stay
/// borrowed. The outside caller funds repeated occurrences and final emission.
/// This is constructor DATA, not a reservation, admission or backend heap claim.
/// Node count bounds fields and containers independently; text is the complete
/// original key/value UTF16 bound, not a Catalog or policy allowance.
pub fn cursor_import_construction_extent(
  nodes : Int,
  text_utf16 : Int,
) -> @source.JsonLiteralConstructionExtent? {
  if nodes < 1 || text_utf16 < 0 {
    return None
  }
  let n = nodes.to_int64()
  let f = n - 1L
  guard @canonical.nfc_lf_construction_extent(text_utf16) is Some(normalization) &&
    @source.json_tree_retained_construction_extent(
      nodes,
      nodes - 1,
      nodes,
      0,
      normalization.max_output_utf16_units + text_utf16.to_int64(),
      keep_spans=false,
    )
    is Some(tree) &&
    @shape.key_admission_construction_extent(nodes, nodes - 1) is Some(keys) &&
    @wire.admission_construction_inventory(
      nodes,
      nodes - 1,
      nodes,
      nodes,
      nodes,
    )
    is Some(index) &&
    @wire.shallow_value_view_construction_extent(nodes - 1, nodes - 1)
    is Some(view) else {
    return None
  }
  // Two concrete tree families coexist: annotated builder tree and the plain
  // Source tree made by source_map.admit. The Source owner's object endpoint
  // also bounds arrays: both use one container; object fields add more storage.
  // Additional roles not in those trees:
  // - builder Node/Annotation/import Value:3N records,6N refs,6N words;
  // - original/import Field plus replacement Node/Annotation/Some:4F,9F,0;
  // - import and source-map Visit/Finish work:4N,4N,4N;
  // - Source/Usage/Map/Result/tuple and refused/returned carriers:12,16,20.
  // Arrays: both work/value roots5; import children/data and builder children/
  // fields4N; source-map visit/finish children2N. All their input-proportional
  // item counts sum to <=12N. Shared Array/Map owners price growth, not us.
  guard @shape.collection_construction_extent({
      records: 12L + 7L * n + 4L * f,
      record_references: 16L + 10L * n + 9L * f,
      record_words: 20L + 10L * n,
      reference_arrays: 5L + 6L * n,
      reference_items: 12L * n,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(imported) else {
    return None
  }
  // import_cursor's count, child-selection and Finish matches each call the
  // shared shallow view constructor, including detached array children. Keep
  // three largest views together, plus
  // two per-edge access families (scheduled child and current field). Their
  // original Cursor/Option/pair recipes remain owned by Decode.
  let child = @wire.indexed_child_construction_extent()
  let field = @wire.indexed_field_construction_extent()
  // build measures one scalar/key at a time. TextOutput is an explicit upper
  // envelope for that same measuring Writer's frames/control; it also co-counts
  // unused text backing rather than inventing a second measuring-sink tariff.
  // Object keys are measured AFTER normalization; scalar values are unchanged.
  let scalar_bytes = 6L *
    (normalization.max_output_utf16_units + text_utf16.to_int64()) +
    32L
  if scalar_bytes > 2147483647L {
    return None
  }
  guard @encode.text_writer_construction_inventory(scalar_bytes.to_int(), 1, 0)
    is Some(measure) else {
    return None
  }
  Some({
    record_headers: 2L * tree.record_headers +
    imported.record_headers +
    3L * view.record_headers +
    n * (child.record_headers + field.record_headers) +
    keys.record_headers +
    normalization.record_headers +
    measure.record_headers +
    index.indexed.record_headers +
    index.keys.record_headers +
    index.ancestry.record_headers +
    index.controls.record_headers,
    reference_slots: 2L * tree.reference_slots +
    imported.reference_slots +
    3L * view.reference_slots +
    n * (child.reference_slots + field.reference_slots) +
    keys.reference_slots +
    normalization.reference_slots +
    measure.reference_slots +
    index.indexed.reference_slots +
    index.keys.reference_slots +
    index.ancestry.reference_slots +
    index.controls.reference_slots,
    scalar_words: 2L * tree.scalar_words +
    imported.scalar_words +
    3L * view.scalar_words +
    n * (child.scalar_words + field.scalar_words) +
    keys.scalar_words +
    normalization.scalar_words +
    measure.scalar_words +
    index.indexed.scalar_words +
    index.keys.scalar_words +
    index.ancestry.scalar_words +
    index.controls.scalar_words,
    // Both tree envelopes co-count their originally borrowed text. The whole
    // normalization scratch/output remains beside all returned normalized keys.
    owned_utf16_units: 2L * tree.owned_utf16_units +
    normalization.owned_utf16_units +
    measure.owned_utf16_units,
  })
}
