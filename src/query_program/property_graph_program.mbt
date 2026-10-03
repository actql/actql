///|
// Resolve syntax names only. Graph domains, key validity, global property
// types and label-property consistency remain common checker obligations.
fn property_mapping_input(
  path : Array[@query.NamePart],
  known : Array[Input],
) -> Input raise Abort {
  resolve_relation_input(path, known)
}

///|
fn property_mapping_column(
  name : @query.NamePart,
  input : Input,
) -> String raise Abort {
  let matches = columns(input).filter(field => {
    same_name(name, { value: field, quoted: false, })
  })
  if matches.is_empty() {
    raise Abort(UnknownColumn)
  }
  if matches.length() != 1 {
    raise Abort(AmbiguousColumn)
  }
  matches[0]
}

///|
fn property_mapping_columns(
  construction : Construction,
  names : Array[@query.NamePart],
  input : Input,
) -> @builder.Node raise Abort {
  construction.array(
    names.map(name => construction.text(property_mapping_column(name, input))),
  )
}

///|
fn property_mapping_properties(
  construction : Construction,
  selection : @query.GraphPropertySelection,
  input : Input,
) -> @builder.Node raise Abort {
  match selection {
    AllColumns =>
      construction.object([("mode", construction.text("all_columns"))])
    NoProperties =>
      construction.object([("mode", construction.text("no_properties"))])
    AllColumnsExcept(names) =>
      construction.object([
        ("mode", construction.text("all_columns_except")),
        ("except", property_mapping_columns(construction, names, input)),
      ])
    Columns(pairs) =>
      construction.object([
        ("mode", construction.text("columns")),
        (
          "columns",
          construction.array(
            pairs.map(pair => {
              construction.object([
                (
                  "from",
                  construction.text(property_mapping_column(pair.0, input)),
                ),
                ("to", construction.text(pair.1.value)),
              ])
            }),
          ),
        ),
      ])
  }
}

///|
fn property_mapping_labels(
  construction : Construction,
  labels : Array[@query.PropertyGraphLabel],
  input : Input,
) -> @builder.Node raise Abort {
  construction.array(
    labels.map(label => {
      construction.object([
        ("name", construction.text(label.name.value)),
        (
          "properties",
          property_mapping_properties(construction, label.properties, input),
        ),
      ])
    }),
  )
}

///|
fn property_mapping_endpoint(
  construction : Construction,
  reference : @query.PropertyEndpointReference,
  input : Input,
  nodes : Array[@query.PropertyNodeDefinition],
  known : Array[Input],
) -> @builder.Node raise Abort {
  let definitions = nodes.filter(node => {
    same_name(node.name, reference.definition)
  })
  if definitions.is_empty() {
    raise Abort(UnknownRelation)
  }
  if definitions.length() != 1 {
    raise Abort(AmbiguousRelation)
  }
  let definition = definitions[0]
  let target = property_mapping_input(definition.producer, known)
  if reference.referenced_key is Some(names) {
    let specified = names.map(name => property_mapping_column(name, target))
    let keys = definition.key.map(name => property_mapping_column(name, target))
    // The selected initial profile admits only ordered KEY references. This
    // is an explicit coverage limit, not a different non-key expansion rule.
    if specified != keys {
      raise Abort(UnsupportedGraph)
    }
  }
  construction.object([
    ("definition", construction.text(definition.name.value)),
    ("key", property_mapping_columns(construction, reference.key, input)),
  ])
}

///|
fn lower_property_graph_step(
  construction : Construction,
  graph : @query.PropertyGraphConstructor,
  known : Array[Input],
  output : String,
  producer_names? : Map[String, String] = Map([]),
) -> @builder.Node raise Abort {
  let names : Array[@query.NamePart] = []
  for node in graph.nodes {
    names.push(node.name)
  }
  for edge in graph.edges {
    names.push(edge.name)
  }
  for index, name in names {
    for previous in 0..<index {
      if same_name(name, names[previous]) {
        raise Abort(AmbiguousRelation)
      }
    }
  }
  let nodes = graph.nodes.map(node => {
    let input = property_mapping_input(node.producer, known)
    construction.object([
      ("name", construction.text(node.name.value)),
      (
        "from",
        construction.text(producer_names.get(input.name).unwrap_or(input.name)),
      ),
      ("key", property_mapping_columns(construction, node.key, input)),
      ("labels", property_mapping_labels(construction, node.labels, input)),
    ])
  })
  let edges = graph.edges.map(edge => {
    let input = property_mapping_input(edge.producer, known)
    construction.object([
      ("name", construction.text(edge.name.value)),
      (
        "from",
        construction.text(producer_names.get(input.name).unwrap_or(input.name)),
      ),
      ("key", property_mapping_columns(construction, edge.key, input)),
      (
        "source",
        property_mapping_endpoint(
          construction,
          edge.source,
          input,
          graph.nodes,
          known,
        ),
      ),
      (
        "target",
        property_mapping_endpoint(
          construction,
          edge.destination,
          input,
          graph.nodes,
          known,
        ),
      ),
      ("labels", property_mapping_labels(construction, edge.labels, input)),
    ])
  })
  construction.object([
    (
      "property_graph",
      construction.object([
        ("version", construction.text("actql-property-graph-constructor/0.1")),
        ("nodes", construction.array(nodes)),
        ("edges", construction.array(edges)),
      ]),
    ),
    ("as", construction.text(output)),
  ])
}
