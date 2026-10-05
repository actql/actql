///|
// Parentheses retain the literal/whole-parameter role required by the common
// analytic contract. Never turn an arbitrary expression into an offset value.
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
      Parenthesized(child) => index = child
      Number(text) => {
        let mut value = 0L
        for unit in text {
          if work >= max_work {
            raise Abort(Expression({ issue: WorkLimit, origin: Some(origin), }))
          }
          work += 1
          let digit = unit.to_int() - 48
          if digit < 0 ||
            digit > 9 ||
            value > (9007199254740991L - digit.to_int64()) / 10L {
            raise Abort(UnsupportedAnalytic)
          }
          value = value * 10L + digit.to_int64()
        }
        return { ..construction, generated: origin, }.add(
          Number(value.to_double()),
        )
      }
      ParameterReference(parameter) =>
        return { ..construction, generated: origin, }.object([
          ("$param", { ..construction, generated: origin, }.text(parameter)),
        ])
      _ => raise Abort(UnsupportedAnalytic)
    }
  } nobreak {
    raise Abort(UnsupportedAnalytic)
  }
}
