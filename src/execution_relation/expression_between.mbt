///|
// BETWEEN evaluates its three operands once, left to right. The original
// search value stays owned through both bounded comparisons. Comparison
// results are internal state, not additional semantic expression nodes.
priv struct BetweenArgumentsState {
  expression : @lower.Expression
  children : Array[@lower.Expression]
  values : Array[Value]
  roots : Array[ExpressionRootLease?]
  mut index : Int
}

///|
fn between_comparison(
  args : BetweenArgumentsState,
  upper : Bool,
) -> BinaryComparisonState {
  {
    expression: args.expression,
    op: if upper {
      @lower.LessEqual
    } else {
      @lower.GreaterEqual
    },
    left: args.values[0],
    right: args.values[if upper { 2 } else { 1 }],
    left_root: None,
    right_root: None,
    charge: { offset: 0, next: 0, remaining: 0, },
    phase: 0,
    offset: 0,
  }
}
