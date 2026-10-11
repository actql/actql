///|
// Synthetic Pipe continuations retain their complete range scope. Authored CTE
// value-table kinds use separate metadata in the existing Script binding.
fn has_pipe_range_input(query : @query.Query) -> Bool {
  let pending = [query]
  while pending.pop() is Some(current) {
    for index in 0..<@query.cte_count(current) {
      let cte = @query.cte_at(current, index).unwrap()
      if cte.carry_ranges {
        return true
      }
      pending.push(cte.query)
    }
    for index in 0..<@query.set_part_count(current) {
      pending.push(@query.set_part_at(current, index).unwrap().right)
    }
  }
  false
}
