///|
// Grouping and numeric unary plus retain the literal/whole-parameter role.
// Never turn an arbitrary expression into an offset value.
fn lower_analytic_offset(
  construction : Construction,
  expression : @query.Expression,
  index : Int,
  max_work : Int,
) -> @builder.Node raise Abort {
  let mut index = index
  let mut work = 0
  while true {
    let origin = @query.expression_origin(expression, index).unwrap()
    if work >= max_work {
      raise Abort(Expression({ issue: WorkLimit, origin: Some(origin), }))
    }
    work += 1
    let node = @query.expression_node(expression, index).unwrap()
    match node.kind {
      Parenthesized(child) | Unary("+", child) => index = child
      Number(text) => {
        for _ in 0..<text.length() {
          if work >= max_work {
            raise Abort(Expression({ issue: WorkLimit, origin: Some(origin), }))
          }
          work += 1
        }
        guard @query.exact_integer_literal(text) is Some(value) else {
          raise Abort(UnsupportedAnalytic)
        }
        return { ..construction, generated: origin, }.add(
          Number(value.to_double()),
        )
      }
      ParameterReference(parameter) =>
        return { ..construction, generated: origin, }.object([
          (
            "$param",
            { ..construction, generated: origin, }.parameter_text(parameter),
          ),
        ])
      // These forms cannot supply the required literal/whole-parameter role.
      Reference(_) | Binary(_, _, _) => raise Abort(InvalidQuery)
      // A known NULL atom violates the navigation offset's non-null domain.
      // Parentheses and unary plus cannot turn it into a support limitation.
      Null => raise Abort(InvalidQuery)
      Unary("-", child) => {
        if work >= max_work {
          raise Abort(Expression({ issue: WorkLimit, origin: Some(origin), }))
        }
        work += 1
        let child = @query.expression_node(expression, child).unwrap()
        if child.kind is Number(text) {
          let hex = text.has_prefix("0x") || text.has_prefix("0X")
          let mut positive = false
          for index in 0..<text.length() {
            if work >= max_work {
              raise Abort(
                Expression({ issue: WorkLimit, origin: Some(origin), }),
              )
            }
            work += 1
            if hex {
              if index >= 2 {
                positive = positive || text[index] != '0'
              }
            } else {
              let digit = text[index].to_int() - 48
              if digit < 0 || digit > 9 {
                raise Abort(UnsupportedAnalytic)
              }
              positive = positive || digit > 0
            }
          }
          // A directly negated positive integer atom proves a domain violation.
          // Zero and other signed spellings retain their existing support limit.
          if positive {
            raise Abort(InvalidQuery)
          }
        }
        raise Abort(UnsupportedAnalytic)
      }
      _ => raise Abort(UnsupportedAnalytic)
    }
  } nobreak {
    raise Abort(UnsupportedAnalytic)
  }
}
