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
/// Constructor-local builtin linked Map upper inventory including a grow's old
/// and new backing. Each entry has one Entry and two live Some link/bucket
/// wrappers; growth may temporarily keep a further bucket wrapper per entry.
/// Both key and value slots are priced as references even for inline values
/// (same eight-byte tariff). The initial capacity is eight and the threshold
/// is capacity*13/16; this also upper-bounds Map(from_array)'s smaller initial
/// capacities. This helper does not authorize arbitrary Map creation.
fn closed_values_map_constructor_layout(
  entries : Int,
) -> @execution.PreparationRepresentationUnits? {
  if entries < 0 {
    return None
  }
  let n = entries.to_int64()
  let mut capacity = 8L
  while n > capacity * 13L / 16L {
    capacity *= 2L
  }
  Some({
    record_headers: 3L + 4L * n,
    reference_slots: 2L + 2L * capacity + 6L * n,
    scalar_words: 5L + 6L * n,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  })
}

///|
/// `relation_values::scan` traversal storage, before its current ObjectView Map
/// is added separately. node_upper is the admitted source-subtree node bound;
/// largest_object_fields bounds current names. This is an additive coexistence
/// upper bound, not the sum of all sequential scan invocations:
/// - stack wrapper/backing plus old backing during growth;
/// - at most node_upper (Cursor, depth) tuples and their Cursors;
/// - one decoded child array and at most node_upper child Cursors;
/// - current names array, ValueView/ObjectView, returned Usage;
/// - one pop Option, lookup Option, decoded Result and loop view Option.
/// Names, original indexed tree and AdmissionUsage are borrowed. Object maps,
/// caller-local schema/name inventories, scalar admission and sorting remain
/// separate components; none are asserted free by this helper.
fn closed_values_walk_storage_layout(
  node_upper : Int,
  largest_object_fields : Int,
) -> @execution.PreparationRepresentationUnits? {
  if node_upper <= 0 ||
    largest_object_fields < 0 ||
    largest_object_fields > node_upper {
    return None
  }
  closed_values_walk_storage_from_extents(
    node_upper, node_upper, largest_object_fields,
  )
}

///|
/// One constructor formula for generic and guarded traversal. Pending entries
/// own a tuple and Cursor; the current child array owns its Cursor projection.
/// Shared Cursors may make this additive bound conservative, never a second
/// actual allocation charge. Both routes use the same wrapper/backing tariff.
fn closed_values_walk_storage_from_extents(
  pending : Int,
  children : Int,
  names : Int,
) -> @execution.PreparationRepresentationUnits? {
  if pending <= 0 || children < 0 || names < 0 {
    return None
  }
  guard closed_values_append_capacity(pending) is Some(capacity) else {
    return None
  }
  let p = pending.to_int64()
  let c = children.to_int64()
  let f = names.to_int64()
  Some({
    record_headers: 14L + 2L * p + c,
    reference_slots: 10L + 2L * capacity + 3L * p + 3L * c + f,
    scalar_words: 14L + 2L * p + c,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  })
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
