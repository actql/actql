///|
/// Bounded metadata for one exact checked Named Result view. The retained row
/// and column maps do not copy cells or weaken the completed producer's life.
pub(all) struct CompletedResultViewLimits {
  max_fields : Int
  max_mapping_work : Int
  max_order_work : Int
  max_workspace_entries : Int
}

///|
pub(all) enum CompletedResultViewIssue {
  InvalidLimits
  Unavailable
  ForeignOccurrence
  InvalidProjection
  Limit
  Comparison(ScalarIssue)
}

///|
/// Physical coordinates for an exact completed Result occurrence. None means
/// the original identity mapping and avoids allocating a redundant index.
priv struct CompletedExportRows {
  table : CompletedTable
  schema : @schema.Schema
  names : Array[String]
  columns : Array[Int]?
  rows : Array[Int]?
}

///|
/// Private, resumable preparation of one Named Result projection and order.
/// No completed view escapes until every mapping and stable-sort step finishes.
priv struct CompletedResultRowsPreparation {
  source : CompletedOutput
  occurrence : ManagedResultOccurrence
  table : CompletedTable
  schema : @schema.Schema
  port : @results.ResultPort
  limits : CompletedResultViewLimits
  mapping_work : Ref[Int]
  order_work : ControlBudget
  mut columns : Array[Int]
  mut names : Array[String]
  mut terms : Array[ColumnOrder]
  comparison : BoundedRowComparison
  mut mapping_phase : Int
  mut mapping_index : Int
  mut mapping_offset : Int
  mut mapping_input : @schema.FieldName?
  mut merge_charged : Bool
  mut advancing : Bool
  mut projection : Int
  mut order_term : Int
  mut initializing : Int
  mut scratch_initializing : Int
  mut rows : Array[Int]
  mut scratch : Array[Int]
  mut width : Int
  mut start : Int
  mut middle : Int
  mut end : Int
  mut left : Int
  mut right : Int
  mut out : Int
  mut merging : Bool
  mut done : Bool
  mut closed : Bool
}

///|
impl IndexedRows for CompletedExportRows with fn row_count(self) {
  match self.rows {
    Some(rows) => rows.length()
    None => IndexedRows::row_count(self.table)
  }
}

///|
impl IndexedRows for CompletedExportRows with fn column_count(self) {
  self.names.length()
}

///|
impl IndexedRows for CompletedExportRows with fn row_width(self, row) {
  let source = match self.rows {
    Some(rows) => rows[row]
    None => row
  }
  if IndexedRows::row_width(self.table, source) !=
    IndexedRows::column_count(self.table) {
    -1
  } else {
    IndexedRows::column_count(self)
  }
}

///|
impl IndexedRows for CompletedExportRows with fn read_cell(self, row, column) {
  let source_row = match self.rows {
    Some(rows) => rows[row]
    None => row
  }
  let source_column = match self.columns {
    Some(columns) => columns[column]
    None => column
  }
  IndexedRows::read_cell(self.table, source_row, source_column)
}

///|
fn completed_output_export_rows(
  source : CompletedOutput,
) -> CompletedExportRows {
  let owner = @lower.sequence_owner(source.completion.sequence)
  {
    table: source.table.unwrap(),
    schema: @lower.preparation_schema_at(
      @lower.bound_preparation(owner),
      source.target,
    ).unwrap(),
    names: RelationRows::field_names(source.table.unwrap()).copy(),
    columns: None,
    rows: None,
  }
}

///|
impl IndexedRows for CompletedExportRows with fn cell_present(self, row, column) {
  let source_row = match self.rows {
    Some(rows) => rows[row]
    None => row
  }
  let source_column = match self.columns {
    Some(columns) => columns[column]
    None => column
  }
  IndexedRows::cell_present(self.table, source_row, source_column)
}

///|
fn spend_result_mapping(work : Ref[Int], amount : Int) -> Bool {
  if amount < 0 || amount > work.val {
    false
  } else {
    work.val -= amount
    true
  }
}

///|
fn advance_result_column_mapping(
  value : CompletedResultRowsPreparation,
  projection : Bool,
) -> Result[Unit, CompletedResultViewIssue] {
  match value.mapping_phase {
    0 => {
      if projection {
        // Preserve the existing complete projection-search charge. Traversal
        // quantum, including spelling comparison, is independently resumable.
        if !spend_result_mapping(
            value.mapping_work, @results.port_projection_count(value.port),
          ) {
          return Err(Limit)
        }
        value.mapping_phase = 1
      } else {
        if !spend_result_mapping(value.mapping_work, 1) {
          return Err(Limit)
        }
        value.mapping_input = Some(
          @results.port_order_term_at(value.port, value.order_term).unwrap().field,
        )
        value.mapping_phase = 2
      }
    }
    1 => {
      guard @results.port_projection_field_at(value.port, value.mapping_index)
        is Some(candidate) else { return Err(InvalidProjection) }
      let output = @schema.field_at(value.schema, value.projection).unwrap().name
      let (compared, offset, _) = @schema.compare_reference_fragment(
        candidate.output, output, value.mapping_offset, 1,
      )
      value.mapping_offset = offset
      if compared is Some(compared) {
        if compared == 0 {
          if !spend_result_mapping(value.mapping_work, 1) {
            return Err(Limit)
          }
          value.mapping_input = Some(candidate.input)
          value.mapping_index = 0
          value.mapping_phase = 2
        } else {
          value.mapping_index += 1
        }
      }
    }
    2 => {
      if value.mapping_index >= IndexedRows::column_count(value.table) {
        return Err(InvalidProjection)
      }
      if !spend_result_mapping(value.mapping_work, 1) {
        return Err(Limit)
      }
      value.mapping_phase = 3
    }
    3 => {
      let name = RelationRows::field_names(value.table)[value.mapping_index]
      let (compared, offset, _) = @schema.compare_reference_fragment(
        @schema.Unqualified(name), value.mapping_input.unwrap(),
        value.mapping_offset, 1,
      )
      value.mapping_offset = offset
      if compared is Some(compared) {
        if compared == 0 {
          if projection {
            value.names.push(@schema.reference_name(
              @schema.field_at(value.schema, value.projection).unwrap().name,
            ))
            value.columns.push(value.mapping_index)
            value.projection += 1
          } else {
            let term = @results.port_order_term_at(
              value.port, value.order_term,
            ).unwrap()
            value.terms.push({
              column: value.mapping_index,
              descending: term.direction == @order.Desc,
              nulls_first: term.nulls == @order.First,
            })
            value.order_term += 1
          }
          value.mapping_input = None
          value.mapping_index = 0
          value.mapping_phase = 0
        } else {
          value.mapping_index += 1
          value.mapping_phase = 2
        }
      }
    }
    _ => return Err(InvalidProjection)
  }
  Ok(())
}

///|
fn completed_result_export_rows(
  source : CompletedOutput,
  occurrence : ManagedResultOccurrence,
  limits : CompletedResultViewLimits,
) -> Result[CompletedExportRows, CompletedResultViewIssue] {
  let preparation = match
    start_completed_result_rows(source, occurrence, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  while true {
    match advance_completed_result_rows(preparation, 1024) {
      Ok((true, _)) => break
      Ok((false, _)) => continue
      Err(issue) => return Err(issue)
    }
  }
  finish_completed_result_rows(preparation)
}

///|
/// Begin bounded Result-view preparation. Potentially large row maps and the
/// stable sort are built only by `advance_completed_result_rows`.
fn start_completed_result_rows(
  source : CompletedOutput,
  occurrence : ManagedResultOccurrence,
  limits : CompletedResultViewLimits,
) -> Result[CompletedResultRowsPreparation, CompletedResultViewIssue] {
  if limits.max_fields < 0 ||
    limits.max_mapping_work < 0 ||
    limits.max_order_work < 0 ||
    limits.max_workspace_entries < 0 {
    return Err(InvalidLimits)
  }
  if !completed_output_available(source) {
    return Err(Unavailable)
  }
  guard source.table is Some(table) else { return Err(Unavailable) }
  let owner = managed_result_occurrence_owner(occurrence)
  let actual_owner = @lower.sequence_owner(source.completion.sequence)
  let port = managed_result_occurrence_port(occurrence)
  if !physical_equal(owner, actual_owner) ||
    @results.port_target(port) != source.target {
    return Err(ForeignOccurrence)
  }
  let schema = @results.port_schema(port)
  if @schema.field_count(schema) > limits.max_fields {
    return Err(Limit)
  }
  Ok({
    source,
    occurrence,
    table,
    schema,
    port,
    limits,
    mapping_work: Ref(limits.max_mapping_work),
    order_work: { remaining: limits.max_order_work, max_frames: 0, },
    columns: [],
    names: [],
    terms: [],
    comparison: {
      left: -1, right: -1, terms: 0, term: 0, phase: -1, offset: 0,
      charge: { offset: 0, next: 0, remaining: 0, }, tree: None,
    },
    mapping_phase: 0,
    mapping_index: 0,
    mapping_offset: 0,
    mapping_input: None,
    merge_charged: false,
    advancing: false,
    projection: 0,
    order_term: 0,
    initializing: 0,
    scratch_initializing: 0,
    rows: [],
    scratch: [],
    width: 1,
    start: 0,
    middle: 0,
    end: 0,
    left: 0,
    right: 0,
    out: 0,
    merging: false,
    done: false,
    closed: false,
  })
}

///|
fn cancel_completed_result_rows(value : CompletedResultRowsPreparation) -> Bool {
  if value.closed {
    false
  } else {
    value.closed = true
    value.rows = []
    value.scratch = []
    value.columns = []
    value.names = []
    value.terms = []
    value.mapping_input = None
    true
  }
}

///|
/// Perform at most `quantum` preparation steps, including reference spelling
/// lookup, Text charging and comparison inside a stable merge.
fn advance_completed_result_rows(
  value : CompletedResultRowsPreparation,
  quantum : Int,
) -> Result[(Bool, Int), CompletedResultViewIssue] {
  if quantum <= 0 || value.advancing {
    return Err(InvalidLimits)
  }
  if value.closed {
    return Err(Unavailable)
  }
  value.advancing = true
  let result = (fn() -> Result[(Bool, Int), CompletedResultViewIssue] {
    if !completed_output_available(value.source) || value.closed {
      return Err(Unavailable)
    }
    if value.done {
      return Ok((true, 0))
    }
    advance_completed_result_rows_impl(value, quantum)
  })()
  value.advancing = false
  if result is Err(_) {
    cancel_completed_result_rows(value) |> ignore
  }
  result
}

///|
fn advance_completed_result_rows_impl(
  value : CompletedResultRowsPreparation,
  quantum : Int,
) -> Result[(Bool, Int), CompletedResultViewIssue] {
  let count = IndexedRows::row_count(value.table)
  let mut spent = 0
  while spent < quantum && !value.done {
    if value.projection < @schema.field_count(value.schema) {
      match advance_result_column_mapping(value, true) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
      spent += 1
      continue
    }
    if value.order_term < @results.port_order_term_count(value.port) {
      match advance_result_column_mapping(value, false) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
      spent += 1
      continue
    }
    if value.initializing < count {
      if IndexedRows::row_width(value.table, value.initializing) !=
        IndexedRows::column_count(value.table) {
        return Err(InvalidProjection)
      }
      if value.rows.length() + value.terms.length() >=
        value.limits.max_workspace_entries ||
        !spend_control(value.order_work, 1) {
        return Err(Limit)
      }
      value.rows.push(value.initializing)
      value.initializing += 1
      spent += 1
      continue
    }
    if count < 2 || value.terms.is_empty() {
      value.done = true
      continue
    }
    if value.scratch_initializing < count {
      if value.rows.length() + value.scratch.length() + value.terms.length() >=
        value.limits.max_workspace_entries ||
        !spend_control(value.order_work, 1) {
        return Err(Limit)
      }
      value.scratch.push(0)
      value.scratch_initializing += 1
      spent += 1
      continue
    }
    if !value.merging {
      if value.start >= count {
        let previous = value.rows
        value.rows = value.scratch
        value.scratch = previous
        if value.width > count / 2 {
          value.done = true
          continue
        }
        value.width *= 2
        value.start = 0
      }
      value.middle = value.start + Int::min(value.width, count - value.start)
      value.end = value.middle + Int::min(value.width, count - value.middle)
      value.left = value.start
      value.right = value.middle
      value.out = value.start
      value.merging = true
    }
    if !value.merge_charged {
      if !spend_control(value.order_work, 1) {
        return Err(Limit)
      }
      value.merge_charged = true
      spent += 1
      continue
    }
    let choose_left = if value.left == value.middle {
      false
    } else if value.right == value.end {
      true
    } else {
      match
        bounded_row_comparison_step_with(
          value.comparison,
          value.terms,
          value.order_work,
          (row, column) => Some(IndexedRows::read_cell(value.table, row, column)),
          value.rows[value.left], value.rows[value.right], value.terms.length(),
        ) {
        Ok(Some(comparison)) => comparison <= 0
        Ok(None) => {
          spent += 1
          continue
        }
        Err(InvalidInput) => return Err(InvalidProjection)
        Err(Limit) => return Err(Limit)
        Err(Scalar(issue)) => return Err(Comparison(issue))
      }
    }
    if choose_left {
      value.scratch[value.out] = value.rows[value.left]
      value.left += 1
    } else {
      value.scratch[value.out] = value.rows[value.right]
      value.right += 1
    }
    value.out += 1
    value.merge_charged = false
    if value.out == value.end {
      value.start = value.end
      value.merging = false
    }
    spent += 1
  }
  Ok((value.done, spent))
}

///|
fn finish_completed_result_rows(
  value : CompletedResultRowsPreparation,
) -> Result[CompletedExportRows, CompletedResultViewIssue] {
  if value.closed || value.advancing || !value.done {
    return Err(Unavailable)
  }
  value.advancing = true
  let available = completed_output_available(value.source)
  value.advancing = false
  if !available || value.closed {
    cancel_completed_result_rows(value) |> ignore
    return Err(Unavailable)
  }
  value.closed = true
  let rows : CompletedExportRows = {
    table: value.table,
    schema: value.schema,
    names: value.names,
    columns: Some(value.columns),
    rows: Some(value.rows),
  }
  value.rows = []
  value.scratch = []
  value.columns = []
  value.names = []
  value.terms = []
  Ok(rows)
}

///|
fn completed_export_field_names(rows : CompletedExportRows) -> Array[String] {
  rows.names.copy()
}
