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
  carry_ranges? : Bool = false,
  retain_value_table? : Bool = false,
  graphs? : Array[ScriptGraph] = [],
  positional_set_output? : Bool = false,
  allow_nonrelation? : Bool = false,
  set_head? : Bool = false,
) -> Input raise Abort {
  let (known, graphs) = lower_script_bindings(
    construction, query, known, graphs, context, sources, limits, steps, reserved,
  )
  let query = @query.after_query_bindings(query)
  let (query, known) = lower_script_relation_primary(
    construction, query, known, context, sources, limits, steps, reserved,
  )
  let current = lower_script_primary(
    construction, query, known, graphs, context, sources, limits, steps, reserved,
  )
  let query = @query.after_producer_primary(query)
  let graph = current_script_graph(current, query, graphs, known)
  check_script_graph_expectation(
    construction, query, graph, known, context, sources, limits, steps, reserved,
  )
  let query = if graph is Some(_) {
    @query.graph_source_query(query)
  } else {
    query
  }
  // The outer set owner already owns its right operands and final operations.
  // A Graph-row head continuation lowers only this first term's operations.
  let single_term = set_head || @query.set_part_count(query) == 0
  if graph is Some(graph) && single_term {
    if @query.graph_query(query)
      .map(value => value.pattern is Some(_))
      .unwrap_or(false) {
      return lower_script_keyed_graph_query(
        construction,
        query,
        graphs,
        limits,
        steps,
        reserved,
        output,
        retained.unwrap_or([]),
        known~,
        current=Some(graph),
      )
    }
    if script_has_graph_rows(query) {
      return lower_script_graph_rows(
        construction,
        query,
        graph,
        limits,
        steps,
        reserved,
        output,
        known~,
        graphs~,
        retained~,
        positional_set_output~,
        set_head~,
        continuation=Some((context, sources)),
        allow_nonrelation~,
      )
    }
    raise Abort(UnsupportedGraph)
  }
  if single_term && script_has_carrier_calls(query) {
    return lower_script_carrier_calls(
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
      allow_nonrelation~,
      set_head~,
    )
  }
  if single_term && @query.operation_at(query, 0) is Some(Nearest(_)) {
    return lower_script_nearest_carrier(
      construction,
      query,
      known,
      context,
      sources,
      limits,
      steps,
      reserved,
      output,
      retained,
      set_head~,
      graphs~,
    )
  }
  if single_term {
    let input = known
      .filter(input => input_relation_matches(@query.relation(query), input))
      .get(0)
    if input is Some(input) &&
      sources.carriers.get(input.name) is Some(carrier) &&
      !(carrier is @carrier.Relation(_)) {
      let query = @query.graph_source_query(query)
      if @query.relation_alias(query) is Some(_) ||
        Array::makei(@query.operation_count(query), i => {
          @query.operation_at(query, i)
        }).any(operation => operation is Some(Alias(_))) {
        raise Abort(RangeAliasRequiresRelation)
      }
      guard allow_nonrelation &&
        @query.operation_count(query) == 0 &&
        !has_retained_result(query) else {
        raise Abort(UnsupportedProjection)
      }
      return input
    }
  }
  if !single_term {
    return lower_script_set_relation(
      construction,
      query,
      known,
      context,
      sources,
      limits,
      steps,
      reserved,
      output,
      graphs~,
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
    carry_ranges~,
    retain_value_table~,
    graphs~,
    positional_set_output~,
    set_head~,
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
  carry_ranges? : Bool = false,
  retain_value_table? : Bool = false,
  graphs? : Array[ScriptGraph] = [],
  positional_set_output? : Bool = false,
  set_head? : Bool = false,
) -> Input raise Abort {
  if script_has_graph_rows(query) {
    let graph = require_script_graph_input(
      current_script_graph(None, query, graphs, known),
      query,
      known,
    )
    return lower_script_graph_rows(
      construction,
      query,
      graph,
      limits,
      steps,
      reserved,
      output,
      known~,
      graphs~,
      retained~,
      positional_set_output~,
      set_head~,
      continuation=Some((context, sources)),
    )
  }
  if @query.graph_query(query) is Some(_) {
    raise Abort(UnsupportedGraph)
  }
  let preserved : Array[JoinChainScope]? = if carry_ranges {
    Some([])
  } else {
    None
  }
  let value_scope : Array[JoinChainScope] = []
  if @query.join_part_count(query) > 0 {
    let bound = lower_script_join_relation(
      construction,
      query,
      known,
      context,
      sources,
      limits,
      steps,
      reserved,
      retained,
      preserved_scope=preserved,
      positional_set_output~,
    )
    if preserved is Some(scopes) {
      sources.ranges[bound.name] = scopes[0]
    }
    return bound
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
  let nearest_inputs = bind_script_nearest_inputs(
    construction, query, known, selected, input, context, sources, steps, reserved,
  )
  let nearest_vectors = script_nearest_vector_inputs(
    construction, query, nearest_inputs, context, sources, limits, steps,
  )
  let (body, output_fields) = compile_steps(
    construction,
    query,
    input,
    fields,
    limits.max_expression_work,
    limits,
    limits.max_collection_items,
    limits.max_collection_bytes,
    start_at,
    false,
    output,
    nearest_inputs~,
    nearest_vectors~,
    retained~,
    parameter_declarations=context.parameter_declarations,
    initial_scope=script_input_scope(
      sources,
      input.name,
      query_range_name(query),
    ),
    preserved_scope=preserved,
    value_table_scope=if retain_value_table { Some(value_scope) } else { None },
    prefix_steps=steps.copy(),
    prefix_context=Some(context),
    positional_set_output~,
  )
  steps.append(body)
  let name = if body.is_empty() && carry_ranges {
    // Scope belongs to this continuation, never to the shared Source binding.
    steps.push(
      construction.object([
        ("from", construction.text(input.name)),
        (
          "select",
          construction.array(
            output_fields.map(field => construction.text(field)),
          ),
        ),
        ("as", construction.text(output)),
      ]),
    )
    output
  } else if body.is_empty() {
    input.name
  } else {
    output
  }
  if preserved is Some(scopes) {
    sources.ranges[name] = scopes[0]
  } else if value_scope.get(0) is Some(scope) {
    sources.value_tables[name] = scope
  }
  {
    relation: [],
    name,
    source: StepReference,
    visible_fields: output_fields,
    graph_bindings: [],
  }
}

///|
// Compose WITH producer references in one existing pipeline. Binding does not add
// Stage Results, Artifact boundaries or physical task requests.
pub fn compile_query_script(
  script : @query.QueryScript,
  context : Context,
  limits : Limits,
  table_writes? : Array[TableWriteBinding] = [],
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
  let parameter_names = query_parameter_names(
    context.parameter_declarations,
    limits.max_expression_work,
  ) catch {
    Abort(issue) => {
      @builder.discard(builder)
      return Err(issue)
    }
  }
  let construction : Construction = {
    builder,
    generated,
    model_tasks: context.model_tasks,
    parameter_names,
  }
  try {
    let steps : Array[@builder.Node] = []
    let sources : ScriptSources = {
      declarations: [],
      stages: [],
      bound: Map([]),
      unshared: unshared_script_sources(script, context.inputs),
      ranges: Map([]),
      value_tables: Map([]),
      binding_ranges: [],
      carriers: Map([]),
      carrier_work: limits.max_expression_work,
    }
    let root = @query.script_query(script)
    let has_bindings = @query.query_binding_count(root) > 0
    let reserved = context.inputs.map(input => input.name)
    let (known, graphs) = lower_script_bindings(
      construction,
      root,
      context.inputs,
      [],
      context,
      sources,
      limits,
      steps,
      reserved,
    )
    let (root, known) = lower_script_relation_primary(
      construction, root, known, context, sources, limits, steps, reserved,
    )
    let primary_graph = lower_script_primary(
      construction, root, known, graphs, context, sources, limits, steps, reserved,
    )
    let tail = @query.after_producer_primary(@query.after_query_bindings(root))
    let current_graph = current_script_graph(primary_graph, tail, graphs, known)
    let mut query = if current_graph is Some(_) {
      @query.graph_source_query(tail)
    } else {
      tail
    }
    let mut stage_context = context
    let mut stage_steps = steps
    let mut stage_sources = sources
    let mut stage_known = known
    let stages : Array[@builder.Node] = []
    let stage_arrays : Array[Array[@builder.Node]] = []
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
      let resolved_graph = if stages.is_empty() {
        current_graph
      } else {
        current_script_graph(None, current, graphs, stage_known)
      }
      check_script_graph_expectation(
        construction, current, resolved_graph, stage_known, stage_context, stage_sources,
        limits, stage_steps, reserved,
      )
      let retained : Array[RetainedResult] = []
      let graph_row_set = script_has_graph_rows(current) &&
        @query.set_part_count(current) > 0
      let result = if script_has_graph_rows(current) &&
        !graph_row_set &&
        !script_has_carrier_calls(current) {
        let graph = require_script_graph_input(
          resolved_graph, current, stage_known,
        )
        lower_script_graph_rows(
          construction,
          current,
          graph,
          limits,
          stage_steps,
          reserved,
          "aql_script_result",
          known=stage_known,
          graphs~,
          retained=Some(retained),
          continuation=Some((stage_context, stage_sources)),
        )
      } else if @query.graph_query(current) is Some(_) && !graph_row_set {
        lower_script_keyed_graph_query(
          construction,
          current,
          graphs,
          limits,
          stage_steps,
          reserved,
          "aql_script_result",
          retained,
          known=stage_known,
          current=resolved_graph,
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
          graphs~,
        )
      }
      // The current Model component owns a complete Unit. Crossing a public
      // Result here must not drop private immutable range snapshots or make
      // another retained root silently refer to its terminal output.
      if split is Some(_) &&
        (retained.length() != 1 || !retained[0].carrier_complete) {
        raise Abort(UnsupportedEffect)
      }
      let table_effect = @query.terminal_table_effect(current)
      let stage_entries = [
        ("id", construction.text(stage_context.stage_id)),
        ("inputs", construction.object(stage_sources.declarations)),
        ("steps", construction.array(stage_steps)),
        (
          "results",
          if table_effect is Some(_) && retained.is_empty() {
            construction.object([])
          } else {
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
            )
          },
        ),
      ]
      if table_effect is Some(clause) {
        let selected = match
          resolve_table_write_binding(
            table_writes,
            clause.target,
            clause.allow_replace,
            limits.max_expression_work,
          ) {
          Ok(value) => value
          Err(issue) => raise Abort(TableWriteBinding(issue))
        }
        let input_name = "aql_table_input"
        stage_entries.push(
          (
            "table_inputs",
            construction.object([
              (
                input_name,
                construction.object([
                  ("from", construction.text(result.name)),
                  (
                    "fields",
                    construction.array(
                      result.visible_fields.map(field => {
                        construction.text(field)
                      }),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        )
        stage_entries.push(
          (
            "effects",
            lower_table_effect(construction, clause, selected, input_name),
          ),
        )
      }
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
      stage_arrays.push(stage_steps)
      for
        (name, port) in retained_result_exports(stage_context, retained).unwrap_or([
            (stage_context.result_name, stage_context.stage_result),
          ],
        ) {
        if table_effect is Some(_) && retained.is_empty() {
          continue
        }
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
        ranges: Map([]),
        value_tables: Map([]),
        binding_ranges: sources.binding_ranges,
        carriers: Map([]),
        carrier_work: stage_sources.carrier_work,
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
    if !has_bindings {
      return admit_query_source(source, document, context, limits)
    }
    // Resolve and check every authored binding before demand selection. This
    // temporary syntax owner does not publish another Program/Plan/Run.
    let source = resolve_query_members(source, document, context, limits)
    let complete = match
      @program.admit_generated_source(source, limits.program) {
      Ok(program) => program
      Err(issue) => return Err(Admission(issue))
    }
    let checked = match check_query_bindings(complete, context, limits) {
      Ok(checked) => checked
      Err(issue) => return Err(BindingPreparation(issue))
    }
    let demand = match
      trace_query_binding_demand(
        checked,
        stage_arrays,
        sources.stages.length(),
        sources.binding_ranges,
        limits.max_expression_work,
      ) {
      Ok(demand) => demand
      Err(issue) => return Err(BindingPreparation(Demand(issue)))
    }
    let source = match
      prune_query_binding_source(source, demand, document, limits) {
      Ok(source) => source
      Err(issue) => return Err(issue)
    }
    let program = match
      @program.admit_generated_source(source, limits.program) {
      Ok(program) => program
      Err(issue) => return Err(Admission(issue))
    }
    // New syntax gets its own common owners. Never transfer conditional
    // evidence issued for the complete temporary pipeline onto the pruned one.
    match prepare_query_bindings(program, context, limits) {
      Ok(_) => Ok(program)
      Err(issue) => Err(BindingPreparation(issue))
    }
  } catch {
    Abort(issue) => {
      @builder.discard(builder)
      Err(issue)
    }
  }
}
