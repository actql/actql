///|
pub(all) enum ValuesMeasurementIssue {
  InvalidRequirement
  ForeignOwner
  Encoding(@encode.EncodeFailure)
} derive(Debug)

///|
/// Measure the execution params' complete /rows JSON value for one owned values
/// requirement. Returns (UTF-8 bytes, value nodes, peak container depth), including
/// the outer array and row objects, but not the schema or params envelope.
/// Bindings come only from this cell-resolution owner's exact occurrences.
/// These numbers are measurement material, not bound witnesses, selected Host
/// ceilings or a discharge of ResolvePublicationResources.
pub fn measure_operation_values_rows(
  cells : ProgramOperationCells,
  requirement_index : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[(Int, Int, Int), ValuesMeasurementIssue] {
  let requirements = cells.requirements
  guard requirements.entries.get(requirement_index) is Some(site) else {
    return Err(InvalidRequirement)
  }
  guard site.requirement
    is @pipeline.ValuesRequirement(@values.ResolvePublicationResources) else {
    return Err(InvalidRequirement)
  }
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) else {
    return Err(ForeignOwner)
  }
  guard step.operation is @pipeline.Values(values) else {
    return Err(ForeignOwner)
  }
  if site.index != 0 ||
    @pipeline.operation_obligations_scope(site.obligations) != @pipeline.Body {
    return Err(ForeignOwner)
  }
  let schema = @values.output_schema(values)
  let width = @schema.field_count(schema)
  let mut next_binding = 1
  try {
    let out = @encode.measuring_writer(max_bytes, max_nodes, max_depth)
    @encode.begin_array(out)
    for row_index in 0..<@values.row_count(values) {
      @encode.begin_object(out)
      let row = @values.row_at(values, row_index).unwrap()
      for column in 0..<width {
        let field = @schema.field_at(schema, column).unwrap()
        @encode.key(out, @schema.reference_name(field.name))
        let (value, next) = match
          resolved_values_cell(
            cells, site, values, requirement_index, row, row_index, column, next_binding,
          ) {
          Ok(v) => v
          Err(e) => return Err(e)
        }
        next_binding = next
        @value.emit_wire_value(value.value, out)
      }
      @encode.end_object(out)
    }
    if next_binding != @values.pending_validation_count(values) {
      return Err(ForeignOwner)
    }
    @encode.end_array(out)
    Ok(@encode.finish_measurement_usage(out))
  } catch {
    error => Err(Encoding(error))
  }
}

///|
fn resolved_values_cell(
  cells : ProgramOperationCells,
  site : OperationRequirementSite,
  values : @values.CheckedValues,
  requirement_index : Int,
  row : @values.Row,
  row_index : Int,
  column : Int,
  next_binding : Int,
) -> Result[(@value.CheckedValue, Int), ValuesMeasurementIssue] {
  match @values.cell_at(row, column).unwrap() {
    @values.Literal(value, ..) => Ok((value, next_binding))
    @values.Parameter(_, ..) => {
      let requirements = cells.requirements
      if next_binding >= requirements.entries.length() - requirement_index {
        return Err(ForeignOwner)
      }
      let position = requirement_index + next_binding
      guard cells.by_requirement.get(position) is Some(index) else {
        return Err(ForeignOwner)
      }
      let entry = cells.entries[index]
      if !physical_equal(entry.site, requirements.entries[position]) ||
        !physical_equal(entry.values, values) ||
        !physical_equal(entry.site.obligations, site.obligations) ||
        !physical_equal(entry.site.pipeline, site.pipeline) ||
        entry.site.stage != site.stage ||
        entry.site.producer_visit != site.producer_visit ||
        entry.site.step != site.step ||
        entry.site.group != site.group ||
        entry.site.index != next_binding ||
        entry.occurrence.row != row_index ||
        entry.occurrence.column != column {
        return Err(ForeignOwner)
      }
      guard entry.site.requirement
        is @pipeline.ValuesRequirement(@values.BindCell(_)) else {
        return Err(ForeignOwner)
      }
      // Name/type checks belong to this exact resolved occurrence. Do not
      // rescan a potentially long Parameter name while measuring values.
      Ok((entry.parameter.value, next_binding + 1))
    }
  }
}
