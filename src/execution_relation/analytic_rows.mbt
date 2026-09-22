///|
priv struct AnalyticPartitionRange {
  start : Int
  end : Int
}

///|
priv enum AnalyticCountIndex {
  CountRows
  CountPrefix(Array[Int])
}

///|
fn[T : IndexedRows] measure_analytic_row_array(
  rows : T,
  names : Array[String],
  indices : Array[Int],
  start : Int,
  end : Int,
  ceiling : Int64,
  scope : AnalyticEnvelopeScope,
  control : ControlBudget,
) -> Result[Unit, RowIssue] {
  if ceiling < 0L || start < 0 || end < start || end > indices.length() {
    return Err(AnalyticEnvelope(Measurement))
  }
  let cap = Int64::min(ceiling, 2147483647L).to_int()
  let result = try {
    let writer = @encode.measuring_writer(cap, 2147483647, 2147483647)
    @encode.begin_array(writer)
    for position in start..<end {
      let row = indices[position]
      if row < 0 ||
        row >= rows.row_count() ||
        rows.row_width(row) != names.length() ||
        !spend_control(control, 1) {
        return Err(AnalyticEnvelope(Measurement))
      }
      @encode.begin_object(writer)
      for column in 0..<names.length() {
        if !spend_control(control, 1) {
          return Err(AnalyticEnvelope(Measurement))
        }
        @encode.key(writer, names[column])
        emit_runtime_value(rows.read_cell(row, column), writer)
      }
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    @encode.finish_measurement(writer) |> ignore
    Ok(())
  } catch {
    _ => Err(AnalyticEnvelope(scope))
  }
  result
}

///|
fn emit_analytic_output_row(
  writer : @encode.Writer,
  names : Array[String],
  row : Array[Value],
  control : ControlBudget,
) -> Result[Unit, RowIssue] {
  if names.length() != row.length() || !spend_control(control, 1) {
    return Err(AnalyticEnvelope(Measurement))
  }
  try {
    @encode.begin_object(writer)
    for column in 0..<names.length() {
      if !spend_control(control, 1) {
        return Err(AnalyticEnvelope(Measurement))
      }
      @encode.key(writer, names[column])
      emit_runtime_value(row[column], writer)
    }
    @encode.end_object(writer)
    Ok(())
  } catch {
    _ => Err(AnalyticEnvelope(OutputWireBytes))
  }
}

///|
pub fn analytic_execution_supported(analytic : @lower.PreparedAnalytic) -> Bool {
  analytic_execution_supported_with_profile(analytic, false)
}

///|
/// Numeric capability changes only frame aggregates with checked observation
/// slots. Ranking, navigation, ordering, and every other aggregate retain the
/// same closed support predicate.
pub fn analytic_execution_supported_with_numeric(
  analytic : @lower.PreparedAnalytic,
) -> Bool {
  analytic_execution_supported_with_profile(analytic, true)
}

///|
fn analytic_execution_supported_with_profile(
  analytic : @lower.PreparedAnalytic,
  numeric : Bool,
) -> Bool {
  let schema = @lower.analytic_input_schema(analytic)
  for i in 0..<@lower.analytic_partition_count(analytic) {
    guard @schema.lookup(
        schema,
        @lower.analytic_partition_at(analytic, i).unwrap(),
      )
      is Some(contract) else {
      return false
    }
    if !supported_comparison(contract, contract) {
      return false
    }
  }
  for i in 0..<@lower.analytic_position_term_count(analytic) {
    let (field, _, _) = @lower.analytic_position_term_at(analytic, i).unwrap()
    guard @schema.lookup(schema, field) is Some(contract) else { return false }
    if !supported_comparison(contract, contract) {
      return false
    }
  }
  for i in 0..<@lower.analytic_call_count(analytic) {
    let call = @lower.analytic_call_at(analytic, i).unwrap()
    match @lower.analytic_call_function(call) {
      PreparedRowNumber
      | PreparedRank
      | PreparedDenseRank
      | PreparedLag(_, _)
      | PreparedLead(_, _)
      | PreparedFirstValue(_)
      | PreparedLastValue(_) => ()
      PreparedFrameAggregate(aggregate) =>
        if @lower.analytic_frame(analytic) is None ||
          !direct_aggregate_execution_supported(
            aggregate,
            @lower.analytic_position_term_count(analytic) > 0,
            numeric~,
          ) {
          return false
        }
    }
  }
  true
}

///|
fn analytic_frame_range(
  frame : @lower.PreparedRowsFrame,
  position : Int,
  length : Int,
) -> (Int, Int)? {
  if position < 0 || position >= length || length <= 0 {
    return None
  }
  let current = Int64::from_int(position)
  let last = Int64::from_int(length - 1)
  let boundary = fn(value : @lower.PreparedFrameBoundary) -> Int64 {
    match value {
      PreparedUnboundedPreceding => 0L
      PreparedPreceding(distance) => current - distance
      PreparedCurrentRow => current
      PreparedFollowing(distance) => current + distance
      PreparedUnboundedFollowing => last
    }
  }
  let start = boundary(@lower.prepared_frame_start(frame))
  let end = boundary(@lower.prepared_frame_end(frame))
  // Intersect the logical interval with the partition. A start beyond the
  // partition or an end before it produces an empty frame; neither is clamped
  // onto an existing row.
  if start > last || end < 0L || start > end {
    return None
  }
  let first = if start < 0L { 0L } else { start }
  let last_member = if end > last { last } else { end }
  Some((first.to_int(), last_member.to_int() + 1))
}

///|
fn prepare_analytic_aggregate_demand(
  sorted : Array[Int],
  ranges : Array[AnalyticPartitionRange],
  frame : @lower.PreparedRowsFrame,
  control : ControlBudget,
  workspace : RowWorkspace,
) -> Result[(Array[Bool], Int), RowIssue] {
  let count = sorted.length()
  if count == 2147483647 ||
    !reserve_slots(workspace, count) ||
    !reserve_slots(workspace, count) ||
    !reserve_slots(workspace, 1) {
    return Err(RowLimit)
  }
  let difference = Array::make(count + 1, 0)
  let demanded = Array::make(count, false)
  let mut visits = 0
  for range in ranges {
    if range.start < 0 || range.end < range.start || range.end > count {
      return Err(InvalidRows)
    }
    let length = range.end - range.start
    for relative in 0..<length {
      if !spend_control(control, 1) {
        return Err(RowLimit)
      }
      visits += 1
      match analytic_frame_range(frame, relative, length) {
        None => ()
        Some((first, end)) => {
          difference[range.start + first] += 1
          difference[range.start + end] -= 1
        }
      }
    }
  }
  let mut active = 0
  for position in 0..<count {
    if !spend_control(control, 1) {
      return Err(RowLimit)
    }
    visits += 1
    active += difference[position]
    let source = sorted[position]
    if source < 0 || source >= count || active < 0 {
      return Err(InvalidRows)
    }
    demanded[source] = active > 0
  }
  if active + difference[count] != 0 {
    return Err(InvalidRows)
  }
  Ok((demanded, visits))
}

///|
fn[T : IndexedRows] analytic_expression_value(
  expression : @lower.Expression,
  input : T,
  names : Array[String],
  row : Int,
  call : Int,
  control : ControlBudget,
  workspace : RowWorkspace,
  scope : ExpressionRoots?,
) -> Result[Value, RowIssue] {
  let baseline = workspace.live
  let snapshot : Map[String, Value] = Map([])
  for column in 0..<names.length() {
    if !spend_control(control, 1) ||
      !spend_control_text(control, names[column]) ||
      !reserve_slots(workspace, 1) {
      release_slots(workspace, workspace.live - baseline)
      return Err(RowLimit)
    }
    snapshot[names[column]] = IndexedRows::read_cell(input, row, column)
  }
  if scope is Some(value) {
    match charge_logical_work(value.budget, 1L) {
      Ok(_) => ()
      Err(issue) => {
        release_slots(workspace, workspace.live - baseline)
        return Err(LogicalRows(issue))
      }
    }
  }
  let result = match
    evaluate_expression_with_workspace(
      expression,
      snapshot,
      [],
      control,
      workspace,
      logical_work=scope.map(value => value.budget),
    ) {
    Ok(value) => Ok(value)
    Err(issue) => Err(evaluation_row_issue(row, call, issue))
  }
  release_slots(workspace, workspace.live - baseline)
  result
}

///|
/// Fold one frame from call-local source values that were evaluated once in
/// canonical failure order. Frame membership still controls aggregation and
/// numeric observation occurrences; it no longer replays filter or argument
/// expressions.
fn evaluate_precomputed_analytic_aggregate(
  aggregate : @lower.PreparedAggregate,
  sorted : Array[Int],
  range : AggregateGroupRange,
  arguments : Array[Value?],
  included : Array[Bool],
  control : ControlBudget,
  workspace : RowWorkspace,
  selected : Array[SelectedAggregateOutput],
  identity_limits : ValueLimits,
  numeric : NumericAggregateExecution?,
  numeric_step : Int,
  numeric_occurrence : Int,
) -> Result[Value, RowIssue] {
  if range.start < 0 || range.end < range.start || range.end > sorted.length() {
    return Err(InvalidRows)
  }
  if !reserve_slots(workspace, range.end - range.start) {
    return Err(RowLimit)
  }
  let values : Array[Value] = []
  for position in range.start..<range.end {
    if !spend_control(control, 1) {
      return Err(RowLimit)
    }
    let source = sorted[position]
    if source < 0 || source >= included.length() {
      return Err(InvalidRows)
    }
    if included[source] {
      guard arguments[source] is Some(value) else { return Err(InvalidRows) }
      values.push(value)
    }
  }
  if !reserve_slots(workspace, values.length()) ||
    !spend_control(control, values.length()) {
    return Err(RowLimit)
  }
  let rows : DynamicAggregateRows = { values, }
  let indices = Array::makei(values.length(), i => i)
  let ordered = match @lower.group_aggregate_function(aggregate) {
    @relation.First
    | @relation.Last
    | @relation.ArrayAgg
    | @relation.StringAgg => true
    _ => false
  }
  if ordered && !reserve_slots(workspace, 1) {
    return Err(RowLimit)
  }
  evaluate_direct_aggregate(
    aggregate,
    rows,
    indices,
    {
      representative: if indices.is_empty() {
        None
      } else {
        Some(0)
      },
      start: 0,
      end: indices.length(),
    },
    if @lower.group_aggregate_argument(aggregate) is @lower.AggregateRows {
      None
    } else {
      Some(0)
    },
    if ordered {
      [{ column: 1, descending: false, nulls_first: true, }]
    } else {
      []
    },
    control,
    workspace,
    selected,
    identity_limits,
    numeric~,
    numeric_step~,
    numeric_occurrence~,
  )
}

///|
fn[T : RelationRows] evaluate_analytic_into(
  analytic : @lower.PreparedAnalytic,
  input : T,
  max_rows : Int,
  control : ControlBudget,
  output : ValueBudget,
  workspace : RowWorkspace,
  scope : ExpressionRoots?,
  aggregate_outputs : Array[SelectedAggregateOutput],
  envelope : SelectedAnalyticEnvelope?,
  identity_limits : ValueLimits,
  numeric : NumericAggregateExecution?,
  step~ : Int,
  accept_row : (Array[Value], Int, Array[String], Array[Int]?) -> Result[
    Unit,
    RowIssue,
  ],
) -> Result[Array[String], RowIssue] {
  if !analytic_execution_supported_with_profile(analytic, numeric is Some(_)) {
    return Err(InvalidRows)
  }
  let names = input.field_names()
  let count = IndexedRows::row_count(input)
  if count > max_rows {
    return Err(RowLimit)
  }
  if envelope is Some(value) && Int64::from_int(count) > value.output_rows {
    return Err(AnalyticEnvelope(OutputRows))
  }
  if envelope is Some(value) {
    if !reserve_slots(workspace, count) {
      return Err(RowLimit)
    }
    let input_order = Array::makei(count, i => i)
    match
      measure_analytic_row_array(
        input,
        names,
        input_order,
        0,
        count,
        value.input_wire_bytes,
        InputWireBytes,
        control,
      ) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    release_slots(workspace, count)
  }
  let ordinals : Map[String, Int] = Map([])
  for column in 0..<names.length() {
    if !spend_control(control, 1) ||
      !spend_control_text(control, names[column]) ||
      !reserve_slots(workspace, 1) {
      return Err(RowLimit)
    }
    if ordinals.contains(names[column]) {
      return Err(InvalidRows)
    }
    ordinals[names[column]] = column
  }
  let input_roots : Array[ExpressionRootLease] = []
  if scope is Some(value) {
    match admit_logical_rows(value.budget, count.to_int64()) {
      Ok(_) => ()
      Err(issue) => return Err(LogicalRows(issue))
    }
    for row in 0..<count {
      let source = IndexedRow::{ table: input, row, }
      if RowValues::value_count(source) != names.length() {
        return Err(InvalidRows)
      }
      if !reserve_slots(workspace, 1) {
        return Err(RowLimit)
      }
      let root = match retain_logical_row(value.budget, names, source) {
        Ok(root) => root
        Err(issue) => return Err(LogicalRows(issue))
      }
      let lease = match register_scope_root(value, root) {
        Ok(lease) => lease
        Err(issue) => return Err(LogicalRows(issue))
      }
      input_roots.push(lease)
      match charge_logical_work(value.budget, 1L) {
        Ok(_) => ()
        Err(issue) => return Err(LogicalRows(issue))
      }
    }
  }
  let resolve = fn(field : @schema.FieldName) -> Result[Int, RowIssue] {
    let name = @schema.reference_name(field)
    if !spend_control_text(control, name) {
      return Err(RowLimit)
    }
    match ordinals.get(name) {
      Some(column) => Ok(column)
      None => Err(InvalidRows)
    }
  }
  let partitions : Array[ColumnOrder] = []
  let peer_order : Array[ColumnOrder] = []
  let complete : Array[ColumnOrder] = []
  for i in 0..<@lower.analytic_partition_count(analytic) {
    let column = match
      resolve(@lower.analytic_partition_at(analytic, i).unwrap()) {
      Ok(column) => column
      Err(issue) => return Err(issue)
    }
    let term = { column, descending: false, nulls_first: true, }
    partitions.push(term)
    complete.push(term)
  }
  for i in 0..<@lower.analytic_peer_term_count(analytic) {
    let (field, descending, nulls_first) = @lower.analytic_peer_term_at(
      analytic, i,
    ).unwrap()
    let column = match resolve(field) {
      Ok(column) => column
      Err(issue) => return Err(issue)
    }
    peer_order.push({ column, descending, nulls_first, })
  }
  for i in 0..<@lower.analytic_position_term_count(analytic) {
    let (field, descending, nulls_first) = @lower.analytic_position_term_at(
      analytic, i,
    ).unwrap()
    let column = match resolve(field) {
      Ok(column) => column
      Err(issue) => return Err(issue)
    }
    complete.push({ column, descending, nulls_first, })
  }
  let sorted = match stable_order_indices(input, complete, control, workspace) {
    Ok(indices) => indices
    Err(issue) => return Err(ordering_row_issue(issue))
  }
  let ranges : Array[AnalyticPartitionRange] = []
  let mut start = 0
  for position in 0..<=sorted.length() {
    let boundary = if position == sorted.length() {
      true
    } else if position == 0 {
      false
    } else {
      match
        compare_row_indices(
          input,
          sorted[position - 1],
          sorted[position],
          partitions,
          control,
        ) {
        Ok(value) => value != 0
        Err(issue) => return Err(ordering_row_issue(issue))
      }
    }
    if boundary {
      if !reserve_slots(workspace, 1) {
        return Err(RowLimit)
      }
      ranges.push({ start, end: position, })
      start = position
    }
  }
  if envelope is Some(value) {
    for range in ranges {
      match
        measure_analytic_row_array(
          input,
          names,
          sorted,
          range.start,
          range.end,
          value.partition_wire_bytes,
          PartitionWireBytes,
          control,
        ) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
    }
  }
  let call_count = @lower.analytic_call_count(analytic)
  if !reserve_slots(workspace, call_count) {
    return Err(RowLimit)
  }
  let aggregate_arguments : Array[AggregateInput?] = Array::make(
    call_count,
    None,
  )
  for call_index in 0..<call_count {
    guard @lower.analytic_call_function(
        @lower.analytic_call_at(analytic, call_index).unwrap(),
      )
      is PreparedFrameAggregate(aggregate) else {
      continue
    }
    aggregate_arguments[call_index] = Some(
      match @lower.group_aggregate_argument(aggregate) {
        @lower.AggregateRows => AggregateInputRows
        @lower.AggregateField(field) =>
          match resolve(field) {
            Ok(column) => AggregateInputField(column)
            Err(issue) => return Err(issue)
          }
        @lower.AggregateExpression(expression) =>
          AggregateInputExpression(expression)
      },
    )
  }
  if !reserve_slots(workspace, call_count) {
    return Err(RowLimit)
  }
  let count_indices : Array[AnalyticCountIndex?] = Array::make(call_count, None)
  for call_index in 0..<call_count {
    guard @lower.analytic_call_function(
        @lower.analytic_call_at(analytic, call_index).unwrap(),
      )
      is PreparedFrameAggregate(aggregate) else {
      continue
    }
    if @lower.group_aggregate_distinct(aggregate) == Some(true) ||
      @lower.group_aggregate_filter(aggregate) is Some(_) {
      continue
    }
    let function = @lower.group_aggregate_function(aggregate)
    if function is @relation.Count &&
      aggregate_arguments[call_index] is Some(AggregateInputRows) {
      count_indices[call_index] = Some(CountRows)
      continue
    }
    if !(function is @relation.Count || function is @relation.CountIf) {
      continue
    }
    guard aggregate_arguments[call_index] is Some(AggregateInputField(column)) else {
      continue
    }
    if !reserve_slots(workspace, count + 1) {
      return Err(RowLimit)
    }
    let prefix = Array::make(count + 1, 0)
    for range in ranges {
      for position in range.start..<range.end {
        if !spend_control(control, 1) {
          return Err(RowLimit)
        }
        let value = IndexedRows::read_cell(input, sorted[position], column)
        let increment = if function is @relation.Count {
          if value is Null {
            0
          } else {
            1
          }
        } else {
          match value {
            Boolean(true) => 1
            Boolean(false) | Null => 0
            _ => return Err(InvalidRows)
          }
        }
        prefix[position + 1] = prefix[position] + increment
      }
    }
    count_indices[call_index] = Some(CountPrefix(prefix))
  }
  for _ in 0..<5 {
    if !reserve_slots(workspace, count) {
      return Err(RowLimit)
    }
  }
  if !reserve_matrix_slots(workspace, call_count, count) {
    return Err(RowLimit)
  }
  let position_by_row = Array::make(count, -1)
  let partition_start = Array::make(count, -1)
  let partition_by_row = Array::make(count, -1)
  let ranks = Array::make(count, 0)
  let dense_ranks = Array::make(count, 0)
  let references : Array[Array[Int]] = Array::makei(call_count, _ => {
    Array::make(count, -1)
  })
  if !reserve_matrix_slots(workspace, call_count, count) {
    return Err(RowLimit)
  }
  let demanded : Array[Array[Bool]] = Array::makei(call_count, _ => {
    Array::make(count, false)
  })
  let mut needs_aggregate_demand = false
  for call_index in 0..<call_count {
    if @lower.analytic_call_function(
        @lower.analytic_call_at(analytic, call_index).unwrap(),
      )
      is PreparedFrameAggregate(_) &&
      count_indices[call_index] is None {
      needs_aggregate_demand = true
    }
  }
  let mut frame_memberships = 0L
  for range_index in 0..<ranges.length() {
    let range = ranges[range_index]
    let mut peer_start = range.start
    let mut dense = 1
    for position in range.start..<range.end {
      if !spend_control(control, 1) {
        return Err(RowLimit)
      }
      if position > range.start {
        let same_peer = match
          compare_row_indices(
            input,
            sorted[position - 1],
            sorted[position],
            peer_order,
            control,
          ) {
          Ok(value) => value == 0
          Err(issue) => return Err(ordering_row_issue(issue))
        }
        if !same_peer {
          peer_start = position
          dense += 1
        }
      }
      let source = sorted[position]
      position_by_row[source] = position
      partition_start[source] = range.start
      partition_by_row[source] = range_index
      ranks[source] = peer_start - range.start + 1
      dense_ranks[source] = dense
      let relative = position - range.start
      let length = range.end - range.start
      for call_index in 0..<call_count {
        let call = @lower.analytic_call_at(analytic, call_index).unwrap()
        let reference = match @lower.analytic_call_function(call) {
          PreparedLag(_, offset) =>
            if offset <= Int64::from_int(relative) {
              sorted[position - offset.to_int()]
            } else {
              -1
            }
          PreparedLead(_, offset) => {
            let remaining = length - relative - 1
            if offset <= Int64::from_int(remaining) {
              sorted[position + offset.to_int()]
            } else {
              -1
            }
          }
          PreparedFirstValue(_) | PreparedLastValue(_) => {
            guard @lower.analytic_frame(analytic) is Some(frame) else {
              return Err(InvalidRows)
            }
            match analytic_frame_range(frame, relative, length) {
              None => -1
              Some((first, end)) => {
                let selected = if @lower.analytic_call_function(call)
                  is PreparedFirstValue(_) {
                  first
                } else {
                  end - 1
                }
                sorted[range.start + selected]
              }
            }
          }
          PreparedRowNumber | PreparedRank | PreparedDenseRank => -1
          PreparedFrameAggregate(_) => -1
        }
        references[call_index][source] = reference
        if envelope is Some(value) {
          let memberships = match @lower.analytic_call_function(call) {
            PreparedLag(_, _)
            | PreparedLead(_, _)
            | PreparedFirstValue(_)
            | PreparedLastValue(_) => if reference >= 0 { 1L } else { 0L }
            PreparedFrameAggregate(_) => {
              guard @lower.analytic_frame(analytic) is Some(frame) else {
                return Err(InvalidRows)
              }
              match analytic_frame_range(frame, relative, length) {
                None => 0L
                Some((first, end)) => Int64::from_int(end - first)
              }
            }
            PreparedRowNumber | PreparedRank | PreparedDenseRank => 0L
          }
          if memberships > value.frame_memberships - frame_memberships {
            return Err(AnalyticEnvelope(FrameMemberships))
          }
          frame_memberships += memberships
        }
      }
    }
  }
  let aggregate_demand = if needs_aggregate_demand {
    guard @lower.analytic_frame(analytic) is Some(frame) else {
      return Err(InvalidRows)
    }
    match
      prepare_analytic_aggregate_demand(
        sorted, ranges, frame, control, workspace,
      ) {
      Ok((demand, _)) => Some(demand)
      Err(issue) => return Err(issue)
    }
  } else {
    None
  }
  if !reserve_matrix_slots(workspace, call_count, count) ||
    !reserve_matrix_slots(workspace, call_count, count) ||
    !reserve_matrix_slots(workspace, call_count, count) {
    return Err(RowLimit)
  }
  let evaluated : Array[Array[Value?]] = Array::makei(call_count, _ => {
    Array::make(count, None)
  })
  let arguments : Array[Array[Value?]] = Array::makei(call_count, _ => {
    Array::make(count, None)
  })
  let included : Array[Array[Bool]] = Array::makei(call_count, _ => {
    Array::make(count, false)
  })
  for call_index in 0..<call_count {
    for source in 0..<count {
      let reference = references[call_index][source]
      if reference >= 0 {
        demanded[call_index][reference] = true
      }
    }
  }
  if !reserve_slots(workspace, ranges.length()) {
    return Err(RowLimit)
  }
  let failure_sources : Array[Array[Int]] = Array::makei(ranges.length(), _ => {
    []
  })
  for source in 0..<count {
    let range_index = partition_by_row[source]
    if range_index < 0 ||
      !spend_control(control, 1) ||
      !reserve_slots(workspace, 1) {
      return Err(RowLimit)
    }
    failure_sources[range_index].push(source)
  }
  if !reserve_slots(workspace, call_count) {
    return Err(RowLimit)
  }
  let call_order = Array::makei(call_count, i => i)
  for i in 1..<call_order.length() {
    let mut cursor = i
    while cursor > 0 {
      if !spend_control(control, 1) {
        return Err(RowLimit)
      }
      let left = call_order[cursor - 1]
      let right = call_order[cursor]
      let comparison = @canonical.compare_utf16(
        @lower.analytic_call_name(
          @lower.analytic_call_at(analytic, left).unwrap(),
        ),
        @lower.analytic_call_name(
          @lower.analytic_call_at(analytic, right).unwrap(),
        ),
      )
      if comparison <= 0 {
        break
      }
      call_order[cursor - 1] = right
      call_order[cursor] = left
      cursor -= 1
    }
  }
  for range_index in 0..<ranges.length() {
    for source in failure_sources[range_index] {
      for call_index in call_order {
        let call = @lower.analytic_call_at(analytic, call_index).unwrap()
        if @lower.analytic_call_function(call)
          is PreparedFrameAggregate(aggregate) {
          if count_indices[call_index] is Some(_) {
            continue
          }
          guard aggregate_demand is Some(demand) && demand[source] else {
            continue
          }
          if @lower.group_aggregate_filter(aggregate) is Some(filter) {
            let accepted = match
              analytic_expression_value(
                filter, input, names, source, call_index, control, workspace, scope,
              ) {
              Ok(Boolean(true)) => true
              Ok(Boolean(false) | Null) => false
              Ok(_) => return Err(InvalidRows)
              Err(issue) => return Err(issue)
            }
            if !accepted {
              continue
            }
          }
          guard aggregate_arguments[call_index] is Some(argument) else {
            return Err(InvalidRows)
          }
          let value = match argument {
            AggregateInputRows => Null
            AggregateInputField(column) =>
              IndexedRows::read_cell(input, source, column)
            AggregateInputExpression(expression) =>
              match
                analytic_expression_value(
                  expression, input, names, source, call_index, control, workspace,
                  scope,
                ) {
                Ok(value) => value
                Err(issue) => return Err(issue)
              }
          }
          included[call_index][source] = true
          arguments[call_index][source] = Some(value)
          continue
        }
        if demanded[call_index][source] {
          let expression = match @lower.analytic_call_function(call) {
            PreparedLag(expression, _)
            | PreparedLead(expression, _)
            | PreparedFirstValue(expression)
            | PreparedLastValue(expression) => expression
            _ => continue
          }
          let value = match
            analytic_expression_value(
              expression, input, names, source, call_index, control, workspace, scope,
            ) {
            Ok(value) => value
            Err(issue) => return Err(issue)
          }
          arguments[call_index][source] = Some(value)
        }
      }
    }
  }
  for range_index in 0..<ranges.length() {
    for source in failure_sources[range_index] {
      for call_index in call_order {
        let call = @lower.analytic_call_at(analytic, call_index).unwrap()
        guard @lower.analytic_call_function(call)
          is PreparedFrameAggregate(aggregate) else {
          continue
        }
        guard @lower.analytic_frame(analytic) is Some(frame) else {
          return Err(InvalidRows)
        }
        let position = position_by_row[source] - ranges[range_index].start
        let length = ranges[range_index].end - ranges[range_index].start
        let (first, end) = match analytic_frame_range(frame, position, length) {
          Some((first, end)) =>
            (ranges[range_index].start + first, ranges[range_index].start + end)
          None => (ranges[range_index].start, ranges[range_index].start)
        }
        let value = match count_indices[call_index] {
          Some(CountRows) => Number((end - first).to_double())
          Some(CountPrefix(prefix)) =>
            Number((prefix[end] - prefix[first]).to_double())
          None => {
            let baseline = workspace.live
            let computed = evaluate_precomputed_analytic_aggregate(
              aggregate,
              sorted,
              { representative: Some(source), start: first, end, },
              arguments[call_index],
              included[call_index],
              control,
              workspace,
              aggregate_outputs,
              identity_limits,
              numeric,
              step,
              source,
            )
            let value = match computed {
              Ok(value) => value
              Err(issue) => return Err(issue)
            }
            release_slots(workspace, workspace.live - baseline)
            value
          }
        }
        evaluated[call_index][source] = Some(value)
      }
    }
  }
  let call_by_name : Map[String, Int] = Map([])
  for i in 0..<call_count {
    let name = @lower.analytic_call_name(
      @lower.analytic_call_at(analytic, i).unwrap(),
    )
    if !spend_control_text(control, name) || !reserve_slots(workspace, 1) {
      return Err(RowLimit)
    }
    call_by_name[name] = i
  }
  let schema = @lower.analytic_output_schema(analytic)
  let output_names : Array[String] = []
  let output_columns : Array[(Bool, Int)] = []
  for i in 0..<@schema.field_count(schema) {
    let name = @schema.reference_name(@schema.field_at(schema, i).unwrap().name)
    if !spend_control_text(control, name) || !reserve_slots(workspace, 2) {
      return Err(RowLimit)
    }
    output_names.push(name)
    match ordinals.get(name) {
      Some(column) => output_columns.push((false, column))
      None =>
        match call_by_name.get(name) {
          Some(call) => output_columns.push((true, call))
          None => return Err(InvalidRows)
        }
    }
  }
  let output_writer = match envelope {
    None => None
    Some(value) => {
      let cap = Int64::min(value.output_wire_bytes, 2147483647L).to_int()
      let writer = @encode.measuring_writer(cap, 2147483647, 2147483647) catch {
        _ => return Err(AnalyticEnvelope(OutputWireBytes))
      }
      @encode.begin_array(writer) catch {
        _ => return Err(AnalyticEnvelope(OutputWireBytes))
      }
      Some(writer)
    }
  }
  for source in 0..<count {
    let row : Array[Value] = []
    if !spend_control(control, 1) ||
      !reserve_slots(workspace, output_columns.length()) {
      return Err(RowLimit)
    }
    for (generated, index) in output_columns {
      if !spend_control(control, 1) {
        return Err(RowLimit)
      }
      if !generated {
        row.push(IndexedRows::read_cell(input, source, index))
      } else {
        let call = @lower.analytic_call_at(analytic, index).unwrap()
        row.push(
          match @lower.analytic_call_function(call) {
            PreparedRowNumber =>
              Number(
                (position_by_row[source] - partition_start[source] + 1).to_double(),
              )
            PreparedRank => Number(ranks[source].to_double())
            PreparedDenseRank => Number(dense_ranks[source].to_double())
            PreparedLag(_, _)
            | PreparedLead(_, _)
            | PreparedFirstValue(_)
            | PreparedLastValue(_) => {
              let reference = references[index][source]
              if reference < 0 {
                Null
              } else {
                arguments[index][reference].unwrap()
              }
            }
            PreparedFrameAggregate(_) =>
              match evaluated[index][source] {
                Some(value) => value
                None => return Err(InvalidRows)
              }
          },
        )
      }
    }
    if output_writer is Some(writer) {
      match emit_analytic_output_row(writer, output_names, row, control) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
    }
    if !retain_row(row, output_names, output) {
      return Err(RowLimit)
    }
    if scope is Some(value) {
      match
        row_event_output(value, output_names, row, [], input_roots[source]) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
    }
    match accept_row(row, source, output_names, None) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  if output_writer is Some(writer) {
    try {
      @encode.end_array(writer)
      @encode.finish_measurement(writer) |> ignore
    } catch {
      _ => return Err(AnalyticEnvelope(OutputWireBytes))
    }
  }
  if numeric is Some(execution) {
    for call_index in 0..<call_count {
      let call = @lower.analytic_call_at(analytic, call_index).unwrap()
      guard @lower.analytic_call_function(call)
        is PreparedFrameAggregate(aggregate) else {
        continue
      }
      if @lower.group_aggregate_requires_numeric_observation(aggregate) &&
        !seal_numeric_aggregate(
          execution,
          step,
          @lower.analytic_call_name(call),
          count,
        ) {
        return Err(InvalidRows)
      }
    }
  }
  Ok(output_names)
}
