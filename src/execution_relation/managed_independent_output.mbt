///|
/// Finite Local relocation from a checked output view to a new owned in-memory
/// generation. Checked values are immutable; row/column occurrence arrays are
/// copied so the new generation no longer borrows the producer bridge or its
/// source material. This establishes no logical content identity.
pub(all) enum ManagedIndependentOutputIssue {
  Unavailable
  UnsupportedRepresentation
  Limit
  Control(@bounded.Issue)
} derive(Eq, Debug)

///|
pub fn copy_completed_output_independent(
  output : CompletedOutput,
  max_rows : Int,
  max_columns : Int,
) -> Result[CompletedOutput, ManagedIndependentOutputIssue] {
  if max_rows < 0 || max_columns < 0 || !completed_output_available(output) {
    return Err(
      if max_rows < 0 || max_columns < 0 {
        Limit
      } else {
        Unavailable
      },
    )
  }
  guard output.table is Some(source) &&
    IndexedRows::row_count(source) <= max_rows &&
    IndexedRows::column_count(source) <= max_columns else {
    return Err(
      match output.table {
        Some(_) => Limit
        None => UnsupportedRepresentation
      },
    )
  }
  for row in 0..<IndexedRows::row_count(source) {
    if IndexedRows::row_width(source, row) != IndexedRows::column_count(source) {
      return Err(UnsupportedRepresentation)
    }
  }
  let table = match source {
    PresenceTable(rows) =>
      CompletedTable::PresenceTable({
        ..rows,
        names: rows.names.copy(),
        rows: rows.rows.map(row => { ..row, cells: row.cells.copy(), }),
      })
    RowTable(rows) =>
      CompletedTable::RowTable({
        owner: rows.owner,
        id: rows.id,
        names: rows.names.copy(),
        rows: rows.rows.map(row => row.copy()),
      })
    AdmittedTable(rows) =>
      CompletedTable::AdmittedTable({
        owner: rows.owner,
        id: rows.id,
        names: rows.names.copy(),
        rows: rows.rows.map(row => row.copy()),
      })
    ColumnTable(columns) => {
      let count = columns.count
      CompletedTable::ColumnTable({
        owner: columns.owner,
        id: columns.id,
        names: columns.names.copy(),
        columns: columns.columns.map(column => {
          Array::makei(count, row => {
            let source_row = match columns.selection {
              Some(selection) => selection[row]
              None => row
            }
            column[source_row]
          })
        }),
        count,
        selection: None,
      })
    }
    NumberTable(numbers) => {
      let count = numbers.count
      let columns : Array[CompletedNumberColumn] = numbers.columns.map(column => {
        values: FixedArray::makei(count, row => {
          let source_row = match numbers.selection {
            Some(selection) => selection[row]
            None => row
          }
          column.values[source_row]
        }),
        valid: FixedArray::makei(count, row => {
          let source_row = match numbers.selection {
            Some(selection) => selection[row]
            None => row
          }
          column.valid[source_row]
        }),
      })
      CompletedTable::NumberTable({
        owner: numbers.owner,
        id: numbers.id,
        names: numbers.names.copy(),
        columns,
        count,
        selection: None,
      })
    }
  }
  let prepared = @lower.bound_preparation(RelationRows::checked_owner(source))
  let completion : CompletedSequence = {
    ..output.completion,
    result_identity: Ref(()),
    store: ImportedStore(
      @lower.preparation_input_count(prepared),
      output.target,
      table,
    ),
    // Provenance remains in input_bindings. The owned copy must not retain
    // ancestor storage merely to keep its new physical generation readable.
    _producer_inputs: [],
    live: None,
  }
  Ok({
    completion,
    target: output.target,
    table: Some(table),
    representation: None,
  })
}

///|
priv enum IndependentRowCopyPhase {
  CopyNames
  BeginRow
  CopyCells
  CommitRow
  FinishCopy
}

///|
priv struct IndependentRowCopyState {
  mut source : CompletedOutput?
  mut source_rows : CompletedTable?
  workspace : RowWorkspace
  mut names : Array[String]
  mut rows : Array[Array[Value]]
  mut row_values : Array[Value]?
  mut presence_rows : Array[AdmittedRelationRow]
  mut presence_cells : Array[@admitted.Value?]?
  mut row : Int
  mut column : Int
  mut phase : IndependentRowCopyPhase
}

///|
struct BoundedIndependentRowCopy {
  control : @bounded.Control
  session : @bounded.Session[
    IndependentRowCopyState,
    CompletedOutput,
    ManagedIndependentOutputIssue,
  ]
  mut token : @bounded.Token?
}

///|
pub enum IndependentRowCopyPoll {
  RowCopyContinue(progress~ : Int64, work~ : Int64)
  RowCopyComplete(CompletedOutput, progress~ : Int64, work~ : Int64)
  RowCopyFailed(ManagedIndependentOutputIssue, progress~ : Int64, work~ : Int64)
  RowCopyStopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
fn independent_row_copy_step(
  state : IndependentRowCopyState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[CompletedOutput, ManagedIndependentOutputIssue] {
  let mut used = 0
  let mut progress = 0
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    guard state.source is Some(source) &&
      state.source_rows is Some(source_rows) &&
      completed_output_available(source) else {
      return @bounded.Failed(Unavailable, progress, used)
    }
    match state.phase {
      CopyNames =>
        if state.column < RelationRows::field_names(source_rows).length() {
          if !reserve_slots(state.workspace, 1) {
            return @bounded.Failed(Limit, progress, used)
          }
          state.names.push(RelationRows::field_names(source_rows)[state.column])
          state.column += 1
          used += 1
        } else {
          state.column = 0
          state.phase = BeginRow
        }
      BeginRow =>
        if state.row < IndexedRows::row_count(source_rows) {
          if IndexedRows::row_width(source_rows, state.row) !=
            state.names.length() {
            return @bounded.Failed(UnsupportedRepresentation, progress, used)
          }
          if !reserve_slots(state.workspace, 1) {
            return @bounded.Failed(Limit, progress, used)
          }
          if source_rows is PresenceTable(_) {
            state.presence_cells = Some([])
          } else {
            state.row_values = Some([])
          }
          state.column = 0
          state.phase = CopyCells
          used += 1
        } else {
          state.phase = FinishCopy
        }
      CopyCells =>
        if state.column < state.names.length() {
          if !reserve_slots(state.workspace, 1) {
            return @bounded.Failed(Limit, progress, used)
          }
          match source_rows {
            PresenceTable(table) => {
              guard state.presence_cells is Some(cells) else {
                return @bounded.Failed(
                  UnsupportedRepresentation,
                  progress,
                  used,
                )
              }
              cells.push(table.rows[state.row].cells[state.column])
            }
            _ => {
              guard state.row_values is Some(row_values) else {
                return @bounded.Failed(
                  UnsupportedRepresentation,
                  progress,
                  used,
                )
              }
              row_values.push(
                IndexedRows::read_cell(source_rows, state.row, state.column),
              )
            }
          }
          state.column += 1
          used += 1
        } else {
          state.phase = CommitRow
        }
      CommitRow => {
        if !reserve_slots(state.workspace, 1) {
          return @bounded.Failed(Limit, progress, used)
        }
        match source_rows {
          PresenceTable(table) => {
            guard state.presence_cells is Some(cells) else {
              return @bounded.Failed(UnsupportedRepresentation, progress, used)
            }
            state.presence_rows.push({ ..table.rows[state.row], cells, })
          }
          _ => {
            guard state.row_values is Some(row_values) else {
              return @bounded.Failed(UnsupportedRepresentation, progress, used)
            }
            state.rows.push(row_values)
          }
        }
        state.row_values = None
        state.presence_cells = None
        state.row += 1
        state.phase = BeginRow
        progress += 1
        used += 1
      }
      FinishCopy => {
        let table : CompletedTable = match source_rows {
          PresenceTable(original) =>
            PresenceTable({
              ..original,
              names: state.names,
              rows: state.presence_rows,
            })
          _ =>
            RowTable({
              owner: RelationRows::checked_owner(source_rows),
              id: RelationRows::relation_id(source_rows),
              names: state.names,
              rows: state.rows,
            })
        }
        let prepared = @lower.bound_preparation(
          RelationRows::checked_owner(source_rows),
        )
        let completion : CompletedSequence = {
          ..source.completion,
          result_identity: Ref(()),
          store: ImportedStore(
            @lower.preparation_input_count(prepared),
            source.target,
            table,
          ),
          _producer_inputs: [],
          live: None,
        }
        state.names = []
        state.rows = []
        state.presence_rows = []
        state.source = None
        state.source_rows = None
        // The completed generation takes custody of these admitted arrays.
        release_slots(state.workspace, state.workspace.live)
        used += 1
        return @bounded.Complete(
          {
            completion,
            target: source.target,
            table: Some(table),
            representation: None,
          },
          progress,
          used,
        )
      }
    }
  }
  @bounded.Continue(progress, used)
}

///|
fn cleanup_independent_row_copy_state(state : IndependentRowCopyState) -> Bool {
  state.source = None
  state.source_rows = None
  state.names = []
  state.rows = []
  state.row_values = None
  state.presence_rows = []
  state.presence_cells = None
  release_slots(state.workspace, state.workspace.live)
  true
}

///|
pub fn start_bounded_independent_row_copy(
  control : @bounded.Control,
  output : CompletedOutput,
  max_rows : Int,
  max_columns : Int,
  max_entries : Int,
) -> Result[BoundedIndependentRowCopy, ManagedIndependentOutputIssue] {
  if max_rows < 0 || max_columns < 0 || max_entries < 0 {
    return Err(Limit)
  }
  if !completed_output_available(output) {
    return Err(Unavailable)
  }
  guard output.table is Some(source) else {
    return Err(UnsupportedRepresentation)
  }
  if IndexedRows::row_count(source) > max_rows ||
    IndexedRows::column_count(source) > max_columns {
    return Err(Limit)
  }
  let workspace = row_workspace(max_entries)
  if !reserve_slots(workspace, 2) {
    return Err(Limit)
  }
  let state : IndependentRowCopyState = {
    source: Some(output),
    source_rows: Some(source),
    workspace,
    names: [],
    rows: [],
    row_values: None,
    presence_rows: [],
    presence_cells: None,
    row: 0,
    column: 0,
    phase: CopyNames,
  }
  let (session, token) = @bounded.start(
    control,
    state,
    independent_row_copy_step,
    cleanup_independent_row_copy_state,
    _output => true,
  )
  Ok({ control, session, token: Some(token), })
}

///|
pub fn completed_output_has_row_table(output : CompletedOutput) -> Bool {
  output.table is Some(RowTable(_))
}

///|
pub fn advance_bounded_independent_row_copy(
  value : BoundedIndependentRowCopy,
  quantum : Int,
) -> Result[IndependentRowCopyPoll, ManagedIndependentOutputIssue] {
  guard value.token is Some(token) else {
    return Err(Control(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(Control(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(RowCopyContinue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      Ok(RowCopyComplete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(RowCopyFailed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(RowCopyStopped(reason, progress~, work~))
    }
  }
}

///|
pub fn request_bounded_independent_row_copy_cancel(
  value : BoundedIndependentRowCopy,
) -> Bool {
  @bounded.request_cancel(value.control)
}

///|
pub fn bounded_independent_row_copy_stopped(
  value : BoundedIndependentRowCopy,
) -> Bool {
  @bounded.session_stopped(value.session)
}

///|
pub fn cleanup_bounded_independent_row_copy(
  value : BoundedIndependentRowCopy,
) -> Result[Bool, ManagedIndependentOutputIssue] {
  @bounded.cleanup(value.session).map_err(issue => Control(issue))
}

///|
pub fn bounded_independent_row_copy_cleanup_pending(
  value : BoundedIndependentRowCopy,
) -> Bool {
  @bounded.cleanup_pending(value.session)
}
