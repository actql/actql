///|
/// Quote only the additional synchronous member codec scratch on the SAME
/// saved-control construction. Its result stays in the already retained sum
/// of row-control families; this does not create another owner or allowance.
pub fn installed_effect_member_receipt_construction(
  rows : Int,
  row_bytes : Int,
  row_nodes : Int,
  row_depth : Int,
) -> (@execution.ExecutionCapacity, Int, Int, Int)? {
  // Empty members keep their existing base-control path; no row reservation
  // exists from which to prove returned aggregate retention.
  if rows < 1 || row_bytes < 1 || row_nodes < 1 || row_depth < 1 {
    return None
  }
  guard @effect.effect_member_receipt_encoding_limits(rows)
    is Some((bytes, nodes, depth)) else {
    return None
  }
  // Four returned value families and three text envelopes per actual row are
  // retained by standard_create_saved_receipt_capacity. The aggregate is the
  // SAME four-family codec, not an extra set beside all of them. Coheld row
  // heads/terminal receipts and member trees remain within those row families.
  if bytes.to_int64() > row_bytes.to_int64() * rows.to_int64() ||
    nodes.to_int64() > row_nodes.to_int64() * rows.to_int64() ||
    depth > row_depth {
    return None
  }
  guard standard_create_saved_receipt_capacity(bytes, nodes, depth)
    is Some(codec) &&
    @execution.execution_capacity(
      0L,
      @execution.execution_capacity_execution_bytes(codec) -
      @execution.execution_capacity_retained_bytes(codec),
    )
    is Some(scratch) else {
    return None
  }
  Some((scratch, bytes, nodes, depth))
}
