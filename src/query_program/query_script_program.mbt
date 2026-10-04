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
  sources : ScriptSources,
  limits : Limits,
  steps : Array[@builder.Node],
  reserved : Array[String],
  output : String,
  retained? : Array[RetainedResult]? = None,
) -> Input raise Abort {
  let known = if @query.cte_count(query) == 0 {
    known
  } else {
    validate_cte_scope(query, known)
    let mut scoped = known.copy()
    for index in 0..<@query.cte_count(query) {
      let cte = @query.cte_at(query, index).unwrap()
      let name = pipe_physical_name(reserved, "aql_script_cte_")
      reserved.push(name)
      let bound = lower_script_relation(
        construction,
        cte.query,
        scoped,
        context,
        sources,
        limits,
        steps,
        reserved,
        name,
      )
      scoped = scoped.filter(input => !input_relation_matches([cte.name], input))
      scoped.push({ ..bound, relation: [cte.name], })
    }
    scoped
  }
  if @query.set_part_count(query) > 0 {
    return lower_script_set_relation(
      construction, query, known, context, sources, limits, steps, reserved, output,
    )
  }
  lower_script_relation_term(
    construction,
    query,
    known,
    context,
    sources,
    limits,
    steps,
    reserved,
    output,
    retained~,
  )
}

///|
fn lower_script_relation_term(
  construction : Construction,
  query : @query.Query,
  known : Array[Input],
  context : Context,
  sources : ScriptSources,
  limits : Limits,
  steps : Array[@builder.Node],
  reserved : Array[String],
  output : String,
  retained? : Array[RetainedResult]? = None,
) -> Input raise Abort {
  if @query.graph_query(query) is Some(_) {
    raise Abort(UnsupportedGraph)
  }
  if @query.join_part_count(query) > 0 {
    return lower_script_join_relation(
      construction, query, known, context, sources, limits, steps, reserved, retained,
    )
  }
  let selected = selected_input(query, { ..context, inputs: known, }, limits)
  let fields = query_columns(query, selected)
  let mut start_at = 0
  let predicate = if context.captured_stage is Some(_) &&
    selected.source is Captured(_) &&
    sources.unshared.contains(selected.name) {
    match @query.operation_at(query, 0) {
      Some(Where(expression)) => {
        start_at = 1
        Some(
          append_expression(
            construction,
            expression,
            query,
            selected,
            fields,
            limits.max_expression_work,
          ),
        )
      }
      _ => None
    }
  } else {
    None
  }
  let input = bind_script_input(
    construction,
    selected,
    context,
    sources,
    steps,
    reserved,
    predicate~,
  )
  let (body, output_fields) = compile_steps(
    construction,
    query,
    input,
    fields,
    limits.max_expression_work,
    limits.max_collection_items,
    limits.max_collection_bytes,
    start_at,
    false,
    output,
    retained~,
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
pub fn compile_query_script(
  script : @query.QueryScript,
  context : Context,
  limits : Limits,
) -> Result[@program.Program, Issue] {
  if context.program_id.is_empty() ||
    context.stage_id.is_empty() ||
    context.stage_result.is_empty() ||
    context.result_name.is_empty() ||
    context.captured_stage == Some("") ||
    context.captured_stage == Some(context.stage_id) ||
    context.inputs.any(input => input.name.is_empty()) ||
    limits.max_expression_work < 0 {
    return Err(InvalidContext)
  }
  for index, input in context.inputs {
    for previous in 0..<index {
      if context.inputs[previous].name == input.name {
        return Err(InvalidContext)
      }
    }
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
    let sources : ScriptSources = {
      declarations: [],
      stages: [],
      bound: Map([]),
      unshared: unshared_script_sources(script, context.inputs),
    }
    let mut known = context.inputs.copy()
    let mut graphs : Array[ScriptGraph] = []
    let reserved = known.map(input => input.name)
    for index in 0..<@query.data_declaration_count(script) {
      let declaration = @query.data_declaration_at(script, index).unwrap()
      let output = pipe_physical_name(reserved, "aql_data_")
      reserved.push(output)
      match declaration.value {
        RelationQuery(query) => {
          let graph = script_graph_input(query, graphs)
          if graph is Some(graph) {
            let bound = lower_script_graph_calls(
              construction, query, graph, steps, reserved,
            )
            if @query.operation_count(@query.after_graph_calls(query)) != 0 {
              raise Abort(UnsupportedGraph)
            }
            graphs = graphs.filter(graph => {
              !same_name(graph.name, declaration.name)
            })
            graphs.push({ ..bound, name: declaration.name, })
            known = known.filter(input => {
              !(input.relation.length() == 1 &&
              same_name(input.relation[0], declaration.name))
            })
            continue
          }
          let bound = lower_script_relation(
            construction, query, known, context, sources, limits, steps, reserved,
            output,
          )
          // Body resolution precedes binding. Existing published names may be
          // shadowed only afterward; no forward/recursive DATA reference exists.
          known = known.filter(input => {
            !(input.relation.length() == 1 &&
            same_name(input.relation[0], declaration.name))
          })
          known.push({ ..bound, relation: [declaration.name], })
          graphs = graphs.filter(graph => {
            !same_name(graph.name, declaration.name)
          })
        }
        PropertyGraph(mapping) => {
          // Resolve against the original source kind: binding a captured
          // Relation must not turn its quoted-name rules into DATA alias rules.
          let producer_names : Map[String, String] = Map([])
          let references = mapping.nodes.map(node => node.producer) +
            mapping.edges.map(edge => edge.producer)
          for path in references {
            let input = property_mapping_input(path, known)
            if !producer_names.contains(input.name) {
              let bound = bind_script_input(
                construction, input, context, sources, steps, reserved,
              )
              producer_names[input.name] = bound.name
            }
          }
          steps.push(
            lower_property_graph_step(
              construction,
              mapping,
              known,
              output,
              producer_names~,
            ),
          )
          graphs = graphs.filter(graph => {
            !same_name(graph.name, declaration.name)
          })
          graphs.push({
            name: declaration.name,
            producer: output,
            mapping,
            inputs: known.copy(),
          })
          // A Graph has its own Carrier, never a fabricated Relation binding.
          known = known.filter(input => {
            !(input.relation.length() == 1 &&
            same_name(input.relation[0], declaration.name))
          })
        }
        NamedGraphCall(_) =>
          // Explicit Graph-list construction has no adapted output contract
          // yet. Never add the current Graph or reinterpret it as a Relation.
          raise Abort(UnsupportedGraph)
      }
    }
    let mut query = @query.script_query(script)
    let mut stage_context = context
    let mut stage_steps = steps
    let mut stage_sources = sources
    let mut stage_known = known
    let stages : Array[@builder.Node] = []
    let exports : Array[(String, (String, String))] = []
    while true {
      let input_name = pipe_physical_name(
        reserved, "aql_script_continuation_input_",
      )
      let split = @query.effect_result_continuation(query, {
        value: input_name,
        quoted: true,
      })
      let current = split.map(pair => pair.0).unwrap_or(query)
      let retained : Array[RetainedResult] = []
      let result = if @query.graph_query(current) is Some(_) {
        lower_script_keyed_graph_query(
          construction, current, graphs, limits, stage_steps, reserved, "aql_script_result",
          retained,
        )
      } else {
        lower_script_relation(
          construction,
          current,
          stage_known,
          stage_context,
          stage_sources,
          limits,
          stage_steps,
          reserved,
          "aql_script_result",
          retained=Some(retained),
        )
      }
      // The current Model component owns a complete Unit. Crossing a public
      // Result here must not drop private immutable range snapshots or make
      // another retained root silently refer to its terminal output.
      if split is Some(_) &&
        (retained.length() != 1 || !retained[0].carrier_complete) {
        raise Abort(UnsupportedEffect)
      }
      let stage_entries = [
        ("id", construction.text(stage_context.stage_id)),
        ("inputs", construction.object(stage_sources.declarations)),
        ("steps", construction.array(stage_steps)),
        (
          "results",
          retained_stage_results(
            construction,
            stage_context.stage_result,
            construction.object([
              ("from", construction.text(result.name)),
              (
                "fields",
                construction.array(
                  result.visible_fields.map(field => construction.text(field)),
                ),
              ),
            ]),
            retained,
          ),
        ),
      ]
      if @query.terminal_effect(current) is Some(effect) {
        stage_entries.push(
          (
            "effects",
            lower_update_effect(
              construction,
              effect,
              stage_context.stage_result,
              retained,
              limits.max_expression_work,
            ),
          ),
        )
      }
      stages.push(construction.object(stage_entries))
      for
        (name, port) in retained_result_exports(stage_context, retained).unwrap_or([
            (stage_context.result_name, stage_context.stage_result),
          ],
        ) {
        if exports.any(entry => ascii_upper(entry.0) == ascii_upper(name)) {
          raise Abort(DuplicateOutput)
        }
        exports.push((name, (stage_context.stage_id, port)))
      }
      guard split is Some((_, continuation)) else { break }
      // The same Program imports the retained checked producer through the
      // ordinary Stage Result edge. Its Source/Model is never called by this
      // continuation, and the terminal Effect stays with its existing owner.
      let reference = construction.object([
        (
          "result",
          construction.object([
            ("stage", construction.text(stage_context.stage_id)),
            ("result", construction.text(stage_context.stage_result)),
          ]),
        ),
      ])
      stage_sources = {
        declarations: [(input_name, reference)],
        stages: sources.stages,
        bound: Map([]),
        unshared: [],
      }
      stage_known = [
        {
          relation: [{ value: input_name, quoted: true, }],
          name: input_name,
          source: StepReference,
          visible_fields: result.visible_fields,
          graph_bindings: [],
        },
      ]
      let mut next_stage = "aql_script_continuation_" +
        (stages.length() - 1).to_string()
      while reserved.contains(next_stage) ||
            next_stage == context.stage_id ||
            context.captured_stage
            .map(base => {
              next_stage == base ||
              Array::makei(sources.stages.length(), i => {
                base + "_" + i.to_string()
              }).contains(next_stage)
            })
            .unwrap_or(false) {
        next_stage += "_generated"
      }
      reserved.push(input_name)
      reserved.push(next_stage)
      stage_context = { ..context, stage_id: next_stage, captured_stage: None, }
      stage_steps = []
      query = continuation
    }
    let root = program_root(
      construction,
      context,
      sources.stages + stages,
      staged_result_exports=Some(exports),
    )
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
