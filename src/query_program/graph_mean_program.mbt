///|
// This is only a source-name view. The common Mean owner still checks domains,
// definitions, label/property extents, contracts, presence and numeric rules.
// Compatible mean inputs have the same named definition/property extents;
// key-column aliases survive only when every occurrence retains that role.
fn script_mean_name_view(
  samples : Array[ScriptGraph],
) -> ScriptGraph raise Abort {
  let first = samples[0]
  let nodes = first.mapping.nodes.map(definition => {
    let aliases = definition.key.map(key => {
      @carrier.graph_name_identity(
        property_mapping_column(
          key,
          property_mapping_input(definition.producer, first.inputs),
        ),
      )
    })
    let shared = samples.all(sample => {
      sample.mapping.nodes.any(candidate => {
        @carrier.graph_name_identity(candidate.name.value) ==
        @carrier.graph_name_identity(definition.name.value) &&
        candidate.key.map(key => {
          @carrier.graph_name_identity(
            property_mapping_column(
              key,
              property_mapping_input(candidate.producer, sample.inputs),
            ),
          )
        }) ==
        aliases
      })
    })
    { ..definition, key: if shared { definition.key } else { [] }, }
  })
  let edges = first.mapping.edges.map(definition => {
    let aliases = definition.key.map(key => {
      @carrier.graph_name_identity(
        property_mapping_column(
          key,
          property_mapping_input(definition.producer, first.inputs),
        ),
      )
    })
    let shared = samples.all(sample => {
      sample.mapping.edges.any(candidate => {
        @carrier.graph_name_identity(candidate.name.value) ==
        @carrier.graph_name_identity(definition.name.value) &&
        candidate.key.map(key => {
          @carrier.graph_name_identity(
            property_mapping_column(
              key,
              property_mapping_input(candidate.producer, sample.inputs),
            ),
          )
        }) ==
        aliases
      })
    })
    { ..definition, key: if shared { definition.key } else { [] }, }
  })
  { ..first, mapping: { ..first.mapping, nodes, edges, }, }
}

///|
// Emit a generator with exactly its authored ordered Graph list. No implicit
// current input, pairwise reduction, acquisition or artificial Result boundary.
fn lower_script_mean_generator(
  construction : Construction,
  document : @origin.Document,
  call : @query.SgaCall,
  graphs : Array[ScriptGraph],
  known : Array[Input],
  limits : Limits,
  steps : Array[@builder.Node],
  output : String,
) -> ScriptGraph raise Abort {
  guard call.operation == "mean_graphs" else { raise Abort(UnsupportedGraph) }
  let required = ["with", "weights", "support", "properties"]
  if call.arguments.length() != required.length() ||
    call.arguments.any(argument => !required.contains(argument.0)) ||
    required.any(name => !call.arguments.any(argument => argument.0 == name)) {
    raise Abort(InvalidQuery)
  }
  let construction = {
    ..construction,
    generated: @origin.range(document, call.start, call.end).unwrap(),
  }
  let samples : Array[ScriptGraph] = []
  let fields = call.arguments.map(argument => {
    let value = if argument.0 == "with" {
      guard argument.1 is ListValue(items) && !items.is_empty() else {
        raise Abort(InvalidQuery)
      }
      construction.array(
        items.map(item => {
          guard item is Producer(name) else { raise Abort(InvalidQuery) }
          guard script_graph_named_input(name, graphs) is Some(graph) else {
            raise Abort(UnknownRelation)
          }
          samples.push(graph)
          construction.text(graph.producer)
        }),
      )
    } else {
      script_traversal_argument(construction, argument.1, known, limits)
    }
    (argument.0, value)
  })
  steps.push(
    construction.object([
      ("mean_graphs", construction.object(fields)),
      ("as", construction.text(output)),
    ]),
  )
  { ..script_mean_name_view(samples), producer: output, }
}
