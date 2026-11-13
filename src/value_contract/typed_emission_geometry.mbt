///|
/// Scalar DATA from an already checked Contract. No JSON writer, field/enum
/// array copy, hash, wire or validation is constructed. This traversal's call
/// stack and scalar/result controls must already be backed by its caller.
/// It cannot fund its own traversal from the result it has yet to produce.
pub(all) struct CheckedEmissionGeometry {
  contract_nodes : Int
  value_nodes : Int
  depth : Int
  enum_items : Int
  max_fields : Int
} derive(Eq, Debug)

///|
/// Exact value-node/container geometry of emit_checked; strings are borrowed
/// and their byte lengths are deliberately not measured here. None means an
/// Int-sized geometry cannot represent this checked tree, never permission to
/// truncate, substitute a policy limit or weaken its original contract.
pub fn checked_emission_geometry(
  value : Contract,
  max_depth? : Int = 2147483647,
) -> CheckedEmissionGeometry? {
  if max_depth < 1 {
    return None
  }
  // Every checked object has nullable and type, plus its own object node.
  let mut contracts = 1L
  let mut nodes = 3L
  let mut depth = 1
  let mut enums = 0L
  let mut max_fields = 0
  match value.shape {
    Text(bounds) => {
      if bounds.min_length is Some(_) {
        nodes += 1L
      }
      if bounds.max_codepoints is Some(_) {
        nodes += 1L
      }
      if bounds.max_utf8_bytes is Some(_) {
        nodes += 1L
      }
      if text_enumerant_count(bounds) is Some(count) {
        enums = count.to_int64()
        nodes += 1L + enums
        depth = 2
      }
    }
    Decimal(..) | Vector(..) => nodes += 2L
    ResourceRef(..) => nodes += 1L
    ContentRef(media_type~) => if media_type is Some(_) { nodes += 1L }
    Array(child, max_items~) => {
      guard checked_emission_geometry(child, max_depth=max_depth - 1)
        is Some(child) else {
        return None
      }
      contracts += child.contract_nodes.to_int64()
      nodes += child.value_nodes.to_int64()
      if max_items is Some(_) {
        nodes += 1L
      }
      if child.depth == 2147483647 {
        return None
      }
      depth = child.depth + 1
      enums += child.enum_items.to_int64()
      max_fields = child.max_fields
    }
    Object(fields) => {
      // additional_properties and the fields object, whose members directly
      // contain their checked child contract (keys are not value nodes).
      nodes += 2L
      depth = 2
      max_fields = field_count(fields)
      for index in 0..<field_count(fields) {
        guard field_at(fields, index) is Some(field) &&
          checked_emission_geometry(field.contract, max_depth=max_depth - 2)
          is Some(child) else {
          return None
        }
        contracts += child.contract_nodes.to_int64()
        nodes += child.value_nodes.to_int64()
        enums += child.enum_items.to_int64()
        if child.depth > 2147483645 {
          return None
        }
        depth = Int::max(depth, child.depth + 2)
        max_fields = Int::max(max_fields, child.max_fields)
        if contracts > 2147483647L || nodes > 2147483647L || enums > 2147483647L {
          return None
        }
      }
    }
    _ => ()
  }
  if depth > max_depth ||
    contracts > 2147483647L ||
    nodes > 2147483647L ||
    enums > 2147483647L {
    return None
  }
  Some({
    contract_nodes: contracts.to_int(),
    value_nodes: nodes.to_int(),
    depth,
    enum_items: enums.to_int(),
    max_fields,
  })
}
