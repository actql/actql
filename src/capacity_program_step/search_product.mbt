///|
priv enum SearchProductArithmeticIssue {
  MissingOperandBound
  Overflow
}

///|
/// Callers validate every supplied proof's operand ownership before arithmetic.
/// This shared arithmetic does not select a search contract or a realization.
fn search_product_upper(
  left : TargetRows?,
  right : TargetRows?,
) -> Result[Int64, SearchProductArithmeticIssue] {
  let l = left.map(target_rows_value)
  let r = right.map(target_rows_value)
  if l == Some(0L) || r == Some(0L) {
    return Ok(0L)
  }
  guard l is Some(l) && r is Some(r) else { return Err(MissingOperandBound) }
  // TargetRows already admits nonnegative safe-integer row witnesses.
  match
    @numeric.multiply(@numeric.read(l).unwrap(), @numeric.read(r).unwrap()) {
    Ok(n) => Ok(@numeric.value(n))
    Err(_) => Err(Overflow)
  }
}
