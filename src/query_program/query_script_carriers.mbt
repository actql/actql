///|
// The current prefix has no synthetic Result. Its actual inputs, capture
// imports and source origins are checked by the shared topology owner. Reading
// a Carrier neither closes deferred order/value obligations nor issues a Plan.
fn script_prefix_carrier(
  construction : Construction,
  query : @query.Query,
  context : Context,
  sources : ScriptSources,
  limits : Limits,
  steps : Array[@builder.Node],
  producer : String,
) -> @carrier.Carrier raise Abort {
  let root = program_root(
    construction,
    context,
    sources.stages +
    [
      construction.object([
        ("id", construction.text(context.stage_id)),
        ("inputs", construction.object(sources.declarations)),
        ("steps", construction.array(steps)),
        ("results", construction.object([])),
      ]),
    ],
    staged_result_exports=Some([]),
  )
  let source = match @builder.snapshot(construction.builder, root) {
    Ok(source) => source
    Err(issue) => raise Abort(Construction(issue))
  }
  let source = resolve_query_members(
    source,
    @query.query_document(query),
    context,
    { ..limits, max_expression_work: sources.carrier_work, },
  )
  let prefix = match @program.admit_generated_prefix(source, limits.program) {
    Ok(prefix) => prefix
    Err(issue) => raise Abort(Admission(issue))
  }
  let checked = match
    check_query_prefix(prefix, context, {
      ..limits,
      max_expression_work: sources.carrier_work,
    }) {
    Ok(checked) => checked
    Err(issue) => raise Abort(BindingPreparation(issue))
  }
  let usage = @stage_results.topology_usage(checked.topology)
  if usage.work < 0 || usage.work > sources.carrier_work {
    raise Abort(BindingPreparation(Demand(WorkLimit)))
  }
  sources.carrier_work -= usage.work
  let stage = @stage_results.topology_stage_at(
    checked.topology,
    sources.stages.length(),
  ).unwrap()
  let pipeline = @pipeline_parameters.pipeline(
    @stage_parameters.collection(@stage_results.topology_stage_source(stage)),
  )
  let target = @pipeline.lookup(pipeline, producer).unwrap()
  match @pipeline.carrier_at(pipeline, target) {
    Some(carrier) => carrier
    None => raise Abort(UnsupportedProjection)
  }
}

///|
fn script_carrier_operation(name : String) -> Bool {
  [
    "to_vectors", "normalize_vectors", "score_vectors", "pool_vectors", "vectors",
    "to_events", "row_window", "window_events", "watermark_events", "dedupe_events",
    "session", "events", "watermark_rows", "lag",
  ].contains(name)
}

///|
fn script_has_carrier_calls(query : @query.Query) -> Bool {
  @query.operation_at(query, 0) is Some(GraphCall(call)) &&
  script_carrier_operation(call.operation)
}

///|
fn script_carrier_columns(carrier : @carrier.Carrier) -> Array[String] {
  let records = match carrier {
    @carrier.Relation(rows) => Some(rows)
    @carrier.VectorValue(vectors) => Some(@carrier.vector_records(vectors))
    @carrier.EventValue(events) => Some(@carrier.event_records(events))
    _ => None
  }
  match records {
    Some(rows) =>
      @carrier.fields(rows).map(field => @schema.reference_name(field.name))
    None => []
  }
}

///|
// Carrier fields use the same retained scope as ordinary FieldRef selectors.
// A miss must never fall back to an input range removed by a projection.
fn script_carrier_field_name(
  path : Array[@query.NamePart],
  query : @query.Query,
  input : Input,
  sources : ScriptSources,
) -> String raise Abort {
  let resolved = match
    script_input_scope(sources, input.name, query_range_name(query)) {
    Some(scope) => pipe_slot(path, scope.visible, scope.ranges)
    None => resolve_column(path, query, input, columns(input))
  }
  guard resolved is Some(name) else { raise Abort(UnknownColumn) }
  name
}

///|
// A field reference is distinct from a String value. Reuse ordinary column
// resolution for a Relation range; Vectors/Events have no row-range alias.
fn script_carrier_field(
  construction : Construction,
  argument : @query.SgaArgument,
  query : @query.Query,
  input : Input,
  sources : ScriptSources,
) -> @builder.Node raise Abort {
  match argument {
    FieldReference(path) =>
      construction.text(script_carrier_field_name(path, query, input, sources))
    ListValue(items) =>
      construction.array(
        items.map(item => {
          script_carrier_field(construction, item, query, input, sources)
        }),
      )
    _ => raise Abort(InvalidQuery)
  }
}

///|
// Resolve only the field roles. Direction, NULL placement, partition equality
// and top-tie obligations are checked by the existing common Event owner.
fn script_carrier_order(
  construction : Construction,
  argument : @query.SgaArgument,
  query : @query.Query,
  input : Input,
  sources : ScriptSources,
  known : Array[Input],
  limits : Limits,
) -> @builder.Node raise Abort {
  match argument {
    ListValue(items) =>
      construction.array(
        items.map(item => {
          script_carrier_order(
            construction, item, query, input, sources, known, limits,
          )
        }),
      )
    FieldMapValue(fields) =>
      construction.object(
        fields.map(field => {
          (
            script_carrier_field_name(field.0, query, input, sources),
            script_traversal_argument(construction, field.1, known, limits),
          )
        }),
      )
    ObjectValue(fields) =>
      construction.object(
        fields.map(field => {
          (
            field.0,
            if field.0 == "field" {
              script_carrier_field(construction, field.1, query, input, sources)
            } else {
              script_traversal_argument(construction, field.1, known, limits)
            },
          )
        }),
      )
    _ => script_traversal_argument(construction, argument, known, limits)
  }
}

///|
fn lower_script_carrier_calls(
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
  allow_nonrelation? : Bool = false,
) -> Input raise Abort {
  let selected = selected_input(query, { ..context, inputs: known, }, limits)
  let mut input = bind_script_input(
    construction, selected, context, sources, steps, reserved,
  )
  let mut carrier = script_prefix_carrier(
    construction,
    query,
    context,
    sources,
    limits,
    steps,
    input.name,
  )
  // An installed producer can precede other lowered bindings. Its actual slot,
  // rather than the last operation in the prefix, owns its declared Carrier.
  if sources.carriers.get(input.name) is Some(known_carrier) {
    carrier = known_carrier
  }
  let query = if carrier is @carrier.Relation(_) {
    query
  } else {
    let query = @query.graph_source_query(query)
    if @query.relation_alias(query) is Some(_) {
      raise Abort(RangeAliasRequiresRelation)
    }
    query
  }
  for index in 0..<@query.operation_count(query) {
    guard @query.operation_at(query, index) is Some(GraphCall(call)) else {
      break
    }
    // after_graph_calls removes the whole leading call sequence. Every call
    // in that sequence must have been lowered, never silently discarded.
    if !script_carrier_operation(call.operation) {
      raise Abort(UnsupportedGraph)
    }
    let fields = match call.operation {
      "to_vectors" => ["id", "vector"]
      "pool_vectors" => ["by", "vector"]
      "to_events" => ["id", "time"]
      "row_window" | "watermark_rows" => ["time"]
      "dedupe_events" => ["by"]
      "lag" => ["partition_by", "field"]
      "session" =>
        if carrier is @carrier.Relation(_) {
          ["id", "time", "by"]
        } else {
          ["by"]
        }
      _ => []
    }
    let allowed = match call.operation {
      "to_vectors" | "to_events" => fields
      "session" => fields + ["gap"]
      "score_vectors" => ["query", "metric"]
      "pool_vectors" => ["by", "vector", "method", "output_id"]
      "row_window" => ["kind", "time", "size", "step", "offset"]
      "window_events" => ["kind", "size", "step", "offset"]
      "watermark_events" => ["watermark_ms", "policy"]
      "watermark_rows" => ["time", "late_policy", "watermark_ms", "max_skew"]
      "dedupe_events" => ["by", "order_by"]
      "lag" => ["partition_by", "order_by", "field", "output", "offset"]
      _ => []
    }
    // Optional pool roles are preserved as authored. The common pool owner
    // requires a Relation component field, validates member-key evidence and
    // permits only an exact Vectors component-role restatement.
    let required = if call.operation == "pool_vectors" {
      ["by", "method"]
    } else if call.operation == "row_window" {
      ["kind", "time", "size"]
    } else if call.operation == "window_events" {
      ["kind", "size"]
    } else if call.operation == "lag" {
      ["partition_by", "order_by", "field", "output"]
    } else if call.operation == "watermark_rows" {
      // The common watermark owner checks exactly one threshold source.
      // Never choose precedence or synthesize a threshold in the frontend.
      ["time", "late_policy"]
    } else {
      allowed
    }
    guard call.arguments.all(argument => allowed.contains(argument.0)) &&
      required.all(name => call.arguments.any(argument => argument.0 == name)) else {
      raise Abort(InvalidQuery)
    }
    let origin = @origin.range(
      @query.query_document(query),
      call.start,
      call.end,
    ).unwrap()
    let construction = { ..construction, generated: origin, }
    let body = if call.arguments.is_empty() {
      construction.add(Bool(true))
    } else {
      construction.object(
        call.arguments.map(argument => {
          let value = if fields.contains(argument.0) {
            script_carrier_field(
              construction,
              argument.1,
              query,
              input,
              sources,
            )
          } else if ["dedupe_events", "lag"].contains(call.operation) &&
            argument.0 == "order_by" {
            script_carrier_order(
              construction,
              argument.1,
              query,
              input,
              sources,
              known,
              limits,
            )
          } else {
            script_traversal_argument(construction, argument.1, known, limits)
          }
          (argument.0, value)
        }),
      )
    }
    let name = pipe_physical_name(reserved, "aql_carrier_")
    reserved.push(name)
    steps.push(
      construction.object([
        ("from", construction.text(input.name)),
        (call.operation, body),
        ("as", construction.text(name)),
      ]),
    )
    carrier = script_prefix_carrier(
      construction, query, context, sources, limits, steps, name,
    )
    input = {
      ..input,
      name,
      source: StepReference,
      visible_fields: script_carrier_columns(carrier),
    }
    sources.carriers[name] = carrier
  }
  let tail = @query.after_graph_calls(query)
  if @query.operation_at(tail, 0) is Some(Nearest(_)) {
    let peers = known.map(peer => {
      if input_relation_matches(@query.relation(tail), peer) {
        { ..input, relation: peer.relation, }
      } else {
        peer
      }
    })
    return lower_script_nearest_carrier(
      construction, tail, peers, context, sources, limits, steps, reserved, output,
      retained,
    )
  }
  if !(carrier is @carrier.Relation(_)) {
    if Array::makei(@query.operation_count(tail), i => {
        @query.operation_at(tail, i)
      }).any(operation => operation is Some(Alias(_))) {
      raise Abort(RangeAliasRequiresRelation)
    }
    guard allow_nonrelation &&
      @query.operation_count(tail) == 0 &&
      !has_retained_result(tail) else {
      raise Abort(UnsupportedProjection)
    }
    return input
  }
  // Only the explicit common bridge makes a Relation available to SELECT and
  // later relational operations. Its schema/order/key evidence is not invented.
  let visible = known.map(peer => {
    if input_relation_matches(@query.relation(tail), peer) {
      { ..input, relation: peer.relation, }
    } else {
      peer
    }
  })
  lower_script_relation_term(
    construction,
    tail,
    visible,
    context,
    sources,
    limits,
    steps,
    reserved,
    output,
    retained~,
  )
}
