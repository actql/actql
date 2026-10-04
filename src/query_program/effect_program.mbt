///|
// A terminal declaration uses the already retained Result port. It does not
// append a row operator, perform I/O or create an approval/capture owner.
fn lower_update_effect(
  construction : Construction,
  clause : @query.UpdateEffectClause,
  default_port : String,
  retained : Array[RetainedResult],
  max_work : Int,
) -> @builder.Node raise Abort {
  let results = retained.filter(result => {
    same_name({ value: result.name, quoted: false, }, clause.result)
  })
  guard results.length() == 1 else { raise Abort(UnsupportedEffect) }
  let result = results[0]
  let resolve = fn(path : Array[@query.NamePart]) -> String? {
    if path.length() == 1 {
      result.fields
      .filter(field => same_name({ value: field, quoted: false, }, path[0]))
      .get(0)
    } else {
      None
    }
  }
  guard resolve([clause.id]) is Some(id) else { raise Abort(UnknownColumn) }
  let assignments : Array[(String, @builder.Node)] = []
  for (field, expression) in clause.set {
    if assignments.any(entry => {
        same_name({ value: entry.0, quoted: false, }, field)
      }) {
      raise Abort(DuplicateOutput)
    }
    let mut root = @query.expression_node(
      expression,
      @query.expression_root(expression),
    ).unwrap()
    while root.kind is Parenthesized(child) {
      root = @query.expression_node(expression, child).unwrap()
    }
    // EffectValue is a field or literal. Computation belongs in the ordinary
    // pipeline before RESULT, never in a new Effect evaluator.
    let value = match root.kind {
      Reference(path) => {
        guard resolve(path) is Some(slot) else { raise Abort(UnknownColumn) }
        construction.object([("field", construction.text(slot))])
      }
      Null | Boolean(_) | Number(_) | StringLiteral(_) =>
        match
          @expression.append(
            expression,
            resolve,
            construction.builder,
            max_work,
          ) {
          Ok(value) => value
          Err(error) => raise Abort(Expression(error))
        }
      Unary("-" | "+", child) => {
        guard @query.expression_node(expression, child).unwrap().kind
          is Number(_) else {
          raise Abort(UnsupportedEffect)
        }
        match
          @expression.append(
            expression,
            resolve,
            construction.builder,
            max_work,
          ) {
          Ok(value) => value
          Err(error) => raise Abort(Expression(error))
        }
      }
      _ => raise Abort(UnsupportedEffect)
    }
    assignments.push((field.value, value))
  }
  construction.object([
    (
      clause.name.value,
      construction.object([
        (
          "update",
          construction.object([
            ("target", construction.text(clause.target)),
            ("mapping", construction.text(clause.mapping.value)),
            (
              "from",
              construction.object([
                (
                  "result",
                  construction.text(
                    if result.terminal {
                      default_port
                    } else {
                      retained_result_port(default_port, result.port)
                    },
                  ),
                ),
              ]),
            ),
            ("id", construction.text(id)),
            ("set", construction.object(assignments)),
          ]),
        ),
      ]),
    ),
  ])
}
