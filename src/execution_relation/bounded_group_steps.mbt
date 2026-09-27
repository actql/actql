///|
/// The whole `group` operation as one resumable state, in the order and with
/// the checks of `evaluate_group_into`. Name resolution pays one control
/// unit per advance, ordering and group boundaries use their resumable
/// owners, and each aggregate of each group advances through its own
/// evaluation state. Emitting one row is bounded by the output schema and
/// the per-value limits.
priv struct BoundedGroup[T] {
  group : @lower.PreparedGroup
  input : T
  max_rows : Int
  control : ControlBudget
  output : ValueBudget
  workspace : RowWorkspace
  scope : ExpressionRoots?
  accept_row : (Array[Value], Int, Array[String], Array[Int]?) -> Result[
    Unit,
    RowIssue,
  ]
  aggregate_outputs : Array[SelectedAggregateOutput]
  identity_limits : ValueLimits
  numeric : NumericAggregateExecution?
  step : Int
  names : Array[String]
  ordinals : Map[String, Int]
  order : Array[ColumnOrder]
  key_by_name : Map[String, Int]
  aggregate_by_name : Map[String, Int]
  arguments : Array[AggregateInput]
  aggregate_orders : Array[Array[ColumnOrder]]
  output_names : Array[String]
  projection : Array[(Bool, Int)]
  pending : PendingUnits
  mut phase : Int
  mut index : Int
  mut term : Int
  mut charging : Bool
  mut current_order : Array[ColumnOrder]
  mut indices : Array[Int]
  mut groups : Array[AggregateGroupRange]
  mut sorter : StableOrderExecution[T]?
  mut ranges : AggregateGroupRangeExecution[T]?
  mut group_index : Int
  mut aggregate_values : Array[Value]
  mut evaluation : AggregateEvaluation[T]?
  mut baseline : Int
  mut closed : Bool
}

///|
fn[T : RelationRows] start_bounded_group(
  group : @lower.PreparedGroup,
  input : T,
  max_rows : Int,
  control : ControlBudget,
  output : ValueBudget,
  workspace : RowWorkspace,
  scope : ExpressionRoots?,
  accept_row : (Array[Value], Int, Array[String], Array[Int]?) -> Result[
    Unit,
    RowIssue,
  ],
  aggregate_outputs : Array[SelectedAggregateOutput],
  identity_limits : ValueLimits,
  numeric : NumericAggregateExecution?,
  step~ : Int,
) -> BoundedGroup[T] {
  {
    group,
    input,
    max_rows,
    control,
    output,
    workspace,
    scope,
    accept_row,
    aggregate_outputs,
    identity_limits,
    numeric,
    step,
    names: input.field_names(),
    ordinals: Map([]),
    order: [],
    key_by_name: Map([]),
    aggregate_by_name: Map([]),
    arguments: [],
    aggregate_orders: [],
    output_names: [],
    projection: [],
    pending: { remaining: 0, },
    phase: 0,
    index: 0,
    term: 0,
    charging: false,
    current_order: [],
    indices: [],
    groups: [],
    sorter: None,
    ranges: None,
    group_index: 0,
    aggregate_values: [],
    evaluation: None,
    baseline: 0,
    closed: false,
  }
}

///|
fn[T] close_bounded_group(state : BoundedGroup[T]) -> Unit {
  if state.closed {
    return
  }
  if state.sorter is Some(value) {
    close_stable_order(value)
  }
  if state.ranges is Some(value) {
    close_aggregate_group_ranges(value)
  }
  if state.evaluation is Some(value) {
    close_aggregate_evaluation(value)
  }
  state.closed = true
}

///|
fn[T : RelationRows] advance_bounded_group(
  state : BoundedGroup[T],
) -> Result[Array[String]?, RowIssue] {
  if state.closed {
    return Err(InvalidRows)
  }
  let result = advance_bounded_group_impl(state)
  match result {
    Err(_) => close_bounded_group(state)
    Ok(Some(_)) => state.closed = true
    Ok(None) => ()
  }
  result
}

///|
/// Pay `1 + UTF-8(name)` units, one per advance. Returns true when paid.
fn[T] bounded_group_charge_name(
  s : BoundedGroup[T],
  name : String,
) -> Result[Bool, RowIssue] {
  if !s.charging {
    s.pending.remaining = match utf8_units(name) {
      Ok(bytes) => 1 + bytes
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
fn[T] bounded_group_column(
  s : BoundedGroup[T],
  field : @schema.FieldName,
) -> Result[Int, RowIssue] {
  match s.ordinals.get(@schema.reference_name(field)) {
    Some(index) => Ok(index)
    None => Err(InvalidRows)
  }
}

///|
fn[T : RelationRows] advance_bounded_group_impl(
  s : BoundedGroup[T],
) -> Result[Array[String]?, RowIssue] {
  let key_count = @lower.group_key_count(s.group)
  let aggregate_count = @lower.group_aggregate_count(s.group)
  match s.phase {
    // Supported profile.
    0 => {
      if !group_execution_supported_with_profile(s.group, s.numeric is Some(_)) {
        return Err(InvalidRows)
      }
      s.phase = 1
      Ok(None)
    }
    // Input field names: one unit and the name, then a slot.
    1 => {
      if s.index < s.names.length() {
        match bounded_group_charge_name(s, s.names[s.index]) {
          Err(issue) => return Err(issue)
          Ok(false) => return Ok(None)
          Ok(true) => ()
        }
        if !reserve_slots(s.workspace, 1) {
          return Err(RowLimit)
        }
        if s.ordinals.contains(s.names[s.index]) {
          return Err(InvalidRows)
        }
        s.ordinals[s.names[s.index]] = s.index
        s.index += 1
        return Ok(None)
      }
      if !reserve_slots(s.workspace, key_count) ||
        !reserve_slots(s.workspace, aggregate_count) ||
        !reserve_slots(s.workspace, aggregate_count) ||
        !reserve_slots(s.workspace, aggregate_count) {
        return Err(RowLimit)
      }
      s.index = 0
      s.phase = 2
      Ok(None)
    }
    // Group keys.
    2 => {
      if s.index < key_count {
        let field = @lower.group_key_at(s.group, s.index).unwrap()
        let name = @schema.reference_name(field)
        match bounded_group_charge_name(s, name) {
          Err(issue) => return Err(issue)
          Ok(false) => return Ok(None)
          Ok(true) => ()
        }
        let column = match bounded_group_column(s, field) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        s.order.push({ column, descending: false, nulls_first: true, })
        if !s.key_by_name.contains(name) {
          s.key_by_name[name] = column
        }
        s.index += 1
        return Ok(None)
      }
      s.index = 0
      s.phase = 3
      Ok(None)
    }
    // Aggregate name.
    3 => {
      if s.index >= aggregate_count {
        let width = @schema.field_count(@lower.group_output_schema(s.group))
        if !reserve_slots(s.workspace, width) ||
          !reserve_slots(s.workspace, width) {
          return Err(RowLimit)
        }
        s.index = 0
        s.phase = 6
        return Ok(None)
      }
      let aggregate = @lower.group_aggregate_at(s.group, s.index).unwrap()
      match
        bounded_group_charge_name(s, @lower.group_aggregate_name(aggregate)) {
        Err(issue) => return Err(issue)
        Ok(false) => return Ok(None)
        Ok(true) => ()
      }
      s.aggregate_by_name[@lower.group_aggregate_name(aggregate)] = s.index
      s.phase = 4
      Ok(None)
    }
    // Aggregate argument.
    4 => {
      let aggregate = @lower.group_aggregate_at(s.group, s.index).unwrap()
      match @lower.group_aggregate_argument(aggregate) {
        @lower.AggregateRows => s.arguments.push(AggregateInputRows)
        @lower.AggregateExpression(expression) =>
          s.arguments.push(AggregateInputExpression(expression))
        @lower.AggregateField(field) => {
          match bounded_group_charge_name(s, @schema.reference_name(field)) {
            Err(issue) => return Err(issue)
            Ok(false) => return Ok(None)
            Ok(true) => ()
          }
          match bounded_group_column(s, field) {
            Ok(column) => s.arguments.push(AggregateInputField(column))
            Err(issue) => return Err(issue)
          }
        }
      }
      if !reserve_slots(
          s.workspace,
          @lower.group_aggregate_order_count(aggregate),
        ) {
        return Err(RowLimit)
      }
      s.current_order = []
      s.term = 0
      s.phase = 5
      Ok(None)
    }
    // Aggregate-local order terms.
    5 => {
      let aggregate = @lower.group_aggregate_at(s.group, s.index).unwrap()
      if s.term < @lower.group_aggregate_order_count(aggregate) {
        let (field, descending, nulls_first) = @lower.group_aggregate_order_term_at(
          aggregate,
          s.term,
        ).unwrap()
        match bounded_group_charge_name(s, @schema.reference_name(field)) {
          Err(issue) => return Err(issue)
          Ok(false) => return Ok(None)
          Ok(true) => ()
        }
        match bounded_group_column(s, field) {
          Ok(column) =>
            s.current_order.push({ column, descending, nulls_first, })
          Err(issue) => return Err(issue)
        }
        s.term += 1
        return Ok(None)
      }
      s.aggregate_orders.push(s.current_order)
      s.index += 1
      s.phase = 3
      Ok(None)
    }
    // Output fields.
    6 => {
      let schema = @lower.group_output_schema(s.group)
      if s.index < @schema.field_count(schema) {
        let name = @schema.reference_name(
          @schema.field_at(schema, s.index).unwrap().name,
        )
        match bounded_group_charge_name(s, name) {
          Err(issue) => return Err(issue)
          Ok(false) => return Ok(None)
          Ok(true) => ()
        }
        s.output_names.push(name)
        match s.aggregate_by_name.get(name) {
          Some(index) => s.projection.push((true, index))
          None =>
            match s.key_by_name.get(name) {
              Some(column) => s.projection.push((false, column))
              None => return Err(InvalidRows)
            }
        }
        s.index += 1
        return Ok(None)
      }
      s.sorter = Some(
        start_stable_order(s.input, s.order, s.control, s.workspace),
      )
      s.phase = 7
      Ok(None)
    }
    // Stable key order.
    7 => {
      guard s.sorter is Some(sorter) else { return Err(InvalidRows) }
      match advance_stable_order(sorter) {
        Err(issue) => Err(ordering_row_issue(issue))
        Ok(None) => Ok(None)
        Ok(Some(indices)) => {
          s.sorter = None
          s.indices = indices
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
          s.phase = 8
          Ok(None)
        }
      }
    }
    // Group boundaries.
    8 => {
      guard s.ranges is Some(ranges) else { return Err(InvalidRows) }
      match advance_aggregate_group_ranges(ranges) {
        Err(issue) => Err(issue)
        Ok(None) => Ok(None)
        Ok(Some(groups)) => {
          s.ranges = None
          s.groups = groups
          s.group_index = 0
          s.phase = 9
          Ok(None)
        }
      }
    }
    // Start the next group.
    9 => {
      if s.group_index >= s.groups.length() {
        s.index = 0
        s.phase = 12
        return Ok(None)
      }
      let width = s.output_names.length()
      if !spend_control(s.control, 1) ||
        !reserve_slots(s.workspace, aggregate_count) ||
        !reserve_slots(s.workspace, 1) ||
        !reserve_slots(s.workspace, width) {
        return Err(RowLimit)
      }
      s.aggregate_values = []
      s.index = 0
      s.phase = 10
      Ok(None)
    }
    // The group's aggregates, one evaluation at a time.
    10 => {
      if s.index >= aggregate_count {
        s.phase = 11
        return Ok(None)
      }
      let evaluation = match s.evaluation {
        Some(value) => value
        None => {
          s.baseline = s.workspace.live
          let value = start_aggregate_evaluation(
            @lower.group_aggregate_at(s.group, s.index).unwrap(),
            s.input,
            s.names,
            s.indices,
            s.groups[s.group_index],
            s.arguments[s.index],
            s.aggregate_orders[s.index],
            s.index,
            s.control,
            s.workspace,
            s.aggregate_outputs,
            s.identity_limits,
            s.scope,
            s.numeric,
            s.step,
            s.group_index,
          )
          s.evaluation = Some(value)
          return Ok(None)
        }
      }
      match advance_aggregate_evaluation(evaluation) {
        Err(issue) => Err(issue)
        Ok(None) => Ok(None)
        Ok(Some(value)) => {
          s.evaluation = None
          release_slots(s.workspace, s.workspace.live - s.baseline)
          s.aggregate_values.push(value)
          s.index += 1
          Ok(None)
        }
      }
    }
    // Emit the group's row.
    11 => {
      let range = s.groups[s.group_index]
      let row : Array[Value] = []
      for pair in s.projection {
        let (aggregate, index) = pair
        if aggregate {
          row.push(s.aggregate_values[index])
        } else {
          guard range.representative is Some(source) else {
            return Err(InvalidRows)
          }
          row.push(IndexedRows::read_cell(s.input, source, index))
        }
      }
      if !retain_row(row, s.output_names, s.output) {
        return Err(RowLimit)
      }
      match
        (s.accept_row)(
          row,
          range.representative.unwrap_or(-1),
          s.output_names,
          None,
        ) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
      release_slots(s.workspace, aggregate_count)
      s.group_index += 1
      s.phase = 9
      Ok(None)
    }
    // Seal the selected numeric occurrence domains.
    _ => {
      if s.numeric is Some(execution) {
        for i in 0..<aggregate_count {
          let aggregate = @lower.group_aggregate_at(s.group, i).unwrap()
          if @lower.group_aggregate_requires_numeric_observation(aggregate) &&
            !seal_numeric_aggregate(
              execution,
              s.step,
              @lower.group_aggregate_name(aggregate),
              s.groups.length(),
            ) {
            return Err(InvalidRows)
          }
        }
      }
      Ok(Some(s.output_names))
    }
  }
}
