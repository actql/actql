///|
/// Only newly computed physical columns cross this admission boundary.
/// Unchanged values remain represented by the Core builder's exact metadata.
struct ManagedComputedPhysicalOutput[T] {
  computed : @execution.ManagedComputedView[T]
  physical : PhysicalResult
  columns : Array[Int?]
  mut open : Bool
}

///|
pub(all) enum ManagedComputedPhysicalIssue {
  Physical(PhysicalResultIssue)
  Computed(@execution.ManagedComputedViewIssue)
  Closed
}

///|
/// Fields describe ONLY new-value columns. Reordered fields are allowed, but
/// missing, duplicate, inherited or incompatible fields cannot be substituted.
pub fn[T] prepare_managed_computed_physical_output(
  computed : @execution.ManagedComputedView[T],
  fields : Array[(String, PhysicalType)],
  limits : PhysicalResultLimits,
  max_metadata_work : Int,
) -> Result[ManagedComputedPhysicalOutput[T], ManagedComputedPhysicalIssue] {
  let schema = @execution.managed_computed_view_schema(computed)
  let width = @schema.field_count(schema)
  if max_metadata_work < 0 {
    return Err(Physical(InvalidLimits))
  }
  if width > max_metadata_work {
    return Err(Physical(MetadataLimit))
  }
  let mut work = max_metadata_work - width
  let selected = []
  let columns = []
  for column in 0..<width {
    if @execution.managed_computed_view_source_column(computed, column)
      is Some(_) {
      columns.push(None)
    } else {
      let field = @schema.field_at(schema, column).unwrap()
      match
        @scalar.admit_utf8_length(@schema.reference_name(field.name), work) {
        Ok(bytes) => work -= bytes
        Err(_) => return Err(Physical(MetadataLimit))
      }
      columns.push(Some(selected.length()))
      selected.push((field.name, field.contract))
    }
  }
  let selected_schema = match
    @schema.from_fields(
      selected,
      max_fields=width,
      max_name_bytes=max_metadata_work,
    ) {
    Ok(schema) => schema
    Err(_) => return Err(Physical(SchemaMismatch))
  }
  prepare_physical_result(selected_schema, fields, limits, work)
  .map(physical => { computed, physical, columns, open: true, })
  .map_err(issue => Physical(computed_physical_issue_columns(columns, issue)))
}

///|
/// Public diagnostics retain full output-schema positions, not the compact
/// new-column transport's positions.
fn computed_physical_issue_columns(
  columns : Array[Int?],
  issue : PhysicalResultIssue,
) -> PhysicalResultIssue {
  let compact = match issue {
    FieldType(column, _) | Cell(_, column, _) => column
    _ => return issue
  }
  for column, source in columns {
    if source == Some(compact) {
      return match issue {
        FieldType(_, cause) => FieldType(column, cause)
        Cell(row, _, cause) => Cell(row, column, cause)
        _ => issue
      }
    }
  }
  issue
}

///|
pub fn[T] cancel_managed_computed_physical_output(
  output : ManagedComputedPhysicalOutput[T],
) -> Bool {
  if !output.open {
    return false
  }
  output.open = false
  cancel_physical_result(output.physical)
  @execution.cancel_managed_computed_view(output.computed) |> ignore
  true
}

///|
pub fn[T] append_managed_computed_physical_output(
  output : ManagedComputedPhysicalOutput[T],
  rows : Int,
  columns : Array[@decode.Cursor],
) -> Result[Unit, ManagedComputedPhysicalIssue] {
  if !output.open {
    return Err(Closed)
  }
  let batch = match admit_physical_chunk(output.physical, rows, columns) {
    Ok(batch) => batch
    Err(issue) => {
      cancel_managed_computed_physical_output(output) |> ignore
      return Err(
        Physical(computed_physical_issue_columns(output.columns, issue)),
      )
    }
  }
  for row in 0..<rows {
    match
      @execution.append_managed_computed_view(output.computed, column => {
        match output.columns.get(column) {
          Some(Some(index)) => physical_batch_cell(batch, row, index)
          _ => None
        }
      }) {
      Ok(_) => ()
      Err(issue) => {
        cancel_managed_computed_physical_output(output) |> ignore
        return Err(Computed(issue))
      }
    }
  }
  Ok(())
}

///|
pub fn[T] managed_computed_physical_usage(
  output : ManagedComputedPhysicalOutput[T],
) -> (Int, Int, Int, Int) {
  physical_result_usage(output.physical)
}

///|
/// Still provisional: the returned selection requires the installed execution
/// verifier, exact physical retention, and common completion.
pub fn[T] finish_managed_computed_physical_output(
  output : ManagedComputedPhysicalOutput[T],
) -> Result[@execution.ManagedViewSelection[T], ManagedComputedPhysicalIssue] {
  if !output.open {
    return Err(Closed)
  }
  output.open = false
  cancel_physical_result(output.physical)
  @execution.finish_managed_computed_view(output.computed).map_err(issue => {
    Computed(issue)
  })
}
