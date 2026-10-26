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
  if max_input_bytes < 1 || max_nodes < 1 || max_depth < 1 {
    return None
  }
  let bytes = max_input_bytes.to_int64()
  let nodes = max_nodes.to_int64()
  let edges = nodes - 1L
  let depth = Int::min(max_nodes, max_depth).to_int64() + 1L
  // Node/Value/Span:3H4R8W; Field/key Span:2H4R6W; at most
  // two decoded key/value Strings per node. Each container owns its wrapper
  // and backing. Fields and containers are each bounded by all parsed nodes.
  let tree_headers = 3L * nodes + 2L * nodes + 2L * nodes + 2L * nodes
  let tree_refs = 4L * nodes + 4L * nodes + 9L * nodes + 2L * edges
  let tree_words = 8L * nodes + 6L * nodes + 2L * nodes
  // Old/new array backing and the existing exact-key map construction/growth.
  // All object keys, even a discarded duplicate's parsed value, stay charged.
  let growth_headers = nodes + 8L * nodes + 4L * nodes
  let growth_refs = 4L * nodes + edges + 19L * nodes + 11L * nodes
  let growth_words = 21L * nodes + 13L * nodes
  // Frame/Container/Point/pending tuple+Some/PathSegment, two growing ancestry
  // vectors and one current leaf. No complete path is copied per success node.
  let ancestry_headers = 6L * depth + 6L
  let ancestry_refs = 9L * depth + 2L * (12L + 3L * depth) + 2L
  let ancestry_words = 9L * depth + 4L
  // Fixed Parser, Limits, Document, String, Point/builder/completion, poll,
  // Result and error/path carriers. The scalar UTF8 scan's Result/tuple/issue
  // alternatives are conservatively co-counted (3H2R4W); it allocates no wire.
  let control_headers = 49L + 3L
  let control_refs = 60L + 2L * depth + 2L
  let control_words = 83L + 4L
  // Decoded tree text plus overlapping quoted builder/output and numeric
  // spelling/builder/output. Precision refusal occurs after taking the
  // original number spelling, so its input-bound text must also be covered.
  Some({
    record_headers: tree_headers +
    growth_headers +
    ancestry_headers +
    control_headers,
    reference_slots: tree_refs + growth_refs + ancestry_refs + control_refs,
    scalar_words: tree_words + growth_words + ancestry_words + control_words,
    owned_utf16_units: bytes + 2L * bytes + 2L * (bytes + 6L) + 4L,
  })
}
