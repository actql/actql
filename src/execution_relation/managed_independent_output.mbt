///|
/// Finite Local relocation from a checked output view to a new owned in-memory
/// generation. Checked values are immutable; row/column occurrence arrays are
/// copied so the new generation no longer borrows the producer bridge or its
/// source material. This establishes no logical content identity.
pub(all) enum ManagedIndependentOutputIssue {
  Unavailable
  UnsupportedRepresentation
  Limit
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
