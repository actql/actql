///|
priv enum RowsToEventsPhase {
  BeginRow
  ReadCell
  RecheckCell
  CommitRow
  AppendRow
  FinishRows
}

///|
priv struct RowsToEventsState {
  input : @execution.ProducerRead
  mut output : @records.OutputBuilder?
  schema : @schema.Schema
  value_limits : @value.Limits
  max_workspace_slots : Int
  mut phase : RowsToEventsPhase
  mut row : Int
  mut column : Int
  mut fields : Array[(@schema.FieldName, @value.CheckedValue)]
  mut recheck : @value.RecheckCursor?
  mut append : @records.RecordAppend?
}

///|
struct RowsToEventsExecution {
  session : @bounded.Session[
    RowsToEventsState,
    @records.Completed,
    EventsBridgeIssue,
  ]
  mut token : @bounded.Token?
}

///|
pub enum RowsToEventsPoll {
  Continue(progress~ : Int64, work~ : Int64)
  Complete(@records.Completed, progress~ : Int64, work~ : Int64)
  Failed(EventsBridgeIssue, progress~ : Int64, work~ : Int64)
  Stopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
priv enum EventsToRowsPhase {
  InitializeGraphOrder
  SortGraphOrder
  BeginRecord
  InitializeRecordCells
  ScanFields
  MatchRecordName
  MatchGraphField
  RecheckGraphField
  VerifyFields
  CommitRelationRow
  AppendRelationRow
  FinishRelation
}

///|
priv enum EventsToRowsSource {
  Stored(@storage.Storage)
  Viewed(@lifecycle.ProducerView)
  GraphRows(GraphRowsSource)
}

///|
priv struct EventsToRowsState {
  available : () -> Bool
  mut owned : @records.Completed?
  source : EventsToRowsSource
  mut output : @execution.AdmittedOutput?
  rows : Ref[@execution.AdmittedOutputRows?]
  live : Ref[Bool]
  accepted : Ref[Bool]
  port : @execution.TrustedOutputPort[Unit]
  schema : @schema.Schema
  value_limits : @execution.ValueLimits
  mut phase : EventsToRowsPhase
  mut record : Int
  mut source_field : Int
  mut verified_column : Int
  mut matched_count : Int
  mut control_work_remaining : Int?
  mut pending_graph_field : (@schema.FieldName, @value.Value)?
  mut graph_column : Int
  mut graph_recheck : @value.RecheckCursor?
  mut record_cells : Array[@value.CheckedValue?]
  mut record_field : (@schema.FieldName, @value.CheckedValue)?
  mut match_low : Int
  mut match_high : Int
  mut name_offset : Int
  row_workspace : Int
  mut output_row : @execution.AdmittedOutputRowCursor?
}

///|
fn events_source_record_count(source : EventsToRowsSource) -> Int? {
  match source {
    Stored(storage) => Some(@storage.record_count(storage))
    Viewed(view) => @lifecycle.producer_view_record_count(view)
    GraphRows(source) => graph_rows_count(source)
  }
}

///|
fn events_source_field_count(source : EventsToRowsSource, record : Int) -> Int? {
  match source {
    Stored(storage) => @storage.record_field_count(storage, record)
    Viewed(view) =>
      match @lifecycle.producer_view_record_field_count(view, record) {
        Ok(value) => Some(value)
        Err(_) => None
      }
    GraphRows(source) => graph_rows_field_count(source, record)
  }
}

///|
fn events_source_field(
  source : EventsToRowsSource,
  record : Int,
  field : Int,
) -> (@schema.FieldName, @value.CheckedValue)? {
  match source {
    Stored(storage) => @storage.record_field_at(storage, record, field)
    Viewed(view) =>
      match @lifecycle.producer_view_record_field(view, record, field) {
        Ok(value) => Some(value)
        Err(_) => None
      }
    GraphRows(_) => None
  }
}

///|
struct EventsToRowsExecution {
  session : @bounded.Session[
    EventsToRowsState,
    @execution.CompletedOutput,
    EventsBridgeIssue,
  ]
  mut token : @bounded.Token?
  accepted : Ref[Bool]
}

///|
pub enum EventsToRowsPoll {
  Continue(progress~ : Int64, work~ : Int64)
  Complete(@execution.CompletedOutput, progress~ : Int64, work~ : Int64)
  Failed(EventsBridgeIssue, progress~ : Int64, work~ : Int64)
  Stopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
pub(all) enum EventsBridgeIssue {
  InvalidKernel
  ControlWorkLimit
  InputUnavailable
  InvalidRow(Int)
  InvalidRecord(Int)
  Output(@records.Issue)
  RelationOutput(@execution.CaptureIssue)
  Completion(@execution.TrustedOutputIssue)
  Execution(@bounded.Issue)
  Presence(@execution.RelationPresenceIssue)
  GraphOrder(@sort.Issue)
} derive(Eq, Debug)

///|
fn rows_to_events_step(
  state : RowsToEventsState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[@records.Completed, EventsBridgeIssue] {
  let mut used = 0
  let mut progress = 0
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    if !@execution.producer_read_available(state.input) {
      return @bounded.Failed(InputUnavailable, progress, used)
    }
    match state.phase {
      BeginRow =>
        if state.row < @execution.producer_read_row_count(state.input) {
          state.column = 0
          state.fields = []
          state.phase = ReadCell
        } else {
          state.phase = FinishRows
        }
      ReadCell =>
        if state.column < @schema.field_count(state.schema) {
          guard state.output is Some(output) else {
            return @bounded.Failed(InvalidKernel, progress, used)
          }
          let retained = @records.output_workspace_slots(output)
          // One borrowed root, the recheck handle, and at most depth+1
          // traversal frames overlap the pending field snapshot.
          let depth = state.value_limits.max_depth
          if depth > 2147483644 ||
            retained > state.max_workspace_slots ||
            depth + 3 > state.max_workspace_slots - retained ||
            state.fields.length() >
            state.max_workspace_slots - retained - depth - 3 {
            return @bounded.Failed(
              Output(@records.Storage(@storage.WorkspaceLimit)),
              progress,
              used,
            )
          }
          guard @schema.field_at(state.schema, state.column) is Some(field) &&
            @execution.producer_read_cell(state.input, state.row, state.column)
            is Some(cell) else {
            return @bounded.Failed(InvalidRow(state.row), progress, used)
          }
          used += 1
          // Reuse the exact receiving contract without validating raw Text
          // before the first caller-controlled yield/stop boundary.
          let recheck = match cell {
            @execution.Text(text) =>
              @value.start_recheck_runtime_text(
                text,
                field.contract,
                state.value_limits,
              )
            _ => {
              let raw = match cell {
                @execution.Null => Some(@value.null_value())
                @execution.Number(number) => @value.number_value(number)
                @execution.Boolean(boolean) =>
                  Some(@value.boolean_value(boolean))
                @execution.Captured(value) => Some(value)
                @execution.Text(_) => None
              }
              raw.bind(value => {
                @value.start_recheck_runtime_value(
                  value,
                  field.contract,
                  state.value_limits,
                )
              })
            }
          }
          guard recheck is Some(recheck) else {
            return @bounded.Failed(InvalidRow(state.row), progress, used)
          }
          state.recheck = Some(recheck)
          state.phase = RecheckCell
        } else {
          state.phase = CommitRow
        }
      RecheckCell => {
        guard state.recheck is Some(recheck) else {
          return @bounded.Failed(InvalidKernel, progress, used)
        }
        used += 1
        match @value.advance_recheck_runtime_value(recheck) {
          @value.RecheckContinue => ()
          @value.RecheckFailed =>
            return @bounded.Failed(InvalidRow(state.row), progress, used)
          @value.RecheckComplete(checked, _, _) => {
            let field = @schema.field_at(state.schema, state.column).unwrap()
            state.fields.push((field.name, checked))
            state.recheck = None
            state.column += 1
            state.phase = ReadCell
          }
        }
      }
      CommitRow => {
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidKernel, progress, used)
        }
        used += 1
        match
          @records.start_record_append(
            output,
            state.fields,
            external_workspace_slots=state.fields.length() + 2,
          ) {
          Err(issue) => return @bounded.Failed(Output(issue), progress, used)
          Ok(append) => {
            state.append = Some(append)
            state.phase = AppendRow
          }
        }
      }
      AppendRow => {
        guard state.append is Some(append) else {
          return @bounded.Failed(InvalidKernel, progress, used)
        }
        used += 1
        match @records.advance_record_append(append) {
          Ok(false) => ()
          Ok(true) => {
            state.append = None
            state.fields = []
            state.row += 1
            state.phase = BeginRow
            progress += 1
          }
          Err(issue) => return @bounded.Failed(Output(issue), progress, used)
        }
      }
      FinishRows => {
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidKernel, progress, used)
        }
        state.output = None
        return match @records.finish_output(output) {
          Ok(completed) => @bounded.Complete(completed, progress, used)
          Err(issue) => @bounded.Failed(Output(issue), progress, used)
        }
      }
    }
  }
  @bounded.Continue(progress, used)
}

///|
fn cleanup_rows_to_events_state(state : RowsToEventsState) -> Bool {
  if state.recheck is Some(recheck) {
    @value.cancel_recheck_runtime_value(recheck)
    state.recheck = None
  }
  if state.append is Some(append) {
    @records.cleanup_record_append(append) |> ignore
    state.append = None
  }
  if state.output is Some(output) {
    @records.cancel_output(output) |> ignore
    state.output = None
  }
  state.fields = []
  true
}

///|
fn start_rows_to_records(
  control : @bounded.Control,
  sequence : @lower.PreparedSequence,
  step : Int,
  input : @execution.ProducerRead,
  limits : @storage.Limits,
  storage_bytes : Int64,
  available : () -> Bool,
  accepts : (@lower.PreparedStep, @lower.PreparedNode) -> Bool,
) -> Result[RowsToEventsExecution, EventsBridgeIssue] {
  let owner = @lower.sequence_owner(sequence)
  guard @lower.sequence_step(sequence, step) is Some(prepared) &&
    @lower.node_at(@lower.bound_preparation(owner), step) is Some(node) &&
    accepts(prepared, node) &&
    @execution.producer_read_matches_operation_input(input, owner, step, 0) else {
    return Err(InvalidKernel)
  }
  let schema = @execution.producer_read_schema(input)
  let output = match
    @records.prepare_output(
      owner,
      @pipeline.Step(step),
      limits,
      storage_bytes,
      available,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Output(issue))
  }
  let state : RowsToEventsState = {
    input,
    output: Some(output),
    schema,
    value_limits: {
      max_nodes: limits.max_value_nodes,
      max_depth: limits.max_value_depth,
      max_text_bytes: limits.max_value_bytes,
    },
    max_workspace_slots: limits.max_workspace_slots,
    phase: BeginRow,
    row: 0,
    column: 0,
    fields: [],
    recheck: None,
    append: None,
  }
  let (session, token) = @bounded.start(
    control, state, rows_to_events_step, cleanup_rows_to_events_state, @records.discard_completed,
  )
  Ok({ session, token: Some(token), })
}

///|
pub fn start_rows_to_events(
  control : @bounded.Control,
  sequence : @lower.PreparedSequence,
  step : Int,
  input : @execution.ProducerRead,
  limits : @storage.Limits,
  storage_bytes : Int64,
  available : () -> Bool,
) -> Result[RowsToEventsExecution, EventsBridgeIssue] {
  start_rows_to_records(
    control,
    sequence,
    step,
    input,
    limits,
    storage_bytes,
    available,
    fn(prepared, node) {
      match prepared {
        @lower.EventStep(event) =>
          @lower.operation(node) == "BRIDGE.rows.to_events" &&
          @carrier.kind(@lower.event_output_carrier(event)) ==
          @carrier.EventsKind
        _ => false
      }
    },
  )
}

///|
pub fn advance_rows_to_events(
  value : RowsToEventsExecution,
  quantum : Int,
) -> Result[RowsToEventsPoll, EventsBridgeIssue] {
  guard value.token is Some(token) else {
    return Err(Execution(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(Execution(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(Continue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      Ok(Complete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(Failed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(Stopped(reason, progress~, work~))
    }
  }
}

///|
pub fn cleanup_rows_to_events(
  value : RowsToEventsExecution,
) -> Result[Bool, EventsBridgeIssue] {
  @bounded.cleanup(value.session).map_err(issue => Execution(issue))
}

///|
pub fn rows_to_events_cleanup_pending(value : RowsToEventsExecution) -> Bool {
  @bounded.cleanup_pending(value.session)
}

///|
fn events_to_rows_step(
  state : EventsToRowsState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[@execution.CompletedOutput, EventsBridgeIssue] {
  let mut used = 0
  let mut progress = 0
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    if !(state.available)() {
      return @bounded.Failed(InputUnavailable, progress, used)
    }
    match state.phase {
      InitializeGraphOrder => {
        guard state.source is GraphRows(source) &&
          graph_rows_count(source) is Some(count) else {
          return @bounded.Failed(InputUnavailable, progress, used)
        }
        if state.record < count {
          if !charge_events_to_rows_work(state) {
            return @bounded.Failed(ControlWorkLimit, progress, used)
          }
          guard graph_rows_order_key(source, state.record) is Some(key) else {
            return @bounded.Failed(InvalidRecord(state.record), progress, used)
          }
          source.order_keys.push([key])
          state.record += 1
          used += 1
        } else {
          source.order = match
            @sort.prepare(source.order_keys, source.order_slots) {
            Ok(sort) => Some(sort)
            Err(issue) =>
              return @bounded.Failed(GraphOrder(issue), progress, used)
          }
          state.record = 0
          state.phase = SortGraphOrder
        }
      }
      SortGraphOrder => {
        guard state.source is GraphRows(source) && source.order is Some(sort) else {
          return @bounded.Failed(InvalidKernel, progress, used)
        }
        if state.control_work_remaining is Some(remaining) && remaining == 0 {
          return @bounded.Failed(ControlWorkLimit, progress, used)
        }
        let (finished, work) = match @sort.advance(sort, 1) {
          Err(issue) =>
            return @bounded.Failed(GraphOrder(issue), progress, used)
          Ok(@sort.Continue(work~, ..)) => (false, work)
          Ok(@sort.Complete(work~, ..)) => (true, work)
        }
        if work != 0L {
          if work != 1L || !charge_events_to_rows_work(state) {
            return @bounded.Failed(ControlWorkLimit, progress, used)
          }
          used += 1
        }
        if finished {
          state.phase = BeginRecord
        }
      }
      BeginRecord =>
        if events_source_record_count(state.source) is Some(count) &&
          state.record < count {
          if state.source is GraphRows(source) &&
            (
              source.selected_definition is Some(_) ||
              source.selected_label is Some(_)
            ) {
            if !charge_events_to_rows_work(state) {
              return @bounded.Failed(ControlWorkLimit, progress, used)
            }
            used += 1
            match graph_row_selected(source, state.record) {
              None => return @bounded.Failed(InputUnavailable, progress, used)
              Some(PendingSelection) => continue
              Some(SkipRow) => {
                state.record += 1
                continue
              }
              Some(SelectedRow) => ()
            }
          }
          state.source_field = 0
          state.verified_column = 0
          state.matched_count = 0
          state.record_cells = []
          state.phase = InitializeRecordCells
        } else {
          state.phase = FinishRelation
        }
      InitializeRecordCells =>
        if state.record_cells.length() < @schema.field_count(state.schema) {
          if !charge_events_to_rows_work(state) {
            return @bounded.Failed(ControlWorkLimit, progress, used)
          }
          used += 1
          state.record_cells.push(None)
        } else {
          state.phase = ScanFields
        }
      ScanFields => {
        guard events_source_field_count(state.source, state.record)
          is Some(width) else {
          return @bounded.Failed(InvalidRecord(state.record), progress, used)
        }
        if state.matched_count == @schema.field_count(state.schema) {
          state.phase = VerifyFields
        } else if state.source_field < width {
          if !charge_events_to_rows_work(state) {
            return @bounded.Failed(ControlWorkLimit, progress, used)
          }
          used += 1
          match state.source {
            GraphRows(source) =>
              match graph_rows_field(source, state.record, state.source_field) {
                Ok(PendingField) => continue
                Ok(AbsentField) => ()
                Ok(GraphField(name, value)) => {
                  state.pending_graph_field = Some((name, value))
                  state.graph_column = 0
                  state.name_offset = 0
                  state.source_field += 1
                  state.phase = MatchGraphField
                  continue
                }
                Err(issue) => return @bounded.Failed(issue, progress, used)
              }
            _ => {
              guard events_source_field(
                  state.source,
                  state.record,
                  state.source_field,
                )
                is Some((name, checked)) else {
                return @bounded.Failed(
                  InvalidRecord(state.record),
                  progress,
                  used,
                )
              }
              state.record_field = Some((name, checked))
              state.match_low = 0
              state.match_high = @schema.field_count(state.schema)
              state.name_offset = 0
              state.phase = MatchRecordName
            }
          }
          state.source_field += 1
        } else {
          state.phase = VerifyFields
        }
      }
      MatchRecordName => {
        guard state.record_field is Some((name, checked)) else {
          return @bounded.Failed(InvalidKernel, progress, used)
        }
        if state.match_low >= state.match_high {
          state.record_field = None
          state.phase = ScanFields
          continue
        }
        if !charge_events_to_rows_work(state) {
          return @bounded.Failed(ControlWorkLimit, progress, used)
        }
        used += 1
        let column = state.match_low + (state.match_high - state.match_low) / 2
        let expected = @schema.field_at(state.schema, column).unwrap()
        let (comparison, offset, _) = @schema.compare_reference_fragment(
          expected.name,
          name,
          state.name_offset,
          64,
        )
        state.name_offset = offset
        match comparison {
          None => ()
          Some(0) => {
            if state.record_cells[column] is None {
              if !physical_equal(expected.contract, checked.contract) {
                return @bounded.Failed(
                  InvalidRecord(state.record),
                  progress,
                  used,
                )
              }
              state.record_cells[column] = Some(checked)
              state.matched_count += 1
            }
            state.record_field = None
            state.phase = ScanFields
          }
          Some(order) =>
            if order < 0 {
              state.match_low = column + 1
            } else {
              state.match_high = column
            }
        }
      }
      MatchGraphField => {
        guard state.pending_graph_field is Some((name, raw)) &&
          @schema.field_at(state.schema, state.graph_column) is Some(expected) else {
          return @bounded.Failed(InvalidRecord(state.record), progress, used)
        }
        if !charge_events_to_rows_work(state) {
          return @bounded.Failed(ControlWorkLimit, progress, used)
        }
        used += 1
        guard name is @schema.Unqualified(actual_name) &&
          expected.name is @schema.Unqualified(expected_name) else {
          return @bounded.Failed(InvalidRecord(state.record), progress, used)
        }
        let (comparison, offset, _) = @carrier.compare_property_name_fragment(
          actual_name,
          expected_name,
          state.name_offset,
          64,
        )
        state.name_offset = offset
        if comparison is None {
          continue
        }
        if comparison == Some(0) {
          guard @value.start_recheck_runtime_value(raw, expected.contract, {
              max_nodes: state.value_limits.max_nodes,
              max_text_bytes: state.value_limits.max_text_bytes,
              max_depth: state.value_limits.max_depth,
            })
            is Some(recheck) else {
            return @bounded.Failed(InvalidRecord(state.record), progress, used)
          }
          state.graph_recheck = Some(recheck)
          state.phase = RecheckGraphField
        } else {
          state.graph_column += 1
        }
      }
      RecheckGraphField => {
        guard state.graph_recheck is Some(recheck) else {
          return @bounded.Failed(InvalidKernel, progress, used)
        }
        if !charge_events_to_rows_work(state) {
          return @bounded.Failed(ControlWorkLimit, progress, used)
        }
        used += 1
        match @value.advance_recheck_runtime_value(recheck) {
          @value.RecheckContinue => ()
          @value.RecheckFailed =>
            return @bounded.Failed(InvalidRecord(state.record), progress, used)
          @value.RecheckComplete(checked, _, _) => {
            if state.record_cells[state.graph_column] is Some(_) {
              return @bounded.Failed(
                InvalidRecord(state.record),
                progress,
                used,
              )
            }
            state.matched_count += 1
            state.record_cells[state.graph_column] = Some(checked)
            state.graph_recheck = None
            state.pending_graph_field = None
            state.phase = ScanFields
          }
        }
      }
      VerifyFields =>
        if state.verified_column < @schema.field_count(state.schema) {
          if !charge_events_to_rows_work(state) {
            return @bounded.Failed(ControlWorkLimit, progress, used)
          }
          used += 1
          guard @schema.field_at(state.schema, state.verified_column)
            is Some(expected) else {
            return @bounded.Failed(InvalidRecord(state.record), progress, used)
          }
          let present = state.record_cells[state.verified_column] is Some(_)
          if expected.presence == @schema.Required && !present {
            return @bounded.Failed(InvalidRecord(state.record), progress, used)
          }
          state.verified_column += 1
        } else {
          state.phase = CommitRelationRow
        }
      CommitRelationRow => {
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidKernel, progress, used)
        }
        if !charge_events_to_rows_work(state) {
          return @bounded.Failed(ControlWorkLimit, progress, used)
        }
        used += 1
        let row_workspace = state.row_workspace -
          (match state.source {
            GraphRows(source) => source.label_reserved
            _ => 0
          })
        let started = if @schema.all_fields_required(state.schema) {
          @execution.start_admitted_output_row(output, row_workspace, column => {
            state.record_cells
            .get(column)
            .bind(value => value)
            .map(value => value.value)
          })
        } else {
          @execution.start_admitted_presence_output_row(output, row_workspace, column => {
            state.record_cells
            .get(column)
            .map(cell => {
              @execution.relation_cell(cell.map(checked => checked.value))
            })
          })
        }
        match started {
          Ok(row) => {
            state.output_row = Some(row)
            state.phase = AppendRelationRow
          }
          Err(issue) =>
            return @bounded.Failed(relation_row_issue(issue), progress, used)
        }
      }
      AppendRelationRow => {
        guard state.output_row is Some(row) else {
          return @bounded.Failed(InvalidKernel, progress, used)
        }
        if !charge_events_to_rows_work(state) {
          return @bounded.Failed(ControlWorkLimit, progress, used)
        }
        used += 1
        match @execution.advance_admitted_output_row(row) {
          Ok(false) => ()
          Ok(true) => {
            @execution.cleanup_admitted_output_row(row) |> ignore
            state.output_row = None
            state.record_cells = []
            if state.source is GraphRows(source) {
              source.label_reserved = 0
            }
            state.record += 1
            state.phase = BeginRecord
            progress += 1
          }
          Err(issue) =>
            return @bounded.Failed(relation_row_issue(issue), progress, used)
        }
      }
      FinishRelation => {
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidKernel, progress, used)
        }
        state.output = None
        let rows = match @execution.finish_admitted_output(output) {
          Ok(value) => value
          Err(issue) =>
            return @bounded.Failed(RelationOutput(issue), progress, used)
        }
        state.rows.val = Some(rows)
        return match @execution.complete_trusted_output(state.port, ()) {
          Ok(completed) => {
            if state.owned is Some(owned) {
              @records.discard_completed(owned) |> ignore
              state.owned = None
            }
            @bounded.Complete(completed, progress, used)
          }
          Err(issue) => @bounded.Failed(Completion(issue), progress, used)
        }
      }
    }
  }
  @bounded.Continue(progress, used)
}

///|
fn relation_row_issue(
  issue : @execution.AdmittedOutputRowIssue,
) -> EventsBridgeIssue {
  match issue {
    @execution.OutputRowCapture(issue) => RelationOutput(issue)
    @execution.OutputRowWorkspace => RelationOutput(@execution.CaptureLimit)
  }
}

///|
fn charge_events_to_rows_work(state : EventsToRowsState) -> Bool {
  match state.control_work_remaining {
    None => true
    Some(remaining) =>
      if remaining <= 0 {
        false
      } else {
        state.control_work_remaining = Some(remaining - 1)
        true
      }
  }
}

///|
fn cleanup_events_to_rows_state(state : EventsToRowsState) -> Bool {
  if state.output_row is Some(row) {
    @execution.cleanup_admitted_output_row(row) |> ignore
    state.output_row = None
  }
  state.record_field = None
  state.record_cells = []
  if state.graph_recheck is Some(recheck) {
    @value.cancel_recheck_runtime_value(recheck)
    state.graph_recheck = None
  }
  state.pending_graph_field = None
  if state.source is GraphRows(source) {
    source.selection_label_index = 0
    source.selection_name_offset = 0
    if source.label_recheck is Some(recheck) {
      @value.cancel_recheck_runtime_value(recheck)
      source.label_recheck = None
    }
    if source.label_builder is Some(builder) {
      @value.cancel_array_value(builder) |> ignore
      source.label_builder = None
    }
    source.label_reserved = 0
    if source.order is Some(sort) {
      @sort.cleanup(sort) |> ignore
    }
    source.order = None
    source.order_keys.clear()
  }
  if state.output is Some(output) {
    @execution.cancel_admitted_output(output) |> ignore
    state.output = None
  }
  if state.owned is Some(owned) {
    @records.discard_completed(owned) |> ignore
    state.owned = None
  }
  if !state.accepted.val {
    state.rows.val = None
    state.live.val = false
  }
  true
}

///|
fn start_storage_to_rows(
  control : @bounded.Control,
  preparation : @execution.CompletionPreparation,
  owner : @lower.BoundPrepared,
  target : @pipeline.Target,
  source : EventsToRowsSource,
  available : () -> Bool,
  owned : @records.Completed?,
  schema : @schema.Schema,
  max_rows : Int,
  limits : @execution.ValueLimits,
  max_entries : Int,
  max_name_bytes : Int,
  inputs : Array[@execution.ProducerRead]?,
  control_work_limit : Int?,
  trusted_inputs? : Array[@execution.TrustedOutputInput]? = None,
) -> Result[EventsToRowsExecution, EventsBridgeIssue] {
  if control_work_limit is Some(limit) && limit < 0 {
    return Err(ControlWorkLimit)
  }
  // Identity-key references and both sort index buffers share the existing
  // workspace allowance with trusted output admission; no separate budget.
  let max_entries = if source is GraphRows(graph) {
    guard graph_rows_count(graph) is Some(count) && count <= max_entries / 4 else {
      return Err(GraphOrder(@sort.WorkspaceLimit))
    }
    max_entries - count * 4
  } else {
    max_entries
  }
  let output = match
    @execution.prepare_admitted_output(owner, target, max_rows, limits) {
    Ok(value) => value
    Err(issue) => return Err(RelationOutput(issue))
  }
  let rows : Ref[@execution.AdmittedOutputRows?] = Ref(None)
  let live = Ref(true)
  let accepted = Ref(false)
  let prepared_port = if trusted_inputs is Some(retained) {
    @execution.prepare_trusted_output_port_with_inputs(
      preparation,
      target,
      max_entries,
      max_name_bytes,
      fn(_) { if live.val { rows.val } else { None } },
      inputs=retained,
    )
  } else {
    @execution.prepare_trusted_output_port(
      preparation,
      target,
      max_entries,
      max_name_bytes,
      fn(_) { if live.val { rows.val } else { None } },
      inputs?,
    )
  }
  let port = match prepared_port {
    Ok(value) => value
    Err(issue) => {
      @execution.cancel_admitted_output(output) |> ignore
      return Err(Completion(issue))
    }
  }
  // Keep matched cells and borrowed name/recheck custody within the existing
  // admission workspace, including conditional Graph presence cells.
  let width = @schema.field_count(schema)
  let row_workspace = {
    if limits.max_depth > 2147483644 ||
      width > max_entries ||
      limits.max_depth + 3 > max_entries - width {
      @execution.cancel_admitted_output(output) |> ignore
      return Err(RelationOutput(@execution.CaptureLimit))
    }
    max_entries - width - limits.max_depth - 3
  }
  if source is GraphRows(graph) {
    graph.label_workspace = row_workspace
  }
  let state : EventsToRowsState = {
    available,
    owned,
    source,
    output: Some(output),
    rows,
    live,
    accepted,
    port,
    schema,
    value_limits: limits,
    phase: if source is GraphRows(_) {
      InitializeGraphOrder
    } else {
      BeginRecord
    },
    record: 0,
    source_field: 0,
    verified_column: 0,
    matched_count: 0,
    control_work_remaining: control_work_limit,
    pending_graph_field: None,
    graph_column: 0,
    graph_recheck: None,
    record_cells: [],
    record_field: None,
    match_low: 0,
    match_high: 0,
    name_offset: 0,
    row_workspace,
    output_row: None,
  }
  let (session, token) = @bounded.start(
    control,
    state,
    events_to_rows_step,
    cleanup_events_to_rows_state,
    _output => {
      state.live.val = false
      true
    },
  )
  Ok({ session, token: Some(token), accepted, })
}

///|
fn start_records_to_rows(
  control : @bounded.Control,
  preparation : @execution.CompletionPreparation,
  sequence : @lower.PreparedSequence,
  step : Int,
  input : @records.ProducerRead,
  max_rows : Int,
  limits : @execution.ValueLimits,
  max_entries : Int,
  max_name_bytes : Int,
  inputs : Array[@execution.ProducerRead],
  expected : @projection.Operation,
  carrier_matches : (@carrier.Carrier) -> Bool,
  control_work_limit : Int?,
) -> Result[EventsToRowsExecution, EventsBridgeIssue] {
  let owner = @lower.sequence_owner(sequence)
  guard physical_equal(
      @execution.completion_preparation_owner(preparation),
      owner,
    ) &&
    @lower.sequence_step(sequence, step)
    is Some(@lower.CarrierProjectionStep(projection)) &&
    @lower.carrier_projection_operation(projection) == expected &&
    @records.producer_read_matches_operation_input(input, owner, step, 0) &&
    @records.producer_read_storage(input) is Some(source) &&
    carrier_matches(@storage.carrier(source)) &&
    @lower.preparation_schema_at(
      @lower.bound_preparation(owner),
      @pipeline.Step(step),
    )
    is Some(schema) else {
    return Err(InvalidKernel)
  }
  start_storage_to_rows(
    control,
    preparation,
    owner,
    @pipeline.Step(step),
    Stored(source),
    fn() { @records.producer_read_available(input) },
    None,
    schema,
    max_rows,
    limits,
    max_entries,
    max_name_bytes,
    Some(inputs),
    control_work_limit,
  )
}

///|
pub fn start_completed_relation_to_rows(
  control : @bounded.Control,
  preparation : @execution.CompletionPreparation,
  sequence : @lower.PreparedSequence,
  step : Int,
  input : @records.Completed,
  max_rows : Int,
  limits : @execution.ValueLimits,
  max_entries : Int,
  max_name_bytes : Int,
  inputs : Array[@execution.ProducerRead],
  control_work_limit? : Int? = None,
) -> Result[EventsToRowsExecution, EventsBridgeIssue] {
  let owner = @lower.sequence_owner(sequence)
  guard physical_equal(
      @execution.completion_preparation_owner(preparation),
      owner,
    ) &&
    @lower.sequence_step(sequence, step) is Some(@lower.EventStep(_)) &&
    @lower.node_at(@lower.bound_preparation(owner), step) is Some(node) &&
    @carrier.kind(@lower.node_output_carrier(node)) == @carrier.RelationKind &&
    @lifecycle.completion_reference_matches_port(
      @records.completed_carrier_reference(input),
      owner,
      @pipeline.Step(step),
    ) &&
    @records.completed_available(input) &&
    @records.completed_storage(input) is Some(source) &&
    @carrier.kind(@storage.carrier(source)) == @carrier.RelationKind &&
    @lower.preparation_schema_at(
      @lower.bound_preparation(owner),
      @pipeline.Step(step),
    )
    is Some(schema) else {
    return Err(InvalidKernel)
  }
  start_storage_to_rows(
    control,
    preparation,
    owner,
    @pipeline.Step(step),
    Stored(source),
    fn() { @records.completed_available(input) },
    Some(input),
    schema,
    max_rows,
    limits,
    max_entries,
    max_name_bytes,
    Some(inputs),
    control_work_limit,
  )
}

///|
pub fn start_events_view_to_rows(
  control : @bounded.Control,
  preparation : @execution.CompletionPreparation,
  sequence : @lower.PreparedSequence,
  step : Int,
  input : @lifecycle.ProducerView,
  max_rows : Int,
  limits : @execution.ValueLimits,
  max_entries : Int,
  max_name_bytes : Int,
  control_work_limit? : Int? = None,
) -> Result[EventsToRowsExecution, EventsBridgeIssue] {
  let owner = @lower.sequence_owner(sequence)
  guard physical_equal(
      @execution.completion_preparation_owner(preparation),
      owner,
    ) &&
    @lower.sequence_step(sequence, step)
    is Some(@lower.CarrierProjectionStep(projection)) &&
    @lower.carrier_projection_operation(projection) == @projection.Events &&
    @lifecycle.producer_read_reference_matches_operation_input(
      @lifecycle.producer_view_read_reference(input),
      owner,
      step,
      0,
    ) &&
    @lifecycle.producer_view_kind(input) == @carrier.EventsKind &&
    @lower.preparation_schema_at(
      @lower.bound_preparation(owner),
      @pipeline.Step(step),
    )
    is Some(schema) else {
    return Err(InvalidKernel)
  }
  start_storage_to_rows(
    control,
    preparation,
    owner,
    @pipeline.Step(step),
    Viewed(input),
    fn() { @lifecycle.producer_view_record_count(input) is Some(_) },
    None,
    schema,
    max_rows,
    limits,
    max_entries,
    max_name_bytes,
    None,
    control_work_limit,
  )
}

///|
pub fn start_events_to_rows(
  control : @bounded.Control,
  preparation : @execution.CompletionPreparation,
  sequence : @lower.PreparedSequence,
  step : Int,
  input : @records.ProducerRead,
  max_rows : Int,
  limits : @execution.ValueLimits,
  max_entries : Int,
  max_name_bytes : Int,
  inputs : Array[@execution.ProducerRead],
  control_work_limit? : Int? = None,
) -> Result[EventsToRowsExecution, EventsBridgeIssue] {
  start_records_to_rows(
    control,
    preparation,
    sequence,
    step,
    input,
    max_rows,
    limits,
    max_entries,
    max_name_bytes,
    inputs,
    @projection.Events,
    fn(carrier) { carrier is @carrier.EventValue(_) },
    control_work_limit,
  )
}

///|
pub fn advance_events_to_rows(
  value : EventsToRowsExecution,
  quantum : Int,
) -> Result[EventsToRowsPoll, EventsBridgeIssue] {
  guard value.token is Some(token) else {
    return Err(Execution(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(Execution(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(Continue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      value.accepted.val = true
      Ok(Complete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(Failed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(Stopped(reason, progress~, work~))
    }
  }
}

///|
pub fn cleanup_events_to_rows(
  value : EventsToRowsExecution,
) -> Result[Bool, EventsBridgeIssue] {
  @bounded.cleanup(value.session).map_err(issue => Execution(issue))
}

///|
pub fn events_to_rows_cleanup_pending(value : EventsToRowsExecution) -> Bool {
  @bounded.cleanup_pending(value.session)
}
