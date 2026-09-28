///|
// Both source forms remain ordinary Program material. Generated steps are
// admitted again with the complete Program; this is not a checked Graph value.
pub(all) enum GraphInputSource {
  CapturedGraph(@wire.Cursor)
  GeneratedGraph(Array[@wire.Cursor])
}

///|
pub(all) struct GraphInput {
  relation : Array[@query.NamePart]
  name : String
  source : GraphInputSource
  node_fields : Array[String]
  edge_fields : Array[String]
}

///|
fn graph_selected_input(
  query : @query.Query,
  context : Context,
) -> GraphInput raise Abort {
  let mut selected : GraphInput? = None
  for input in context.graph_inputs {
    if same_relation_path(@query.relation(query), input.relation) {
      if selected is Some(_) {
        raise Abort(AmbiguousRelation)
      }
      selected = Some(input)
    }
  }
  match selected {
    Some(input) => input
    None => raise Abort(UnknownRelation)
  }
}

///|
fn graph_node_field(
  path : Array[@query.NamePart],
  variable : @query.NamePart?,
  fields : Array[String],
) -> String? {
  if path.length() < 1 || path.length() > 2 {
    return None
  }
  if path.length() == 2 {
    match variable {
      Some(name) if same_name(path[0], name) => ()
      _ => return None
    }
  }
  let mut found : String? = None
  for field in fields {
    if same_name(path.last().unwrap(), { value: field, quoted: false, }) {
      if found is Some(_) {
        return None
      }
      found = Some(field)
    }
  }
  found
}

///|
fn graph_node_predicate(
  construction : Construction,
  graph : @query.GraphQuery,
  node : @query.GraphNodePattern,
  fields : Array[String],
  prefix : String,
  max_work : Int,
) -> @builder.Node? raise Abort {
  let predicates : Array[@builder.Node] = []
  match node.label {
    Some(label) => {
      let field = match graph.label_field {
        Some(field) => field
        None => raise Abort(UnsupportedGraph)
      }
      if !fields.contains(field) {
        raise Abort(UnknownColumn)
      }
      predicates.push(
        construction.object([
          (
            "eq",
            construction.array([
              construction.object([("field", construction.text(prefix + field))]),
              construction.object([("literal", construction.text(label.value))]),
            ]),
          ),
        ]),
      )
    }
    None => ()
  }
  let resolve = fn(path : Array[@query.NamePart]) -> String? {
    graph_node_field(path, node.variable, fields).map(name => prefix + name)
  }
  match node.constraint {
    Some(Predicate(expression)) =>
      predicates.push(
        match
          @expression.append(
            expression,
            resolve,
            construction.builder,
            max_work,
          ) {
          Ok(value) => value
          Err(error) => raise Abort(Expression(error))
        },
      )
    Some(Properties(properties)) =>
      for (field, expression) in properties {
        let name = match graph_node_field([field], node.variable, fields) {
          Some(name) => name
          None => raise Abort(UnknownColumn)
        }
        let value = match
          @expression.append(
            expression,
            resolve,
            construction.builder,
            max_work,
          ) {
          Ok(value) => value
          Err(error) => raise Abort(Expression(error))
        }
        predicates.push(
          construction.object([
            (
              "eq",
              construction.array([
                construction.object([
                  ("field", construction.text(prefix + name)),
                ]),
                value,
              ]),
            ),
          ]),
        )
      }
    None => ()
  }
  if predicates.is_empty() {
    None
  } else if predicates.length() == 1 {
    Some(predicates[0])
  } else {
    Some(construction.object([("and", construction.array(predicates))]))
  }
}

///|
fn graph_edge_predicate(
  construction : Construction,
  edge : @query.GraphEdgePattern,
  fields : Array[String],
  prefix : String,
  max_work : Int,
) -> @builder.Node? raise Abort {
  let predicates : Array[@builder.Node] = []
  match edge.label {
    Some(label) => {
      if !fields.contains("rel") {
        raise Abort(UnknownColumn)
      }
      predicates.push(
        construction.object([
          (
            "eq",
            construction.array([
              construction.object([("field", construction.text(prefix + "rel"))]),
              construction.object([("literal", construction.text(label.value))]),
            ]),
          ),
        ]),
      )
    }
    None => ()
  }
  let resolve = fn(path : Array[@query.NamePart]) -> String? {
    graph_node_field(path, edge.variable, fields).map(name => prefix + name)
  }
  match edge.constraint {
    Some(Predicate(expression)) =>
      predicates.push(
        match
          @expression.append(
            expression,
            resolve,
            construction.builder,
            max_work,
          ) {
          Ok(value) => value
          Err(error) => raise Abort(Expression(error))
        },
      )
    Some(Properties(properties)) =>
      for (field, expression) in properties {
        let name = match graph_node_field([field], edge.variable, fields) {
          Some(value) => value
          None => raise Abort(UnknownColumn)
        }
        let value = match
          @expression.append(
            expression,
            resolve,
            construction.builder,
            max_work,
          ) {
          Ok(value) => value
          Err(error) => raise Abort(Expression(error))
        }
        predicates.push(
          construction.object([
            (
              "eq",
              construction.array([
                construction.object([
                  ("field", construction.text(prefix + name)),
                ]),
                value,
              ]),
            ),
          ]),
        )
      }
    None => ()
  }
  if predicates.is_empty() {
    None
  } else if predicates.length() == 1 {
    Some(predicates[0])
  } else {
    Some(construction.object([("and", construction.array(predicates))]))
  }
}

///|
fn graph_field(
  construction : Construction,
  name : String,
) -> @builder.Node raise Abort {
  construction.object([("field", construction.text(name))])
}

///|
fn graph_distinct(
  construction : Construction,
  left : String,
  right : String,
) -> @builder.Node raise Abort {
  construction.object([
    (
      "is_distinct_from",
      construction.array([
        graph_field(construction, left),
        graph_field(construction, right),
      ]),
    ),
  ])
}

///|
fn graph_renamed_fields(
  construction : Construction,
  fields : Array[String],
  prefix : String,
) -> @builder.Node raise Abort {
  construction.array(
    fields.map(field => {
      construction.object([(prefix + field, construction.text(field))])
    }),
  )
}

///|
fn graph_join_step(
  construction : Construction,
  left : String,
  right : String,
  left_key : String,
  right_key : String,
  left_fields : Array[String],
  right_fields : Array[String],
  result : String,
  max_rows : Int64,
) -> @builder.Node raise Abort {
  let select : Array[(String, @builder.Node)] = []
  for field in left_fields {
    select.push((field, construction.text("left." + field)))
  }
  for field in right_fields {
    select.push((field, construction.text("right." + field)))
  }
  construction.object([
    ("from", construction.text(left)),
    (
      "join",
      construction.object([
        ("with", construction.text(right)),
        ("kind", construction.text("inner")),
        (
          "on",
          construction.array([
            construction.object([
              ("left", construction.text(left_key)),
              ("right", construction.text(right_key)),
            ]),
          ]),
        ),
        ("max_output_rows", construction.add(Number(max_rows.to_double()))),
        ("select", construction.object(select)),
      ]),
    ),
    ("as", construction.text(result)),
  ])
}

///|
fn graph_filter_step(
  construction : Construction,
  source : String,
  predicate : @builder.Node,
  result : String,
) -> @builder.Node raise Abort {
  construction.object([
    ("from", construction.text(source)),
    ("filter", predicate),
    ("as", construction.text(result)),
  ])
}

///|
fn graph_all(
  construction : Construction,
  predicates : Array[@builder.Node],
) -> @builder.Node raise Abort {
  if predicates.length() == 1 {
    predicates[0]
  } else {
    construction.object([("and", construction.array(predicates))])
  }
}

///|
fn graph_order_step(
  construction : Construction,
  source : String,
  keys : Array[String],
) -> @builder.Node raise Abort {
  construction.object([
    ("from", construction.text(source)),
    (
      "sort",
      construction.array(
        keys.map(field => {
          construction.object([
            ("field", construction.text(field)),
            ("dir", construction.text("asc")),
            ("nulls", construction.text("last")),
          ])
        }),
      ),
    ),
    ("as", construction.text("aql_graph_ordered")),
  ])
}

///|
fn graph_unique_path_step(
  construction : Construction,
  source : String,
  keys : Array[String],
) -> @builder.Node raise Abort {
  let names = construction.array(keys.map(name => construction.text(name)))
  let order = construction.array(
    keys.map(field => {
      construction.object([
        ("field", construction.text(field)),
        ("dir", construction.text("asc")),
        ("nulls", construction.text("last")),
      ])
    }),
  )
  construction.object([
    ("from", construction.text(source)),
    ("dedupe_rows", construction.object([("by", names), ("order_by", order)])),
    ("as", construction.text("aql_graph_unique_path")),
  ])
}

///|
fn graph_fixed_pattern(
  construction : Construction,
  graph : @query.GraphQuery,
  pattern : @query.GraphPattern,
  input : GraphInput,
  limits : Limits,
  seed : Array[@builder.Node],
) -> (String, Array[String], Array[GraphBinding]) raise Abort {
  seed.push(
    construction.object([
      ("from", construction.text(input.name)),
      ("edge_rows", construction.add(Bool(true))),
      ("as", construction.text("aql_graph_edges")),
    ]),
  )
  let node_prefixes : Array[String] = []
  let edge_prefixes : Array[String] = []
  let bindings : Array[GraphBinding] = []
  for index in 0..<pattern.nodes.length() {
    let prefix = "aql_n" + index.to_string() + "_"
    node_prefixes.push(prefix)
    seed.push(
      construction.object([
        ("from", construction.text("aql_graph_nodes_0")),
        (
          "select",
          graph_renamed_fields(construction, input.node_fields, prefix),
        ),
        ("as", construction.text("aql_graph_n" + index.to_string())),
      ]),
    )
    match pattern.nodes[index].variable {
      Some(variable) =>
        if !bindings.any(binding => same_name(binding.variable, variable)) {
          bindings.push({ variable, prefix, fields: input.node_fields, })
        }
      None => ()
    }
  }
  for index in 0..<pattern.edges.length() {
    let prefix = "aql_e" + index.to_string() + "_"
    edge_prefixes.push(prefix)
    seed.push(
      construction.object([
        ("from", construction.text("aql_graph_edges")),
        (
          "select",
          graph_renamed_fields(construction, input.edge_fields, prefix),
        ),
        ("as", construction.text("aql_graph_e" + index.to_string())),
      ]),
    )
    match pattern.edges[index].variable {
      Some(variable) =>
        if bindings.any(binding => same_name(binding.variable, variable)) {
          let mut node_variable = false
          for node in pattern.nodes {
            match node.variable {
              Some(name) if same_name(name, variable) => node_variable = true
              _ => ()
            }
          }
          if node_variable {
            raise Abort(AmbiguousColumn)
          }
        } else {
          bindings.push({ variable, prefix, fields: input.edge_fields, })
        }
      None => ()
    }
  }
  let mut current = "aql_graph_n0"
  let mut fields = input.node_fields.map(field => node_prefixes[0] + field)
  match
    graph_node_predicate(
      construction,
      graph,
      pattern.nodes[0],
      input.node_fields,
      node_prefixes[0],
      limits.max_expression_work,
    ) {
    Some(predicate) => {
      current = "aql_graph_selected_0"
      seed.push(
        graph_filter_step(construction, "aql_graph_n0", predicate, current),
      )
    }
    None => ()
  }
  for index in 0..<pattern.edges.length() {
    let edge = pattern.edges[index]
    let edge_prefix = edge_prefixes[index]
    let edge_fields = input.edge_fields.map(field => edge_prefix + field)
    let edge_alias = "aql_graph_hop_edge_" + index.to_string()
    seed.push(
      graph_join_step(
        construction,
        current,
        "aql_graph_e" + index.to_string(),
        node_prefixes[index] + "id",
        edge_prefix + (if edge.direction == "out" { "src" } else { "dst" }),
        fields,
        edge_fields,
        edge_alias,
        limits.max_join_output_rows,
      ),
    )
    current = edge_alias
    fields = fields + edge_fields
    let edge_filters : Array[@builder.Node] = []
    if pattern.mode != Walk {
      for prior in 0..<index {
        let older = edge_prefixes[prior]
        edge_filters.push(
          construction.object([
            (
              "or",
              construction.array([
                graph_distinct(construction, edge_prefix + "src", older + "src"),
                graph_distinct(construction, edge_prefix + "dst", older + "dst"),
                graph_distinct(construction, edge_prefix + "rel", older + "rel"),
              ]),
            ),
          ]),
        )
      }
    }
    for prior in 0..<index {
      match (pattern.edges[prior].variable, edge.variable) {
        (Some(before), Some(after)) if same_name(before, after) =>
          for field in ["src", "dst", "rel"] {
            edge_filters.push(
              construction.object([
                (
                  "not",
                  graph_distinct(
                    construction,
                    edge_prefix + field,
                    edge_prefixes[prior] + field,
                  ),
                ),
              ]),
            )
          }
        _ => ()
      }
    }
    match
      graph_edge_predicate(
        construction,
        edge,
        input.edge_fields,
        edge_prefix,
        limits.max_expression_work,
      ) {
      Some(predicate) => edge_filters.push(predicate)
      None => ()
    }
    if !edge_filters.is_empty() {
      let selected_edge = "aql_graph_selected_edge_" + index.to_string()
      seed.push(
        graph_filter_step(
          construction,
          current,
          graph_all(construction, edge_filters),
          selected_edge,
        ),
      )
      current = selected_edge
    }
    let node_prefix = node_prefixes[index + 1]
    let node_fields = input.node_fields.map(field => node_prefix + field)
    let node_alias = "aql_graph_hop_node_" + index.to_string()
    seed.push(
      graph_join_step(
        construction,
        current,
        "aql_graph_n" + (index + 1).to_string(),
        edge_prefix + (if edge.direction == "out" { "dst" } else { "src" }),
        node_prefix + "id",
        fields,
        node_fields,
        node_alias,
        limits.max_join_output_rows,
      ),
    )
    current = node_alias
    fields = fields + node_fields
    let node_filters : Array[@builder.Node] = []
    if pattern.mode == Acyclic {
      for prior in 0..<(index + 1) {
        node_filters.push(
          graph_distinct(
            construction,
            node_prefix + "id",
            node_prefixes[prior] + "id",
          ),
        )
      }
    }
    for prior in 0..<(index + 1) {
      match (pattern.nodes[prior].variable, pattern.nodes[index + 1].variable) {
        (Some(before), Some(after)) if same_name(before, after) =>
          node_filters.push(
            construction.object([
              (
                "not",
                graph_distinct(
                  construction,
                  node_prefix + "id",
                  node_prefixes[prior] + "id",
                ),
              ),
            ]),
          )
        _ => ()
      }
    }
    match
      graph_node_predicate(
        construction,
        graph,
        pattern.nodes[index + 1],
        input.node_fields,
        node_prefix,
        limits.max_expression_work,
      ) {
      Some(predicate) => node_filters.push(predicate)
      None => ()
    }
    if !node_filters.is_empty() {
      let selected_node = "aql_graph_selected_node_" + (index + 1).to_string()
      seed.push(
        graph_filter_step(
          construction,
          current,
          graph_all(construction, node_filters),
          selected_node,
        ),
      )
      current = selected_node
    }
  }
  (current, fields, bindings)
}

///|
fn compile_graph_query(
  query : @query.Query,
  context : Context,
  limits : Limits,
) -> Result[@program.Program, Issue] {
  guard @query.graph_query(query) is Some(graph) &&
    graph.pattern is Some(pattern) else {
    return Err(UnsupportedGraph)
  }
  let mut selected = false
  for index in 0..<@query.operation_count(query) {
    if @query.operation_at(query, index) is Some(Select(_, _)) {
      selected = true
    }
  }
  if pattern.nodes.length() != pattern.edges.length() + 1 ||
    pattern.edges.any(edge => edge.quantified) ||
    @query.cte_count(query) != 0 ||
    @query.set_part_count(query) != 0 ||
    @query.join_part_count(query) != 0 ||
    context.captured_stage is Some(_) ||
    context.program_id == "" ||
    context.stage_id == "" ||
    context.stage_result == "" ||
    context.result_name == "" ||
    limits.max_expression_work < 0 ||
    limits.max_join_output_rows < 1L ||
    !selected {
    return Err(UnsupportedGraph)
  }
  let input = graph_selected_input(query, context) catch {
    Abort(issue) => return Err(issue)
  }
  if input.name == "" ||
    !input.node_fields.contains("id") ||
    (
      !pattern.edges.is_empty() &&
      (
        !input.edge_fields.contains("src") ||
        !input.edge_fields.contains("dst") ||
        !input.edge_fields.contains("rel")
      )
    ) {
    return Err(InvalidContext)
  }
  let document = @query.query_document(query)
  let generated = @origin.range(document, 0, 0, kind=Generated).unwrap()
  let builder = match @builder.create(document, limits.source) {
    Ok(builder) => builder
    Err(issue) => return Err(Construction(issue))
  }
  let construction : Construction = { builder, generated, }
  try {
    let inputs : Array[(String, @builder.Node)] = []
    let seed : Array[@builder.Node] = []
    match input.source {
      CapturedGraph(declaration) => {
        let imported = match
          @builder.import_cursor(builder, declaration, generated) {
          Ok(value) => value
          Err(issue) => raise Abort(Construction(issue))
        }
        inputs.push((input.name, imported))
      }
      GeneratedGraph(steps) => {
        if steps.is_empty() {
          raise Abort(InvalidContext)
        }
        for step in steps {
          seed.push(
            match @builder.import_cursor(builder, step, generated) {
              Ok(value) => value
              Err(issue) => raise Abort(Construction(issue))
            },
          )
        }
      }
    }
    let node_alias = "aql_graph_nodes_0"
    seed.push(
      construction.object([
        ("from", construction.text(input.name)),
        ("node_rows", construction.add(Bool(true))),
        ("as", construction.text(node_alias)),
      ]),
    )
    let (relation_alias, visible_fields, graph_bindings) = if pattern.edges.is_empty() {
      let mut relation_alias = node_alias
      match
        graph_node_predicate(
          construction,
          graph,
          pattern.nodes[0],
          input.node_fields,
          "",
          limits.max_expression_work,
        ) {
        Some(predicate) => {
          relation_alias = "aql_graph_selected_0"
          seed.push(
            graph_filter_step(
              construction, node_alias, predicate, relation_alias,
            ),
          )
        }
        None => ()
      }
      let bindings : Array[GraphBinding] = []
      match pattern.nodes[0].variable {
        Some(variable) =>
          bindings.push({ variable, prefix: "", fields: input.node_fields, })
        None => ()
      }
      (relation_alias, input.node_fields, bindings)
    } else {
      graph_fixed_pattern(construction, graph, pattern, input, limits, seed)
    }
    let order_keys : Array[String] = []
    if pattern.edges.is_empty() {
      order_keys.push("id")
    } else {
      for index in 0..<pattern.nodes.length() {
        order_keys.push("aql_n" + index.to_string() + "_id")
        if index < pattern.edges.length() {
          order_keys.push("aql_e" + index.to_string() + "_rel")
        }
      }
    }
    let sorted_source = if pattern.edges.is_empty() {
      relation_alias
    } else {
      // Graph construction collapses equal edge identities. The complete
      // occurrence key is unique for each surviving path, so this step
      // establishes a bounded order without collapsing different paths.
      seed.push(
        graph_unique_path_step(construction, relation_alias, order_keys),
      )
      "aql_graph_unique_path"
    }
    seed.push(graph_order_step(construction, sorted_source, order_keys))
    let relation_alias = "aql_graph_ordered"
    let relation_input : Input = {
      relation: @query.relation(query),
      name: relation_alias,
      source: StageResult(context.stage_id, relation_alias),
      visible_fields,
      graph_bindings,
    }
    let (steps, output) = compile_steps(
      construction,
      query,
      relation_input,
      visible_fields,
      limits.max_expression_work,
      limits.max_collection_items,
      limits.max_collection_bytes,
      0,
      false,
      "aql_graph_result_0",
    )
    let result_alias = if steps.is_empty() {
      relation_alias
    } else {
      "aql_graph_result_0"
    }
    let stage = construction.object([
      ("id", construction.text(context.stage_id)),
      ("inputs", construction.object(inputs)),
      ("steps", construction.array(seed + steps)),
      (
        "results",
        construction.object([
          (
            context.stage_result,
            construction.object([
              ("from", construction.text(result_alias)),
              (
                "fields",
                construction.array(
                  output.map(field => construction.text(field)),
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
