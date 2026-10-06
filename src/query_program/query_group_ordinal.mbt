///|
// An expanded star column already has a checked input slot. Do not synthesize
// an expression from its spelling or confuse the ordinal with a literal value.
priv enum GroupKeyReference {
  Expression(@query.Expression)
  StarColumn((String, String))
}

///|
fn resolved_group_key(
  key : @query.Expression,
  projections : Array[@query.Projection],
  input_visible : Array[(String, String)],
  sql : Bool,
) -> GroupKeyReference raise Abort {
  let mut root = @query.expression_node(key, @query.expression_root(key)).unwrap()
  while true {
    match root.kind {
      Parenthesized(child) | Unary("+", child) =>
        root = @query.expression_node(key, child).unwrap()
      _ => break
    }
  }
  match root.kind {
    Number(text) => {
      if !sql {
        raise Abort(UnsupportedGrouping)
      }
      let mut width = 0
      for projection in projections {
        let columns = match projection.star {
          Some("*") => expanded_star_columns(projection, input_visible).length()
          Some(_) => raise Abort(UnsupportedProjection)
          None => 1
        }
        // Any expanded SELECT must fit the same Int-indexed output arrays.
        if width > 2147483647 - columns {
          raise Abort(UnsupportedGrouping)
        }
        width += columns
      }
      let mut ordinal = 0
      for unit in text {
        let digit = unit.to_int() - 48
        if digit < 0 || digit > 9 || ordinal > (width - digit) / 10 {
          raise Abort(UnsupportedGrouping)
        }
        ordinal = ordinal * 10 + digit
        if ordinal > width {
          raise Abort(UnsupportedGrouping)
        }
      }
      if ordinal < 1 {
        raise Abort(UnsupportedGrouping)
      }
      for projection in projections {
        match projection.star {
          Some("*") => {
            let columns = expanded_star_columns(projection, input_visible)
            if ordinal <= columns.length() {
              return StarColumn(columns[ordinal - 1])
            }
            ordinal -= columns.length()
          }
          Some(_) => raise Abort(UnsupportedProjection)
          None => {
            if ordinal == 1 {
              // Aggregates and analytic values cannot be grouping keys.
              if projection.aggregate is Some(_) ||
                projection.analytic is Some(_) {
                raise Abort(UnsupportedGrouping)
              }
              guard projection.expression is Some(expression) else {
                raise Abort(UnsupportedGrouping)
              }
              // This is the selected expression over the input snapshot,
              // not a new alias lookup or a second expression evaluation.
              return Expression(expression)
            }
            ordinal -= 1
          }
        }
      }
      raise Abort(UnsupportedGrouping)
    }
    Unary("-", child) =>
      if @query.expression_node(key, child).unwrap().kind is Number(_) {
        raise Abort(UnsupportedGrouping)
      }
    StringLiteral(_) | Boolean(_) | Null => raise Abort(UnsupportedGrouping)
    _ => ()
  }
  Expression(if sql { group_key_expression(key, projections) } else { key })
}
