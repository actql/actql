///|
priv enum ConditionalRowPhase {
  ReadConditionalCell
  RecheckConditionalValue
  MeasureConditionalName
  MeasureConditionalValue
  SealConditionalRow
}

///|
priv struct ConditionalRowState {
  builder : ConditionalRowBuilder
  mut read : ((Int) -> @admitted.CheckedValue??)?
  workspace : RowWorkspace
  max_work : Int
  mut work : Int
  mut column : Int
  mut pending : @admitted.CheckedValue?
  mut admission : @admitted.RecheckCursor?
  mut measure : SteppedValueMeasure?
  mut phase : ConditionalRowPhase
  mut material : ConditionalRow?
  mut reclaimed : Bool
}

///|
struct ConditionalRowPreparation {
  state : ConditionalRowState
  session : @bounded.Session[
    ConditionalRowState,
    ConditionalRow,
    ConditionalRowIssue,
  ]
  mut token : @bounded.Token
  control : @bounded.Control
  mut accepted : Bool
}

///|
pub enum ConditionalRowPoll {
  ConditionalRowContinue(work~ : Int64)
  ConditionalRowComplete(ConditionalRow, work~ : Int64)
  ConditionalRowFailed(ConditionalRowIssue, work~ : Int64)
  ConditionalRowStopped(work~ : Int64)
}

///|
fn discard_conditional_row_state(state : ConditionalRowState) -> Bool {
  if state.reclaimed {
    return true
  }
  if state.measure is Some(cursor) {
    clear_stepped_measure(cursor)
    state.measure = None
  }
  if state.admission is Some(cursor) {
    @admitted.cancel_recheck_runtime_value(cursor)
    state.admission = None
  }
  state.read = None
  state.pending = None
  state.builder.cells.clear()
  state.builder.open = false
  if state.material is Some(row) {
    row.cells.clear()
    state.material = None
  }
  release_slots(state.workspace, state.workspace.live)
  state.reclaimed = true
  workspace_healthy(state.workspace)
}

///|
fn start_conditional_name_measure(state : ConditionalRowState) -> Bool {
  let field = @schema.presence_field_at(state.builder.schema, state.column).unwrap()
  let cursor : SteppedValueMeasure = {
    frames: [],
    workspace: state.workspace,
    workspace_failed: false,
  }
  if !push_stepped_measure(
      cursor,
      SteppedTextNext(
        @schema.reference_name(@schema.presence_field_name(field)),
        0,
      ),
    ) {
    return false
  }
  state.measure = Some(cursor)
  state.phase = MeasureConditionalName
  true
}

///|
fn advance_conditional_row_state(
  state : ConditionalRowState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[ConditionalRow, ConditionalRowIssue] {
  let mut used = 0
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, used, used)
    }
    if !state.builder.open || state.work >= state.max_work {
      return @bounded.Failed(Limit, used, used)
    }
    state.work += 1
    used += 1
    match state.phase {
      ReadConditionalCell => {
        if state.column == @schema.presence_field_count(state.builder.schema) {
          state.phase = SealConditionalRow
          continue
        }
        if !reserve_slots(state.workspace, 1) ||
          !charge_node(state.builder.budget, 2) {
          return @bounded.Failed(Limit, used, used)
        }
        let field = @schema.presence_field_at(
          state.builder.schema,
          state.column,
        ).unwrap()
        guard state.read is Some(read) && read(state.column) is Some(cell) else {
          return @bounded.Failed(InvalidWidth, used, used)
        }
        match cell {
          None => {
            if @schema.field_presence(field) == @schema.Required {
              return @bounded.Failed(MissingRequired(state.column), used, used)
            }
            state.builder.cells.push(None)
            state.column += 1
          }
          Some(checked) => {
            state.pending = Some(checked)
            if !physical_equal(
                @schema.presence_field_contract(field),
                checked.contract,
              ) {
              let budget = state.builder.budget
              guard @admitted.start_recheck_runtime_value(
                  checked.value,
                  @schema.presence_field_contract(field),
                  {
                    max_nodes: budget.limits.max_nodes - budget.nodes,
                    max_depth: budget.limits.max_depth,
                    max_text_bytes: budget.limits.max_text_bytes - budget.text,
                  },
                )
                is Some(cursor) else {
                return @bounded.Failed(Limit, used, used)
              }
              state.admission = Some(cursor)
              state.phase = RecheckConditionalValue
            } else if !start_conditional_name_measure(state) {
              return @bounded.Failed(Limit, used, used)
            }
          }
        }
      }
      RecheckConditionalValue => {
        let cursor = state.admission.unwrap()
        match @admitted.advance_recheck_runtime_value(cursor) {
          @admitted.RecheckContinue => ()
          @admitted.RecheckFailed =>
            return @bounded.Failed(ForeignValue(state.column), used, used)
          @admitted.RecheckComplete(checked, _, _) => {
            state.admission = None
            state.pending = Some(checked)
            if !start_conditional_name_measure(state) {
              return @bounded.Failed(Limit, used, used)
            }
          }
        }
      }
      MeasureConditionalName | MeasureConditionalValue => {
        let cursor = state.measure.unwrap()
        match advance_stepped_measure_result(cursor, state.builder.budget) {
          SteppedMeasureContinue => ()
          SteppedMeasureLimit | SteppedMeasureWorkspaceLimit =>
            return @bounded.Failed(Limit, used, used)
          SteppedMeasureComplete => {
            state.measure = None
            if state.phase is MeasureConditionalName {
              guard start_stepped_measure_result(
                  Captured(state.pending.unwrap().value),
                  state.workspace,
                )
                is Some(value) else {
                return @bounded.Failed(Limit, used, used)
              }
              state.measure = Some(value)
              state.phase = MeasureConditionalValue
            } else {
              state.builder.cells.push(state.pending)
              state.pending = None
              state.column += 1
              state.phase = ReadConditionalCell
            }
          }
        }
      }
      SealConditionalRow =>
        match finish_conditional_row(state.builder) {
          Ok(row) => {
            state.material = Some(row)
            return @bounded.Complete(row, used, used)
          }
          Err(issue) => return @bounded.Failed(issue, used, used)
        }
    }
  }
  @bounded.Continue(used, used)
}

///|
/// The reader is an installed, constant-time cell lookup over pinned immutable
/// input; it returns Some(None) for an absent conditional field. Start allocates
/// no schema-width array, and every append and nested-value visit is stepped.
pub fn start_conditional_row_preparation(
  schema : @schema.ConditionalSchema,
  limits : ValueLimits,
  max_step_work : Int,
  max_workspace_slots : Int,
  read : (Int) -> @admitted.CheckedValue??,
) -> Result[ConditionalRowPreparation, ConditionalRowIssue] {
  if max_step_work < 0 || max_workspace_slots < 0 {
    return Err(InvalidLimits)
  }
  let builder = match prepare_conditional_row(schema, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let state : ConditionalRowState = {
    builder,
    read: Some(read),
    workspace: row_workspace(max_workspace_slots),
    max_work: max_step_work,
    work: 0,
    column: 0,
    pending: None,
    admission: None,
    measure: None,
    phase: ReadConditionalCell,
    material: None,
    reclaimed: false,
  }
  let control = @bounded.control()
  let (session, token) = @bounded.start(
    control,
    state,
    advance_conditional_row_state,
    discard_conditional_row_state,
    _ => discard_conditional_row_state(state),
  )
  Ok({ state, session, token, control, accepted: false, })
}

///|
pub fn advance_conditional_row_preparation(
  value : ConditionalRowPreparation,
  quantum : Int,
) -> Result[ConditionalRowPoll, @bounded.Issue] {
  match @bounded.advance(value.session, value.token, quantum) {
    Err(issue) => Err(issue)
    Ok(@bounded.ContinueWith(token, work~, ..)) => {
      value.token = token
      Ok(ConditionalRowContinue(work~))
    }
    Ok(@bounded.Completed(row, work~, ..)) => {
      value.accepted = true
      Ok(ConditionalRowComplete(row, work~))
    }
    Ok(@bounded.FailedWith(issue, work~, ..)) =>
      Ok(ConditionalRowFailed(issue, work~))
    Ok(@bounded.StoppedWith(_, work~, ..)) => Ok(ConditionalRowStopped(work~))
  }
}

///|
pub fn cancel_conditional_row_preparation(
  value : ConditionalRowPreparation,
) -> Bool {
  @bounded.request_cancel(value.control)
}

///|
pub fn conditional_row_preparation_value(
  value : ConditionalRowPreparation,
) -> ConditionalRow? {
  if value.state.reclaimed || !value.accepted {
    None
  } else {
    value.state.material
  }
}

///|
pub fn cleanup_conditional_row_preparation(
  value : ConditionalRowPreparation,
) -> Result[Bool, @bounded.Issue] {
  if value.state.reclaimed {
    return Ok(true)
  }
  @bounded.cleanup(value.session)
}
