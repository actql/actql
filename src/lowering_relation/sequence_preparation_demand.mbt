///|
/// Authored Values intake, not execution/output cardinality. A JOIN can expand
/// or restrict output without changing the original rows visited by lowering.
/// These scalar facts grant no execution, storage, or binding authority.
pub(all) struct SequencePreparationDemand {
  authored_literal_rows : Int
  authored_literal_cells : Int
  work_used : Int
} derive(Eq, Debug)

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
  }
  Ok({
    authored_literal_rows: rows.to_int(),
    authored_literal_cells: cells.to_int(),
    work_used: count,
  })
}
