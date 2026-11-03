///|
/// A cardinality fact about the original checked node, not execution authority.
/// Unknown/expanding operations deliberately return None. Input occurrences are
/// positional, so repeated Append inputs contribute independently.
pub fn node_row_count_bound(node : PreparedNode, inputs : Array[Int]) -> Int? {
  if inputs.length() != node.input_targets.length() {
    return None
  }
  for count in inputs {
    if count < 0 {
      return None
    }
  }
  match node.payload {
    Values(_) | Serialize(_) => node_input_independent_row_count_bound(node)
    InnerJoin(join) =>
      intrinsic_join_row_bound(
        @join.kind(join),
        @join.output_guard(join),
        inputs,
      )
    CrossJoinRows(join) =>
      intrinsic_join_row_bound(
        @join.Inner,
        @join.cross_output_guard(join),
        inputs,
      )
    Unnest(operation) => {
      // The checked array bound and positional input count prove this product.
      // Missing bounds remain unknown; a policy ceiling is never an item bound.
      guard inputs.length() == 1 &&
        @relation.reshape(operation)
        is Some(@relation.Unnest(outer~, max_items=Some(items), ..)) &&
        items >= 0L &&
        items <= 2147483647L else {
        return None
      }
      let per_row = if outer { Int64::max(1L, items) } else { items }
      let total = inputs[0].to_int64() * per_row
      if total > 2147483647L {
        None
      } else {
        Some(total.to_int())
      }
    }
    Derive(_)
    | Where(_)
    | Select(_)
    | Limit(_)
    | TopK(_)
    | TopKBy(_)
    | Distinct(_)
    | Dedupe(_)
    | Sort(_)
    | AssertRows(_) => if inputs.length() == 1 { Some(inputs[0]) } else { None }
    CountGroup(_) =>
      if inputs.length() == 1 {
        Some(Int::max(1, inputs[0]))
      } else {
        None
      }
    AppendRows(_) => {
      let mut total = 0L
      for count in inputs {
        total += count.to_int64()
      }
      if total > 2147483647L {
        None
      } else {
        Some(total.to_int())
      }
    }
    _ => None
  }
}

///|
/// A successful-output bound already present on the same checked node, even
/// when an upstream input's cardinality is unknown. This neither proves that
/// input's demand nor turns a failed output guard into successful truncation.
/// Parameter guards require their original binding and deliberately decline.
pub fn node_input_independent_row_count_bound(node : PreparedNode) -> Int? {
  match node.payload {
    Values(values) => Some(@values.row_count(values))
    // Successful serialization emits one Content metadata row, including for
    // empty input. This does not bound the separate input/sort workload.
    Serialize(_) => if node.input_targets.length() == 1 { Some(1) } else { None }
    InnerJoin(join) =>
      declared_join_row_bound(
        @join.output_guard(join),
        node.input_targets.length(),
      )
    CrossJoinRows(join) =>
      declared_join_row_bound(
        @join.cross_output_guard(join),
        node.input_targets.length(),
      )
    _ => None
  }
}

///|
/// Work-bounded closed-pipeline cardinality certificate. The returned work is
/// debited by a caller composing multiple original owners; external inputs or
/// unknown cardinality operations cannot borrow an assumed row count.
pub fn prepared_closed_row_bound(
  prepared : Prepared,
  max_work : Int,
  target_step? : Int? = None,
) -> (Int, Int)? {
  if target_step is Some(step) && (step < 0 || step >= node_count(prepared)) {
    return None
  }
  if max_work < 0 || preparation_input_count(prepared) != 0 {
    return None
  }
  let count = node_count(prepared)
  if count > max_work {
    return None
  }
  let mut remaining = max_work - count
  let bounds : Array[Int] = []
  let mut maximum = 0
  for index in 0..<count {
    guard node_at(prepared, index) is Some(node) else { return None }
    let ports = node_input_count(node)
    if ports > remaining {
      return None
    }
    remaining -= ports
    let inputs : Array[Int] = []
    for port in 0..<ports {
      guard node_input_target(node, port) is Some(@pipeline.Step(step)) &&
        bounds.get(step) is Some(rows) else {
        return None
      }
      inputs.push(rows)
    }
    guard node_row_count_bound(node, inputs) is Some(rows) else { return None }
    bounds.push(rows)
    maximum = Int::max(maximum, rows)
    if target_step == Some(index) {
      return Some((rows, max_work - remaining))
    }
  }
  Some((maximum, max_work - remaining))
}

///|
// A checked total-output guard bounds successful execution for every Join kind,
// including unmatched outer rows. It does not bound authored input demand and
// does not imply that an output above the guard may be truncated successfully.
// Parameter guards require their original binding; this unbound proof declines.
fn declared_join_row_bound(output_guard : @join.Guard?, ports : Int) -> Int? {
  if ports != 2 {
    return None
  }
  match output_guard {
    Some(@join.Literal(rows)) if rows > 0L && rows <= 2147483647L =>
      Some(rows.to_int())
    _ => None
  }
}

///|
// Successful equijoin output cannot exceed every possible matching pair plus
// the relevant unmatched side. These are bounds, not uniqueness assumptions.
// Parameter guards can only reduce successful output, so need not be resolved.
fn intrinsic_join_row_bound(
  kind : @join.Kind,
  output_guard : @join.Guard?,
  inputs : Array[Int],
) -> Int? {
  if inputs.length() != 2 || inputs[0] < 0 || inputs[1] < 0 {
    return None
  }
  let left = inputs[0].to_int64()
  let right = inputs[1].to_int64()
  let intrinsic = match kind {
    @join.Inner => left * right
    @join.Left => left * Int64::max(1L, right)
    @join.Right => Int64::max(1L, left) * right
    @join.Semi | @join.Anti => left
    // Full Join execution remains outside this specialization's supported
    // route; retain only its existing checked literal guard proof.
    @join.Full => return declared_join_row_bound(output_guard, 2)
  }
  let bound = match output_guard {
    Some(@join.Literal(rows)) if rows > 0L => Int64::min(intrinsic, rows)
    Some(@join.Literal(_)) => return None
    _ => intrinsic
  }
  if bound > 2147483647L {
    None
  } else {
    Some(bound.to_int())
  }
}
