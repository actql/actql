///|
/// Logical Node-JS construction inventory for parse_json_literal, including
/// rejected input. It does not price bytes, grant capacity, parse the input or
/// describe a Native allocator/GC. The original input String is borrowed.
pub(all) struct JsonLiteralConstructionExtent {
  record_headers : Int64
  reference_slots : Int64
  scalar_words : Int64
  owned_utf16_units : Int64
} derive(Eq, Debug)

///|
/// Bound the actual non-normalizing Parser/JsonDocument/JsonString family.
/// Unicode and escaped text use the byte bound as a UTF16 upper bound; no
/// ASCII eligibility assertion or identifier-normalization proof is borrowed.
/// All values, including discarded duplicates, spend the parser node limit.
pub fn json_literal_construction_extent(
  max_input_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> JsonLiteralConstructionExtent? {
  json_construction_extent(
    max_input_bytes,
    max_nodes,
    max_depth,
    normalize_keys=false,
  )
}
