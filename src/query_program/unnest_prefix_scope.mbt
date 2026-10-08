///|
// Inspect the actual lowered Relation prefix through the existing member/type
// owners. These are schema facts only, never key, presence, capacity or Source
// admission evidence. In particular SET's current slot and its range snapshot
// are separate fields in this prefix; the initial schema cannot replace it.
fn unnest_prefix_element(
  construction : Construction,
  nodes : Array[@builder.Node],
  column : String,
  expression : @query.Expression,
  context : Context?,
  declarations : @parameters.Declarations?,
  limits : Limits,
  max_work : Int,
) -> @contract.Contract? raise Abort {
  let source = member_construct(
    @builder.snapshot(construction.builder, construction.array(nodes)),
  )
  let resolution : MemberResolution = {
    source,
    document: @query.expression_document(expression),
    limits,
    work: max_work,
    output_work: 0,
    probe_refused: false,
    replacements: Map([]),
  }
  let root = @builder.cursor(source)
  resolution.spend(root, @builder.usage(source).nodes)
  let names : Map[String, @carrier.Carrier?] = Map([])
  if context is Some(context) {
    for (name, schema) in context.input_schemas {
      names[name] = resolution.relation_carrier(root, Some(schema))
    }
  }
  let mut current : @carrier.Carrier? = None
  for step in @wire.elements(root).unwrap() {
    if resolution.probe_refused {
      return None
    }
    resolution.spend(step, 1)
    if member_text(step, "from") is Some(name) {
      current = names.get(name).bind(value => value)
    }
    let mut output : @carrier.Carrier? = None
    for index in 0..<@wire.object_length(step).unwrap() {
      let (tag, body) = @wire.field_at(step, index).unwrap()
      if ["from", "as", "meta"].contains(tag) {
        continue
      }
      if tag != "values" {
        resolution.expression(body, current.bind(member_rows), declarations)
      }
      output = resolution.operation_carrier(
        tag, body, current, names, declarations,
      )
    }
    current = output
    if member_text(step, "as") is Some(name) {
      names[name] = current
    }
  }
  guard current
    .bind(member_rows)
    .bind(rows => @schema.lookup(rows, @schema.Unqualified(column)))
    is Some(contract) else {
    return None
  }
  match contract.shape {
    @contract.Array(element, ..) => Some(element)
    _ =>
      raise Abort(
        Expression({
          issue: @expression.InvalidArguments,
          origin: @query.expression_origin(
            expression,
            @query.expression_root(expression),
          ),
        }),
      )
  }
}
