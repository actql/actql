///|
/// Price the existing canonical retained representation and its domain-owned
/// controls with the shared preparation tariff. This counts backing capacity,
/// not just used members. The original domain supplies multiplicity, aliasing
/// and separate String/control facts; no tree is walked, copied or admitted.
/// Traversal scratch, including max_frame_slots, is not retained backing.
/// This DATA projection grants no capacity, lifetime, Owner or authority.
pub fn canonical_preparation_retained_bytes(
  tree : @identity.CanonicalRepresentationExtent,
  headers : Int64,
  references : Int64,
  words : Int64,
  text : Int64,
) -> Int64? {
  guard tree.max_frame_slots >= 0L &&
    checked_preparation_add_product(tree.arrays, tree.objects, 1L)
    is Some(containers) &&
    checked_preparation_add_product(headers, tree.nodes, 1L) is Some(h0) &&
    checked_preparation_add_product(h0, tree.strings, 1L) is Some(h1) &&
    checked_preparation_add_product(h1, containers, 3L) is Some(h2) &&
    checked_preparation_add_product(h2, tree.object_backing_slots, 1L)
    is Some(h) &&
    checked_preparation_add_product(references, tree.nodes, 1L) is Some(r0) &&
    checked_preparation_add_product(r0, containers, 2L) is Some(r1) &&
    checked_preparation_add_product(r1, tree.array_backing_slots, 1L)
    is Some(r2) &&
    checked_preparation_add_product(r2, tree.object_backing_slots, 3L)
    is Some(r) &&
    checked_preparation_add_product(words, tree.nodes, 2L) is Some(w0) &&
    checked_preparation_add_product(w0, containers, 2L) is Some(w) &&
    checked_preparation_add_product(text, tree.text_utf16_units, 1L) is Some(t) else {
    return None
  }
  preparation_representation_cost({
    record_headers: h,
    reference_slots: r,
    scalar_words: w,
    owned_utf16_units: t,
    owned_wire_bytes: 0L,
  })
}
