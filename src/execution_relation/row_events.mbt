///|
// Keep the logical output alive before releasing its producing slots and input.
// Storage builders run afterwards; physical layout does not choose root order.
fn[T : RowValues] row_event_output(
  scope : ExpressionRoots,
  names : Array[String],
  row : T,
  slots : Array[ExpressionRootLease],
  input : ExpressionRootLease,
) -> Result[Unit, RowIssue] {
  let root = match retain_logical_row(scope.budget, names, row) {
    Ok(root) => root
    Err(e) => return Err(LogicalRows(e))
  }
  row_event_retained_output(scope, root, slots, input)
}

///|
/// The same transfer boundary after a bounded row measurement completes.
fn row_event_retained_output(
  scope : ExpressionRoots,
  root : LogicalRoot,
  slots : Array[ExpressionRootLease],
  input : ExpressionRootLease,
) -> Result[Unit, RowIssue] {
  match register_scope_root(scope, root) {
    Ok(_) => ()
    Err(e) => return Err(LogicalRows(e))
  }
  for root in slots {
    match release_expression_root(root) {
      Ok(_) => ()
      Err(e) => return Err(LogicalRows(e))
    }
  }
  match release_expression_root(input) {
    Ok(_) => Ok(())
    Err(e) => Err(LogicalRows(e))
  }
}
