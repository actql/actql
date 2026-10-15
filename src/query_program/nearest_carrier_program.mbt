///|
fn script_nearest_prefix_pipeline(
  construction : Construction,
  query : @query.Query,
  context : Context,
  sources : ScriptSources,
  nodes : Array[@builder.Node],
  limits : Limits,
) -> @pipeline.CheckedPipeline raise Abort {
  let budget = construction.infer_budget
  if budget.remaining_work > sources.carrier_work {
    budget.remaining_work = sources.carrier_work
  }
  sources.carrier_work = 0
  let checked = checked_query_prefix_pipeline(
    construction,
    query,
    context,
    sources.stages + sources.prior_stages,
    sources.declarations,
    nodes,
    limits,
    budget,
  )
  sources.carrier_work = budget.remaining_work
  checked
}

///|
fn script_nearest_carrier(
  construction : Construction,
  query : @query.Query,
  input : Input,
  context : Context,
  sources : ScriptSources,
  limits : Limits,
  steps : Array[@builder.Node],
) -> @carrier.Carrier raise Abort {
  match sources.carriers.get(input.name) {
    Some(carrier) => carrier
    None => {
      let carrier = script_prefix_carrier(
        construction,
        query,
        context,
        sources,
        limits,
        steps,
        input.name,
      )
      sources.carriers[input.name] = carrier
      carrier
    }
  }
}

///|
// Only the actual checked prefix determines either input kind and intrinsic
// Vectors roles. Original named-input binding/capture remains with its owner.
fn lower_script_nearest_carrier(
  construction : Construction,
  query : @query.Query,
  known : Array[Input],
  context : Context,
  sources : ScriptSources,
  limits : Limits,
  steps : Array[@builder.Node],
  reserved : Array[String],
  output : String,
  retained : Array[RetainedResult]?,
  set_head? : Bool = false,
  graphs? : Array[ScriptGraph] = [],
) -> Input raise Abort {
  guard @query.operation_at(query, 0) is Some(Nearest(clause)) else {
    raise Abort(InvalidQuery)
  }
  let selected = selected_input(query, { ..context, inputs: known, }, limits)
  let input = bind_script_input(
    construction, selected, context, sources, steps, reserved,
  )
  let dependencies = nearest_dependencies(query, known)
  let candidate = dependencies.filter(peer => {
      same_relation_path(peer.relation, clause.relation)
    })[0]
  let candidate = bind_script_input(
    construction, candidate, context, sources, steps, reserved,
  )
  let query_carrier = script_nearest_carrier(
    construction, query, input, context, sources, limits, steps,
  )
  let candidate_carrier = script_nearest_carrier(
    construction, query, candidate, context, sources, limits, steps,
  )
  if query_carrier is @carrier.Relation(_) &&
    candidate_carrier is @carrier.Relation(_) {
    return lower_script_relation_term(
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
      set_head~,
      graphs~,
    )
  }
  let query_vectors = match query_carrier {
    @carrier.VectorValue(vectors) => Some((vectors, input.name))
    @carrier.Relation(_) => None
    _ => raise Abort(InvalidQuery)
  }
  let candidate_vectors = match candidate_carrier {
    @carrier.VectorValue(vectors) => Some(vectors)
    @carrier.Relation(_) => None
    _ => raise Abort(InvalidQuery)
  }
  if query_vectors is Some(_) &&
    @query.relation_alias(@query.graph_source_query(query)) is Some(_) {
    raise Abort(RangeAliasRequiresRelation)
  }
  let visible = columns(input).map(field => (field, field))
  let ranges = [(query_range_name(query), visible)]
  let (body, fields) = lower_nearest_steps(
    construction,
    clause,
    candidate,
    visible,
    ranges,
    columns(input),
    [("from", construction.text(input.name))],
    steps.length(),
    reserved.copy(),
    limits.max_expression_work,
    query_typed=query_vectors,
    candidate_typed=candidate_vectors,
    completion_limits=Some(limits),
    hit_only_projection=nearest_hit_only_projection(
      construction,
      query,
      0,
      clause.name,
    ),
    checked_prefix=Some(nodes => {
      script_nearest_prefix_pipeline(
        construction,
        query,
        context,
        sources,
        steps.copy() + nodes,
        limits,
      )
    }),
  )
  for members in body {
    steps.push(construction.object(members))
  }
  let bound_name = pipe_physical_name(reserved, "aql_nearest_rows_")
  reserved.push(bound_name)
  steps.push(
    construction.object([
      (
        "select",
        construction.array(fields.map(field => construction.text(field))),
      ),
      ("as", construction.text(bound_name)),
    ]),
  )
  let bound : Input = {
    relation: @query.relation(query),
    name: bound_name,
    source: StepReference,
    visible_fields: fields,
    graph_bindings: [],
  }
  // NEAREST publishes a new scope; prior operand aliases are not row aliases
  // of its output. Carry that ordinary scope snapshot through the continuation.
  let result_fields = fields.map(field => (field, field))
  sources.ranges[bound_name] = {
    visible: result_fields,
    columns: result_fields,
    ranges: [],
    star_ranges: [],
    value_table: false,
    value_columns: [],
    receivers: [],
    key_labels: seed_infer_key_labels(construction, [], result_fields),
    scalar_ranges: [],
  }
  let tail = @query.after_first_query_operation(query).unwrap()
  let visible_peers = known.map(peer => {
    if input_relation_matches(@query.relation(tail), peer) {
      { ..bound, relation: peer.relation, }
    } else {
      peer
    }
  })
  lower_script_relation(
    construction,
    tail,
    visible_peers,
    context,
    sources,
    limits,
    steps,
    reserved,
    output,
    retained~,
    set_head~,
    graphs~,
  )
}
