///|
/// Source-owned spans and decoded text retained by an immutable index, after
/// the original Source AST/parser/temporary builders have unwound. Paths are
/// borrowed from the separately held original source-path owner. These counts
/// describe a bounded original family, not admission, a tariff or physical RAM.
pub(all) struct IndexedSourceDependencyExtent {
  record_headers : Int64
  reference_slots : Int64
  scalar_words : Int64
  owned_utf16_units : Int64
} derive(Eq, Debug)

///|
/// Each Node and field key has one retained Span; a field Span is shared by
/// index Edge and OwnedField, never charged twice. Count each retained decoded
/// key/value String once. The caller supplies a proven retained UTF16 bound
/// (for an admitted Unicode index, its measured UTF8 total also bounds UTF16).
/// No parser tree, normalization workspace or independent source-path backing
/// escapes through this projection. Nonnegative Int counts fit these products.
pub fn indexed_source_dependency_extent(
  nodes : Int,
  fields : Int,
  strings : Int,
  text_utf16_bound : Int64,
) -> IndexedSourceDependencyExtent? {
  if nodes < 0 || fields < 0 || strings < 0 || text_utf16_bound < 0L {
    return None
  }
  let spans = nodes.to_int64() + fields.to_int64()
  Some({
    record_headers: spans + strings.to_int64(),
    reference_slots: spans,
    scalar_words: 6L * spans,
    owned_utf16_units: text_utf16_bound,
  })
}
