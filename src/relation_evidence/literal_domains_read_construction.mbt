///|
// Read1H1R, Reading1H1R1W, body1H6R1W, original Budget1H2W.
// The pinned original Map iterator is supplied by its shared storage owner.
let literal_domains_read_controls : @shape.CollectionConstructionExtent = {
  record_headers: 4L,
  reference_slots: 8L,
  scalar_words: 4L,
}

///|
/// Original borrowed Map/domain/value bodies and Strings are not copied.
pub fn literal_domains_read_entry_construction(
  root_path_depth : Int64,
) -> @shape.CollectionConstructionExtent? {
  guard @decode.issue_path_construction_extent(root_path_depth) is Some(path) else {
    return None
  }
  @shape.compose_collection_construction_extents([
    literal_domains_read_controls,
    @shape.reference_map_iterator_construction_extent(),
    // Original begin Ok and invalid-limit Issue/Stop/Err alternatives.
    { record_headers: 4L, reference_slots: 5L, scalar_words: 4L, },
    path,
  ])
}

///|
pub fn literal_domains_read_retained_extent(
  read : LiteralDomainsRead,
) -> @shape.CollectionConstructionExtent? {
  match read.state {
    Reading(body) =>
      @shape.compose_collection_construction_extents([
        literal_domains_read_controls,
        @shape.reference_map_iterator_retained_extent(),
        if body.domain is Some(_) {
          { record_headers: 1L, reference_slots: 1L, scalar_words: 1L, }
        } else {
          { record_headers: 0L, reference_slots: 0L, scalar_words: 0L, }
        },
      ])
    Completed(_) =>
      Some({ record_headers: 3L, reference_slots: 3L, scalar_words: 3L, })
    // Failure keeps the whole admitted construction peak until actual clear.
    _ => None
  }
}

///|
/// One original field or scalar charge, not a full traversal or input maximum.
pub fn literal_domains_read_step_construction(
  read : LiteralDomainsRead,
) -> @shape.CollectionConstructionExtent? {
  guard read.state is Reading(body) &&
    @decode.issue_path_construction_extent(
      @decode.admission_usage(body.source).depth.to_int64(),
    )
    is Some(path) else {
    return None
  }
  let utf8 = @scalar.utf8_length_admission_construction_units()
  @shape.compose_collection_construction_extents([
    // Transfer/Completed2H2R3W; Issue/Stop/Rejected3H5R3W;
    // original domain Some1H1R1W; consumed-work Some1H1W;
    // take's Ok/Err/Some alternatives3H3R3W.
    { record_headers: 10L, reference_slots: 11L, scalar_words: 11L, },
    { record_headers: utf8.0, reference_slots: utf8.1, scalar_words: utf8.2, },
    if body.domain is None {
      @shape.reference_map_iterator_next_construction_extent()
    } else {
      { record_headers: 0L, reference_slots: 0L, scalar_words: 0L, }
    },
    path,
  ])
}
