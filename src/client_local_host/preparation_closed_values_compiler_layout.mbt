///|
/// Pinned builtin Array growth: empty append arrays start at eight slots and
/// double (arraycore_nonjs.mbt::array_growth_capacity). JS exposes only logical
/// length; this common logical spare-capacity envelope covers that length too.
/// This is not a claim about either engine's allocator or physical heap size.
fn closed_values_append_capacity(length : Int) -> Int64? {
  if length < 0 {
    return None
  }
  if length == 0 {
    return Some(0L)
  }
  let mut capacity = 8L
  while capacity < length.to_int64() {
    capacity *= 2L
  }
  Some(capacity)
}

///|
/// Logical sorting frame/view envelope for the pinned builtin sort_by, not
/// engine stack/RSS. Only the smaller partition recurses, so repeatedly halving
/// field count bounds all live quick-sort frames. Each level counts all named
/// argument/loop/local slots (including shadows): eight reference slots and
/// fifteen scalar slots, plus two tuple results, three views and two predecessor
/// Options: (8 headers,13 refs,27 words). Fixed nonrecursive helper frames are model-A runtime baseline, not
/// per-request owners. Pivot's two allocated closures/counter box/tuple, two
/// partition tuple results, heap slice view and comparator closure contribute
/// (8,5,9); these are allocated objects, not baseline frames.
/// Both schema-name and Field sorts are synchronous and share this peak, not
/// two retained arrays or one frame per comparison. ASCII comparison borrows
/// strings. This constructor convention excludes opaque runtime stack backing.
fn closed_values_sort_scratch_layout(
  fields : Int,
) -> @execution.PreparationRepresentationUnits? {
  if fields <= 0 {
    return None
  }
  let mut size = fields
  let mut depth = 1L
  while size > 1 {
    size = size / 2
    depth += 1L
  }
  Some({
    record_headers: 8L + 8L * depth,
    reference_slots: 5L + 13L * depth,
    scalar_words: 9L + 27L * depth,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  })
}
