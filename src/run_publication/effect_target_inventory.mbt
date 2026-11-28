///|
/// Canonical target identity order is shared Effect meaning. Return only
/// original source indexes so callers retain each request and observation
/// owner together; this inventory is neither a read nor write permission.
fn derive_effect_target_canonical_row_inventory(
  originals : Array[@json.CanonicalValue],
  max_rows : Int,
  max_total_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Array[Int], EffectPreviewIdentityIssue] {
  if max_rows < 0 ||
    max_total_bytes < 1 ||
    max_nodes < 1 ||
    max_depth < 1 ||
    originals.length() > max_rows {
    return Err(Encoding)
  }
  let mut remaining_bytes = max_total_bytes
  let targets : Array[(String, Int)] = []
  for index, original in originals {
    let (canonical, bytes, _, _) = @json.stringify_value_with_usage(
      original, remaining_bytes, max_nodes, max_depth,
    ) catch {
      _ => return Err(Encoding)
    }
    remaining_bytes -= bytes
    targets.push((canonical, index))
  }
  order_effect_target_inventory(targets)
}

///|
fn order_effect_target_inventory(
  targets : Array[(String, Int)],
) -> Result[Array[Int], EffectPreviewIdentityIssue] {
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
