///|
/// Source-owned String and Span bodies borrowed by a decoder index or typed
/// result after parsing. The source path is borrowed installed DATA. One Span
/// owns one path reference and six scalar coordinates; no source text buffer
/// is retained by a Span. String headers are bounded by nodes plus field keys.
/// max_text_utf16_units is the caller's proved total DECODED text bound, not
/// wire bytes or a parser limit. These quantities do not admit a tree.
pub fn json_index_borrowed_construction_extent(
  nodes : Int,
  fields : Int,
  max_text_utf16_units : Int64,
  keep_spans~ : Bool,
) -> JsonConstructionExtent? {
  if nodes < 1 || fields < 0 || fields >= nodes || max_text_utf16_units < 0L {
    return None
  }
  let count = nodes.to_int64() + fields.to_int64()
  Some({
    record_headers: count + (if keep_spans { count } else { 0L }),
    reference_slots: if keep_spans {
      count
    } else {
      0L
    },
    scalar_words: if keep_spans {
      6L * count
    } else {
      0L
    },
    owned_utf16_units: max_text_utf16_units,
  })
}

///|
/// Complete returned JSON tree, excluding parser/key-normalization scratch.
/// Node/Value2H3R2W and Field1H3R borrow the SAME String/Span family above.
/// Container backing follows the existing shared Array constructor bound;
/// this is a retained upper envelope, not a minimum or allocator measurement.
/// Source trees keep spans by default. A caller projecting a proven span-free
/// Host JSON value may omit only those Source-path/coordinate records; all
/// original node/value/field/container and String quantities stay present.
pub fn json_tree_retained_construction_extent(
  nodes : Int,
  fields : Int,
  objects : Int,
  arrays : Int,
  max_text_utf16_units : Int64,
  keep_spans? : Bool = true,
) -> JsonConstructionExtent? {
  if objects < 0 || arrays < 0 || objects > nodes || arrays > nodes - objects {
    return None
  }
  guard json_index_borrowed_construction_extent(
      nodes,
      fields,
      max_text_utf16_units,
      keep_spans~,
    )
    is Some(borrowed) else {
    return None
  }
  let n = nodes.to_int64()
  let f = fields.to_int64()
  let containers = objects.to_int64() + arrays.to_int64()
  let owned = @shape.collection_construction_extent({
    records: 2L * n + f,
    record_references: 3L * n + 3L * f,
    record_words: 2L * n,
    reference_arrays: containers,
    reference_items: n - 1L,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  }).unwrap()
  Some({
    record_headers: owned.record_headers + borrowed.record_headers,
    reference_slots: owned.reference_slots + borrowed.reference_slots,
    scalar_words: owned.scalar_words + borrowed.scalar_words,
    owned_utf16_units: borrowed.owned_utf16_units,
  })
}
