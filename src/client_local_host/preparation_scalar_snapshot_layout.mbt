///|
/// One scalar captured snapshot from the ORIGINAL result-schema/row bound.
/// No post-emission measurement grants capacity. Final canonical rows are
/// borrowed by later capture; no second source parse is priced there.
priv struct ScalarSnapshotLayout {
  retained : PreparationRepresentationUnits
  temporary : PreparationRepresentationUnits
}

///|
fn scalar_snapshot_layout(
  fields : Int,
  name_bytes : Int,
  rows : Int,
) -> ScalarSnapshotLayout? {
  if fields < 0 || name_bytes < 0 || rows < 0 {
    return None
  }
  let f = fields.to_int64()
  let r = rows.to_int64()
  let names = name_bytes.to_int64()
  let k = f * r
  let n = 1L + r + k
  let lexical = 1L + r + 2L * k
  let text = r * names
  guard client_local_scalar_wire_byte_bound(fields, name_bytes, rows)
    is Some(wire_bytes) else {
    return None
  }
  let bytes = wire_bytes.to_int64()
  if n > 2147483645L ||
    lexical > 2147483647L ||
    text > 2147483647L ||
    bytes > 2147483647L {
    return None
  }
  let facts : ClosedValuesLexicalFacts = {
    input_bytes: bytes.to_int(),
    node_upper: lexical.to_int(),
    objects: rows,
    arrays: 1,
    fields_upper: k.to_int(),
    quoted_tokens: k.to_int(),
    quoted_utf16_units: text.to_int(),
    longest_quoted_utf16: name_bytes,
    longest_atom_utf16: 25,
    depth_upper: 2,
  }
  let source = closed_values_source_inventories(facts)
  guard compilation_canonical_layout({
      nodes: n.to_int(),
      arrays: 1,
      objects: rows,
      fields: k.to_int(),
      depth: 2,
      largest_object: if rows == 0 {
        0
      } else {
        fields
      },
    })
    is Some(canonical) else {
    return None
  }
  // Data-key parser and decoder do not normalize. The final canonical tuples
  // borrow decoded key Strings, NOT AST Nodes/Spans or the indexed owner.
  let strings : PreparationRepresentationUnits = {
    record_headers: k,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: text,
    owned_wire_bytes: 0L,
  }
  let snapshot : PreparationRepresentationUnits = {
    record_headers: 1L,
    reference_slots: 5L,
    scalar_words: 3L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  let final_fields = closed_values_program_arrays(1L, f, false)
  guard closed_values_sum_layouts([
      canonical.tree,
      strings,
      snapshot,
      final_fields,
    ])
    is Some(retained) &&
    closed_values_units_subtract(source.source_retained, strings)
    is Some(private_source) else {
    return None
  }
  // Parsing -> indexed admission -> canonical admission may overlap at transfer.
  // Sum their private inventories conservatively. Strings above remain R even
  // after those owners are cleared; no GC or RSS release claim is made.
  guard closed_values_sum_layouts([
      private_source,
      source.source_growth_peak,
      source.indexed_additional,
      source.key_admission_peak,
      source.parser_ancestry_peak,
      source.decoder_ancestry_peak,
      source.parser_controls_peak,
      source.decoder_controls_peak,
    ])
    is Some(source_peak) else {
    return None
  }
  // One active row Object at a time. CursorAdmission keeps root Array output,
  // current row output and at most Read/Next/Append per depth (depth=2 plus
  // scalar leaf). Output backing growth is additional to final canonical tree.
  // Keys: one growing outer Array plus F singleton Arrays. Sort owns two
  // growing Int arrays, Sort(3refs/11words), and validation Some(Int).
  let keys = closed_values_program_arrays(1L + f, 2L * f, true)
  let key_map = closed_values_program_maps(1L, f, true)
  let pending = closed_values_program_arrays(1L, 9L, true)
  let indices : PreparationRepresentationUnits = {
    record_headers: 6L,
    reference_slots: 2L,
    scalar_words: 4L + 24L + 6L * f,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  let admission : PreparationRepresentationUnits = {
    // CursorAdmission, InputBudget, root/value/text/size Options, Utf8Admission;
    // 9 pending variants + current pop, at most3 Cursor wrappers; Sort +Some.
    record_headers: 2L + 5L + 1L + 10L + 3L + 2L,
    reference_slots: 5L + 3L + 1L + 30L + 6L + 4L,
    scalar_words: 9L + 5L + 3L + 30L + 3L + 13L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  let output_growth : PreparationRepresentationUnits = {
    record_headers: 1L + r,
    reference_slots: 4L * (1L + r) + (n - 1L),
    scalar_words: 0L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  // Snapshot owns preparation21slots, phase/result/Some carriers, two growing
  // Arrays (fields+keys), one field singleton per F, and one separate sorter.
  // CanonicalEmit pending <=2*depth+2=8, cursor/rest records <=depth+1=4.
  // Two emitters (text and logical hash) are summed, not lifetime-maxed here.
  let emit_pending = closed_values_program_arrays(2L, 16L, true)
  let emits : PreparationRepresentationUnits = {
    record_headers: 2L + 16L + 8L + 4L,
    reference_slots: 4L + 16L + 8L + 12L,
    scalar_words: 16L + 8L + 20L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  let preparation : PreparationRepresentationUnits = {
    record_headers: 1L + 12L,
    reference_slots: 11L + 18L,
    scalar_words: 11L + 24L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  let field_sort : PreparationRepresentationUnits = {
    record_headers: 2L,
    reference_slots: 4L,
    scalar_words: 13L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  // Current decode.field_at tuple/Some, decode.view tagged scalar, child Cursor
  // and poll/Result carriers beside the retained pending-frame variants.
  let access : PreparationRepresentationUnits = {
    record_headers: 6L,
    reference_slots: 8L,
    scalar_words: 8L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  let field_keys = closed_values_program_arrays(1L + f, 2L * f, true)
  let field_growth = closed_values_program_arrays(1L, f, true)
  // Original rows wire coexists with canonical text/compare; returned text is
  // already covered by the material writer's old/new text packet below.
  let original_wire : PreparationRepresentationUnits = {
    record_headers: 1L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: bytes,
    owned_wire_bytes: 0L,
  }
  guard compilation_writer_ancestry_layout(
      n.to_int() + 2,
      3,
      Int::max(2, fields),
      2,
      1,
      bytes.to_int(),
    )
    is Some(writers) else {
    return None
  }
  guard scalar_snapshot_name_normalization_layout(name_bytes)
    is Some(normalization) &&
    closed_values_sum_layouts([
      source_peak, keys, key_map, pending, indices, admission, output_growth, emit_pending,
      emits, preparation, field_keys, field_growth, indices, writers, normalization,
      field_sort, access,
    ])
    is Some(admission_peak) else {
    return None
  }
  // completed_snapshot_preparation emits the ORIGINAL bare rows first. Its
  // private writer/step state does not escape PublicationSnapshotPhase::Export;
  // only wire and fields pass to Admit. Price these shared returned owners once.
  guard compilation_writer_ancestry_layout(
      n.to_int(),
      2,
      fields,
      1,
      1,
      bytes.to_int(),
    )
    is Some(export_writer) else {
    return None
  }
  let shared_text : PreparationRepresentationUnits = {
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: bytes,
    owned_wire_bytes: 0L,
  }
  guard closed_values_units_subtract(export_writer, shared_text)
    is Some(private_export_writer) else {
    return None
  }
  // CompletedRelationSnapshotPreparation (outer wrapper is shared below)
  // +RowWorkspace; rows/order/receipt/wire Some; Key/Cell phase carriers;
  // OrderedKeyEmitCursor, SteppedRuntimeWire and ScalarWire. Only one scalar
  // cell is active, and its payload borrows the original completed output.
  let export_controls : PreparationRepresentationUnits = {
    record_headers: 13L,
    reference_slots: 23L,
    scalar_words: 21L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  guard closed_values_sum_layouts([private_export_writer, export_controls])
    is Some(export_peak) else {
    return None
  }
  // Componentwise maximum is conservative for the shared tariff. This max is
  // ONLY across the proven Export->Admit phase replacement, not arbitrary
  // parser/index/canonical subcomponents or retained aliases.
  let sequential : PreparationRepresentationUnits = {
    record_headers: Int64::max(
      export_peak.record_headers,
      admission_peak.record_headers,
    ),
    reference_slots: Int64::max(
      export_peak.reference_slots,
      admission_peak.reference_slots,
    ),
    scalar_words: Int64::max(
      export_peak.scalar_words,
      admission_peak.scalar_words,
    ),
    owned_utf16_units: Int64::max(
      export_peak.owned_utf16_units,
      admission_peak.owned_utf16_units,
    ),
    owned_wire_bytes: Int64::max(
      export_peak.owned_wire_bytes,
      admission_peak.owned_wire_bytes,
    ),
  }
  let export_fields = closed_values_program_arrays(1L, f, true)
  // start_captured_result_snapshot runs before phase becomes Admit. The old
  // completed writer therefore overlaps these INITIAL parser/preparation
  // constructors (not the full parsed tree). The access packet also covers
  // two contract_string calls (four Some values, no copied field arrays).
  // Keep the named transition packet
  // outside the phase max; no eager credit merely from finish() being called.
  let initial_arrays = closed_values_program_arrays(2L, 0L, true)
  let outer : PreparationRepresentationUnits = {
    record_headers: 1L,
    reference_slots: 2L,
    scalar_words: 4L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  guard closed_values_sum_layouts([
      sequential,
      original_wire,
      export_fields,
      preparation,
      initial_arrays,
      source.parser_controls_peak,
      source.parser_ancestry_peak,
      outer,
      access,
    ])
    is Some(temporary) else {
    return None
  }
  Some({ retained, temporary, })
}

///|
/// Fields are already canonical but NFC_QC=Maybe still takes the full path.
/// One field at a time; total schema-name UTF8 bounds its UTF16 length. Unicode
/// 16 canonical decomposition <=4 scalars/input scalar (Hangul<=3), recursion4.
/// Existing pinned table/conformance proof owns that coefficient. This is the
/// same logical JS layout, not an allocator/native-builder claim.
fn scalar_snapshot_name_normalization_layout(
  units : Int,
) -> PreparationRepresentationUnits? {
  if units < 0 {
    return None
  }
  let u = units.to_int64()
  // Scalars/decomposed/composed growing arrays +classes/run/256-offset arrays.
  // Sum all backing overlaps conservatively; only one run's sorted array lives.
  // All six arrays are scalar-backed, not reference-backed.
  let arrays : PreparationRepresentationUnits = {
    record_headers: 15L,
    reference_slots: 6L,
    scalar_words: 12L + 36L + 35L * u + 256L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  // Builder +old/new rendered strings and LF pass strings/views. Up to8U NFC
  // UTF16 units, LF nonexpanding. Source canonical field String is borrowed.
  let text : PreparationRepresentationUnits = {
    record_headers: 10L,
    reference_slots: 8L,
    scalar_words: 6L,
    owned_utf16_units: 40L * u + 2L,
    owned_wire_bytes: 0L,
  }
  // Canonical owner control extent: conservative SUM of seven named phases
  // quickcheck/extract/decompose/order/compose/render/LF, including one tagged
  // result per frame plus transition; fixed builtin VM frames are baseline.
  let controls : PreparationRepresentationUnits = {
    record_headers: 75L,
    reference_slots: 109L,
    scalar_words: 218L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  closed_values_sum_layouts([arrays, text, controls])
}
