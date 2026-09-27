///|
/// `percentile_disc` and `percentile_cont` over non-empty contributors with at
/// most one control unit per advance. Contributors are ordered by the
/// resumable merge with complete-value comparisons; the rank or
/// interpolation charges match the atomic evaluator.
priv struct AggregatePercentile {
  fraction : Double
  discrete : Bool
  control : ControlBudget
  workspace : RowWorkspace
  count : Int
  sort : AggregateMergeSort[Value]
  numbers : Array[Double]
  pending : PendingUnits
  mut sorted : Array[Value]
  mut phase : Int
  mut index : Int
  mut remainder : Double
  mut base : Int
  mut closed : Bool
}

///|
fn start_aggregate_percentile(
  values : Array[Value],
  fraction : Double,
  discrete : Bool,
  control : ControlBudget,
  workspace : RowWorkspace,
) -> AggregatePercentile {
  {
    fraction,
    discrete,
    control,
    workspace,
    count: values.length(),
    sort: start_aggregate_merge_sort(
      values,
      complete_value_step_comparator(control),
    ),
    numbers: [],
    pending: { remaining: 0, },
    sorted: [],
    phase: 0,
    index: 0,
    remainder: 0.0,
    base: 0,
    closed: false,
  }
}

///|
fn advance_aggregate_percentile(
  state : AggregatePercentile,
) -> Result[Value?, RowIssue] {
  if state.closed {
    return Err(InvalidRows)
  }
  let result = advance_aggregate_percentile_impl(state)
  match result {
    Err(_) | Ok(Some(_)) => {
      close_aggregate_merge_sort(state.sort)
      state.closed = true
    }
    Ok(None) => ()
  }
  result
}

///|
fn advance_aggregate_percentile_impl(
  s : AggregatePercentile,
) -> Result[Value?, RowIssue] {
  match s.phase {
    0 => {
      if !reserve_slots(s.workspace, s.count) {
        return Err(RowLimit)
      }
      s.phase = 1
      Ok(None)
    }
    1 =>
      match advance_aggregate_merge_sort(s.sort) {
        Err(issue) => Err(issue)
        Ok(None) => Ok(None)
        Ok(Some(sorted)) => {
          release_slots(s.workspace, s.count)
          s.sorted = sorted
          if s.discrete {
            s.pending.remaining = 2
            s.phase = 2
          } else {
            s.phase = 3
          }
          Ok(None)
        }
      }
    // percentile_disc: two units, then the nearest-rank value.
    2 =>
      match pay_pending_unit(s.pending, s.control) {
        Err(issue) => Err(issue)
        Ok(false) => Ok(None)
        Ok(true) => {
          let rank = Int::max(
            1,
            (s.fraction * s.count.to_double()).ceil().to_int(),
          )
          Ok(Some(s.sorted[rank - 1]))
        }
      }
    // percentile_cont: reserve and admit finite numbers one per advance.
    3 => {
      if !reserve_slots(s.workspace, s.count) {
        return Err(RowLimit)
      }
      s.phase = 4
      Ok(None)
    }
    4 => {
      if s.index < s.count {
        guard s.sorted[s.index] is Number(number) &&
          !number.is_nan() &&
          !number.is_inf() else {
          return Err(InvalidRows)
        }
        s.numbers.push(number)
        s.index += 1
        return Ok(None)
      }
      s.pending.remaining = 4
      s.phase = 5
      Ok(None)
    }
    5 =>
      match pay_pending_unit(s.pending, s.control) {
        Err(issue) => Err(issue)
        Ok(false) => Ok(None)
        Ok(true) => {
          let h = match
            finite_aggregate_number((s.count - 1).to_double() * s.fraction) {
            Ok(value) => value
            Err(issue) => return Err(issue)
          }
          s.base = h.floor().to_int()
          s.remainder = match finite_aggregate_number(h - s.base.to_double()) {
            Ok(value) => value
            Err(issue) => return Err(issue)
          }
          if s.remainder == 0.0 {
            return Ok(Some(Number(s.numbers[s.base])))
          }
          s.pending.remaining = 3
          s.phase = 6
          Ok(None)
        }
      }
    _ =>
      match pay_pending_unit(s.pending, s.control) {
        Err(issue) => Err(issue)
        Ok(false) => Ok(None)
        Ok(true) => {
          let difference = match
            finite_aggregate_number(s.numbers[s.base + 1] - s.numbers[s.base]) {
            Ok(value) => value
            Err(issue) => return Err(issue)
          }
          let weighted = match
            finite_aggregate_number(s.remainder * difference) {
            Ok(value) => value
            Err(issue) => return Err(issue)
          }
          match finite_aggregate_number(s.numbers[s.base] + weighted) {
            Ok(value) => Ok(Some(Number(value)))
            Err(issue) => Err(issue)
          }
        }
      }
  }
}

///|
/// Population and sample variance and standard deviation with at most one
/// control unit per advance. Contributors are put in canonical identity
/// order by the resumable merge, then summed and squared with the charges of
/// the atomic evaluator.
priv struct AggregateStatistical {
  values : Array[Value]
  sample : Bool
  deviation : Bool
  control : ControlBudget
  workspace : RowWorkspace
  identity_limits : ValueLimits
  entries : Array[(String, Double)]
  numbers : Array[Double]
  pending : PendingUnits
  mut sort : AggregateMergeSort[(String, Double)]?
  mut ordered : Array[(String, Double)]
  mut phase : Int
  mut index : Int
  mut cid : String
  mut sum : Double
  mut mean : Double
  mut squares : Double
  mut variance : Double
  mut closed : Bool
}

///|
fn start_aggregate_statistical(
  values : Array[Value],
  sample : Bool,
  deviation : Bool,
  control : ControlBudget,
  workspace : RowWorkspace,
  identity_limits : ValueLimits,
) -> AggregateStatistical {
  {
    values,
    sample,
    deviation,
    control,
    workspace,
    identity_limits,
    entries: [],
    numbers: [],
    pending: { remaining: 0, },
    sort: None,
    ordered: [],
    phase: 0,
    index: 0,
    cid: "",
    sum: 0.0,
    mean: 0.0,
    squares: 0.0,
    variance: 0.0,
    closed: false,
  }
}

///|
fn advance_aggregate_statistical(
  state : AggregateStatistical,
) -> Result[Value?, RowIssue] {
  if state.closed {
    return Err(InvalidRows)
  }
  let result = advance_aggregate_statistical_impl(state)
  match result {
    Err(_) | Ok(Some(_)) => {
      if state.sort is Some(sort) {
        close_aggregate_merge_sort(sort)
      }
      state.closed = true
    }
    Ok(None) => ()
  }
  result
}

///|
fn advance_aggregate_statistical_impl(
  s : AggregateStatistical,
) -> Result[Value?, RowIssue] {
  let count = s.values.length()
  match s.phase {
    0 => {
      if !reserve_slots(s.workspace, count) ||
        !reserve_slots(s.workspace, count) {
        return Err(RowLimit)
      }
      s.phase = 1
      Ok(None)
    }
    // Canonical identity of the next finite number.
    1 => {
      if s.index >= count {
        s.sort = Some(
          start_aggregate_merge_sort(
            s.entries,
            identity_step_comparator(s.control),
          ),
        )
        s.index = 0
        s.phase = 3
        return Ok(None)
      }
      guard s.values[s.index] is Number(number) &&
        !number.is_nan() &&
        !number.is_inf() else {
        return Err(InvalidRows)
      }
      let (cid, bytes) = match
        runtime_value_identity_usage(
          s.values[s.index],
          s.control,
          s.workspace,
          s.identity_limits,
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      s.cid = cid
      s.pending.remaining = bytes
      s.phase = 2
      Ok(None)
    }
    2 =>
      match pay_pending_unit(s.pending, s.control) {
        Err(issue) => Err(issue)
        Ok(false) => Ok(None)
        Ok(true) => {
          guard s.values[s.index] is Number(number) else {
            return Err(InvalidRows)
          }
          s.entries.push((s.cid, number))
          s.index += 1
          s.phase = 1
          Ok(None)
        }
      }
    3 => {
      guard s.sort is Some(sort) else { return Err(InvalidRows) }
      match advance_aggregate_merge_sort(sort) {
        Err(issue) => Err(issue)
        Ok(None) => Ok(None)
        Ok(Some(sorted)) => {
          s.ordered = sorted
          s.sort = None
          s.phase = 4
          Ok(None)
        }
      }
    }
    // Copy the ordered numbers one per advance.
    4 => {
      if s.index < s.ordered.length() {
        s.numbers.push(s.ordered[s.index].1)
        s.index += 1
        return Ok(None)
      }
      s.index = 0
      s.phase = 5
      Ok(None)
    }
    // Sum: one unit per contributor.
    5 => {
      if s.index < s.numbers.length() {
        if !spend_control(s.control, 1) {
          return Err(RowLimit)
        }
        s.sum = match finite_aggregate_number(s.sum + s.numbers[s.index]) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        s.index += 1
        return Ok(None)
      }
      if !spend_control(s.control, 1) {
        return Err(RowLimit)
      }
      s.mean = match
        finite_aggregate_number(s.sum / s.numbers.length().to_double()) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      s.index = 0
      s.pending.remaining = 3
      s.phase = 6
      Ok(None)
    }
    // Squares: three units per contributor.
    6 => {
      if s.index < s.numbers.length() {
        match pay_pending_unit(s.pending, s.control) {
          Err(issue) => return Err(issue)
          Ok(false) => return Ok(None)
          Ok(true) => ()
        }
        let difference = match
          finite_aggregate_number(s.numbers[s.index] - s.mean) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        let square = match finite_aggregate_number(difference * difference) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        s.squares = match finite_aggregate_number(s.squares + square) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        s.index += 1
        s.pending.remaining = 3
        return Ok(None)
      }
      if !spend_control(s.control, 1) {
        return Err(RowLimit)
      }
      let divisor = if s.sample {
        s.numbers.length() - 1
      } else {
        s.numbers.length()
      }
      s.variance = match
        finite_aggregate_number(s.squares / divisor.to_double()) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      if !s.deviation {
        return Ok(Some(Number(s.variance)))
      }
      s.phase = 7
      Ok(None)
    }
    _ => {
      if !spend_control(s.control, 1) {
        return Err(RowLimit)
      }
      match finite_aggregate_number(s.variance.sqrt()) {
        Ok(value) => Ok(Some(Number(value)))
        Err(issue) => Err(issue)
      }
    }
  }
}
