///|
/// Logical Node-JS Parser/JsonDocument construction inventory, including
/// rejected input and optionally canonicalized keys. The original input and
/// source-path Strings are borrowed. This DATA does not price bytes, parse,
/// grant capacity or prove
/// Native allocator/GC/outer-backend supply.
pub type JsonConstructionExtent = JsonLiteralConstructionExtent

///|
/// Bound the SAME Parser/JsonDocument/JsonString family for literal data and
/// normalized Program/Source keys. normalize_keys describes the original
/// parser mode; it does not change its semantics or authorize a parse. True
/// also bounds Program literal-key exceptions, which normalize fewer keys.
/// Unicode/escaped text uses the byte bound as a UTF16 bound, without ASCII
/// eligibility. All values, including discarded duplicates, spend node limits.
pub fn json_construction_extent(
  max_input_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  normalize_keys~ : Bool,
) -> JsonConstructionExtent? {
  json_construction_extent_owned(
    max_input_bytes,
    max_nodes,
    max_depth,
    max_nodes,
    max_nodes,
    max_nodes,
    max_nodes,
    max_nodes,
    normalize_keys~,
  )
}

///|
/// SAME Parser constructor with independently supplied upper bounds for the
/// emitted tree's fields, containers and objects. These are sizing DATA, not
/// admission, syntax validation or permission. General callers without those
/// original observations keep json_construction_extent's whole-node bounds.
pub fn json_shaped_construction_extent(
  max_input_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  fields : Int,
  containers : Int,
  objects : Int,
  largest_object : Int,
  strings : Int,
  normalize_keys~ : Bool,
) -> JsonConstructionExtent? {
  json_construction_extent_owned(
    max_input_bytes,
    max_nodes,
    max_depth,
    fields,
    containers,
    objects,
    largest_object,
    strings,
    normalize_keys~,
  )
}

///|
fn json_construction_extent_owned(
  max_input_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  fields : Int,
  containers : Int,
  objects : Int,
  largest_object : Int,
  strings : Int,
  normalize_keys~ : Bool,
) -> JsonConstructionExtent? {
  if max_input_bytes < 1 ||
    max_nodes < 1 ||
    max_depth < 1 ||
    fields < 0 ||
    fields > max_nodes ||
    containers < 0 ||
    containers > max_nodes ||
    objects < 0 ||
    objects > containers ||
    largest_object < 0 ||
    largest_object > fields ||
    strings < 0 ||
    strings > max_nodes {
    return None
  }
  // ObjectFields owns KeyAdmission only while its original Frame is open.
  // Completing that Frame drops the Map; the returned Object retains fields,
  // not the seen-key owner. All parsed entries, including discarded duplicate
  // values, remain covered separately by the full node bound.
  let live_objects = Int::min(objects, max_depth)
  let live_keys = Int64::min(
    fields.to_int64(),
    live_objects.to_int64() * largest_object.to_int64(),
  ).to_int()
  guard @shape.key_admission_construction_extent(live_objects, live_keys)
    is Some(keys) else {
    return None
  }
  let bytes = max_input_bytes.to_int64()
  let nodes = max_nodes.to_int64()
  let f = fields.to_int64()
  let c = containers.to_int64()
  let string_headers = fields.to_int64() + strings.to_int64()
  let edges = nodes - 1L
  let depth = Int::min(max_nodes, max_depth).to_int64() + 1L
  // Node/Value/Span:3H4R8W; Field/key Span:2H4R6W; at most
  // two decoded key/value Strings per node. Each container owns its wrapper
  // and backing. Fields and containers are each bounded by all parsed nodes.
  let tree_headers = 3L * nodes + 2L * f + 2L * c + string_headers
  let tree_refs = 4L * nodes + 4L * f + 9L * c + 2L * edges
  let tree_words = 8L * nodes + 6L * f + 2L * c
  // Old/new array backing and the existing exact-key map construction/growth.
  // All object keys, even a discarded duplicate's parsed value, stay charged.
  let growth_headers = c + keys.record_headers
  let growth_refs = 4L * c + edges + keys.reference_slots
  let growth_words = keys.scalar_words
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
  let decoded : JsonConstructionExtent = {
    record_headers: tree_headers +
    growth_headers +
    ancestry_headers +
    control_headers,
    reference_slots: tree_refs + growth_refs + ancestry_refs + control_refs,
    scalar_words: tree_words + growth_words + ancestry_words + control_words,
    owned_utf16_units: bytes + 2L * bytes + 2L * (bytes + 6L) + 4L,
  }
  if !normalize_keys {
    return Some(decoded)
  }
  guard @canonical.nfc_lf_construction_extent(max_input_bytes)
    is Some(normalization) else {
    return None
  }
  // Completed fields plus one pending key can reach all node slots before a
  // one-short value refusal. Retain their normalized text and one String per
  // key beside the literal tree. The current key normalizes synchronously;
  // one canonical workspace suffices, not one workspace per retained key.
  // Cumulative decoded key length <=input bytes, including escaped spelling.
  // The canonical owner supplies its Unicode expansion and backing overlap.
  Some({
    record_headers: decoded.record_headers +
    normalization.record_headers +
    nodes,
    reference_slots: decoded.reference_slots + normalization.reference_slots,
    scalar_words: decoded.scalar_words + normalization.scalar_words,
    owned_utf16_units: decoded.owned_utf16_units +
    normalization.owned_utf16_units +
    normalization.max_output_utf16_units,
  })
}

///|
/// The SAME staged parser's grammar phase, including one exported ready
/// geometry/report beside the original cursor. Initial preflight and grammar
/// are sequential; take their maximum, not their sum. The parser/document
/// already belong to json_construction_extent and are never counted twice.
/// Additional original roles: retained preflight view+geometry2H1R19W,
/// resumable JsonParse1H1R4W, ready geometry1H12W and its two carriers2H2R2W.
/// This is the existing logical JS recipe, not Native physical backing.
pub fn json_source_grammar_construction_extent(
  max_input_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> JsonConstructionExtent? {
  guard json_construction_extent(
      max_input_bytes,
      max_nodes,
      max_depth,
      normalize_keys=true,
    )
    is Some(grammar) else {
    return None
  }
  Some({
    record_headers: grammar.record_headers + 6L,
    reference_slots: grammar.reference_slots + 4L,
    scalar_words: grammar.scalar_words + 37L,
    owned_utf16_units: grammar.owned_utf16_units,
  })
}
