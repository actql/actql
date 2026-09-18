///|
priv struct AnalyticPartitionRange {
  start : Int
  end : Int
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
    Err(issue) => Err(Evaluation(row, call, issue))
  }
  release_slots(workspace, workspace.live - baseline)
  result
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
  accept_row : (Array[Value], Int, Array[String], Array[Int]?) -> Result[
    Unit,
    RowIssue,
  ],
) -> Result[Array[String], RowIssue] {
  if !analytic_execution_supported(analytic) {
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
    Err(InvalidInput) => return Err(InvalidRows)
    Err(Limit) => return Err(RowLimit)
    Err(Scalar(issue)) => return Err(Comparison(issue))
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
        Err(InvalidInput) => return Err(InvalidRows)
        Err(Limit) => return Err(RowLimit)
        Err(Scalar(issue)) => return Err(Comparison(issue))
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
  let aggregate_arguments : Array[Int?] = Array::make(call_count, None)
  if !reserve_slots(workspace, call_count) {
    return Err(RowLimit)
  }
  for call_index in 0..<call_count {
    guard @lower.analytic_call_function(
        @lower.analytic_call_at(analytic, call_index).unwrap(),
      )
      is PreparedFrameAggregate(aggregate) else {
      continue
    }
    aggregate_arguments[call_index] = match
      @lower.group_aggregate_argument(aggregate) {
      @lower.AggregateRows => None
      @lower.AggregateField(field) =>
        match resolve(field) {
          Ok(column) => Some(column)
          Err(issue) => return Err(issue)
        }
      @lower.AggregateExpression(_) => return Err(InvalidRows)
    }
  }
  let position_by_row = Array::make(count, -1)
  let partition_start = Array::make(count, -1)
  let partition_by_row = Array::make(count, -1)
  let ranks = Array::make(count, 0)
  let dense_ranks = Array::make(count, 0)
  let references : Array[Array[Int]] = Array::makei(call_count, _ => {
    Array::make(count, -1)
  })
  for _ in 0..<5 {
    if !reserve_slots(workspace, count) {
      return Err(RowLimit)
    }
  }
  for _ in 0..<call_count {
    if !reserve_slots(workspace, count) {
      return Err(RowLimit)
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
          Err(InvalidInput) => return Err(InvalidRows)
          Err(Limit) => return Err(RowLimit)
          Err(Scalar(issue)) => return Err(Comparison(issue))
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
  let evaluated : Array[Array[Value?]] = Array::makei(call_count, _ => {
    Array::make(count, None)
  })
  let demanded : Array[Array[Bool]] = Array::makei(call_count, _ => {
    Array::make(count, false)
  })
  for _ in 0..<call_count {
    if !reserve_slots(workspace, count) || !reserve_slots(workspace, count) {
      return Err(RowLimit)
    }
  }
  for call_index in 0..<call_count {
    for source in 0..<count {
      let reference = references[call_index][source]
      if reference >= 0 {
        demanded[call_index][reference] = true
      }
    }
  }
  let failure_sources : Array[Array[Int]] = Array::makei(ranges.length(), _ => {
    []
  })
  if !reserve_slots(workspace, ranges.length()) {
    return Err(RowLimit)
  }
  for source in 0..<count {
    let range_index = partition_by_row[source]
    if range_index < 0 ||
      !spend_control(control, 1) ||
      !reserve_slots(workspace, 1) {
      return Err(RowLimit)
    }
    failure_sources[range_index].push(source)
  }
  let call_order = Array::makei(call_count, i => i)
  if !reserve_slots(workspace, call_count) {
    return Err(RowLimit)
  }
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
          guard @lower.analytic_frame(analytic) is Some(frame) else {
            return Err(InvalidRows)
          }
          let position = position_by_row[source] - ranges[range_index].start
          let length = ranges[range_index].end - ranges[range_index].start
          let (first, end) = match
            analytic_frame_range(frame, position, length) {
            Some((first, end)) =>
              (
                ranges[range_index].start + first,
                ranges[range_index].start + end,
              )
            None => (ranges[range_index].start, ranges[range_index].start)
          }
          let baseline = workspace.live
          let value = match
            evaluate_direct_aggregate(
              aggregate,
              input,
              sorted,
              { representative: Some(source), start: first, end, },
              aggregate_arguments[call_index],
              complete,
              control,
              workspace,
              aggregate_outputs,
              identity_limits,
            ) {
            Ok(value) => value
            Err(issue) => return Err(issue)
          }
          release_slots(workspace, workspace.live - baseline)
          evaluated[call_index][source] = Some(value)
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
          evaluated[call_index][source] = Some(value)
        }
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
                evaluated[index][reference].unwrap()
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
  Ok(output_names)
}
