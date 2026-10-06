///|
fn event_name_length(name : @schema.FieldName) -> Int64 {
  match name {
    @schema.Unqualified(text) => text.length().to_int64()
    @schema.Qualified(@schema.Left, text) => text.length().to_int64() + 5L
    @schema.Qualified(@schema.Right, text) => text.length().to_int64() + 6L
  }
}

///|
/// Borrow typed names and scan at most one common reference fragment.
/// Spelling equality does not replace carrier role or input-owner admission.
fn event_name_equal(
  left : @schema.FieldName,
  right : @schema.FieldName,
  offset : Int,
) -> (Bool?, Int) {
  if event_name_length(left) != event_name_length(right) {
    return (Some(false), 0)
  }
  let (order, next, _) = @schema.compare_reference_fragment(
    left, right, offset, 64,
  )
  (order.map(order => order == 0), next)
}
