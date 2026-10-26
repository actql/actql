///|
/// The structural Program constructor does not visit schema fields or cells.
/// This inventory is valid only after closed_values_shape established exactly
/// one Stage, no imports/effects/table inputs, one step and one Result/export.
/// Its Cursor backing, names and ParseUsage belong to the source phase.
struct ClosedValuesProgramInventories {
  retained : PreparationRepresentationUnits
  containers_peak : PreparationRepresentationUnits
  carriers_peak : PreparationRepresentationUnits
  failure_peak : PreparationRepresentationUnits
}

///|
/// Logical Array wrapper/backing plus reference slots; growth uses the pinned
/// <=8+2n retained capacity and <=12+3n old/new overlap. No copied element owner
/// is silently included: callers add tuples/Cursors separately.
fn closed_values_program_arrays(
  count : Int64,
  items : Int64,
  growing : Bool,
) -> PreparationRepresentationUnits {
  {
    record_headers: (if growing { 3L } else { 2L }) * count,
    reference_slots: count +
    (if growing { 12L * count + 3L * items } else { 8L * count + 2L * items }),
    scalar_words: 2L * count,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
}

///|
/// Map record (2 refs/5 words), backing buckets, Entry (2 refs/4 words),
/// and payload-bearing Some links/cursors. All keys borrow source Strings.
/// Grow overlap uses <=12+6n buckets rather than a capacity multiplier from
/// the evaluator. This is the same explicit representation convention used
/// by the schema constructor inventory, not a native allocator size claim.
fn closed_values_program_maps(
  count : Int64,
  entries : Int64,
  growing : Bool,
) -> PreparationRepresentationUnits {
  let buckets = if growing {
    12L * count + 6L * entries
  } else {
    8L * count + 4L * entries
  }
  let tagged = 3L * entries + 4L * count
  {
    record_headers: 2L * count +
    entries +
    tagged +
    (if growing { count } else { 0L }),
    reference_slots: 2L * count + buckets + 2L * entries + tagged,
    scalar_words: 5L * count + buckets + 4L * entries + tagged,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
}

///|
fn closed_values_program_units_add(
  a : PreparationRepresentationUnits,
  b : PreparationRepresentationUnits,
) -> PreparationRepresentationUnits {
  // Only fixed narrow constructor cardinalities call this helper. Resource
  // projection remains checked by preparation_representation_cost.
  {
    record_headers: a.record_headers + b.record_headers,
    reference_slots: a.reference_slots + b.reference_slots,
    scalar_words: a.scalar_words + b.scalar_words,
    owned_utf16_units: a.owned_utf16_units + b.owned_utf16_units,
    owned_wire_bytes: a.owned_wire_bytes + b.owned_wire_bytes,
  }
}

///|
fn closed_values_program_inventories(
  _shape : ClosedValuesShape,
) -> ClosedValuesProgramInventories {
  // This exact shape proof establishes the original one-Stage envelope:
  // no input imports, one Result and one public export. The generic syntax
  // owner prices its actual shallow containers; source/name/scratch owners
  // below stay independent. No general Source is narrowed to Values facts.
  let extent = @syntax.program_container_construction_extent({
    stage_records: 1,
    import_tuple_bound: 0L,
    export_tuples: 1,
    name_index_entries: 1L,
    retained_array_capacity_bound: 54L,
    retained_map_capacity_bound: 28L,
    inspection_work: 0,
  }).unwrap()
  let retained : PreparationRepresentationUnits = {
    record_headers: extent.record_headers,
    reference_slots: extent.reference_slots,
    scalar_words: extent.scalar_words,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  // These same record owners also coexist through the decoder's temporary
  // container peak. Their original shallow fields remain separate from the
  // generic retained total, which already includes retained arrays/maps.
  let records : PreparationRepresentationUnits = {
    record_headers: extent.shallow_record_headers,
    reference_slots: extent.shallow_reference_slots,
    scalar_words: extent.shallow_scalar_words,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  // Conservative sum of ALL container constructions in decode_envelope,
  // including those that actually occur sequentially. Six ObjectViews open
  // root(4), Stage(4), inputs(0), exports(1), export(1), from(2). The Stage's
  // nine allowed names select decode_shape's indexed branch: present(4),
  // admitted(9), seen(4). The separate Stage-name seen Map adds one entry.
  // Retained three Maps remain simultaneous and are included here too.
  let maps = closed_values_program_maps(
    6L + 3L + 1L + 3L,
    12L + 17L + 1L + 1L,
    true,
  )
  // Retained six arrays; nodes/steps Cursor arrays (2 slots); input/export
  // names (1); four allowed arrays (7+9+1+2); four key copies (4+4+1+2);
  // four empty required arrays; params/bindings loop array(2); indexed key
  // checker tuple arrays(4+9). All are counted even when an earlier scope
  // has ended; this is bounded conservative construction overlap, not RSS.
  let arrays = closed_values_program_arrays(
    6L + 2L + 2L + 4L + 4L + 4L + 1L + 2L,
    3L + 2L + 1L + 19L + 11L + 0L + 2L + 13L,
    true,
  )
  // Six ObjectViews; 13 key tuples in the indexed Stage checker; one
  // Envelope (5 refs) coexists with the final Program. Cursor/tag/control
  // call frames and failure path owners are separate phase dependencies.
  let additional : PreparationRepresentationUnits = {
    record_headers: 6L + 13L + 1L,
    reference_slots: 12L + 13L + 5L,
    scalar_words: 0L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  let containers_peak = closed_values_program_units_add(
    records,
    closed_values_program_units_add(
      maps,
      closed_values_program_units_add(arrays, additional),
    ),
  )
  // Twelve required() sites each create a lookup Cursor/Some and returned
  // Ok; eight optional lookup sites are absent in this shape. Both create
  // their source-level lookup-map closure. Two elements() calls create one
  // Cursor each; the Stage Cursor is already in retained records above.
  // Result carriers: required12, open6, closed-key checks4, field-names3,
  // elements2, five names × (text/NFC quick/NFC/LF)4, finish1 =48. Some12.
  // Count these sequential carriers together conservatively. No VM frame or
  // copied String is invented: ASCII names return their original Strings.
  let cursors = 12L + 2L - 1L
  let tagged = 48L + 12L
  let closures = 20L + 2L + 1L // lookup, elements, export map
  let carriers_peak : PreparationRepresentationUnits = {
    record_headers: cursors + tagged + closures,
    reference_slots: 2L * cursors + tagged + 20L + 2L + 2L,
    scalar_words: cursors + tagged,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  // One detached diagnostic path can coexist with the partial containers.
  // Actual grammar errors cannot arise after this exact shape proof, but the
  // original failure owner still covers Issue/SyntaxError/Abort/Result and
  // one path-building growth buffer. Existing source span/text are borrowed.
  let depth = @decode.admission_usage(
      @syntax.program_input_cursor(_shape.original),
    ).depth.to_int64() +
    1L
  let failure_peak : PreparationRepresentationUnits = {
    record_headers: 4L + 3L + depth,
    reference_slots: 7L + 1L + 12L + 3L * depth + depth,
    scalar_words: 4L + 2L + 2L * depth,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  { retained, containers_peak, carriers_peak, failure_peak, }
}
