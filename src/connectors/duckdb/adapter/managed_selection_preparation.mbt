///|
/// Begin conditional metadata transfer after native occurrence settlement.
/// Actual execution and retained holding remain separate completion facts.
pub fn[T] begin_managed_fixed_query_selection(
  query : ManagedFixedQuery[T],
  rows : Array[Int],
  max_cells : Int,
  max_work : Int,
) -> Result[@execution.ManagedViewSelectionPreparation[T], NativeQueryIssue] {
  if max_cells < 0 || max_work < 0 {
    return Err(InvalidLimits)
  }
  let prepared = match query.body {
    Fixed(_) => {
      if rows.length() > max_work {
        return Err(Limit)
      }
      let plan = match
        prepare_managed_fixed_view_plan(query, query.compilation) {
        Ok(plan) => plan
        Err(issue) => return Err(issue)
      }
      let previous = Ref(-1)
      @execution.begin_managed_view_selection(
        plan,
        rows,
        max_cells,
        max_work - rows.length(),
        validate_occurrence=fn(_, row) {
          let valid = row > previous.val
          previous.val = row
          valid
        },
      )
    }
    Take(take) => {
      if !managed_take_query_matches(take, take.input) {
        return Err(InputUnavailable)
      }
      let available = @execution.managed_producer_read_row_count(take.input)
      let offset = if take.offset >= available.to_int64() {
        available
      } else {
        take.offset.to_int()
      }
      let remaining = available - offset
      let count = if take.count >= remaining.to_int64() {
        remaining
      } else {
        take.count.to_int()
      }
      if rows.length() != count {
        return Err(UnsupportedShape)
      }
      if take.sorted {
        @execution.begin_managed_view_selection(
          take.plan,
          rows,
          max_cells,
          max_work,
        )
      } else {
        // The virtual interval needs no row-sized map. Check actual native
        // occurrences one at a time without changing existing logical work.
        @execution.begin_managed_view_slice(
          take.plan,
          offset,
          count,
          max_cells,
          max_work,
          validate_occurrence=fn(position, row) {
            rows.length() == count && rows.get(position) == Some(row)
          },
        )
      }
    }
  }
  match prepared {
    Ok(cursor) => Ok(cursor)
    Err(ForeignInput) => Err(InputUnavailable)
    Err(Limit) => Err(Limit)
    Err(InvalidLimits) => Err(InvalidLimits)
    Err(_) => Err(UnsupportedShape)
  }
}
