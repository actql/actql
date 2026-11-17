///|
/// The existing restricted YAML parser shares Parser/Node/Container/key and
/// scalar constructors with JSON. Keep that complete envelope, and add the
/// YAML-only active frame/Point/key views and block-scalar line collection.
/// Line count is a separate observation of the original wire, never a value
/// node count. These quantities describe one current document, not all future
/// Task documents, semantic acceptance, a tariff or physical backing.
pub fn yaml_literal_construction_extent(
  input_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  lines : Int,
) -> JsonLiteralConstructionExtent? {
  if lines < 1 || lines.to_int64() > input_bytes.to_int64() + 1L {
    return None
  }
  guard json_literal_construction_extent(input_bytes, max_nodes, max_depth)
    is Some(common) else {
    return None
  }
  let depth = Int::min(max_nodes, max_depth).to_int64() + 1L
  let count = lines.to_int64()
  // One YamlFrame plus its start/end Point, optional key tuple/Some and
  // current span/Point alternatives: 9H/16R/24W per active depth. The common
  // Container/key backing is already included above; co-counting its generic
  // Frame makes this conservative rather than crediting an unobserved cut.
  // ScalarLine is 1H/1R/2W; each original physical line may belong to one block
  // scalar. Retain its String header, original and growing line-array backing,
  // builder/output/trim text and the final scalar beside the original input.
  Some({
    record_headers: common.record_headers + 9L * depth + 2L * count + 8L,
    reference_slots: common.reference_slots + 16L * depth + 3L * count + 12L,
    scalar_words: common.scalar_words + 24L * depth + 2L * count + 8L,
    owned_utf16_units: common.owned_utf16_units + 8L * input_bytes.to_int64(),
  })
}
