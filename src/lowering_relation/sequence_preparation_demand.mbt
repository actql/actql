///|
/// Checked original Values intake and projection spelling demand, not output
/// cardinality. A JOIN can change output without changing this lowering input.
/// These scalar facts grant no execution, storage, or binding authority.
pub(all) struct SequencePreparationDemand {
  authored_literal_rows : Int
  authored_literal_cells : Int
  projection_name_bytes_bound : Int
  authored_expression_nodes : Int
  work_used : Int
  // Original cached pipeline inventory, separate from work and output rows.
  full_sequence_steps : Int
  // Appended: original checker UTF8 consumption, not a configured maximum.
  authored_expression_text_bytes : Int
} derive(Eq, Debug)

///|
// Checked references need no new spelling or UTF8 Buffer to size their later
// projection. Three bytes per UTF16 unit bounds every valid scalar spelling;
// the original qualifier is separate and exact. This is sizing, not admission.
fn sequence_projection_reference_name_bound(name : @schema.FieldName) -> Int64 {
  match name {
    @schema.Unqualified(leaf) => 3L * leaf.length().to_int64()
    @schema.Qualified(side, leaf) =>
      3L * leaf.length().to_int64() +
      (if side == @schema.Left { 5L } else { 6L })
  }
}

///|
pub(all) enum SequencePreparationDemandIssue {
  InvalidLimits
  WorkLimit
  CountOverflow
} derive(Eq, Debug)

///|
/// Scan each original node once. Unknown, expanding and input-backed nodes do
/// not erase known Values intake. Rectangular rows were already checked by the
/// Values owner; no row/cell copy or input-dependent collection is constructed.
pub fn prepared_sequence_preparation_demand(
  prepared : Prepared,
  max_work : Int,
) -> Result[SequencePreparationDemand, SequencePreparationDemandIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  let count = node_count(prepared)
  if count > max_work {
    return Err(WorkLimit)
  }
  let mut rows = 0L
  let mut cells = 0L
  let mut projection_names = 0L
  let mut expression_nodes = 0L
  let mut expression_text = 0L
  let mut remaining = max_work - count
  for index in 0..<count {
    match prepared.nodes[index].payload {
      Values(values) => {
        let count = @values.row_count(values).to_int64()
        let width = @schema.field_count(@values.output_schema(values)).to_int64()
        let added = count * width
        if count > 2147483647L - rows || added > 2147483647L - cells {
          return Err(CountOverflow)
        }
        rows += count
        cells += added
      }
      _ => ()
    }
    // Reuse the checked bindings' cached annotation counts during this same
    // original-node inventory. No expression tree or literal is walked again.
    let operation = match prepared.nodes[index].payload {
      Derive(op)
      | Where(op)
      | Select(op)
      | Limit(op)
      | TopK(op)
      | TopKBy(op)
      | Pivot(op)
      | Unnest(op)
      | Unpivot(op)
      | Distinct(op)
      | Dedupe(op)
      | Sort(op)
      | CountGroup(op)
      | WindowGroup(op)
      | Lag(op)
      | Watermark(op)
      | Analytic(op)
      | AssertRows(op)
      | JsonPick(op) => Some(op)
      _ => None
    }
    if operation is Some(operation) {
      let bindings = @relation.binding_count(operation)
      if bindings > remaining {
        return Err(WorkLimit)
      }
      remaining -= bindings
      for binding in 0..<bindings {
        if @relation.binding_expression_at(operation, binding) is Some(original) {
          let nodes = @typing.node_count(original).to_int64()
          if nodes > 2147483647L - expression_nodes {
            return Err(CountOverflow)
          }
          expression_nodes += nodes
          // This same binding already retains its semantic text accounting.
          // Propagate only text already charged by the checker. Untallied
          // opaque/late values keep their own original admission limits;
          // no expression/body/string is visited again.
          let text = @typing.usage(original).text_bytes.to_int64()
          if text < 0L || text > 2147483647L - expression_text {
            return Err(CountOverflow)
          }
          expression_text += text
        }
      }
    }
    let projection = match prepared.nodes[index].payload {
      Select(operation) => Some(operation)
      Distinct(operation) if prepared.nodes[index].projection_id is Some(_) =>
        Some(operation)
      _ => None
    }
    if projection is Some(operation) {
      let fields = @relation.projection_field_count(operation)
      if fields > remaining {
        return Err(WorkLimit)
      }
      remaining -= fields
      for field in 0..<fields {
        let original = @relation.projection_field_at(operation, field).unwrap()
        let added = sequence_projection_reference_name_bound(original.input) +
          sequence_projection_reference_name_bound(original.output)
        if added > 2147483647L - projection_names {
          return Err(CountOverflow)
        }
        projection_names += added
      }
    }
  }
  Ok({
    authored_literal_rows: rows.to_int(),
    authored_literal_cells: cells.to_int(),
    projection_name_bytes_bound: projection_names.to_int(),
    authored_expression_nodes: expression_nodes.to_int(),
    authored_expression_text_bytes: expression_text.to_int(),
    work_used: max_work - remaining,
    full_sequence_steps: count,
  })
}
