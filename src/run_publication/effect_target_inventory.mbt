///|
/// Canonical target identity order is shared Effect meaning. Return only
/// original source indexes so callers retain each request and observation
/// owner together; this inventory is neither a read nor write permission.
fn derive_effect_target_row_inventory(
  target_wires : Array[String],
  max_rows : Int,
  max_total_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Array[Int], EffectPreviewIdentityIssue] {
  if max_rows < 0 ||
    max_total_bytes < 1 ||
    max_nodes < 1 ||
    max_depth < 1 ||
    target_wires.length() > max_rows {
    return Err(Encoding)
  }
  let mut remaining_bytes = max_total_bytes
  let targets : Array[(String, Int)] = []
  for index, wire in target_wires {
    if wire.length() > remaining_bytes {
      return Err(Encoding)
    }
    let bytes = @utf8.encode(wire)
    if bytes.length() > remaining_bytes {
      return Err(Encoding)
    }
    remaining_bytes -= bytes.length()
    let value = match
      parse_contract_wire(
        wire,
        bytes.length(),
        max_nodes,
        max_depth,
        data_keys=true,
      ) {
      Ok(value) => value
      Err(_) => return Err(InvalidMember)
    }
    let canonical = @json.stringify_value(
      value, max_total_bytes, max_nodes, max_depth,
    ) catch {
      _ => return Err(Encoding)
    }
    targets.push((canonical, index))
  }
  targets.sort_by((left, right) => @canonical.compare_utf16(left.0, right.0))
  let result : Array[Int] = []
  let mut previous : String? = None
  for (target, index) in targets {
    if previous is Some(value) && value == target {
      return Err(InvalidMember)
    }
    previous = Some(target)
    result.push(index)
  }
  Ok(result)
}
