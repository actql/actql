///|
/// Encode one already-admitted immutable Local row for a registered physical
/// representation provider. This performs no hashing and creates no logical
/// identity; it is only a bounded transport into another checked admission.
pub fn completed_output_row_wire(
  output : CompletedOutput,
  row : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, CompletedExportIssue] {
  if !completed_output_available(output) {
    return Err(Unavailable)
  }
  guard output.table is Some(table) else { return Err(NotCellRepresentation) }
  if row < 0 ||
    row >= IndexedRows::row_count(table) ||
    IndexedRows::row_width(table, row) != IndexedRows::column_count(table) {
    return Err(Wire(InvalidLayout))
  }
  if max_bytes < 0 || max_nodes < 1 || max_depth < 0 {
    return Err(Wire(InvalidLimits))
  }
  let names = RelationRows::field_names(table)
  let width = IndexedRows::column_count(table)
  if width > max_nodes || names.length() != width {
    return Err(Wire(InvalidLayout))
  }
  // A checked select retains an authored projection order independently of
  // the canonical output schema. Ordinary derive and assertion rows also
  // retain their checked input projection order in the physical row wire.
  let wire_order : Array[String]? = match output.target {
    @pipeline.Step(step) =>
      match @lower.sequence_step(output.completion.sequence, step) {
        Some(@lower.RowStep(kernel)) => {
          let body = @lower.kernel_body(kernel)
          match body {
            @lower.Select(fields) =>
              Some(fields.map(field => @schema.reference_name(field.output)))
            @lower.SnapshotMap(_)
            | @lower.OrderedBindings(_)
            | @lower.AssertAll(_)
            | @lower.AssertUnique(_) if !@lower.kernel_has_veca_bindings(kernel) &&
              @lower.sequence_count(output.completion.sequence) == 1 => {
              let prepared = @lower.bound_preparation(
                @lower.sequence_owner(output.completion.sequence),
              )
              let input_schema = @lower.kernel_input_schema(kernel)
              let ordered : Array[String] = []
              match @lower.preparation_input_projection(prepared, 0) {
                Some(view) =>
                  for field in @lower.projection_fields(view) {
                    if ordered.length() >= width {
                      return Err(Wire(InvalidLayout))
                    }
                    ordered.push(@schema.reference_name(field.output))
                  }
                None =>
                  for index in 0..<@schema.field_count(input_schema) {
                    if ordered.length() >= width {
                      return Err(Wire(InvalidLayout))
                    }
                    ordered.push(
                      @schema.reference_name(
                        @schema.field_at(input_schema, index).unwrap().name,
                      ),
                    )
                  }
              }
              let seen : Map[String, Bool] = Map([])
              for name in ordered {
                if seen.contains(name) {
                  return Err(Wire(InvalidLayout))
                }
                seen[name] = true
              }
              let bindings = match body {
                @lower.SnapshotMap(bindings)
                | @lower.OrderedBindings(bindings) => bindings
                _ => []
              }
              for (name, _) in bindings {
                if !seen.contains(name) {
                  if ordered.length() >= width {
                    return Err(Wire(InvalidLayout))
                  }
                  ordered.push(name)
                  seen[name] = true
                }
              }
              Some(ordered)
            }
            _ => None
          }
        }
        _ => None
      }
    _ => None
  }
  let positions : Map[String, Int] = Map([])
  if wire_order is Some(_) {
    for column, name in names {
      if positions.contains(name) {
        return Err(Wire(InvalidLayout))
      }
      positions[name] = column
    }
  }
  try {
    let writer = @encode.writer(max_bytes, max_nodes, max_depth)
    @encode.begin_object(writer)
    match wire_order {
      Some(ordered) => {
        if ordered.length() != width {
          return Err(Wire(InvalidLayout))
        }
        for name in ordered {
          guard positions.get(name) is Some(column) else {
            return Err(Wire(InvalidLayout))
          }
          @encode.key(writer, name)
          emit_runtime_value(IndexedRows::read_cell(table, row, column), writer)
        }
      }
      None =>
        for column in 0..<width {
          @encode.key(writer, names[column])
          emit_runtime_value(IndexedRows::read_cell(table, row, column), writer)
        }
    }
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    issue => Err(Wire(Encoding(issue)))
  }
}
