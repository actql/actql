///|
// The same already-admitted publication owns target selection. SET values,
// row observations and current grants cannot choose a different pair.
fn resolve_store_effect_target(
  clause : @query.StoreEffectClause,
  publication : StoreTargetPublication?,
  max_work : Int,
) -> ResolvedStoreTarget raise Abort {
  guard publication is Some(publication) else {
    raise Abort(StoreTargetBinding(UnresolvedTarget))
  }
  match resolve_store_target_binding(publication, clause.target, max_work) {
    Ok(value) => value
    Err(issue) => raise Abort(StoreTargetBinding(issue))
  }
}

///|
// Pure SET expressions use the existing Relation expression lowerer before a
// closed private Result. A direct ContentRef remains the original field value;
// it is not reconstructed as a scalar literal or an artificial target column.
fn lower_store_capture(
  construction : Construction,
  clause : @query.StoreEffectClause,
  producer : String,
  visible : Array[(String, String)],
  ranges : Array[(@query.NamePart, Array[(String, String)])],
  physical : Array[String],
  max_work : Int,
  reserved_bindings? : Array[String] = [],
  expression_columns? : Array[(String, String)]? = None,
  value_ranges? : Array[@query.NamePart] = [],
) -> (RetainedResult, Array[Array[(String, @builder.Node)]]) raise Abort {
  let expression_visible = expression_columns.unwrap_or(visible)
  let resolve = path => {
    pipe_expression_slot(path, expression_visible, ranges, value_ranges~)
  }
  let projection : Array[@builder.Node] = []
  let fields : Array[String] = []
  let derives : Array[(String, @builder.Node)] = []
  let reserved = physical.copy()
  if clause.set.is_empty() {
    for (name, slot) in visible {
      fields.push(name)
      projection.push(
        if name == slot {
          construction.text(slot)
        } else {
          construction.object([(name, construction.text(slot))])
        },
      )
    }
  } else {
    for (field, expression) in clause.set {
      if fields.any(name => same_name({ value: name, quoted: false, }, field)) {
        raise Abort(DuplicateOutput)
      }
      fields.push(field.value)
      let mut root = @query.expression_node(
        expression,
        @query.expression_root(expression),
      ).unwrap()
      while root.kind is Parenthesized(child) {
        root = @query.expression_node(expression, child).unwrap()
      }
      let direct = match root.kind {
        Reference(path) => resolve(path)
        _ => None
      }
      let slot = if direct is Some(slot) {
        slot
      } else {
        let slot = pipe_physical_name(reserved, "aql_store_value_")
        reserved.push(slot)
        derives.push(
          (
            slot,
            append_pipe_expression(
              construction,
              expression,
              expression_visible,
              ranges,
              max_work,
              value_ranges~,
            ),
          ),
        )
        slot
      }
      projection.push(
        if field.value == slot {
          construction.text(slot)
        } else {
          construction.object([(field.value, construction.text(slot))])
        },
      )
    }
  }
  if fields.is_empty() {
    raise Abort(UnsupportedEffect)
  }
  let body : Array[Array[(String, @builder.Node)]] = []
  let start = [("from", construction.text(producer))]
  if !derives.is_empty() {
    start.push(("derive", construction.object(derives)))
    body.push(start)
  }
  let selected = if derives.is_empty() { start } else { [] }
  selected.push(("select", construction.array(projection)))
  let capture = pipe_physical_name(
    reserved_bindings + [producer],
    "aql_store_capture_",
  )
  reserved_bindings.push(capture)
  selected.push(("as", construction.text(capture)))
  body.push(selected)
  (
    {
      name: "",
      port: "aql_private_store",
      from: capture,
      fields,
      terminal: false,
      carrier_complete: false,
      update: None,
      store: true,
      insert: None,
      command: None,
    },
    body,
  )
}

///|
// Emit only the selected ordinary opcode. The retained publication and pair
// must still be captured by the installed owner; these strings issue no Ref.
fn lower_store_effect(
  construction : Construction,
  clause : @query.StoreEffectClause,
  target : ResolvedStoreTarget,
  default_port : String,
  retained : Array[RetainedResult],
) -> @builder.Node raise Abort {
  let captures = retained.filter(result => result.store)
  guard captures.length() == 1 else { raise Abort(UnsupportedEffect) }
  let capture = captures[0]
  let (target_ref, mapping_ref) = resolved_store_target(target)
  let from = construction.object([
    (
      "result",
      construction.text(retained_result_port(default_port, capture.port)),
    ),
  ])
  let (kind, body) = match resolved_store_target_command(target) {
    Some(pair) =>
      (
        "command",
        construction.object([
          ("from", from),
          (
            "target",
            construction.object([
              (
                "published_store",
                construction.object([
                  ("target_ref", construction.text(target_ref)),
                  ("mapping_ref", construction.text(mapping_ref)),
                ]),
              ),
            ]),
          ),
          (
            "contract",
            construction.text(
              @environment.command_target_id(
                @environment.store_command_target(pair),
              ),
            ),
          ),
          (
            "input",
            construction.object(
              capture.fields.map(field => {
                (
                  field,
                  construction.object([("field", construction.text(field))]),
                )
              }),
            ),
          ),
        ]),
      )
    None =>
      (
        "store",
        construction.object([
          ("target", construction.text(target_ref)),
          ("mapping", construction.text(mapping_ref)),
          ("from", from),
        ]),
      )
  }
  let name = clause.name.map(part => part.value).unwrap_or("aql_store_effect")
  guard name != "" else { raise Abort(UnsupportedEffect) }
  construction.object([(name, construction.object([(kind, body)]))])
}
