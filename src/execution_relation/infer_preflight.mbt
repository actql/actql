///|
/// Exact borrowed input for mapped-value preparation. Binding is not authority
/// to call a provider, and does not discharge model adapter preflight.
struct InferRowInput {
  prepared : @lower.PreparedInferInputs
  expected : @lower.BoundPrepared
  target : @pipeline.Target
  source : InferRowSource
}

///|
priv enum InferRowSource {
  CapturedInput(CapturedRows)
  CompletedInput(CompletedOutput)
}

///|
pub(all) enum InferPreparationIssue {
  InvalidLimits
  ForeignInput
  InputUnavailable
  InputRepresentationUnavailable
  ItemLimit
  WorkLimit
  WorkspaceLimit
  ValueLimit
  InvalidKey(Int, Int)
  DuplicateKey(Int, Int)
  InvalidMappedValue(Int, Int)
  Evaluation(Int, Int, EvalIssue)
  Comparison(@admitted.KeyOrderIssue)
  Session(@bounded.Issue)
}

///|
pub(all) struct InferPreparationLimits {
  max_items : Int
  max_work : Int
  max_frames : Int
  max_workspace_slots : Int
  values : @admitted.Limits
}

///|
/// Bind a capture to the exact checked schema and bound invocation. Equal
/// schemas or a second binding of the same preparation cannot substitute.
pub fn bind_infer_captured_input(
  prepared : @lower.PreparedInferInputs,
  expected : @lower.BoundPrepared,
  target : @pipeline.Target,
  rows : CapturedRows,
) -> Result[InferRowInput, InferPreparationIssue] {
  let actual = match rows.origin {
    ValuesNode(index) => @pipeline.Step(index)
    SuppliedInput(index) => @pipeline.Input(index)
  }
  if !physical_equal(rows.owner, expected) ||
    actual != target ||
    !physical_equal(
      rows.schema,
      @evidence.infer_input_schema(@lower.infer_inputs_owner(prepared)),
    ) {
    return Err(ForeignInput)
  }
  Ok({ prepared, expected, target, source: CapturedInput(rows), })
}

///|
pub fn bind_infer_completed_input(
  prepared : @lower.PreparedInferInputs,
  expected : @lower.BoundPrepared,
  target : @pipeline.Target,
  output : CompletedOutput,
) -> Result[InferRowInput, InferPreparationIssue] {
  if !completed_output_available(output) {
    return Err(InputUnavailable)
  }
  if !completed_has_cell_access(output) {
    return Err(InputRepresentationUnavailable)
  }
  guard @lower.preparation_schema_at(
      @lower.bound_preparation(expected),
      output.target,
    )
    is Some(schema) else {
    return Err(ForeignInput)
  }
  if !physical_equal(
      @lower.sequence_owner(output.completion.sequence),
      expected,
    ) ||
    output.target != target ||
    !physical_equal(
      schema,
      @evidence.infer_input_schema(@lower.infer_inputs_owner(prepared)),
    ) {
    return Err(ForeignInput)
  }
  Ok({ prepared, expected, target, source: CompletedInput(output), })
}

///|
fn infer_rows_count(input : InferRowInput) -> Int {
  match input.source {
    CapturedInput(rows) => captured_row_count(rows)
    CompletedInput(output) => completed_row_count(output)
  }
}

///|
fn infer_rows_available(input : InferRowInput) -> Bool {
  match input.source {
    CapturedInput(rows) => physical_equal(rows.owner, input.expected)
    CompletedInput(output) =>
      completed_output_matches_port(output, input.expected, input.target)
  }
}

///|
fn infer_rows_cell(input : InferRowInput, row : Int, column : Int) -> Value? {
  match input.source {
    CapturedInput(rows) => captured_cell(rows, row, column).map(capture)
    CompletedInput(output) => completed_cell(output, row, column)
  }
}

///|
/// Checked mapped values in canonical typed key order. This is neither a
/// dispatch plan nor captured outcomes: no response or authority is invented.
struct PreparedInferRows {
  input : InferRowInput
  keys : Array[Array[@admitted.CheckedValue]]
  order : Array[Int]
  values : Array[Array[@admitted.CheckedValue]]
  workspace : RowWorkspace
  mut reclaimed : Bool
}

///|
pub fn prepared_infer_rows_owner(
  value : PreparedInferRows,
) -> @evidence.CheckedInfer {
  @lower.infer_inputs_owner(value.input.prepared)
}

///|
pub fn prepared_infer_rows_count(value : PreparedInferRows) -> Int {
  value.order.length()
}

///|
pub fn prepared_infer_rows_key(
  value : PreparedInferRows,
  slot : Int,
  component : Int,
) -> @admitted.CheckedValue? {
  if value.reclaimed || !infer_rows_available(value.input) {
    return None
  }
  value.order
  .get(slot)
  .bind(row => value.keys.get(row))
  .bind(key => key.get(component))
}

///|
pub fn prepared_infer_rows_value(
  value : PreparedInferRows,
  slot : Int,
  role : Int,
) -> @admitted.CheckedValue? {
  if value.reclaimed || !infer_rows_available(value.input) {
    return None
  }
  value.values.get(slot).bind(row => row.get(role))
}

///|
pub fn cleanup_prepared_infer_rows(value : PreparedInferRows) -> Bool {
  if !value.reclaimed {
    value.keys.clear()
    value.order.clear()
    value.values.clear()
    release_slots(value.workspace, value.workspace.live)
    value.reclaimed = true
  }
  true
}

///|
priv enum InferPreparationPhase {
  ResolveSourceColumns
  ResolveKeyColumns
  ReadKeys
  InitializeOrder
  StartKeySort
  SortKeys
  CheckDuplicates
  ReadSnapshot
  EvaluateMapping
  ValidateMapping
  FinishRow
  Finished
}

///|
priv struct InferPreparationState {
  input : InferRowInput
  limits : InferPreparationLimits
  control : ControlBudget
  workspace : RowWorkspace
  mut phase : InferPreparationPhase
  key_columns : Array[Int]
  source_columns : Array[Int]
  keys : Array[Array[@admitted.CheckedValue]]
  mut order : Array[Int]
  mut sort : AggregateMergeSort[Int]?
  mut comparison_failure : InferPreparationIssue?
  values : Array[Array[@admitted.CheckedValue]]
  mut row : Int
  mut field : Int
  mut column : Int
  mut component : Int
  mut comparison : @admitted.BoundedKeyComparison?
  mut recheck : @admitted.RecheckCursor?
  mut recheck_slots : Int
  mut value_nodes : Int
  mut value_bytes : Int
  snapshot : Map[String, Value]
  mut frame : ExpressionFrame?
  mut snapshot_slots : Int
  mut mapped : Array[@admitted.CheckedValue]
  name_charge : BoundedTextCharge
  mut snapshot_charged : Bool
  mut transferred : Bool
}

///|
struct InferRowsPreparation {
  state : InferPreparationState
  session : @bounded.Session[
    InferPreparationState,
    PreparedInferRows,
    InferPreparationIssue,
  ]
  mut token : @bounded.Token
}

///|
pub enum InferRowsPreparationPoll {
  InferRowsContinue(work~ : Int64)
  InferRowsComplete(PreparedInferRows, work~ : Int64)
  InferRowsStopped(@bounded.StopReason, work~ : Int64)
}

///|
/// Small start only. Key scanning, sorting, validation, snapshots and INPUT
/// evaluation all take place in resume, before any model call can be planned.
pub fn start_infer_rows_preparation(
  control : @bounded.Control,
  input : InferRowInput,
  limits : InferPreparationLimits,
) -> Result[InferRowsPreparation, InferPreparationIssue] {
  if limits.max_items < 0 ||
    limits.max_work < 0 ||
    limits.max_frames < 0 ||
    limits.max_workspace_slots < 0 ||
    limits.values.max_nodes < 0 ||
    limits.values.max_text_bytes < 0 ||
    limits.values.max_depth < 0 {
    return Err(InvalidLimits)
  }
  if !infer_rows_available(input) {
    return Err(InputUnavailable)
  }
  // This is a preparation ceiling, not the final Contract/Host/author limit.
  if infer_rows_count(input) > limits.max_items {
    return Err(ItemLimit)
  }
  let state : InferPreparationState = {
    input,
    limits,
    control: { remaining: limits.max_work, max_frames: limits.max_frames, },
    workspace: row_workspace(limits.max_workspace_slots),
    phase: ResolveSourceColumns,
    source_columns: [],
    key_columns: [],
    keys: [],
    order: [],
    values: [],
    sort: None,
    comparison_failure: None,
    row: 0,
    field: 0,
    column: 0,
    component: 0,
    comparison: None,
    recheck: None,
    recheck_slots: 0,
    value_nodes: limits.values.max_nodes,
    value_bytes: limits.values.max_text_bytes,
    snapshot: Map([]),
    frame: None,
    snapshot_slots: 0,
    mapped: [],
    name_charge: { offset: 0, next: 0, remaining: 0, },
    snapshot_charged: false,
    transferred: false,
  }
  let (session, token) = @bounded.start(
    control, state, infer_preparation_advance, infer_preparation_cleanup, cleanup_prepared_infer_rows,
  )
  Ok({ state, session, token, })
}

///|
fn infer_preparation_cleanup(state : InferPreparationState) -> Bool {
  if state.frame is Some(frame) && !frame.closed {
    close_expression_frame(frame)
  }
  state.frame = None
  if state.recheck is Some(cursor) {
    @admitted.cancel_recheck_runtime_value(cursor)
  }
  state.recheck = None
  state.comparison = None
  state.snapshot.clear()
  state.mapped.clear()
  if state.sort is Some(sort) {
    close_aggregate_merge_sort(sort)
  }
  state.sort = None
  state.key_columns.clear()
  state.source_columns.clear()
  if !state.transferred {
    state.keys.clear()
    state.order.clear()
    state.values.clear()
    release_slots(state.workspace, state.workspace.live)
  }
  true
}

///|
fn infer_preparation_reserve(
  state : InferPreparationState,
  size : Int,
) -> Result[Unit, InferPreparationIssue] {
  if reserve_slots(state.workspace, size) {
    Ok(())
  } else {
    Err(WorkspaceLimit)
  }
}

///|
// This converts representation, not admission. The caller must subsequently
// use the exact receiving contract's resumable runtime recheck.
fn infer_preparation_value(value : Value, max_text : Int) -> @admitted.Value? {
  match value {
    Captured(value) => Some(value)
    Text(value) => @admitted.text_value(value, max_text)
    Null => Some(@admitted.null_value())
    Number(value) => @admitted.number_value(value)
    Boolean(value) => Some(@admitted.boolean_value(value))
  }
}

///|
fn infer_preparation_start_recheck(
  state : InferPreparationState,
  value : @admitted.Value,
  contract : @contract.Contract,
) -> Result[Unit, InferPreparationIssue] {
  if state.value_nodes == 0 {
    return Err(ValueLimit)
  }
  // A node cursor and at most two frames per container depth coexist. Reserve
  // their finite upper bound before constructing the shared recheck cursor.
  let slots = match contract.shape {
    @contract.Array(_, ..) | @contract.Object(_) | @contract.Json => {
      let depth = Int::min(
        Int::min(state.limits.values.max_depth, state.value_nodes),
        1073741822,
      )
      depth * 2 + 3
    }
    _ => 1
  }
  match infer_preparation_reserve(state, slots) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard @admitted.start_recheck_runtime_value(value, contract, {
      max_nodes: state.value_nodes,
      max_text_bytes: state.value_bytes,
      max_depth: state.limits.values.max_depth,
    })
    is Some(cursor) else {
    release_slots(state.workspace, slots)
    return Err(ValueLimit)
  }
  state.recheck = Some(cursor)
  state.recheck_slots = slots
  Ok(())
}

///|
fn infer_preparation_compare(
  state : InferPreparationState,
  left : Int,
  right : Int,
) -> Result[Int?, InferPreparationIssue] {
  let count = @evidence.infer_key_count(
    @lower.infer_inputs_owner(state.input.prepared),
  )
  if state.component == count {
    state.component = 0
    return Ok(Some(0))
  }
  if state.comparison is None {
    state.comparison = Some(
      match
        @admitted.start_bounded_key_comparison(
          state.keys[left][state.component],
          state.keys[right][state.component],
        ) {
        Ok(cursor) => cursor
        Err(issue) => return Err(Comparison(issue))
      },
    )
    return Ok(None)
  }
  match @admitted.advance_bounded_key_comparison(state.comparison.unwrap(), 1) {
    Err(issue) => Err(Comparison(issue))
    Ok(KeyComparisonContinue(..)) => Ok(None)
    Ok(KeyComparisonComplete(order~, ..)) => {
      state.comparison = None
      if order == 0 {
        state.component += 1
        Ok(None)
      } else {
        state.component = 0
        Ok(Some(order))
      }
    }
  }
}

///|
fn infer_preparation_step(
  state : InferPreparationState,
) -> Result[Bool, InferPreparationIssue] {
  if !infer_rows_available(state.input) {
    return Err(InputUnavailable)
  }
  if !spend_control(state.control, 1) {
    return Err(WorkLimit)
  }
  let owner = @lower.infer_inputs_owner(state.input.prepared)
  let schema = @evidence.infer_input_schema(owner)
  let count = infer_rows_count(state.input)
  match state.phase {
    ResolveSourceColumns =>
      if state.field == @schema.field_count(schema) {
        state.field = 0
        state.column = 0
        state.phase = ResolveKeyColumns
      } else {
        let expected = @schema.reference_name(
          @schema.field_at(schema, state.field).unwrap().name,
        )
        let position = match state.input.source {
          CapturedInput(_) => Some(state.field)
          CompletedInput(output) => {
            if state.column >= completed_column_count(output) {
              return Err(ForeignInput)
            }
            if completed_column_name(output, state.column) == Some(expected) {
              Some(state.column)
            } else {
              state.column += 1
              None
            }
          }
        }
        if position is Some(index) {
          match infer_preparation_reserve(state, 1) {
            Err(e) => return Err(e)
            Ok(_) => ()
          }
          state.source_columns.push(index)
          state.field += 1
          state.column = 0
        }
      }
    ResolveKeyColumns =>
      if state.field == @evidence.infer_key_count(owner) {
        state.field = 0
        state.column = 0
        state.phase = ReadKeys
      } else if state.column == @schema.field_count(schema) {
        return Err(ForeignInput)
      } else {
        let key = @evidence.infer_key_at(owner, state.field).unwrap()
        if @schema.field_at(schema, state.column).unwrap().name == key.field {
          match infer_preparation_reserve(state, 1) {
            Err(e) => return Err(e)
            Ok(_) => ()
          }
          state.key_columns.push(state.column)
          state.field += 1
          state.column = 0
        } else {
          state.column += 1
        }
      }
    ReadKeys =>
      if state.row == count {
        state.row = 0
        state.phase = InitializeOrder
      } else if state.keys.length() == state.row {
        match infer_preparation_reserve(state, 1) {
          Err(e) => return Err(e)
          Ok(_) => ()
        }
        state.keys.push([])
      } else if state.field == state.key_columns.length() {
        state.row += 1
        state.field = 0
      } else if state.recheck is None {
        guard infer_rows_cell(
            state.input,
            state.row,
            state.source_columns[state.key_columns[state.field]],
          )
          is Some(value) else {
          return Err(InputUnavailable)
        }
        guard infer_preparation_value(value, state.value_bytes) is Some(value) else {
          return Err(ValueLimit)
        }
        let contract = @evidence.infer_key_at(owner, state.field).unwrap().contract
        match infer_preparation_start_recheck(state, value, contract) {
          Err(issue) => return Err(issue)
          Ok(_) => ()
        }
      } else {
        match @admitted.advance_recheck_runtime_value(state.recheck.unwrap()) {
          RecheckContinue => ()
          RecheckFailed => return Err(InvalidKey(state.row, state.field))
          RecheckComplete(value, nodes, bytes) => {
            release_slots(state.workspace, state.recheck_slots)
            state.recheck_slots = 0
            match infer_preparation_reserve(state, 1) {
              Err(e) => return Err(e)
              Ok(_) => ()
            }
            state.value_nodes -= nodes
            state.value_bytes -= bytes
            state.keys[state.row].push(value)
            state.recheck = None
            state.field += 1
          }
        }
      }
    InitializeOrder =>
      if state.row == count {
        state.row = 0
        state.phase = StartKeySort
      } else {
        match infer_preparation_reserve(state, 1) {
          Err(e) => return Err(e)
          Ok(_) => ()
        }
        state.order.push(state.row)
        state.row += 1
      }
    StartKeySort => {
      if count > (state.workspace.limit - state.workspace.live) / 2 {
        return Err(WorkspaceLimit)
      }
      match infer_preparation_reserve(state, count * 2) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
      state.sort = Some(
        start_aggregate_merge_sort(state.order, (left, right) => {
          match infer_preparation_compare(state, left, right) {
            Ok(order) => Ok(order)
            Err(issue) => {
              state.comparison_failure = Some(issue)
              Err(InvalidRows)
            }
          }
        }),
      )
      state.order = []
      state.phase = SortKeys
    }
    SortKeys => {
      let sort = state.sort.unwrap()
      match advance_aggregate_merge_sort(sort) {
        Err(_) => return Err(state.comparison_failure.unwrap_or(ForeignInput))
        Ok(None) => ()
        Ok(Some(order)) => {
          state.order = order
          close_aggregate_merge_sort(sort)
          state.sort = None
          release_slots(state.workspace, count * 2)
          state.row = 1
          state.phase = CheckDuplicates
        }
      }
    }
    CheckDuplicates =>
      if state.row >= count {
        state.row = 0
        state.column = 0
        state.phase = ReadSnapshot
      } else {
        match
          infer_preparation_compare(
            state,
            state.order[state.row - 1],
            state.order[state.row],
          ) {
          Err(e) => return Err(e)
          Ok(None) => ()
          Ok(Some(0)) =>
            return Err(
              DuplicateKey(state.order[state.row - 1], state.order[state.row]),
            )
          Ok(Some(_)) => state.row += 1
        }
      }
    ReadSnapshot => {
      if state.row == count {
        state.phase = Finished
        return Ok(true)
      }
      if state.column == @schema.field_count(schema) {
        state.field = 0
        state.phase = EvaluateMapping
      } else {
        let name = @schema.reference_name(
          @schema.field_at(schema, state.column).unwrap().name,
        )
        if !state.snapshot_charged {
          state.snapshot_charged = true
        } else {
          match
            advance_bounded_text_charge(state.name_charge, state.control, name) {
            Err(_) => return Err(WorkLimit)
            Ok(false) => return Ok(false)
            Ok(true) => ()
          }
          guard infer_rows_cell(
              state.input,
              state.order[state.row],
              state.source_columns[state.column],
            )
            is Some(value) else {
            return Err(InputUnavailable)
          }
          match infer_preparation_reserve(state, 1) {
            Err(e) => return Err(e)
            Ok(_) => ()
          }
          state.snapshot_slots += 1
          state.snapshot[name] = value
          state.column += 1
          state.snapshot_charged = false
          reset_bounded_text_charge(state.name_charge)
        }
      }
    }
    EvaluateMapping =>
      if state.field == @lower.infer_input_count(state.input.prepared) {
        state.phase = FinishRow
      } else if state.frame is None {
        let expression = @lower.infer_input_expression_at(
          state.input.prepared,
          state.field,
        ).unwrap()
        state.frame = Some(
          match
            expression_frame(
              expression,
              state.snapshot,
              [],
              state.control,
              state.workspace,
              None,
            ) {
            Ok(frame) => frame
            Err(issue) => return Err(Evaluation(state.row, state.field, issue))
          },
        )
      } else {
        match advance_expression_frame(state.frame.unwrap()) {
          Err(issue) => return Err(Evaluation(state.row, state.field, issue))
          Ok(None) => ()
          Ok(Some(result)) => {
            guard infer_preparation_value(result.value, state.value_bytes)
              is Some(value) else {
              return Err(ValueLimit)
            }
            let binding = @evidence.infer_input_binding_at(owner, state.field).unwrap()
            guard @model_environment.model_task_input(
                @evidence.infer_model_task(owner),
              ).shape
              is @contract.Object(fields) &&
              @contract.field_at(fields, state.field) is Some(field) &&
              field.name == binding.role else {
              return Err(ForeignInput)
            }
            match
              infer_preparation_start_recheck(state, value, field.contract) {
              Err(issue) => return Err(issue)
              Ok(_) => ()
            }
            state.phase = ValidateMapping
          }
        }
      }
    ValidateMapping =>
      match @admitted.advance_recheck_runtime_value(state.recheck.unwrap()) {
        RecheckContinue => ()
        RecheckFailed => return Err(InvalidMappedValue(state.row, state.field))
        RecheckComplete(value, nodes, bytes) => {
          release_slots(state.workspace, state.recheck_slots)
          state.recheck_slots = 0
          state.value_nodes -= nodes
          state.value_bytes -= bytes
          state.recheck = None
          close_expression_frame(state.frame.unwrap())
          state.frame = None
          match infer_preparation_reserve(state, 1) {
            Err(e) => return Err(e)
            Ok(_) => ()
          }
          state.mapped.push(value)
          state.field += 1
          state.phase = EvaluateMapping
        }
      }
    FinishRow => {
      match infer_preparation_reserve(state, 1) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
      state.values.push(state.mapped)
      state.mapped = []
      state.snapshot.clear()
      release_slots(state.workspace, state.snapshot_slots)
      state.snapshot_slots = 0
      state.row += 1
      state.column = 0
      state.phase = ReadSnapshot
    }
    Finished => return Ok(true)
  }
  Ok(false)
}

///|
fn infer_preparation_advance(
  state : InferPreparationState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[PreparedInferRows, InferPreparationIssue] {
  let mut work = 0
  while work < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return Stopped(reason, work, work)
    }
    work += 1
    match infer_preparation_step(state) {
      Err(issue) => return Failed(issue, work, work)
      Ok(false) => ()
      Ok(true) => {
        release_slots(state.workspace, state.key_columns.length())
        release_slots(state.workspace, state.source_columns.length())
        state.key_columns.clear()
        state.source_columns.clear()
        state.transferred = true
        return Complete(
          {
            input: state.input,
            keys: state.keys,
            order: state.order,
            values: state.values,
            workspace: state.workspace,
            reclaimed: false,
          },
          work,
          work,
        )
      }
    }
  }
  Continue(work, work)
}

///|
pub fn advance_infer_rows_preparation(
  value : InferRowsPreparation,
  quantum : Int,
) -> Result[InferRowsPreparationPoll, InferPreparationIssue] {
  match @bounded.advance(value.session, value.token, quantum) {
    Err(issue) => Err(Session(issue))
    Ok(ContinueWith(token, work~, ..)) => {
      value.token = token
      Ok(InferRowsContinue(work~))
    }
    Ok(Completed(rows, work~, ..)) => Ok(InferRowsComplete(rows, work~))
    Ok(FailedWith(issue, ..)) => Err(issue)
    Ok(StoppedWith(reason, work~, ..)) => Ok(InferRowsStopped(reason, work~))
  }
}

///|
pub fn cleanup_infer_rows_preparation(
  value : InferRowsPreparation,
) -> Result[Bool, InferPreparationIssue] {
  @bounded.cleanup(value.session).map_err(issue => Session(issue))
}

///|
pub fn infer_rows_preparation_stopped(value : InferRowsPreparation) -> Bool {
  @bounded.session_stopped(value.session)
}

///|
pub fn infer_rows_preparation_usage(
  value : InferRowsPreparation,
) -> (Int, Int, Int) {
  (
    value.state.limits.max_work - value.state.control.remaining,
    value.state.workspace.live,
    value.state.workspace.peak,
  )
}
