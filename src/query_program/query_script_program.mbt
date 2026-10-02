///|
// Rename only the structural step binding. The value, its schema and source
// provenance are imported through the existing bounded source builder.
fn import_script_seed(
  construction : Construction,
  source : @wire.Cursor,
  name : String,
) -> @builder.Node raise Abort {
  let fields = @wire.object_field_names(source)
  let fields = match fields {
    Ok(fields) => fields
    Err(_) => raise Abort(InvalidContext)
  }
  let entries : Array[(String, @builder.Node)] = []
  let object = @wire.open_object(source).unwrap()
  for field in fields {
    if field != "as" {
      entries.push(
        (
          field,
          import_query_cursor(
            construction,
            @wire.lookup(object, field).unwrap(),
          ),
        ),
      )
    }
  }
  entries.push(("as", construction.text(name)))
  construction.object(entries)
}

///|
fn lower_script_relation(
  construction : Construction,
  query : @query.Query,
  known : Array[Input],
  context : Context,
  limits : Limits,
  steps : Array[@builder.Node],
  reserved : Array[String],
  output : String,
) -> Input raise Abort {
  if @query.graph_query(query) is Some(_) {
    raise Abort(UnsupportedGraph)
  }
  if @query.cte_count(query) > 0 {
    raise Abort(UnsupportedCte)
  }
  if @query.set_part_count(query) > 0 {
    raise Abort(UnsupportedSet)
  }
  if @query.join_part_count(query) > 0 {
    raise Abort(UnsupportedJoin)
  }
  let selected = selected_input(query, { ..context, inputs: known, }, limits)
  let fields = query_columns(query, selected)
  let input = match selected.source {
    GeneratedValues(source) => {
      let name = pipe_physical_name(reserved, "aql_script_seed_")
      reserved.push(name)
      steps.push(import_script_seed(construction, source, name))
      { ..selected, name, source: StepReference, visible_fields: fields, }
    }
    StepReference => selected
    // These paths must retain their existing acquisition/Stage ownership.
    // They are not silently copied into an independently executable Values step.
    Captured(_) | StageResult(_, _) => raise Abort(InvalidContext)
  }
  let (body, output_fields) = compile_steps(
    construction,
    query,
    input,
    fields,
    limits.max_expression_work,
    limits.max_collection_items,
    limits.max_collection_bytes,
    0,
    false,
    output,
  )
  steps.append(body)
  let name = if body.is_empty() { input.name } else { output }
  {
    relation: [],
    name,
    source: StepReference,
    visible_fields: output_fields,
    graph_bindings: [],
  }
}

///|
// Compose producer references in one existing pipeline. DATA does not add
// Stage Results, Artifact boundaries or physical task requests.
fn compile_query_script(
  script : @query.QueryScript,
  context : Context,
  limits : Limits,
) -> Result[@program.Program, Issue] {
  if context.program_id.is_empty() ||
    context.stage_id.is_empty() ||
    context.stage_result.is_empty() ||
    context.result_name.is_empty() ||
    limits.max_expression_work < 0 {
    return Err(InvalidContext)
  }
  let document = @query.script_document(script)
  let generated = @origin.range(document, 0, 0, kind=Generated).unwrap()
  let builder = match @builder.create(document, limits.source) {
    Ok(builder) => builder
    Err(issue) => return Err(Construction(issue))
  }
  let construction : Construction = { builder, generated, }
  try {
    let steps : Array[@builder.Node] = []
    let mut known = context.inputs.copy()
    let reserved = known.map(input => input.name)
    for index in 0..<@query.data_declaration_count(script) {
      let declaration = @query.data_declaration_at(script, index).unwrap()
      let output = pipe_physical_name(reserved, "aql_data_")
      reserved.push(output)
      match declaration.value {
        RelationQuery(query) => {
          let bound = lower_script_relation(
            construction, query, known, context, limits, steps, reserved, output,
          )
          // Body resolution precedes binding. Existing published names may be
          // shadowed only afterward; no forward/recursive DATA reference exists.
          known = known.filter(input => {
            !(input.relation.length() == 1 &&
            same_name(input.relation[0], declaration.name))
          })
          known.push({ ..bound, relation: [declaration.name], })
        }
        PropertyGraph(mapping) => {
          steps.push(
            lower_property_graph_step(construction, mapping, known, output),
          )
          // Graph-query consumer adaptation follows this mapping boundary.
          // A Graph is never masqueraded as a Relation binding.
          raise Abort(UnsupportedGraph)
        }
      }
    }
    let result = lower_script_relation(
      construction,
      @query.script_query(script),
      known,
      context,
      limits,
      steps,
      reserved,
      "aql_script_result",
    )
    let stage = construction.object([
      ("id", construction.text(context.stage_id)),
      ("inputs", construction.object([])),
      ("steps", construction.array(steps)),
      (
        "results",
        construction.object([
          (
            context.stage_result,
            construction.object([
              ("from", construction.text(result.name)),
              (
                "fields",
                construction.array(
                  result.visible_fields.map(field => construction.text(field)),
                ),
              ),
            ]),
          ),
        ]),
      ),
    ])
    let root = program_root(construction, context, [stage])
    let source = match @builder.finish(builder, root) {
      Ok(source) => source
      Err(issue) => raise Abort(Construction(issue))
    }
    match @program.admit_generated_source(source, limits.program) {
      Ok(program) => Ok(program)
      Err(issue) => Err(Admission(issue))
    }
  } catch {
    Abort(issue) => {
      @builder.discard(builder)
      Err(issue)
    }
  }
}
