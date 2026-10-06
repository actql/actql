///|
fn pool_name_length(name : @schema.FieldName) -> Int64 {
  match name {
    @schema.Unqualified(text) => text.length().to_int64()
    @schema.Qualified(@schema.Left, text) => text.length().to_int64() + 5L
    @schema.Qualified(@schema.Right, text) => text.length().to_int64() + 6L
  }
}

///|
/// Equality needs no scan when reference lengths differ. Otherwise retain
/// only the position in pre-reserved Session custody, borrowing typed names.
fn pool_name_equal_budget(
  state : PoolState,
  left : @schema.FieldName,
  right : @schema.FieldName,
  allowance : Int,
) -> (Bool?, Int) {
  if pool_name_length(left) != pool_name_length(right) {
    state.name_offset = 0
    return (Some(false), 0)
  }
  let (order, offset, spent) = @schema.compare_reference_fragment(
    left,
    right,
    state.name_offset,
    allowance,
  )
  state.name_offset = offset
  (order.map(order => order == 0), spent)
}

///|
fn pool_name_equal(
  state : PoolState,
  left : @schema.FieldName,
  right : @schema.FieldName,
) -> Bool? {
  pool_name_equal_budget(state, left, right, 64).0
}
