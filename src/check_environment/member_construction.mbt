///|
/// member_at's entry Some, captured lookup closure and returned Some, excluding
/// the Member itself. Closure captures original owner, section and index; only
/// owner is a reference. Consumer inventories own each retained Member record.
pub fn member_access_construction_extent() -> @shape.CollectionConstructionExtent {
  member_access_controls
}

///|
let member_access_controls : @shape.CollectionConstructionExtent = {
  record_headers: 3L,
  reference_slots: 3L,
  scalar_words: 4L,
}

///|
/// One original Member wrapper: owner/Entry references, section/index scalars.
/// The admitted Entry, CID and Environment/tree backing remain at their owner.
/// A Snapshot can retain this SAME wrapper after metadata aliases are cleared;
/// do not allocate/count another wrapper or infer its retirement from a cache.
pub fn member_instance_construction_extent() -> @shape.CollectionConstructionExtent {
  member_instance_units
}

///|
let member_instance_units : @shape.CollectionConstructionExtent = {
  record_headers: 1L,
  reference_slots: 2L,
  scalar_words: 2L,
}

///|
/// Additional scalar depth-capture scratch for one envelope read, reused for
/// every member: Ref1H1W and its Some1H1R1W. No member-sized sizing Array.
/// Empty envelopes do not construct it; this is a pre-entry upper bound.
pub fn member_depth_capture_extent() -> @shape.CollectionConstructionExtent {
  member_depth_capture_units
}

///|
let member_depth_capture_units : @shape.CollectionConstructionExtent = {
  record_headers: 2L,
  reference_slots: 1L,
  scalar_words: 2L,
}

///|
/// Additional retained scalar only, one per original private Entry. The
/// existing Entry/Cursor/CID/Environment ownership is not replaced or funded
/// by this delta. Caller supplies actual member count, not max_members.
pub fn member_depth_retention_extent(
  members : Int,
) -> @shape.CollectionConstructionExtent? {
  if members < 0 {
    return None
  }
  Some({
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: members.to_int64(),
  })
}
