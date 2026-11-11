///|
/// Logical Array wrapper/backing plus reference slots; growth uses the pinned
/// <=8+2n retained capacity and <=12+3n old/new overlap. No copied element owner
/// is silently included: callers add tuples/Cursors separately.
fn closed_values_program_arrays(
  count : Int64,
  items : Int64,
  growing : Bool,
) -> @execution.PreparationRepresentationUnits {
  @execution.preparation_array_representation(count, items, growing).unwrap()
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
) -> @execution.PreparationRepresentationUnits {
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
