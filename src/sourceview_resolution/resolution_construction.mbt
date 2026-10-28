///|
/// Original resolver constructor DATA. Returned bounds include growing backing
/// and success/failure alternatives, not a minimum or a partial Resolved.
/// Original Inputs/Catalog/tree/contract and supplied Limits stay borrowed.
pub(all) struct ResolutionConstructionInventory {
  returned : @shape.CollectionConstructionExtent
  temporary : @shape.CollectionConstructionExtent
  returned_utf16_units : Int64
  temporary_utf16_units : Int64
} derive(Eq, Debug)

///|
fn resolution_geometry_fits(g : ResolutionConstructionGeometry) -> Bool {
  g.inputs >= 0 &&
  g.views >= 0 &&
  g.inherited_work >= 0 &&
  g.candidate_inputs >= 0 &&
  g.candidate_inputs <= g.inputs &&
  g.candidate_views >= 0 &&
  g.candidate_views <= g.views &&
  g.max_view_fields >= 0 &&
  g.max_declaration_fields >= 0 &&
  g.identity_utf16 >= 0L &&
  g.max_identity_utf16 >= 0 &&
  g.max_identity_utf16.to_int64() <= g.identity_utf16 &&
  g.max_connector_utf16 >= 0 &&
  g.max_connector_utf16 <= g.max_identity_utf16 &&
  g.max_view_utf16 >= 0 &&
  g.max_view_utf16 <= g.max_identity_utf16 &&
  g.reference_utf16 >= 0L &&
  g.max_reference_utf16 >= 0 &&
  g.max_reference_utf16.to_int64() <= g.reference_utf16 &&
  g.inspection_work >= 0L
}

///|
/// The SAME original work prefix bounds constructed views, normalized identity
/// text and URI copies. Map/Array/NFC/Decode owners supply their representation
/// units; this issues no semantic verdict, Resource grant or byte tariff.
/// Metadata/quotation frames and backend intrinsic/VM backing are separate.
pub fn resolution_construction_inventory(
  g : ResolutionConstructionGeometry,
  limits : Limits,
) -> ResolutionConstructionInventory? {
  let zero : @shape.CollectionConstructionExtent = {
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 0L,
  }
  if resolution_limits_invalid(limits) ||
    g.inputs > limits.max_inputs ||
    g.views > limits.max_views {
    // Original early Issue/flat-kind/Err alternatives, before either Map.
    return Some({
      returned: { record_headers: 3L, reference_slots: 4L, scalar_words: 5L, },
      temporary: zero,
      returned_utf16_units: 0L,
      temporary_utf16_units: 0L,
    })
  }
  if !resolution_geometry_fits(g) {
    return None
  }
  let remaining = if g.inherited_work > limits.max_work {
    0
  } else {
    limits.max_work - g.inherited_work
  }
  let v = Int::min(g.candidate_views, remaining).to_int64()
  let n = if v == 0L {
    0L
  } else {
    Int::min(g.candidate_inputs, remaining).to_int64()
  }
  let ambiguous = v > 1L && g.candidate_inputs > 0
  guard @unicode.nfc_lf_retained_output_units(
      Int64::min(g.identity_utf16, remaining.to_int64()),
    )
    is Some(returned_text) else {
    return None
  }
  // Owner/Resolved/Ok3H5R2W. ResolvedInput1H3R1W, View1H3R and at most
  // three returned normalized Strings per constructed view. Failure-only
  // Issue, private selector association, two Some, kind and Err6H10R5W,
  // plus one retained diagnostic Cursor1H2R1W. Alternatives are co-counted.
  // Ambiguous names retain one Array of borrowed normalized view names; a
  // separate sort buffer is temporary. No Map or contract body escapes anew.
  guard @shape.collection_construction_extent({
      records: 10L + n + 4L * v,
      record_references: 17L + 3L * n + 3L * v,
      record_words: 8L + n,
      reference_arrays: 1L + (if ambiguous { 1L } else { 0L }),
      reference_items: n + (if ambiguous { v } else { 0L }),
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(returned) else {
    return None
  }
  let child = @decode.indexed_child_construction_extent()
  // Fixed named families: Budget1H1W; exact/group probe tuples2H5R;
  // selected tuple1H1R1W; three Map result Some3H3R3W; Catalog usage
  // tuple1H3W; view/input Some2H2R2W; required/text Ok6H6R6W; five
  // source Some5H5R5W; Stop1H1R1W; two length Some2H4W; five URI
  // fragment Strings5H; three StringViews3H3R6W. Four indexed child sites
  // come from required connector/view/CID and failure-only explicit lookup.
  // Stored exact/group tuple keys2H5R per view plus resource String1H;
  // two complete indexes and all group arrays coexist through reader return.
  guard @shape.collection_construction_extent({
      records: 32L + 4L * child.record_headers + 3L * v,
      record_references: 26L + 4L * child.reference_slots + 5L * v,
      record_words: 32L + 4L * child.scalar_words,
      reference_arrays: v + 3L + (if ambiguous { 1L } else { 0L }),
      // Group items plus two borrowed selector slots; two Map literal input
      // arrays are empty. Native retained slots are kept through this frame.
      reference_items: v + 2L + (if ambiguous { v } else { 0L }),
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 2L,
      map_entries: 2L * v,
    })
    is Some(frame) else {
    return None
  }
  let view = if v == 0L {
    Some(zero)
  } else {
    @decode.open_object_construction_extent(
      Int::min(g.max_view_fields, remaining),
    )
  }
  let explicit = if g.candidate_inputs == 0 || g.max_declaration_fields == 0 {
    Some(zero)
  } else {
    @decode.open_object_construction_extent(
      Int::min(g.max_declaration_fields, remaining),
    )
  }
  guard view is Some(view) &&
    explicit is Some(explicit) &&
    @shape.add_collection_construction_extents(frame, view) is Some(frame) &&
    @shape.add_collection_construction_extents(frame, explicit) is Some(frame) else {
    return None
  }
  let normalization = if v == 0L {
    None
  } else {
    @unicode.nfc_lf_construction_scratch_extent(
      Int::min(g.max_identity_utf16, remaining),
    )
  }
  let normalization_units : @shape.CollectionConstructionExtent = match
    normalization {
    None => zero
    Some(n) =>
      {
        record_headers: n.record_headers,
        reference_slots: n.reference_slots,
        scalar_words: n.scalar_words,
      }
  }
  guard @shape.add_collection_construction_extents(frame, normalization_units)
    is Some(temporary) else {
    return None
  }
  // resource_address keeps prefix, suffix and two compared substring copies.
  // Three prefix-sized copies <=3*(13+C), two suffix-sized <=2*(1+V).
  // The intermediate first concat is shorter. Its final resource substring
  // has at most the already-charged original URI length. All resource Strings
  // remain in temporary index keys, distinct from borrowed URI input backing.
  let fragments = if v == 0L {
    0L
  } else {
    guard @unicode.nfc_lf_retained_output_units(
        Int::min(g.max_connector_utf16, remaining).to_int64(),
      )
      is Some(connector) &&
      @unicode.nfc_lf_retained_output_units(
        Int::min(g.max_view_utf16, remaining).to_int64(),
      )
      is Some(name) &&
      @counts.checked_nonnegative_add_product(41L, connector, 3L)
      is Some(prefix) &&
      @counts.checked_nonnegative_add_product(prefix, name, 2L)
      is Some(fragments) else {
      return None
    }
    fragments
  }
  guard @counts.checked_nonnegative_add_product(
      normalization.map(n => n.owned_utf16_units).unwrap_or(0L),
      fragments,
      1L,
    )
    is Some(text) &&
    @counts.checked_nonnegative_add_product(
      text,
      Int64::min(g.reference_utf16, remaining.to_int64()),
      1L,
    )
    is Some(text) else {
    return None
  }
  Some({
    returned,
    temporary,
    returned_utf16_units: returned_text,
    temporary_utf16_units: text,
  })
}
