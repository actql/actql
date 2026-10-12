///|
// COMMAND is a declaration on an existing retained Result. All authority,
// approval, capture and physical apply remain with the common Effect owner.
fn lower_command_effect(
  construction : Construction,
  clause : @query.CommandEffectClause,
  default_port : String,
  retained : Array[RetainedResult],
  max_work : Int,
) -> (String, @builder.Node) raise Abort {
  let results = retained.filter(result => {
    same_name({ value: result.name, quoted: false, }, clause.result)
  })
  guard results.length() == 1 else { raise Abort(UnsupportedEffect) }
  let result = results[0]
  let resolve = fn(path : Array[@query.NamePart]) -> String? {
    let field = if path.length() == 1 {
      Some(path[0])
    } else if path.length() == 2 && same_name(path[0], clause.result_alias) {
      Some(path[1])
    } else {
      None
    }
    match field {
      None => None
      Some(name) => {
        let matches = result.fields.filter(field => {
          same_name({ value: field, quoted: false, }, name)
        })
        if matches.length() == 1 {
          matches.get(0)
        } else {
          None
        }
      }
    }
  }
  let target = append_effect_value(
    construction,
    clause.target,
    resolve,
    max_work,
  )
  let assignments : Array[(String, @builder.Node)] = []
  for (field, expression) in clause.input {
    if assignments.any(entry => {
        same_name({ value: entry.0, quoted: false, }, field)
      }) {
      raise Abort(DuplicateOutput)
    }
    assignments.push(
      (
        field.value,
        append_effect_value(construction, expression, resolve, max_work),
      ),
    )
  }
  (
    clause.name.value,
    construction.object([
      (
        "command",
        construction.object([
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
          ("target", target),
          ("contract", construction.text(clause.contract.value)),
          ("input", construction.object(assignments)),
        ]),
      ),
    ]),
  )
}
