///|
/// The whole `pivot` operation as one resumable state, in the order and with
/// the charges of the draining `evaluate_pivot_rows`. Name resolution and
/// multi-unit charges pay one control unit per advance; ordering and index
/// group boundaries use their resumable owners; each group row advances one
/// member, one comparison unit, one Decimal charge unit or one numeric
/// reduction step at a time. Emitting one row is bounded by the output schema
/// and the per-value limits.
priv struct PivotEvaluation[T] {
  pivot : @lower.PreparedPivot
  input : T
  max_rows : Int
  control : ControlBudget
  output : ValueBudget
  workspace : RowWorkspace
  numeric : NumericAggregateExecution?
  step : Int
  accept_row : (Array[Value], Int) -> Result[Unit, RowIssue]
  function : @relation.AggregateFunction
  decimal_sum_scale : Int?
  numeric_required : Bool
  fill : Value
  names : Array[String]
  ordinals : Map[String, Int]
  order : Array[ColumnOrder]
  index_by_name : Map[String, Int]
  axis_by_name : Map[String, Int]
  output_names : Array[String]
  // false selects an index column; true selects one authored pivot bucket.
  projection : Array[(Bool, Int)]
  pending : PendingUnits
  mut pivot_column : Int
  mut value_column : Int
  mut charging : Bool
  mut phase : Int
  mut index : Int
  mut indices : Array[Int]
  mut sorter : StableOrderExecution[T]?
  mut ranges : AggregateGroupRangeExecution[T]?
  mut groups : Array[AggregateGroupRange]
  // First-occurrence group order.
  mut source : Array[Int]
  mut target : Array[Int]
  mut width : Int
  mut start : Int
  mut middle : Int
  mut end : Int
  mut left : Int
  mut right : Int
  mut group_order : Array[Int]?
  mut group_position : Int
  // The current group row.
  mut position : Int
  mut counts : Array[Int]
  mut selected : Array[Value?]
  mut sums : Array[String?]
  mut numeric_values : Array[Array[Double]]
  mut member_axis : Int
  mut member_value : Value
  mut member_phase : Int
  mut compare_offset : Int
  mut contributor : String
  mut row : Array[Value]
  mut reduction : NumericAggregateStep?
  mut outcome : @numeric.Outcome?
  mut emitted : Int
  mut closed : Bool
}

///|
fn[T : RelationRows] start_pivot_evaluation(
  kernel : @lower.PreparedKernel,
  input : T,
  max_rows : Int,
  control : ControlBudget,
  output : ValueBudget,
  workspace : RowWorkspace,
  numeric : NumericAggregateExecution?,
  step : Int,
  accept_row : (Array[Value], Int) -> Result[Unit, RowIssue],
) -> Result[PivotEvaluation[T], RowIssue] {
  guard @lower.kernel_pivot(kernel) is Some(pivot) else {
    return Err(InvalidRows)
  }
  let function = @lower.pivot_function(pivot)
  let decimal_sum_scale = match function {
    @relation.Sum =>
      match @lower.pivot_result_contract(pivot).shape {
        @contract.Decimal(precision=38, scale~) => Some(scale)
        _ => None
      }
    _ => None
  }
  let numeric_required = pivot_requires_numeric_observation(pivot)
  if !pivot_execution_supported_with_profile(pivot, numeric is Some(_)) ||
    (numeric_required && (numeric is None || step < 0)) {
    return Err(InvalidRows)
  }
  if max_rows < 0 ||
    control.remaining < 0 ||
    control.max_frames < 0 ||
    workspace.limit < 0 ||
    workspace.live < 0 ||
    workspace.live > workspace.limit ||
    workspace.peak < workspace.live {
    return Err(InvalidRowLimits)
  }
  Ok({
    pivot,
    input,
    max_rows,
    control,
    output,
    workspace,
    numeric,
    step,
    accept_row,
    function,
    decimal_sum_scale,
    numeric_required,
    fill: pivot_fill_value(pivot),
    names: input.field_names(),
    ordinals: Map([]),
    order: [],
    index_by_name: Map([]),
    axis_by_name: Map([]),
    output_names: [],
    projection: [],
    pending: { remaining: 0, },
    pivot_column: -1,
    value_column: -1,
    charging: false,
    phase: 0,
    index: 0,
    indices: [],
    sorter: None,
    ranges: None,
    groups: [],
    source: [],
    target: [],
    width: 1,
    start: 0,
    middle: 0,
    end: 0,
    left: 0,
    right: 0,
    group_order: None,
    group_position: 0,
    position: 0,
    counts: [],
    selected: [],
    sums: [],
    numeric_values: [],
    member_axis: -1,
    member_value: Null,
    member_phase: 0,
    compare_offset: 0,
    contributor: "",
    row: [],
    reduction: None,
    outcome: None,
    emitted: 0,
    closed: false,
  })
}

///|
fn[T] close_pivot_evaluation(state : PivotEvaluation[T]) -> Unit {
  if state.closed {
    return
  }
  if state.sorter is Some(sorter) {
    close_stable_order(sorter)
    state.sorter = None
  }
  if state.ranges is Some(ranges) {
    close_aggregate_group_ranges(ranges)
    state.ranges = None
  }
  if state.reduction is Some(reduction) {
    (reduction.close)() |> ignore
    state.reduction = None
  }
  state.closed = true
}

///|
/// Returns the output names once every group row has been accepted and the
/// selected numeric occurrence domains are sealed.
fn[T : RelationRows] advance_pivot_evaluation(
  state : PivotEvaluation[T],
) -> Result[Array[String]?, RowIssue] {
  if state.closed {
    return Err(InvalidRows)
  }
  let result = advance_pivot_evaluation_impl(state)
  match result {
    Err(_) => close_pivot_evaluation(state)
    Ok(Some(_)) => state.closed = true
    Ok(None) => ()
  }
  result
}

///|
/// Pay `1 + UTF-8(name)` units, one per advance. Returns true when paid.
fn[T] pivot_charge_name(
  s : PivotEvaluation[T],
  name : String,
  entry : Bool,
) -> Result[Bool, RowIssue] {
  if !s.charging {
    s.pending.remaining = match utf8_units(name) {
      Ok(bytes) => (if entry { 1 } else { 0 }) + bytes
      Err(issue) => return Err(issue)
    }
    s.charging = true
  }
  match pay_pending_unit(s.pending, s.control) {
    Err(issue) => Err(issue)
    Ok(false) => Ok(false)
    Ok(true) => {
      s.charging = false
      Ok(true)
    }
  }
}

///|
/// Pay previously decided units, one per advance. Returns true when paid.
fn[T] pivot_pay(s : PivotEvaluation[T], units : Int) -> Result[Bool, RowIssue] {
  if !s.charging {
    s.pending.remaining = units
    s.charging = true
  }
  match pay_pending_unit(s.pending, s.control) {
    Err(issue) => Err(issue)
    Ok(false) => Ok(false)
    Ok(true) => {
      s.charging = false
      Ok(true)
    }
  }
}

///|
/// The UTF-8 units `charge_comparison_operand` charges for one operand.
fn pivot_comparison_units(value : Value) -> Result[Int, RowIssue] {
  match value {
    Text(s) | Captured(@admitted.Date(s)) | Captured(@admitted.Timestamp(s)) =>
      utf8_units(s)
    Captured(@admitted.Decimal(d)) => utf8_units(d.coefficient)
    Captured(@admitted.Reference(reference)) =>
      if !@admitted.reference_available(reference) {
        Err(Comparison(InvalidOperand))
      } else {
        utf8_units(@admitted.reference_identity_cid(reference))
      }
    Null | Number(_) | Boolean(_) | Captured(_) => Ok(0)
  }
}

///|
fn[T] pivot_resolve(
  s : PivotEvaluation[T],
  field : @schema.FieldName,
) -> Result[Int?, RowIssue] {
  let name = @schema.reference_name(field)
  match pivot_charge_name(s, name, true) {
    Err(issue) => Err(issue)
    Ok(false) => Ok(None)
    Ok(true) =>
      match s.ordinals.get(name) {
        Some(index) => Ok(Some(index))
        None => Err(InvalidRows)
      }
  }
}

///|
fn[T : RelationRows] advance_pivot_evaluation_impl(
  s : PivotEvaluation[T],
) -> Result[Array[String]?, RowIssue] {
  let pivot = s.pivot
  let index_count = @lower.pivot_index_count(pivot)
  let axis_count = @lower.pivot_axis_count(pivot)
  let schema = @lower.pivot_output_schema(pivot)
  let output_width = @schema.field_count(schema)
  match s.phase {
    // Input field names: one unit and the name, then a slot.
    0 => {
      if s.index >= s.names.length() {
        if !reserve_slots(s.workspace, index_count) ||
          !reserve_slots(s.workspace, axis_count) ||
          !reserve_slots(s.workspace, axis_count) {
          return Err(RowLimit)
        }
        s.phase = 1
        return Ok(None)
      }
      let name = s.names[s.index]
      match pivot_charge_name(s, name, true) {
        Err(issue) => return Err(issue)
        Ok(false) => return Ok(None)
        Ok(true) => ()
      }
      if !reserve_slots(s.workspace, 1) {
        return Err(RowLimit)
      }
      if s.ordinals.contains(name) {
        return Err(InvalidRows)
      }
      s.ordinals[name] = s.index
      s.index += 1
      Ok(None)
    }
    // Index and axis metadata.
    1 =>
      match pivot_pay(s, index_count + axis_count) {
        Err(issue) => Err(issue)
        Ok(false) => Ok(None)
        Ok(true) => {
          s.index = 0
          s.phase = 2
          Ok(None)
        }
      }
    // Index fields.
    2 => {
      if s.index >= index_count {
        s.phase = 3
        return Ok(None)
      }
      let field = @lower.pivot_index_at(pivot, s.index).unwrap()
      match pivot_resolve(s, field) {
        Err(issue) => Err(issue)
        Ok(None) => Ok(None)
        Ok(Some(ordinal)) => {
          s.order.push({
            column: ordinal,
            descending: false,
            nulls_first: true,
          })
          let name = @schema.reference_name(field)
          if !s.index_by_name.contains(name) {
            s.index_by_name[name] = ordinal
          }
          s.index += 1
          Ok(None)
        }
      }
    }
    // Pivot column.
    3 =>
      match pivot_resolve(s, @lower.pivot_column(pivot)) {
        Err(issue) => Err(issue)
        Ok(None) => Ok(None)
        Ok(Some(column)) => {
          s.pivot_column = column
          s.phase = 4
          Ok(None)
        }
      }
    // Value column.
    4 =>
      match pivot_resolve(s, @lower.pivot_value(pivot)) {
        Err(issue) => Err(issue)
        Ok(None) => Ok(None)
        Ok(Some(column)) => {
          s.value_column = column
          s.index = 0
          s.phase = 5
          Ok(None)
        }
      }
    // Authored axis names.
    5 => {
      if s.index >= axis_count {
        if !reserve_slots(s.workspace, output_width) ||
          !reserve_slots(s.workspace, output_width) {
          return Err(RowLimit)
        }
        s.index = 0
        s.phase = 6
        return Ok(None)
      }
      let name = @lower.pivot_axis_at(pivot, s.index).unwrap()
      match pivot_charge_name(s, name, false) {
        Err(issue) => return Err(issue)
        Ok(false) => return Ok(None)
        Ok(true) => ()
      }
      if s.axis_by_name.contains(name) {
        return Err(InvalidRows)
      }
      s.axis_by_name[name] = s.index
      s.index += 1
      Ok(None)
    }
    // Output fields.
    6 => {
      if s.index >= output_width {
        s.sorter = Some(
          start_stable_order(s.input, s.order, s.control, s.workspace),
        )
        s.phase = 7
        return Ok(None)
      }
      let name = @schema.reference_name(
        @schema.field_at(schema, s.index).unwrap().name,
      )
      match pivot_charge_name(s, name, true) {
        Err(issue) => return Err(issue)
        Ok(false) => return Ok(None)
        Ok(true) => ()
      }
      s.output_names.push(name)
      match s.index_by_name.get(name) {
        Some(column) => s.projection.push((false, column))
        None =>
          match s.axis_by_name.get(name) {
            Some(axis) => s.projection.push((true, axis))
            None => return Err(InvalidRows)
          }
      }
      s.index += 1
      Ok(None)
    }
    // Stable index order.
    7 => {
      guard s.sorter is Some(sorter) else { return Err(InvalidRows) }
      match advance_stable_order(sorter) {
        Err(issue) => Err(ordering_row_issue(issue))
        Ok(None) => Ok(None)
        Ok(Some(indices)) => {
          s.sorter = None
          s.indices = indices
          if s.order.is_empty() {
            s.phase = 8
          } else {
            s.ranges = Some(
              start_aggregate_group_ranges(
                s.input,
                s.indices,
                s.order,
                s.max_rows,
                s.control,
                s.workspace,
              ),
            )
            s.phase = 9
          }
          Ok(None)
        }
      }
    }
    // Without index fields every row is one group.
    8 => {
      if s.max_rows < 1 ||
        !spend_control(s.control, 1) ||
        !reserve_slots(s.workspace, 1) {
        return Err(RowLimit)
      }
      s.groups = [
        { representative: s.indices.get(0), start: 0, end: s.indices.length(), },
      ]
      s.phase = 10
      Ok(None)
    }
    // Index group boundaries.
    9 => {
      guard s.ranges is Some(ranges) else { return Err(InvalidRows) }
      match advance_aggregate_group_ranges(ranges) {
        Err(issue) => Err(issue)
        Ok(None) => Ok(None)
        Ok(Some(groups)) => {
          s.ranges = None
          s.groups = groups
          s.phase = 10
          Ok(None)
        }
      }
    }
    // Group order: identity, or first occurrence for empty axes.
    10 => {
      let count = s.groups.length()
      if axis_count == 0 && !s.order.is_empty() {
        if !reserve_slots(s.workspace, count) {
          return Err(RowLimit)
        }
        s.phase = 11
      } else {
        if !reserve_slots(s.workspace, count) {
          return Err(RowLimit)
        }
        s.phase = 14
      }
      Ok(None)
    }
    // First occurrence: the initial coordinates, one unit each.
    11 => {
      let count = s.groups.length()
      if s.source.length() < count {
        if !spend_control(s.control, 1) {
          return Err(RowLimit)
        }
        s.source.push(s.source.length())
        return Ok(None)
      }
      if count < 2 {
        s.group_order = Some(s.source)
        s.phase = 15
        return Ok(None)
      }
      if !reserve_slots(s.workspace, count) {
        return Err(RowLimit)
      }
      s.phase = 12
      Ok(None)
    }
    // First occurrence: the merge buffer.
    12 =>
      match pivot_pay(s, s.groups.length()) {
        Err(issue) => Err(issue)
        Ok(false) => Ok(None)
        Ok(true) => {
          s.width = 1
          s.start = 0
          s.target = []
          s.phase = 13
          s.middle = -1
          Ok(None)
        }
      }
    // First occurrence: one merged element per advance.
    13 => {
      let count = s.groups.length()
      if s.middle < 0 {
        if s.start >= count {
          let previous = s.source
          s.source = s.target
          s.target = previous
          s.target.clear()
          if s.width > count / 2 || s.width * 2 >= count {
            s.group_order = Some(s.source)
            s.phase = 15
            return Ok(None)
          }
          s.width *= 2
          s.start = 0
          return Ok(None)
        }
        s.middle = s.start + Int::min(s.width, count - s.start)
        s.end = s.middle + Int::min(s.width, count - s.middle)
        s.left = s.start
        s.right = s.middle
        return Ok(None)
      }
      if s.target.length() >= s.end {
        s.start = s.end
        s.middle = -1
        return Ok(None)
      }
      if !spend_control(s.control, 1) {
        return Err(RowLimit)
      }
      let choose_left = if s.left == s.middle {
        false
      } else if s.right == s.end {
        true
      } else {
        let a = s.groups[s.source[s.left]].representative.unwrap_or(-1)
        let b = s.groups[s.source[s.right]].representative.unwrap_or(-1)
        a <= b
      }
      if choose_left {
        s.target.push(s.source[s.left])
        s.left += 1
      } else {
        s.target.push(s.source[s.right])
        s.right += 1
      }
      Ok(None)
    }
    // Identity order: one unit per group coordinate.
    14 =>
      match pivot_pay(s, s.groups.length()) {
        Err(issue) => Err(issue)
        Ok(false) => Ok(None)
        Ok(true) => {
          s.phase = 15
          Ok(None)
        }
      }
    // Start the next group row.
    15 => {
      if s.group_position >= s.groups.length() {
        s.index = 0
        s.phase = 20
        return Ok(None)
      }
      if s.emitted >= s.max_rows ||
        !spend_control(s.control, 1) ||
        !reserve_slots(s.workspace, axis_count) ||
        !reserve_slots(s.workspace, axis_count) ||
        (
          (s.decimal_sum_scale is Some(_) || s.numeric_required) &&
          !reserve_slots(s.workspace, axis_count)
        ) ||
        !reserve_slots(s.workspace, output_width) {
        return Err(RowLimit)
      }
      let group = s.groups[pivot_group_at(s)]
      s.counts = Array::make(axis_count, 0)
      s.selected = Array::make(axis_count, None)
      s.sums = Array::make(axis_count, None)
      s.numeric_values = if s.numeric_required {
        Array::makei(axis_count, _ => [])
      } else {
        []
      }
      s.position = group.start
      s.member_phase = 0
      s.phase = 16
      Ok(None)
    }
    // One member of the current group.
    16 => pivot_advance_member(s)
    // Build the group row, one output column per advance.
    17 => pivot_advance_output(s)
    // Accept the group row.
    18 => {
      if !retain_row(s.row, s.output_names, s.output) {
        return Err(RowLimit)
      }
      let group = s.groups[pivot_group_at(s)]
      match (s.accept_row)(s.row, group.representative.unwrap_or(-1)) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
      s.emitted += 1
      s.group_position += 1
      s.phase = 15
      Ok(None)
    }
    // Seal the selected numeric occurrence domains, one axis per advance.
    _ => {
      if !s.numeric_required || s.index >= axis_count {
        return Ok(Some(s.output_names))
      }
      guard s.numeric is Some(execution) else { return Err(InvalidRows) }
      if !seal_numeric_aggregate(
          execution,
          s.step,
          @lower.pivot_axis_at(pivot, s.index).unwrap(),
          s.emitted,
        ) {
        return Err(InvalidRows)
      }
      s.index += 1
      Ok(None)
    }
  }
}

///|
fn[T] pivot_group_at(s : PivotEvaluation[T]) -> Int {
  match s.group_order {
    Some(order) => order[s.group_position]
    None => s.group_position
  }
}

///|
fn[T : RelationRows] pivot_advance_member(
  s : PivotEvaluation[T],
) -> Result[Array[String]?, RowIssue] {
  let group = s.groups[pivot_group_at(s)]
  match s.member_phase {
    // Enter one member and read its bucket and value.
    0 => {
      if s.position >= group.end {
        s.row = []
        s.index = 0
        s.phase = 17
        return Ok(None)
      }
      if !spend_control(s.control, 1) {
        return Err(RowLimit)
      }
      let source = s.indices[s.position]
      let axis = match IndexedRows::read_cell(s.input, source, s.pivot_column) {
        Text(name) => s.axis_by_name.get(name)
        Null => None
        _ => return Err(InvalidRows)
      }
      guard axis is Some(axis) else {
        s.position += 1
        return Ok(None)
      }
      let value = IndexedRows::read_cell(s.input, source, s.value_column)
      if value is Null {
        s.position += 1
        return Ok(None)
      }
      s.counts[axis] += 1
      s.member_axis = axis
      s.member_value = value
      match s.function {
        @relation.Count => s.position += 1
        @relation.First => {
          if s.selected[axis] is None {
            s.selected[axis] = Some(value)
          }
          s.position += 1
        }
        @relation.Min | @relation.Max =>
          if s.selected[axis] is None {
            s.selected[axis] = Some(value)
            s.position += 1
          } else {
            s.member_phase = 1
          }
        @relation.Sum | @relation.Avg =>
          if s.numeric_required {
            guard value is Number(number) else { return Err(InvalidRows) }
            if !reserve_slots(s.workspace, 1) {
              return Err(RowLimit)
            }
            s.numeric_values[axis].push(number)
            s.position += 1
          } else {
            guard value is Captured(@admitted.Decimal(decimal)) &&
              s.decimal_sum_scale is Some(scale) &&
              decimal.scale == scale else {
              return Err(InvalidRows)
            }
            s.contributor = decimal.coefficient
            s.member_phase = 5
          }
        _ => return Err(InvalidRows)
      }
      Ok(None)
    }
    // Comparison entry unit.
    1 => {
      if !spend_control(s.control, 1) {
        return Err(RowLimit)
      }
      s.member_phase = 2
      Ok(None)
    }
    // Charge the selected operand, then the member operand.
    2 | 3 => {
      let operand = if s.member_phase == 2 {
        s.selected[s.member_axis].unwrap()
      } else {
        s.member_value
      }
      if !s.charging {
        match pivot_comparison_units(operand) {
          Ok(units) => {
            s.pending.remaining = units
            s.charging = true
          }
          Err(issue) => return Err(issue)
        }
      }
      match pay_pending_unit(s.pending, s.control) {
        Err(issue) => return Err(issue)
        Ok(false) => return Ok(None)
        Ok(true) => s.charging = false
      }
      s.member_phase += 1
      s.compare_offset = 0
      Ok(None)
    }
    // Compare, one UTF-16 unit per advance for text.
    4 => {
      let previous = s.selected[s.member_axis].unwrap()
      let value = s.member_value
      let comparison = match (value, previous) {
        (Text(a), Text(b)) => {
          let offset = s.compare_offset
          if offset < a.length() && offset < b.length() {
            if a[offset] == b[offset] {
              s.compare_offset += 1
              return Ok(None)
            }
            if a[offset] < b[offset] {
              -1
            } else {
              1
            }
          } else {
            Int::compare(a.length(), b.length())
          }
        }
        _ =>
          match compare(value, previous) {
            Ok(value) => value
            Err(issue) => return Err(Comparison(issue))
          }
      }
      if (s.function is @relation.Min && comparison < 0) ||
        (s.function is @relation.Max && comparison > 0) {
        s.selected[s.member_axis] = Some(value)
      }
      s.position += 1
      s.member_phase = 0
      Ok(None)
    }
    // Decimal sum: charge the running and contributor coefficients and the
    // digit capacity, then add without charging again.
    5 => {
      let previous = s.sums[s.member_axis].unwrap_or("0")
      if !s.charging {
        let running = match utf8_units(previous) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        let contributor = match utf8_units(s.contributor) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        s.pending.remaining = running +
          contributor +
          decimal_sum_capacity(previous, s.contributor)
        s.charging = true
      }
      match pay_pending_unit(s.pending, s.control) {
        Err(issue) => return Err(issue)
        Ok(false) => return Ok(None)
        Ok(true) => s.charging = false
      }
      s.member_phase = 6
      Ok(None)
    }
    _ => {
      let previous = s.sums[s.member_axis].unwrap_or("0")
      let charged : ControlBudget = {
        remaining: 2147483647,
        max_frames: s.control.max_frames,
      }
      s.sums[s.member_axis] = match
        add_decimal_coefficients(previous, s.contributor, charged, s.workspace) {
        Ok(value) => Some(value)
        Err(issue) => return Err(issue)
      }
      s.position += 1
      s.member_phase = 0
      Ok(None)
    }
  }
}

///|
fn[T : RelationRows] pivot_advance_output(
  s : PivotEvaluation[T],
) -> Result[Array[String]?, RowIssue] {
  if s.index >= s.projection.length() {
    s.phase = 18
    return Ok(None)
  }
  let (aggregate, index) = s.projection[s.index]
  if !aggregate {
    let group = s.groups[pivot_group_at(s)]
    guard group.representative is Some(source) else { return Err(InvalidRows) }
    s.row.push(IndexedRows::read_cell(s.input, source, index))
    s.index += 1
    return Ok(None)
  }
  let value = match s.function {
    @relation.Count => Number(s.counts[index].to_double())
    @relation.Sum | @relation.Avg if s.numeric_required =>
      match pivot_advance_numeric(s, index) {
        Err(issue) => return Err(issue)
        Ok(None) => return Ok(None)
        Ok(Some(value)) => value
      }
    @relation.Sum =>
      match s.sums[index] {
        None => s.fill
        Some(coefficient) => {
          guard s.decimal_sum_scale is Some(scale) else {
            return Err(InvalidRows)
          }
          match @admitted.decimal_from_coefficient(coefficient, 38, scale) {
            Some(value) => Captured(value)
            None => return Err(Aggregation(ArithmeticFailure))
          }
        }
      }
    _ => s.selected[index].unwrap_or(s.fill)
  }
  s.row.push(value)
  s.index += 1
  Ok(None)
}

///|
/// One selected numeric reduction for one bucket: start it under the
/// remaining budget, advance the Host-owned step, then pay its reported work
/// one unit per advance.
fn[T] pivot_advance_numeric(
  s : PivotEvaluation[T],
  index : Int,
) -> Result[Value?, RowIssue] {
  guard s.numeric is Some(execution) else { return Err(InvalidRows) }
  if s.outcome is Some(outcome) {
    return match pay_pending_unit(s.pending, s.control) {
      Err(issue) => Err(issue)
      Ok(false) => Ok(None)
      Ok(true) => {
        s.outcome = None
        Ok(
          Some(
            match @numeric.outcome_value(outcome) {
              None => s.fill
              Some(value) => Number(value)
            },
          ),
        )
      }
    }
  }
  let finish = fn(outcome : @numeric.Outcome) {
    s.outcome = Some(outcome)
    s.pending.remaining = @numeric.outcome_work(outcome)
  }
  match s.reduction {
    Some(reduction) =>
      match (reduction.advance)() {
        None => Err(InvalidRows)
        Some(Err(issue)) => Err(numeric_reduction_row_issue(issue))
        Some(Ok(None)) => Ok(None)
        Some(Ok(Some(outcome))) => {
          s.reduction = None
          finish(outcome)
          Ok(None)
        }
      }
    None => {
      let values = s.numeric_values[index]
      let name = @lower.pivot_axis_at(s.pivot, index).unwrap()
      match execution.start {
        Some(start) =>
          match
            start(
              s.step,
              name,
              s.emitted,
              values,
              values.length(),
              s.control.remaining,
            ) {
            None => Err(InvalidRows)
            Some(Err(issue)) => Err(numeric_reduction_row_issue(issue))
            Some(Ok(reduction)) => {
              s.reduction = Some(reduction)
              Ok(None)
            }
          }
        None =>
          match
            (execution.reduce)(
              s.step,
              name,
              s.emitted,
              values,
              values.length(),
              s.control.remaining,
            ) {
            None => Err(InvalidRows)
            Some(Err(issue)) => Err(numeric_reduction_row_issue(issue))
            Some(Ok(outcome)) => {
              finish(outcome)
              Ok(None)
            }
          }
      }
    }
  }
}
