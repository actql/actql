///|
/// The whole `analytic` operation as one resumable state, in the order and
/// with the charges of the draining `evaluate_analytic_into`. Envelope
/// measurement writes one row entry or cell per advance; names and resolved
/// terms pay one unit per advance; the complete order and partition
/// boundaries use the resumable ordering and comparison owners; per-row
/// indexes, frame demand, argument and navigation expressions, frame
/// aggregates and output rows advance one row, one call, one expression step
/// or one aggregate step at a time. Emitting one row is bounded by the output
/// schema and the per-value limits.
priv struct AnalyticEvaluation[T] {
  analytic : @lower.PreparedAnalytic
  input : T
  names : Array[String]
  count : Int
  max_rows : Int
  control : ControlBudget
  output : ValueBudget
  workspace : RowWorkspace
  scope : ExpressionRoots?
  aggregate_outputs : Array[SelectedAggregateOutput]
  envelope : SelectedAnalyticEnvelope?
  identity_limits : ValueLimits
  numeric : NumericAggregateExecution?
  step : Int
  accept_row : (Array[Value], Int) -> Result[Unit, RowIssue]
  call_count : Int
  pending : PendingUnits
  mut charging : Bool
  mut phase : Int
  mut index : Int
  mut inner : Int
  // Resumable envelope measurement of one row array.
  mut writer : @encode.Writer?
  mut wire : SteppedRuntimeWire?
  mut measure_ordered : Bool
  mut measure_start : Int
  mut measure_end : Int
  mut measure_position : Int
  mut measure_column : Int
  mut measure_ceiling : Int64
  mut measure_scope : AnalyticEnvelopeScope
  mut measure_next : Int
  ordinals : Map[String, Int]
  input_roots : Array[ExpressionRootLease]
  partitions : Array[ColumnOrder]
  peer_order : Array[ColumnOrder]
  complete : Array[ColumnOrder]
  mut sorter : StableOrderExecution[T]?
  mut sorted : Array[Int]
  comparison : BoundedRowComparison
  ranges : Array[AnalyticPartitionRange]
  mut range_start : Int
  aggregate_arguments : Array[AggregateInput?]
  count_indices : Array[AnalyticCountIndex?]
  mut prefix : Array[Int]
  // Per-row indexes.
  position_by_row : Array[Int]
  partition_start : Array[Int]
  partition_by_row : Array[Int]
  ranks : Array[Int]
  dense_ranks : Array[Int]
  references : Array[Array[Int]]
  demanded : Array[Array[Bool]]
  mut needs_aggregate_demand : Bool
  mut range_index : Int
  mut position : Int
  mut peer_start : Int
  mut dense : Int
  mut frame_memberships : Int64
  // Frame aggregate demand.
  difference : Array[Int]
  aggregate_demand : Array[Bool]
  mut has_aggregate_demand : Bool
  mut active : Int
  // Evaluated call values.
  evaluated : Array[Array[Value?]]
  arguments : Array[Array[Value?]]
  included : Array[Array[Bool]]
  failure_sources : Array[Array[Int]]
  call_order : Array[Int]
  mut cursor : Int
  mut source_index : Int
  mut call_position : Int
  mut call_phase : Int
  mut expression : AggregateExpressionExecution[T]?
  mut values : Array[Value]
  mut local_indices : Array[Int]
  mut frame_end : Int
  mut baseline : Int
  mut direct : AggregateDirect[DynamicAggregateRows]?
  call_by_name : Map[String, Int]
  output_names : Array[String]
  output_columns : Array[(Bool, Int)]
  mut output_writer : @encode.Writer?
  mut row : Array[Value]
  mut row_retention : SteppedRowRetention?
  mut row_retained : Bool
  mut closed : Bool
}

///|
fn[T : RelationRows] start_analytic_evaluation(
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
  step : Int,
  accept_row : (Array[Value], Int) -> Result[Unit, RowIssue],
) -> AnalyticEvaluation[T] {
  {
    analytic,
    input,
    names: input.field_names(),
    count: IndexedRows::row_count(input),
    max_rows,
    control,
    output,
    workspace,
    scope,
    aggregate_outputs,
    envelope,
    identity_limits,
    numeric,
    step,
    accept_row,
    call_count: @lower.analytic_call_count(analytic),
    pending: { remaining: 0, },
    charging: false,
    phase: 0,
    index: 0,
    inner: 0,
    writer: None,
    wire: None,
    measure_ordered: false,
    measure_start: 0,
    measure_end: 0,
    measure_position: 0,
    measure_column: -1,
    measure_ceiling: 0L,
    measure_scope: Measurement,
    measure_next: 0,
    ordinals: Map([]),
    input_roots: [],
    partitions: [],
    peer_order: [],
    complete: [],
    sorter: None,
    sorted: [],
    comparison: {
      left: -1,
      right: -1,
      terms: 0,
      term: 0,
      phase: -1,
      offset: 0,
      charge: { offset: 0, next: 0, remaining: 0, },
    },
    ranges: [],
    range_start: 0,
    aggregate_arguments: [],
    count_indices: [],
    prefix: [],
    position_by_row: [],
    partition_start: [],
    partition_by_row: [],
    ranks: [],
    dense_ranks: [],
    references: [],
    demanded: [],
    needs_aggregate_demand: false,
    range_index: 0,
    position: 0,
    peer_start: 0,
    dense: 1,
    frame_memberships: 0L,
    difference: [],
    aggregate_demand: [],
    has_aggregate_demand: false,
    active: 0,
    evaluated: [],
    arguments: [],
    included: [],
    failure_sources: [],
    call_order: [],
    cursor: 0,
    source_index: 0,
    call_position: 0,
    call_phase: 0,
    expression: None,
    values: [],
    local_indices: [],
    frame_end: 0,
    baseline: 0,
    direct: None,
    call_by_name: Map([]),
    output_names: [],
    output_columns: [],
    output_writer: None,
    row: [],
    row_retention: None,
    row_retained: false,
    closed: false,
  }
}

///|
fn[T] close_analytic_evaluation(state : AnalyticEvaluation[T]) -> Unit {
  if state.closed {
    return
  }
  if state.sorter is Some(sorter) {
    close_stable_order(sorter)
    state.sorter = None
  }
  if state.expression is Some(expression) {
    close_aggregate_expression(expression)
    state.expression = None
  }
  if state.direct is Some(direct) {
    close_aggregate_direct(direct)
    state.direct = None
  }
  if state.wire is Some(cursor) {
    close_stepped_runtime_wire(cursor)
    state.wire = None
  }
  if state.writer is Some(writer) {
    @encode.cancel_writer(writer)
    state.writer = None
  }
  if state.output_writer is Some(writer) {
    @encode.cancel_writer(writer)
    state.output_writer = None
  }
  if state.row_retention is Some(cursor) {
    close_stepped_row_retention(cursor)
    state.row_retention = None
  }
  state.row = []
  state.closed = true
}

///|
/// Returns the output names once every row was accepted and the selected
/// numeric occurrence domains are sealed.
fn[T : RelationRows] advance_analytic_evaluation(
  state : AnalyticEvaluation[T],
) -> Result[Array[String]?, RowIssue] {
  if state.closed {
    return Err(InvalidRows)
  }
  let result = advance_analytic_evaluation_impl(state)
  match result {
    Err(_) => close_analytic_evaluation(state)
    Ok(Some(_)) => state.closed = true
    Ok(None) => ()
  }
  result
}

///|
/// Pay previously decided units, one per advance. Returns true when paid.
fn[T] analytic_pay(
  s : AnalyticEvaluation[T],
  units : Int,
) -> Result[Bool, RowIssue] {
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
fn[T] analytic_pay_text(
  s : AnalyticEvaluation[T],
  text : String,
  entry : Int,
) -> Result[Bool, RowIssue] {
  if !s.charging {
    match utf8_units(text) {
      Ok(bytes) => {
        s.pending.remaining = entry + bytes
        s.charging = true
      }
      Err(issue) => return Err(issue)
    }
  }
  analytic_pay(s, 0)
}

///|
fn[T] analytic_begin_measure(
  s : AnalyticEvaluation[T],
  ordered : Bool,
  start : Int,
  end : Int,
  ceiling : Int64,
  scope : AnalyticEnvelopeScope,
  next : Int,
) -> Unit {
  s.writer = None
  s.measure_ordered = ordered
  s.measure_start = start
  s.measure_end = end
  s.measure_position = start
  s.measure_column = -1
  s.measure_ceiling = ceiling
  s.measure_scope = scope
  s.measure_next = next
  s.phase = 100
}

///|
/// Called once per charged analytic advance. Small leaves keep their old
/// finite fast path; large cells retain a shared emitter across advances.
fn[T] analytic_emit_cell(
  s : AnalyticEvaluation[T],
  writer : @encode.Writer,
  name : String,
  cell : Value,
  scope : AnalyticEnvelopeScope,
) -> Result[Bool, RowIssue] {
  if !spend_control(s.control, 1) {
    return Err(AnalyticEnvelope(Measurement))
  }
  if s.wire is Some(cursor) {
    match advance_stepped_runtime_wire(cursor) {
      Err(Workspace) => return Err(RowLimit)
      Err(Encoding(_)) => return Err(AnalyticEnvelope(scope))
      Ok(false) => return Ok(false)
      Ok(true) => {
        s.wire = None
        return Ok(true)
      }
    }
  }
  @encode.key(writer, name) catch {
    _ => return Err(AnalyticEnvelope(scope))
  }
  if bounded_small_output_value(cell) {
    emit_runtime_value(cell, writer) catch {
      _ => return Err(AnalyticEnvelope(scope))
    }
    return Ok(true)
  }
  match start_stepped_runtime_wire(cell, writer, s.workspace) {
    Err(Workspace) => Err(RowLimit)
    Err(Encoding(_)) => Err(AnalyticEnvelope(scope))
    Ok(cursor) => {
      s.wire = Some(cursor)
      Ok(false)
    }
  }
}

///|
/// One step of the row-array envelope measurement: the writer, one row entry, one
/// cell, or the closing measurement.
fn[T : RelationRows] analytic_measure_step(
  s : AnalyticEvaluation[T],
) -> Result[Unit, RowIssue] {
  let scope = s.measure_scope
  if s.writer is None {
    if s.measure_ceiling < 0L ||
      s.measure_start < 0 ||
      s.measure_end < s.measure_start ||
      (s.measure_ordered && s.measure_end > s.sorted.length()) {
      return Err(AnalyticEnvelope(Measurement))
    }
    let cap = Int64::min(s.measure_ceiling, 2147483647L).to_int()
    let writer = @encode.measuring_writer(cap, 2147483647, 2147483647) catch {
      _ => return Err(AnalyticEnvelope(scope))
    }
    @encode.begin_array(writer) catch {
      _ => return Err(AnalyticEnvelope(scope))
    }
    s.writer = Some(writer)
    return Ok(())
  }
  let writer = s.writer.unwrap()
  if s.measure_position >= s.measure_end {
    try {
      @encode.end_array(writer)
      @encode.finish_measurement(writer) |> ignore
    } catch {
      _ => return Err(AnalyticEnvelope(scope))
    }
    s.writer = None
    s.phase = s.measure_next
    return Ok(())
  }
  let row = if s.measure_ordered {
    s.sorted[s.measure_position]
  } else {
    s.measure_position
  }
  if s.measure_column < 0 {
    if row < 0 ||
      row >= IndexedRows::row_count(s.input) ||
      IndexedRows::row_width(s.input, row) != s.names.length() ||
      !spend_control(s.control, 1) {
      return Err(AnalyticEnvelope(Measurement))
    }
    @encode.begin_object(writer) catch {
      _ => return Err(AnalyticEnvelope(scope))
    }
    s.measure_column = 0
    return Ok(())
  }
  if s.measure_column < s.names.length() {
    match
      analytic_emit_cell(
        s,
        writer,
        s.names[s.measure_column],
        IndexedRows::read_cell(s.input, row, s.measure_column),
        scope,
      ) {
      Err(issue) => return Err(issue)
      Ok(false) => return Ok(())
      Ok(true) => ()
    }
    s.measure_column += 1
    return Ok(())
  }
  @encode.end_object(writer) catch {
    _ => return Err(AnalyticEnvelope(scope))
  }
  s.measure_column = -1
  s.measure_position += 1
  Ok(())
}

///|
fn[T] analytic_frame_aggregate(
  s : AnalyticEvaluation[T],
  call_index : Int,
) -> @lower.PreparedAggregate? {
  match
    @lower.analytic_call_function(
      @lower.analytic_call_at(s.analytic, call_index).unwrap(),
    ) {
    PreparedFrameAggregate(aggregate) => Some(aggregate)
    _ => None
  }
}

///|
fn[T] analytic_resolve(
  s : AnalyticEvaluation[T],
  field : @schema.FieldName,
) -> Result[Int?, RowIssue] {
  let name = @schema.reference_name(field)
  match analytic_pay_text(s, name, 0) {
    Err(issue) => Err(issue)
    Ok(false) => Ok(None)
    Ok(true) =>
      match s.ordinals.get(name) {
        Some(column) => Ok(Some(column))
        None => Err(InvalidRows)
      }
  }
}

///|
fn[T : RelationRows] advance_analytic_evaluation_impl(
  s : AnalyticEvaluation[T],
) -> Result[Array[String]?, RowIssue] {
  let analytic = s.analytic
  let count = s.count
  let call_count = s.call_count
  match s.phase {
    // Profile, row ceiling and input envelope.
    0 => {
      if !analytic_execution_supported_with_profile(
          analytic,
          s.numeric is Some(_),
        ) {
        return Err(InvalidRows)
      }
      if count > s.max_rows {
        return Err(RowLimit)
      }
      if s.envelope is Some(value) && Int64::from_int(count) > value.output_rows {
        return Err(AnalyticEnvelope(OutputRows))
      }
      match s.envelope {
        Some(value) => {
          if !reserve_slots(s.workspace, count) {
            return Err(RowLimit)
          }
          analytic_begin_measure(
            s,
            false,
            0,
            count,
            value.input_wire_bytes,
            InputWireBytes,
            1,
          )
        }
        None => s.phase = 2
      }
      Ok(None)
    }
    1 => {
      release_slots(s.workspace, count)
      s.phase = 2
      Ok(None)
    }
    // Input names.
    2 => {
      if s.index >= s.names.length() {
        s.index = 0
        s.phase = 3
        if s.scope is Some(value) {
          match admit_logical_rows(value.budget, count.to_int64()) {
            Ok(_) => ()
            Err(issue) => return Err(LogicalRows(issue))
          }
        }
        return Ok(None)
      }
      let name = s.names[s.index]
      match analytic_pay_text(s, name, 1) {
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
    // Input logical roots, one row per advance.
    3 => {
      guard s.scope is Some(value) else {
        s.index = 0
        s.phase = 4
        return Ok(None)
      }
      if s.index >= count {
        s.index = 0
        s.phase = 4
        return Ok(None)
      }
      let source = IndexedRow::{ table: s.input, row: s.index, }
      if RowValues::value_count(source) != s.names.length() {
        return Err(InvalidRows)
      }
      if !reserve_slots(s.workspace, 1) {
        return Err(RowLimit)
      }
      let root = match retain_logical_row(value.budget, s.names, source) {
        Ok(root) => root
        Err(issue) => return Err(LogicalRows(issue))
      }
      let lease = match register_scope_root(value, root) {
        Ok(lease) => lease
        Err(issue) => return Err(LogicalRows(issue))
      }
      s.input_roots.push(lease)
      match charge_logical_work(value.budget, 1L) {
        Ok(_) => ()
        Err(issue) => return Err(LogicalRows(issue))
      }
      s.index += 1
      Ok(None)
    }
    // Partition, peer and position terms.
    4 => {
      let partitions = @lower.analytic_partition_count(analytic)
      let peers = @lower.analytic_peer_term_count(analytic)
      let positions = @lower.analytic_position_term_count(analytic)
      let index = s.index
      if index >= partitions + peers + positions {
        s.sorter = Some(
          start_stable_order(s.input, s.complete, s.control, s.workspace),
        )
        s.phase = 5
        return Ok(None)
      }
      let (field, descending, nulls_first, target) = if index < partitions {
        (@lower.analytic_partition_at(analytic, index).unwrap(), false, true, 0)
      } else if index < partitions + peers {
        let (field, descending, nulls_first) = @lower.analytic_peer_term_at(
          analytic,
          index - partitions,
        ).unwrap()
        (field, descending, nulls_first, 1)
      } else {
        let (field, descending, nulls_first) = @lower.analytic_position_term_at(
          analytic,
          index - partitions - peers,
        ).unwrap()
        (field, descending, nulls_first, 2)
      }
      match analytic_resolve(s, field) {
        Err(issue) => Err(issue)
        Ok(None) => Ok(None)
        Ok(Some(column)) => {
          let term = { column, descending, nulls_first, }
          match target {
            0 => {
              s.partitions.push(term)
              s.complete.push(term)
            }
            1 => s.peer_order.push(term)
            _ => s.complete.push(term)
          }
          s.index += 1
          Ok(None)
        }
      }
    }
    // Complete stable order.
    5 => {
      guard s.sorter is Some(sorter) else { return Err(InvalidRows) }
      match advance_stable_order(sorter) {
        Err(issue) => Err(ordering_row_issue(issue))
        Ok(None) => Ok(None)
        Ok(Some(indices)) => {
          s.sorter = None
          s.sorted = indices
          s.position = 0
          s.range_start = 0
          s.phase = 6
          Ok(None)
        }
      }
    }
    // Partition boundaries, one comparison step per advance.
    6 => {
      let position = s.position
      let boundary = if position == s.sorted.length() {
        true
      } else if position == 0 {
        false
      } else {
        match
          bounded_row_comparison_step_with(
            s.comparison,
            s.partitions,
            s.control,
            (row, column) => Some(IndexedRows::read_cell(s.input, row, column)),
            s.sorted[position - 1],
            s.sorted[position],
            s.partitions.length(),
          ) {
          Err(issue) => return Err(ordering_row_issue(issue))
          Ok(None) => return Ok(None)
          Ok(Some(order)) => order != 0
        }
      }
      if boundary {
        if !reserve_slots(s.workspace, 1) {
          return Err(RowLimit)
        }
        s.ranges.push({ start: s.range_start, end: position, })
        s.range_start = position
      }
      if position == s.sorted.length() {
        s.index = 0
        s.phase = 7
      } else {
        s.position += 1
      }
      Ok(None)
    }
    // Partition envelopes, one range per measurement.
    7 => {
      guard s.envelope is Some(value) else {
        s.index = 0
        s.phase = 8
        return Ok(None)
      }
      if s.index >= s.ranges.length() {
        s.index = 0
        s.phase = 8
        return Ok(None)
      }
      let range = s.ranges[s.index]
      s.index += 1
      analytic_begin_measure(
        s,
        true,
        range.start,
        range.end,
        value.partition_wire_bytes,
        PartitionWireBytes,
        7,
      )
      Ok(None)
    }
    // Aggregate arguments.
    8 => {
      if s.aggregate_arguments.length() == 0 && s.index == 0 && call_count > 0 {
        if !reserve_slots(s.workspace, call_count) {
          return Err(RowLimit)
        }
        for _ in 0..<call_count {
          s.aggregate_arguments.push(None)
        }
      }
      if s.index >= call_count {
        if !reserve_slots(s.workspace, call_count) {
          return Err(RowLimit)
        }
        for _ in 0..<call_count {
          s.count_indices.push(None)
        }
        s.index = 0
        s.phase = 9
        return Ok(None)
      }
      guard analytic_frame_aggregate(s, s.index) is Some(aggregate) else {
        s.index += 1
        return Ok(None)
      }
      match @lower.group_aggregate_argument(aggregate) {
        @lower.AggregateRows =>
          s.aggregate_arguments[s.index] = Some(AggregateInputRows)
        @lower.AggregateExpression(expression) =>
          s.aggregate_arguments[s.index] = Some(
            AggregateInputExpression(expression),
          )
        @lower.AggregateField(field) =>
          match analytic_resolve(s, field) {
            Err(issue) => return Err(issue)
            Ok(None) => return Ok(None)
            Ok(Some(column)) =>
              s.aggregate_arguments[s.index] = Some(AggregateInputField(column))
          }
      }
      s.index += 1
      Ok(None)
    }
    // Count indexes, one prefix position per advance.
    9 => {
      if s.index >= call_count {
        s.phase = 10
        s.index = 0
        return Ok(None)
      }
      guard analytic_frame_aggregate(s, s.index) is Some(aggregate) else {
        s.index += 1
        return Ok(None)
      }
      if @lower.group_aggregate_distinct(aggregate) == Some(true) ||
        @lower.group_aggregate_filter(aggregate) is Some(_) {
        s.index += 1
        return Ok(None)
      }
      let function = @lower.group_aggregate_function(aggregate)
      if function is @relation.Count &&
        s.aggregate_arguments[s.index] is Some(AggregateInputRows) {
        s.count_indices[s.index] = Some(CountRows)
        s.index += 1
        return Ok(None)
      }
      guard (function is @relation.Count || function is @relation.CountIf) &&
        s.aggregate_arguments[s.index] is Some(AggregateInputField(column)) else {
        s.index += 1
        return Ok(None)
      }
      if s.prefix.is_empty() {
        if !reserve_slots(s.workspace, count + 1) {
          return Err(RowLimit)
        }
        s.prefix.push(0)
        return Ok(None)
      }
      let position = s.prefix.length() - 1
      if position < count {
        if !spend_control(s.control, 1) {
          return Err(RowLimit)
        }
        let value = IndexedRows::read_cell(s.input, s.sorted[position], column)
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
        s.prefix.push(s.prefix[position] + increment)
        return Ok(None)
      }
      s.count_indices[s.index] = Some(CountPrefix(s.prefix))
      s.prefix = []
      s.index += 1
      Ok(None)
    }
    // Per-row index storage, one row per advance.
    10 => {
      if s.index == 0 && s.inner == 0 {
        for _ in 0..<5 {
          if !reserve_slots(s.workspace, count) {
            return Err(RowLimit)
          }
        }
        if !reserve_matrix_slots(s.workspace, call_count, count) ||
          !reserve_matrix_slots(s.workspace, call_count, count) {
          return Err(RowLimit)
        }
        for _ in 0..<call_count {
          s.references.push([])
          s.demanded.push([])
        }
        s.inner = 1
        return Ok(None)
      }
      if s.index < count {
        s.position_by_row.push(-1)
        s.partition_start.push(-1)
        s.partition_by_row.push(-1)
        s.ranks.push(0)
        s.dense_ranks.push(0)
        for call_index in 0..<call_count {
          s.references[call_index].push(-1)
          s.demanded[call_index].push(false)
        }
        s.index += 1
        return Ok(None)
      }
      for call_index in 0..<call_count {
        if analytic_frame_aggregate(s, call_index) is Some(_) &&
          s.count_indices[call_index] is None {
          s.needs_aggregate_demand = true
        }
      }
      s.index = 0
      s.inner = 0
      s.range_index = 0
      s.position = if s.ranges.is_empty() { 0 } else { s.ranges[0].start }
      s.peer_start = s.position
      s.dense = 1
      s.phase = 11
      Ok(None)
    }
    // Positions, ranks and navigation references.
    11 => {
      if s.range_index >= s.ranges.length() {
        s.phase = 12
        return Ok(None)
      }
      let range = s.ranges[s.range_index]
      if s.position >= range.end {
        s.range_index += 1
        if s.range_index < s.ranges.length() {
          s.position = s.ranges[s.range_index].start
          s.peer_start = s.position
          s.dense = 1
        }
        s.inner = 0
        return Ok(None)
      }
      let position = s.position
      // Enter the position.
      if s.inner == 0 {
        if !spend_control(s.control, 1) {
          return Err(RowLimit)
        }
        s.inner = if position > range.start { 1 } else { 2 }
        return Ok(None)
      }
      // Peer comparison with the previous position.
      if s.inner == 1 {
        match
          bounded_row_comparison_step_with(
            s.comparison,
            s.peer_order,
            s.control,
            (row, column) => Some(IndexedRows::read_cell(s.input, row, column)),
            s.sorted[position - 1],
            s.sorted[position],
            s.peer_order.length(),
          ) {
          Err(issue) => return Err(ordering_row_issue(issue))
          Ok(None) => return Ok(None)
          Ok(Some(order)) =>
            if order != 0 {
              s.peer_start = position
              s.dense += 1
            }
        }
        s.inner = 2
        return Ok(None)
      }
      let source = s.sorted[position]
      s.position_by_row[source] = position
      s.partition_start[source] = range.start
      s.partition_by_row[source] = s.range_index
      s.ranks[source] = s.peer_start - range.start + 1
      s.dense_ranks[source] = s.dense
      let relative = position - range.start
      let length = range.end - range.start
      for call_index in 0..<call_count {
        let call = @lower.analytic_call_at(analytic, call_index).unwrap()
        let reference = match @lower.analytic_call_function(call) {
          PreparedLag(_, offset) =>
            if offset <= Int64::from_int(relative) {
              s.sorted[position - offset.to_int()]
            } else {
              -1
            }
          PreparedLead(_, offset) => {
            let remaining = length - relative - 1
            if offset <= Int64::from_int(remaining) {
              s.sorted[position + offset.to_int()]
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
                s.sorted[range.start + selected]
              }
            }
          }
          PreparedRowNumber | PreparedRank | PreparedDenseRank => -1
          PreparedFrameAggregate(_) => -1
        }
        s.references[call_index][source] = reference
        if s.envelope is Some(value) {
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
          if memberships > value.frame_memberships - s.frame_memberships {
            return Err(AnalyticEnvelope(FrameMemberships))
          }
          s.frame_memberships += memberships
        }
      }
      s.position += 1
      s.inner = 0
      Ok(None)
    }
    // Frame aggregate demand: one interval pass, then one prefix pass.
    12 => {
      if !s.needs_aggregate_demand {
        s.phase = 14
        s.index = 0
        return Ok(None)
      }
      guard @lower.analytic_frame(analytic) is Some(frame) else {
        return Err(InvalidRows)
      }
      if s.inner == 0 {
        if count == 2147483647 ||
          !reserve_slots(s.workspace, count) ||
          !reserve_slots(s.workspace, count) ||
          !reserve_slots(s.workspace, 1) {
          return Err(RowLimit)
        }
        s.inner = 1
        return Ok(None)
      }
      if s.inner == 1 {
        if s.difference.length() < count + 1 {
          s.difference.push(0)
          if s.aggregate_demand.length() < count {
            s.aggregate_demand.push(false)
          }
          return Ok(None)
        }
        s.inner = 2
        s.range_index = 0
        s.index = 0
        return Ok(None)
      }
      if s.inner == 2 {
        if s.range_index >= s.ranges.length() {
          s.inner = 3
          s.index = 0
          s.active = 0
          return Ok(None)
        }
        let range = s.ranges[s.range_index]
        if range.start < 0 || range.end < range.start || range.end > count {
          return Err(InvalidRows)
        }
        let length = range.end - range.start
        if s.index >= length {
          s.range_index += 1
          s.index = 0
          return Ok(None)
        }
        if !spend_control(s.control, 1) {
          return Err(RowLimit)
        }
        match analytic_frame_range(frame, s.index, length) {
          None => ()
          Some((first, end)) => {
            s.difference[range.start + first] += 1
            s.difference[range.start + end] -= 1
          }
        }
        s.index += 1
        return Ok(None)
      }
      if s.index < count {
        if !spend_control(s.control, 1) {
          return Err(RowLimit)
        }
        s.active += s.difference[s.index]
        let source = s.sorted[s.index]
        if source < 0 || source >= count || s.active < 0 {
          return Err(InvalidRows)
        }
        s.aggregate_demand[source] = s.active > 0
        s.index += 1
        return Ok(None)
      }
      if s.active + s.difference[count] != 0 {
        return Err(InvalidRows)
      }
      s.has_aggregate_demand = true
      s.inner = 0
      s.index = 0
      s.phase = 14
      Ok(None)
    }
    // Call value storage and navigation demand, one row per advance.
    14 => {
      if s.inner == 0 {
        if !reserve_matrix_slots(s.workspace, call_count, count) ||
          !reserve_matrix_slots(s.workspace, call_count, count) ||
          !reserve_matrix_slots(s.workspace, call_count, count) {
          return Err(RowLimit)
        }
        for _ in 0..<call_count {
          s.evaluated.push([])
          s.arguments.push([])
          s.included.push([])
        }
        s.inner = 1
        return Ok(None)
      }
      if s.index < count {
        for call_index in 0..<call_count {
          s.evaluated[call_index].push(None)
          s.arguments[call_index].push(None)
          s.included[call_index].push(false)
        }
        s.index += 1
        return Ok(None)
      }
      if s.inner == 1 {
        s.inner = 2
        s.index = 0
        return Ok(None)
      }
      // Mark navigation demand after every reference is known.
      if s.inner - 2 < count {
        let source = s.inner - 2
        for call_index in 0..<call_count {
          let reference = s.references[call_index][source]
          if reference >= 0 {
            s.demanded[call_index][reference] = true
          }
        }
        s.inner += 1
        return Ok(None)
      }
      if !reserve_slots(s.workspace, s.ranges.length()) {
        return Err(RowLimit)
      }
      s.inner = 0
      s.index = 0
      s.phase = 15
      Ok(None)
    }
    // Failure order: sources by partition.
    15 => {
      // One reserved partition list per advance.
      if s.failure_sources.length() < s.ranges.length() {
        s.failure_sources.push([])
        return Ok(None)
      }
      if s.index < count {
        let range_index = s.partition_by_row[s.index]
        if range_index < 0 ||
          !spend_control(s.control, 1) ||
          !reserve_slots(s.workspace, 1) {
          return Err(RowLimit)
        }
        s.failure_sources[range_index].push(s.index)
        s.index += 1
        return Ok(None)
      }
      if !reserve_slots(s.workspace, call_count) {
        return Err(RowLimit)
      }
      for call_index in 0..<call_count {
        s.call_order.push(call_index)
      }
      s.index = 1
      s.cursor = 1
      s.phase = 16
      Ok(None)
    }
    // Call name order, one insertion comparison per advance.
    16 => {
      if s.index >= s.call_order.length() {
        s.range_index = 0
        s.source_index = 0
        s.call_position = 0
        s.call_phase = 0
        s.phase = 17
        return Ok(None)
      }
      if s.cursor <= 0 {
        s.index += 1
        s.cursor = s.index
        return Ok(None)
      }
      if !spend_control(s.control, 1) {
        return Err(RowLimit)
      }
      let left = s.call_order[s.cursor - 1]
      let right = s.call_order[s.cursor]
      let comparison = @canonical.compare_utf16(
        @lower.analytic_call_name(
          @lower.analytic_call_at(analytic, left).unwrap(),
        ),
        @lower.analytic_call_name(
          @lower.analytic_call_at(analytic, right).unwrap(),
        ),
      )
      if comparison <= 0 {
        s.index += 1
        s.cursor = s.index
      } else {
        s.call_order[s.cursor - 1] = right
        s.call_order[s.cursor] = left
        s.cursor -= 1
      }
      Ok(None)
    }
    // Arguments and navigation values in failure order.
    17 => analytic_advance_arguments(s)
    // Frame aggregates in failure order.
    18 => analytic_advance_aggregates(s)
    // Call names.
    19 => {
      if s.index >= call_count {
        s.index = 0
        s.phase = 20
        return Ok(None)
      }
      let name = @lower.analytic_call_name(
        @lower.analytic_call_at(analytic, s.index).unwrap(),
      )
      match analytic_pay_text(s, name, 0) {
        Err(issue) => return Err(issue)
        Ok(false) => return Ok(None)
        Ok(true) => ()
      }
      if !reserve_slots(s.workspace, 1) {
        return Err(RowLimit)
      }
      s.call_by_name[name] = s.index
      s.index += 1
      Ok(None)
    }
    // Output fields.
    20 => {
      let schema = @lower.analytic_output_schema(analytic)
      if s.index >= @schema.field_count(schema) {
        match s.envelope {
          None => ()
          Some(value) => {
            let cap = Int64::min(value.output_wire_bytes, 2147483647L).to_int()
            let writer = @encode.measuring_writer(cap, 2147483647, 2147483647) catch {
              _ => return Err(AnalyticEnvelope(OutputWireBytes))
            }
            @encode.begin_array(writer) catch {
              _ => return Err(AnalyticEnvelope(OutputWireBytes))
            }
            s.output_writer = Some(writer)
          }
        }
        s.index = 0
        s.inner = -1
        s.phase = 21
        return Ok(None)
      }
      let name = @schema.reference_name(
        @schema.field_at(schema, s.index).unwrap().name,
      )
      match analytic_pay_text(s, name, 0) {
        Err(issue) => return Err(issue)
        Ok(false) => return Ok(None)
        Ok(true) => ()
      }
      if !reserve_slots(s.workspace, 2) {
        return Err(RowLimit)
      }
      s.output_names.push(name)
      match s.ordinals.get(name) {
        Some(column) => s.output_columns.push((false, column))
        None =>
          match s.call_by_name.get(name) {
            Some(call) => s.output_columns.push((true, call))
            None => return Err(InvalidRows)
          }
      }
      s.index += 1
      Ok(None)
    }
    // Output rows.
    21 => analytic_advance_output(s)
    // Close the output envelope and seal numeric occurrence domains.
    22 => {
      if s.output_writer is Some(writer) {
        try {
          @encode.end_array(writer)
          @encode.finish_measurement(writer) |> ignore
        } catch {
          _ => return Err(AnalyticEnvelope(OutputWireBytes))
        }
        s.output_writer = None
      }
      s.index = 0
      s.phase = 23
      Ok(None)
    }
    23 => {
      guard s.numeric is Some(execution) else {
        return Ok(Some(s.output_names))
      }
      if s.index >= call_count {
        return Ok(Some(s.output_names))
      }
      let call = @lower.analytic_call_at(analytic, s.index).unwrap()
      if @lower.analytic_call_function(call)
        is PreparedFrameAggregate(aggregate) &&
        @lower.group_aggregate_requires_numeric_observation(aggregate) &&
        !seal_numeric_aggregate(
          execution,
          s.step,
          @lower.analytic_call_name(call),
          count,
        ) {
        return Err(InvalidRows)
      }
      s.index += 1
      Ok(None)
    }
    // Envelope measurement.
    100 =>
      match analytic_measure_step(s) {
        Ok(_) => Ok(None)
        Err(issue) => Err(issue)
      }
    _ => Err(InvalidRows)
  }
}

///|
/// Advance the failure-order cursor over (partition, source, call).
fn[T] analytic_next_call(s : AnalyticEvaluation[T], next_phase : Int) -> Unit {
  s.call_phase = 0
  s.call_position += 1
  if s.call_position >= s.call_order.length() {
    s.call_position = 0
    s.source_index += 1
    if s.range_index < s.failure_sources.length() &&
      s.source_index >= s.failure_sources[s.range_index].length() {
      s.source_index = 0
      s.range_index += 1
    }
  }
  if s.range_index >= s.failure_sources.length() {
    s.range_index = 0
    s.source_index = 0
    s.call_position = 0
    s.index = 0
    s.phase = next_phase
  }
}

///|
/// Evaluate one expression step for `source` and `call_index`.
fn[T : RelationRows] analytic_expression_step(
  s : AnalyticEvaluation[T],
  expression : @lower.Expression,
  source : Int,
  call_index : Int,
) -> Result[Value?, RowIssue] {
  let state = match s.expression {
    Some(value) => value
    None => {
      let value = start_aggregate_expression(
        expression,
        s.input,
        s.names,
        source,
        call_index,
        s.control,
        s.workspace,
        s.scope,
        unscoped=true,
      )
      s.expression = Some(value)
      value
    }
  }
  match advance_aggregate_expression(state) {
    Err(issue) => {
      s.expression = None
      Err(issue)
    }
    Ok(None) => Ok(None)
    Ok(Some(value)) => {
      s.expression = None
      Ok(Some(value))
    }
  }
}

///|
fn[T : RelationRows] analytic_advance_arguments(
  s : AnalyticEvaluation[T],
) -> Result[Array[String]?, RowIssue] {
  if s.range_index >= s.failure_sources.length() {
    s.range_index = 0
    s.source_index = 0
    s.call_position = 0
    s.call_phase = 0
    s.phase = 18
    return Ok(None)
  }
  let sources = s.failure_sources[s.range_index]
  if s.source_index >= sources.length() || s.call_order.is_empty() {
    s.source_index = 0
    s.call_position = 0
    s.range_index += 1
    return Ok(None)
  }
  let source = sources[s.source_index]
  let call_index = s.call_order[s.call_position]
  let call = @lower.analytic_call_at(s.analytic, call_index).unwrap()
  match @lower.analytic_call_function(call) {
    PreparedFrameAggregate(aggregate) => {
      // Decide demand, then evaluate the filter and the argument.
      if s.call_phase == 0 {
        if s.count_indices[call_index] is Some(_) ||
          !s.has_aggregate_demand ||
          !s.aggregate_demand[source] {
          analytic_next_call(s, 18)
          return Ok(None)
        }
        s.call_phase = if @lower.group_aggregate_filter(aggregate) is Some(_) {
          1
        } else {
          2
        }
        return Ok(None)
      }
      if s.call_phase == 1 {
        guard @lower.group_aggregate_filter(aggregate) is Some(filter) else {
          return Err(InvalidRows)
        }
        match analytic_expression_step(s, filter, source, call_index) {
          Err(issue) => return Err(issue)
          Ok(None) => return Ok(None)
          Ok(Some(Boolean(true))) => s.call_phase = 2
          Ok(Some(Boolean(false) | Null)) => analytic_next_call(s, 18)
          Ok(Some(_)) => return Err(InvalidRows)
        }
        return Ok(None)
      }
      guard s.aggregate_arguments[call_index] is Some(argument) else {
        return Err(InvalidRows)
      }
      let value = match argument {
        AggregateInputRows => Null
        AggregateInputField(column) =>
          IndexedRows::read_cell(s.input, source, column)
        AggregateInputExpression(expression) =>
          match analytic_expression_step(s, expression, source, call_index) {
            Err(issue) => return Err(issue)
            Ok(None) => return Ok(None)
            Ok(Some(value)) => value
          }
      }
      s.included[call_index][source] = true
      s.arguments[call_index][source] = Some(value)
      analytic_next_call(s, 18)
      Ok(None)
    }
    PreparedLag(expression, _)
    | PreparedLead(expression, _)
    | PreparedFirstValue(expression)
    | PreparedLastValue(expression) => {
      if !s.demanded[call_index][source] {
        analytic_next_call(s, 18)
        return Ok(None)
      }
      match analytic_expression_step(s, expression, source, call_index) {
        Err(issue) => Err(issue)
        Ok(None) => Ok(None)
        Ok(Some(value)) => {
          s.arguments[call_index][source] = Some(value)
          analytic_next_call(s, 18)
          Ok(None)
        }
      }
    }
    PreparedRowNumber | PreparedRank | PreparedDenseRank => {
      analytic_next_call(s, 18)
      Ok(None)
    }
  }
}

///|
fn[T] analytic_advance_aggregates(
  s : AnalyticEvaluation[T],
) -> Result[Array[String]?, RowIssue] {
  if s.range_index >= s.failure_sources.length() {
    s.index = 0
    s.phase = 19
    return Ok(None)
  }
  let sources = s.failure_sources[s.range_index]
  if s.source_index >= sources.length() || s.call_order.is_empty() {
    s.source_index = 0
    s.call_position = 0
    s.range_index += 1
    return Ok(None)
  }
  let source = sources[s.source_index]
  let call_index = s.call_order[s.call_position]
  guard analytic_frame_aggregate(s, call_index) is Some(aggregate) else {
    analytic_next_call(s, 19)
    return Ok(None)
  }
  let range = s.ranges[s.range_index]
  match s.call_phase {
    // Frame bounds, or an indexed count.
    0 => {
      guard @lower.analytic_frame(s.analytic) is Some(frame) else {
        return Err(InvalidRows)
      }
      let position = s.position_by_row[source] - range.start
      let length = range.end - range.start
      let (first, end) = match analytic_frame_range(frame, position, length) {
        Some((first, end)) => (range.start + first, range.start + end)
        None => (range.start, range.start)
      }
      match s.count_indices[call_index] {
        Some(CountRows) => {
          s.evaluated[call_index][source] = Some(
            Number((end - first).to_double()),
          )
          analytic_next_call(s, 19)
        }
        Some(CountPrefix(prefix)) => {
          s.evaluated[call_index][source] = Some(
            Number((prefix[end] - prefix[first]).to_double()),
          )
          analytic_next_call(s, 19)
        }
        None => {
          s.baseline = s.workspace.live
          if first < 0 || end < first || end > s.sorted.length() {
            return Err(InvalidRows)
          }
          if !reserve_slots(s.workspace, end - first) {
            return Err(RowLimit)
          }
          s.frame_end = end
          s.position = first
          s.values = []
          s.call_phase = 1
        }
      }
      Ok(None)
    }
    // Collect included frame members, one position per advance.
    1 => {
      if s.position < s.frame_end {
        if !spend_control(s.control, 1) {
          return Err(RowLimit)
        }
        let frame_member = s.sorted[s.position]
        if frame_member < 0 || frame_member >= s.included[call_index].length() {
          return Err(InvalidRows)
        }
        if s.included[call_index][frame_member] {
          guard s.arguments[call_index][frame_member] is Some(value) else {
            return Err(InvalidRows)
          }
          s.values.push(value)
        }
        s.position += 1
        return Ok(None)
      }
      if !s.charging && !reserve_slots(s.workspace, s.values.length()) {
        return Err(RowLimit)
      }
      match analytic_pay(s, s.values.length()) {
        Err(issue) => return Err(issue)
        Ok(false) => return Ok(None)
        Ok(true) => ()
      }
      s.local_indices = []
      s.call_phase = 2
      Ok(None)
    }
    // Local member coordinates, one per advance.
    2 => {
      if s.local_indices.length() < s.values.length() {
        s.local_indices.push(s.local_indices.length())
        return Ok(None)
      }
      let ordered = match @lower.group_aggregate_function(aggregate) {
        @relation.First
        | @relation.Last
        | @relation.ArrayAgg
        | @relation.StringAgg => true
        _ => false
      }
      if ordered && !reserve_slots(s.workspace, 1) {
        return Err(RowLimit)
      }
      s.direct = Some(
        start_aggregate_direct(
          aggregate,
          { values: s.values, },
          s.local_indices,
          {
            representative: if s.local_indices.is_empty() {
              None
            } else {
              Some(0)
            },
            start: 0,
            end: s.local_indices.length(),
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
          s.control,
          s.workspace,
          s.aggregate_outputs,
          s.identity_limits,
          s.numeric,
          s.step,
          source,
        ),
      )
      s.call_phase = 3
      Ok(None)
    }
    // The frame aggregate itself.
    _ => {
      guard s.direct is Some(direct) else { return Err(InvalidRows) }
      match advance_aggregate_direct(direct) {
        Err(issue) => {
          s.direct = None
          Err(issue)
        }
        Ok(None) => Ok(None)
        Ok(Some(value)) => {
          s.direct = None
          release_slots(s.workspace, s.workspace.live - s.baseline)
          s.evaluated[call_index][source] = Some(value)
          s.values = []
          s.local_indices = []
          analytic_next_call(s, 19)
          Ok(None)
        }
      }
    }
  }
}

///|
fn[T : RelationRows] analytic_advance_output(
  s : AnalyticEvaluation[T],
) -> Result[Array[String]?, RowIssue] {
  let source = s.index
  if source >= s.count {
    s.phase = 22
    return Ok(None)
  }
  let width = s.output_columns.length()
  // Enter the row.
  if s.inner == -1 {
    if !spend_control(s.control, 1) || !reserve_slots(s.workspace, width) {
      return Err(RowLimit)
    }
    s.row = []
    s.row_retained = false
    s.inner = 0
    return Ok(None)
  }
  // One output cell per advance.
  if s.inner < width {
    if !spend_control(s.control, 1) {
      return Err(RowLimit)
    }
    let (generated, index) = s.output_columns[s.inner]
    let value = if !generated {
      IndexedRows::read_cell(s.input, source, index)
    } else {
      let call = @lower.analytic_call_at(s.analytic, index).unwrap()
      match @lower.analytic_call_function(call) {
        PreparedRowNumber =>
          Number(
            (s.position_by_row[source] - s.partition_start[source] + 1).to_double(),
          )
        PreparedRank => Number(s.ranks[source].to_double())
        PreparedDenseRank => Number(s.dense_ranks[source].to_double())
        PreparedLag(_, _)
        | PreparedLead(_, _)
        | PreparedFirstValue(_)
        | PreparedLastValue(_) => {
          let reference = s.references[index][source]
          if reference < 0 {
            Null
          } else {
            s.arguments[index][reference].unwrap()
          }
        }
        PreparedFrameAggregate(_) =>
          match s.evaluated[index][source] {
            Some(value) => value
            None => return Err(InvalidRows)
          }
      }
    }
    s.row.push(value)
    s.inner += 1
    return Ok(None)
  }
  // The output envelope: the row entry, then one cell per advance.
  if s.output_writer is Some(writer) && s.inner < 2 * width + 2 {
    let cell = s.inner - width
    if cell == 0 {
      if s.output_names.length() != s.row.length() ||
        !spend_control(s.control, 1) {
        return Err(AnalyticEnvelope(Measurement))
      }
      @encode.begin_object(writer) catch {
        _ => return Err(AnalyticEnvelope(OutputWireBytes))
      }
    } else if cell <= width {
      match
        analytic_emit_cell(
          s,
          writer,
          s.output_names[cell - 1],
          s.row[cell - 1],
          OutputWireBytes,
        ) {
        Err(issue) => return Err(issue)
        Ok(false) => return Ok(None)
        Ok(true) => ()
      }
    } else {
      @encode.end_object(writer) catch {
        _ => return Err(AnalyticEnvelope(OutputWireBytes))
      }
    }
    s.inner += 1
    return Ok(None)
  }
  if !s.row_retained {
    if s.row_retention is Some(cursor) {
      match advance_stepped_row_retention(cursor) {
        Err(issue) => return Err(issue)
        Ok(false) => return Ok(None)
        Ok(true) => {
          s.row_retention = None
          s.row_retained = true
        }
      }
      return Ok(None)
    }
    if bounded_small_retained_row(s.row, s.output_names) {
      if !retain_row(s.row, s.output_names, s.output) {
        return Err(RowLimit)
      }
      s.row_retained = true
    } else {
      match
        start_stepped_row_retention(
          s.row,
          s.output_names,
          s.output,
          s.workspace,
        ) {
        Err(issue) => return Err(issue)
        Ok(cursor) => s.row_retention = Some(cursor)
      }
      return Ok(None)
    }
  }
  if s.scope is Some(value) {
    match
      row_event_output(value, s.output_names, s.row, [], s.input_roots[source]) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  match (s.accept_row)(s.row, source) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  s.row = []
  s.index += 1
  s.inner = -1
  Ok(None)
}
