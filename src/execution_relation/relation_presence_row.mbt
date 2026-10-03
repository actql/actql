///|
/// A cell's row presence, not a new scalar value or acquisition authority.
pub enum RelationCell {
  Absent
  Present(@admitted.Value)
}

///|
pub(all) enum RelationPresenceIssue {
  InvalidLayout
  Unavailable
  RequiredFieldMissing(Int)
  ForeignContract(Int)
  PresenceNotGuaranteed(Int)
  InvalidLimits
  Limit
}

///|
/// Immutable checked cells under one exact Relation schema. This representation
/// carries no completion, execution or Store authority; those remain with the
/// existing bound preparation and retained-output owners.
struct AdmittedRelationRow {
  schema : @schema.Schema
  cells : Array[@admitted.Value?]
  usage : ValueUsage
}

///|
/// Validate presence separately from each already-admitted value contract.
/// Containers and presence slots are charged even when the value is absent.
pub fn admit_relation_row(
  schema : @schema.Schema,
  supplied : Array[@admitted.CheckedValue?],
  limits : ValueLimits,
) -> Result[AdmittedRelationRow, RelationPresenceIssue] {
  let budget = match value_budget(limits) {
    Ok(budget) => budget
    Err(_) => return Err(InvalidLimits)
  }
  let width = @schema.field_count(schema)
  if supplied.length() != width {
    return Err(InvalidLayout)
  }
  if !charge_node(budget, 1) || width > budget.limits.max_nodes - budget.nodes {
    return Err(Limit)
  }
  let cells = []
  for column in 0..<width {
    let field = @schema.field_at(schema, column).unwrap()
    if !charge_text(budget, @schema.reference_name(field.name)) {
      return Err(Limit)
    }
    match supplied[column] {
      None => {
        if field.presence == @schema.Required {
          return Err(RequiredFieldMissing(column))
        }
        // This is physical presence metadata, not an invented logical value.
        if !charge_node(budget, 2) {
          return Err(Limit)
        }
        cells.push(None)
      }
      Some(checked) => {
        if !physical_equal(field.contract, checked.contract) {
          return Err(ForeignContract(column))
        }
        if !measure(checked.value, 2, budget) {
          return Err(Limit)
        }
        cells.push(Some(checked.value))
      }
    }
  }
  Ok({
    schema,
    cells,
    usage: { nodes: budget.nodes, text_bytes: budget.text, work: budget.work, },
  })
}

///|
/// Invalid coordinates are distinct from a valid, absent conditional cell.
pub fn relation_row_cell(
  row : AdmittedRelationRow,
  column : Int,
) -> Result[RelationCell, RelationPresenceIssue] {
  if column < 0 || column >= row.cells.length() {
    return Err(InvalidLayout)
  }
  Ok(
    match row.cells[column] {
      None => Absent
      Some(value) => Present(value)
    },
  )
}

///|
pub fn relation_row_schema(row : AdmittedRelationRow) -> @schema.Schema {
  row.schema
}

///|
pub fn relation_row_usage(row : AdmittedRelationRow) -> ValueUsage {
  row.usage
}

///|
/// Ordinary value access needs a schema guarantee, even if this particular row
/// happens to contain the field. Sampling is not a presence proof.
pub fn relation_row_required_value(
  row : AdmittedRelationRow,
  column : Int,
) -> Result[@admitted.Value, RelationPresenceIssue] {
  guard @schema.field_at(row.schema, column) is Some(field) else {
    return Err(InvalidLayout)
  }
  if field.presence != @schema.Required {
    return Err(PresenceNotGuaranteed(column))
  }
  match row.cells[column] {
    Some(value) => Ok(value)
    None => Err(RequiredFieldMissing(column))
  }
}

///|
/// Copy presence containers while sharing immutable admitted values. Reuses
/// the same resource checks; copying is not an accounting discount.
pub fn copy_relation_row(
  row : AdmittedRelationRow,
  limits : ValueLimits,
) -> Result[AdmittedRelationRow, RelationPresenceIssue] {
  let budget = match value_budget(limits) {
    Ok(budget) => budget
    Err(_) => return Err(InvalidLimits)
  }
  if !measure_relation_row(row, budget) {
    return Err(Limit)
  }
  Ok({
    schema: row.schema,
    cells: row.cells.copy(),
    usage: { nodes: budget.nodes, text_bytes: budget.text, work: budget.work, },
  })
}

///|
// Measure immutable cells without allocating a temporary copy. The caller owns
// the cumulative budget; this routine does not create another accounting owner.
fn measure_relation_row(
  row : AdmittedRelationRow,
  budget : ValueBudget,
) -> Bool {
  if !charge_node(budget, 1) ||
    row.cells.length() > budget.limits.max_nodes - budget.nodes {
    return false
  }
  for column, cell in row.cells {
    let field = @schema.field_at(row.schema, column).unwrap()
    if !charge_text(budget, @schema.reference_name(field.name)) {
      return false
    }
    let measured = match cell {
      None => charge_node(budget, 2)
      Some(value) => measure(value, 2, budget)
    }
    if !measured {
      return false
    }
  }
  true
}

///|
/// Omission and explicit NULL retain the existing canonical object rules.
/// Physical presence slots never enter the logical content preimage.
pub fn emit_relation_row(
  row : AdmittedRelationRow,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  for column in 0..<row.cells.length() {
    if row.cells[column] is Some(value) {
      @encode.key(
        writer,
        @schema.reference_name(
          @schema.field_at(row.schema, column).unwrap().name,
        ),
      )
      @admitted.emit_wire_value(value, writer)
    }
  }
  @encode.end_object(writer)
}
