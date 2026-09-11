///|
/// Constant-size cardinality rule from the checked operation, not execution proof.
pub enum RowCountRule {
  Unknown
  Preserve
  Reduce
  OneRow
  OneExistingRow
  Slice(limit~ : Int64?, offset~ : Int64?)
  Repeat(Int64)
  Expand(Int64?)
}

///|
fn literal_count(value : CountValue) -> Int64? {
  match value {
    Literal(n) => Some(n)
    Parameter(_) => None
  }
}

///|
/// Does not copy grouping, ordering, projection or reshape field arrays.
pub fn row_count_rule(op : CheckedOperation) -> RowCountRule {
  match op.row_operation {
    Some(Take(count~, offset~)) =>
      Slice(limit=literal_count(count), offset=literal_count(offset))
    Some(TopK(count~, ..)) => Slice(limit=literal_count(count), offset=Some(0L))
    Some(TopKBy(partition~, count~, ..)) =>
      if partition.is_empty() {
        Slice(limit=literal_count(count), offset=Some(0L))
      } else {
        Reduce
      }
    Some(DedupeRows(by~, ..)) =>
      if by.is_empty() {
        OneExistingRow
      } else {
        Reduce
      }
    Some(DistinctRows) =>
      if @schema.field_count(output_schema(op)) == 0 {
        OneExistingRow
      } else {
        Reduce
      }
    Some(DistinctKeys(_)) => Reduce
    Some(Watermark(policy~, ..)) =>
      if policy == MarkLate {
        Preserve
      } else {
        Reduce
      }
    _ =>
      match op.reshape {
        Some(Unpivot(columns~, ..)) => Repeat(columns.length().to_int64())
        Some(Unnest(outer~, max_items~, ..)) =>
          Expand(max_items.map(n => if outer && n == 0L { 1L } else { n }))
        _ =>
          match op.group {
            Some(group) => if group.keys.is_empty() { OneRow } else { Reduce }
            None =>
              match op.pivot {
                Some(pivot) =>
                  if pivot.index.is_empty() {
                    OneRow
                  } else {
                    Reduce
                  }
                None =>
                  match op.operation {
                    Filter => Reduce
                    Derive
                    | Select
                    | Rename
                    | Drop
                    | Sort
                    | JsonPick
                    | AssertRows
                    | Analytic
                    | Lag => Preserve
                    _ => Unknown
                  }
              }
          }
      }
  }
}
