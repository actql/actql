///|
/// Search a canonical UTF-16-sorted binding inventory. The returned budget is
/// the exact remainder after charging every visited comparison and name.
fn search_bound_parameter(
  name : String,
  count : Int,
  at : (Int) -> @parameter.BoundParameter?,
  remaining : Int,
) -> Result[(@parameter.BoundParameter?, Int), Unit] {
  let mut budget = remaining
  let mut low = 0
  let mut high = count
  while low < high {
    let mid = low + (high - low) / 2
    guard at(mid) is Some(entry) else { return Err(()) }
    for cost in [1, name.length(), entry.name.length()] {
      if cost > budget {
        return Err(())
      }
      budget -= cost
    }
    let order = @canonical.compare_utf16(name, entry.name)
    if order < 0 {
      high = mid
    } else if order > 0 {
      low = mid + 1
    } else {
      return Ok((Some(entry), budget))
    }
  }
  Ok((None, budget))
}
