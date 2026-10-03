// Shared bounded contract alignment for current Graph selectors; this does
// not compare or construct Graph values.

///|
fn align_domains(
  b : Budget,
  source : @decode.Cursor,
  left : @row.Schema,
  right : @row.Schema,
) -> @row.Schema raise Stop {
  let aligned = match
    @alignment.align_schemas(source, left, right, {
      max_work: b.work,
      max_nodes: b.nodes,
      max_depth: b.limits.max_depth,
      max_text_bytes: b.text,
    }) {
    Ok(v) => v
    Err(e) =>
      if e.kind == @alignment.BudgetExceeded {
        fail(source, BudgetExceeded)
      } else {
        fail(source, ContractMismatch(e.kind))
      }
  }
  let used = @alignment.alignment_usage(aligned)
  b.work -= used.work
  b.nodes -= used.nodes
  b.text -= used.text_bytes
  @alignment.aligned_schema(aligned)
}

///|
fn singleton_schema(c : @contract.Contract) -> @row.Schema {
  @row.from_fields([(Unqualified("value"), c)], max_fields=1, max_name_bytes=5).unwrap()
}
