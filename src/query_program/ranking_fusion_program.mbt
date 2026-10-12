///|
// Storage/acquisition is shared by the existing input owner. Each authored
// ranking occurrence is nevertheless retained in the common operation body.
fn script_ranking_peer(
  construction : Construction,
  argument : @query.SgaArgument,
  known : Array[Input],
  context : Context,
  sources : ScriptSources,
  steps : Array[@builder.Node],
  reserved : Array[String],
) -> @builder.Node raise Abort {
  match argument {
    Producer(name) => {
      let selected = resolve_relation_input([name], known)
      let bound = bind_script_input(
        construction, selected, context, sources, steps, reserved,
      )
      construction.text(bound.name)
    }
    ListValue(items) => {
      // A nested list is not a ranking occurrence; do not flatten it or
      // deduplicate the admitted flat list to fit a different weight vector.
      guard items.all(item => item is Producer(_)) else {
        raise Abort(InvalidQuery)
      }
      construction.array(
        items.map(item => {
          script_ranking_peer(
            construction, item, known, context, sources, steps, reserved,
          )
        }),
      )
    }
    _ => raise Abort(InvalidQuery)
  }
}

///|
// Resolve signature roles only. Score declaration authentication, complete
// input validation, folding/rounding, rank/weight rules and resource ceilings
// remain with the existing common ranking checker and execution owner.
fn script_ranking_fusion_body(
  construction : Construction,
  call : @query.SgaCall,
  query : @query.Query,
  input : Input,
  known : Array[Input],
  context : Context,
  sources : ScriptSources,
  limits : Limits,
  steps : Array[@builder.Node],
  reserved : Array[String],
) -> @builder.Node raise Abort {
  construction.object(
    call.arguments.map(argument => {
      let value = if argument.0 == "with" {
        script_ranking_peer(
          construction,
          argument.1,
          known,
          context,
          sources,
          steps,
          reserved,
        )
      } else if ["by", "candidate", "score", "rank", "tie_break"].contains(
          argument.0,
        ) {
        script_carrier_field(construction, argument.1, query, input, sources)
      } else {
        script_traversal_argument(construction, argument.1, known, limits)
      }
      (argument.0, value)
    }),
  )
}
