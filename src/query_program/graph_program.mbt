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
/// Read the declared Graph edge-label role from the selected source. A field
/// list supplied by a frontend caller is not evidence that a property is the
/// semantic edge type.
fn graph_label_role(input : GraphInput) -> String? {
  let declarations = match input.source {
    GeneratedGraph(steps) => steps
    CapturedGraph(declaration) => [declaration]
  }
  for declaration in declarations {
    guard @wire.open_object(declaration) is Ok(root) &&
      @wire.lookup(root, "graph") is Some(graph_cursor) &&
      @wire.open_object(graph_cursor) is Ok(graph) &&
      @wire.lookup(graph, "edges") is Some(edges_cursor) &&
      @wire.open_object(edges_cursor) is Ok(edges) &&
      @wire.lookup(edges, "label") is Some(label_cursor) &&
      @wire.text(label_cursor) is Ok(label) else {
      continue
    }
    match input.source {
      GeneratedGraph(_) => {
        guard @wire.lookup(root, "as") is Some(alias_cursor) &&
          @wire.text(alias_cursor) == Ok(input.name) else {
          continue
        }
      }
      CapturedGraph(_) => ()
    }
    return Some(label)
  }
  None
}

///|
fn graph_macro_value(
  path : Array[@query.NamePart],
  argument : Array[@query.NamePart],
  bindings : Array[GraphBinding],
) -> @expression.MacroValue? {
  if path.length() != 1 || path[0].quoted || argument.length() != 1 {
    return None
  }
  let name = ascii_upper(path[0].value)
  for binding in bindings {
    if !same_name(argument[0], binding.variable) {
      continue
    }
    let role = match (binding.kind, name) {
      (Node, "NODE_ID") => "id"
      (Edge, "EDGE_SOURCE") => "src"
      (Edge, "EDGE_TARGET") => "dst"
      (Edge, "EDGE_LABEL") =>
        match binding.label_field {
          Some(field) => field
          None => return None
        }
      (Path, "PATH_LENGTH") => {
        if binding.fields.contains("hop_count") {
          return Some(@expression.Field(binding.prefix + "hop_count"))
        }
        return Some(@expression.Integer(binding.hops))
      }
      _ => return None
    }
    if !binding.fields.contains(role) {
      return None
    }
    return Some(@expression.Field(binding.prefix + role))
  }
  None
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
  label_field : String?,
  prefix : String,
  max_work : Int,
) -> @builder.Node? raise Abort {
  let predicates : Array[@builder.Node] = []
  match edge.label {
    Some(label) => {
      let role = match label_field {
        Some(role) if fields.contains(role) => role
        _ => raise Abort(UnsupportedGraph)
      }
      predicates.push(
        construction.object([
          (
            "eq",
            construction.array([
              construction.object([("field", construction.text(prefix + role))]),
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
  label_field : String?,
  limits : Limits,
  seed : Array[@builder.Node],
  branch? : Int = -1,
) -> (String, Array[String], Array[GraphBinding]) raise Abort {
  let tag = if branch < 0 { "" } else { "b" + branch.to_string() + "_" }
  let name = fn(base : String) -> String { "aql_graph_" + tag + base }
  let node_prefix = fn(index : Int) -> String {
    "aql_" + tag + "n" + index.to_string() + "_"
  }
  let edge_prefix = fn(index : Int) -> String {
    "aql_" + tag + "e" + index.to_string() + "_"
  }
  seed.push(
    construction.object([
      ("from", construction.text(input.name)),
      ("edge_rows", construction.add(Bool(true))),
      ("as", construction.text(name("edges"))),
    ]),
  )
  let node_prefixes : Array[String] = []
  let edge_prefixes : Array[String] = []
  let bindings : Array[GraphBinding] = []
  for index in 0..<pattern.nodes.length() {
    let prefix = node_prefix(index)
    node_prefixes.push(prefix)
    seed.push(
      construction.object([
        ("from", construction.text("aql_graph_nodes_0")),
        (
          "select",
          graph_renamed_fields(construction, input.node_fields, prefix),
        ),
        ("as", construction.text(name("n" + index.to_string()))),
      ]),
    )
    match pattern.nodes[index].variable {
      Some(variable) =>
        if !bindings.any(binding => same_name(binding.variable, variable)) {
          bindings.push({
            variable,
            prefix,
            fields: input.node_fields,
            kind: Node,
            hops: 0,
            label_field: None,
          })
        }
      None => ()
    }
  }
  for index in 0..<pattern.edges.length() {
    let prefix = edge_prefix(index)
    edge_prefixes.push(prefix)
    seed.push(
      construction.object([
        ("from", construction.text(name("edges"))),
        (
          "select",
          graph_renamed_fields(construction, input.edge_fields, prefix),
        ),
        ("as", construction.text(name("e" + index.to_string()))),
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
          bindings.push({
            variable,
            prefix,
            fields: input.edge_fields,
            kind: Edge,
            hops: 0,
            label_field,
          })
        }
      None => ()
    }
  }
  let mut current = name("n0")
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
      current = name("selected_0")
      seed.push(graph_filter_step(construction, name("n0"), predicate, current))
    }
    None => ()
  }
  for index in 0..<pattern.edges.length() {
    let edge = pattern.edges[index]
    let edge_prefix = edge_prefixes[index]
    let edge_fields = input.edge_fields.map(field => edge_prefix + field)
    let edge_alias = name("hop_edge_" + index.to_string())
    seed.push(
      graph_join_step(
        construction,
        current,
        name("e" + index.to_string()),
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
        let distincts = [
          graph_distinct(construction, edge_prefix + "src", older + "src"),
          graph_distinct(construction, edge_prefix + "dst", older + "dst"),
        ]
        match label_field {
          Some(role) =>
            distincts.push(
              graph_distinct(construction, edge_prefix + role, older + role),
            )
          None => ()
        }
        edge_filters.push(
          construction.object([("or", construction.array(distincts))]),
        )
      }
    }
    for prior in 0..<index {
      match (pattern.edges[prior].variable, edge.variable) {
        (Some(before), Some(after)) if same_name(before, after) => {
          let identity_fields = ["src", "dst"]
          match label_field {
            Some(role) => identity_fields.push(role)
            None => ()
          }
          for field in identity_fields {
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
        }
        _ => ()
      }
    }
    match
      graph_edge_predicate(
        construction,
        edge,
        input.edge_fields,
        label_field,
        edge_prefix,
        limits.max_expression_work,
      ) {
      Some(predicate) => edge_filters.push(predicate)
      None => ()
    }
    if !edge_filters.is_empty() {
      let selected_edge = name("selected_edge_" + index.to_string())
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
    let node_alias = name("hop_node_" + index.to_string())
    seed.push(
      graph_join_step(
        construction,
        current,
        name("n" + (index + 1).to_string()),
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
      let selected_node = name("selected_node_" + (index + 1).to_string())
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
fn graph_bounded_pattern(
  construction : Construction,
  graph : @query.GraphQuery,
  pattern : @query.GraphPattern,
  input : GraphInput,
  label_field : String?,
  limits : Limits,
  seed : Array[@builder.Node],
) -> (String, Array[String], Array[GraphBinding]) raise Abort {
  let edge = pattern.edges[0]
  if pattern.mode != Acyclic ||
    edge.variable is Some(_) ||
    edge.constraint is Some(_) ||
    pattern.nodes.length() != 2 ||
    edge.max_hops < edge.min_hops ||
    edge.max_hops < 1L {
    raise Abort(UnsupportedGraph)
  }
  let mut start = "aql_graph_nodes_0"
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
      start = "aql_graph_start_nodes"
      seed.push(
        graph_filter_step(construction, "aql_graph_nodes_0", predicate, start),
      )
    }
    None => ()
  }
  let traversal = [
    (
      "start",
      construction.object([
        ("from", construction.text(start)),
        ("id", construction.text("id")),
      ]),
    ),
    ("direction", construction.text(edge.direction)),
    ("min_hops", construction.add(Number(edge.min_hops.to_double()))),
    ("max_hops", construction.add(Number(edge.max_hops.to_double()))),
    ("emit", construction.text("paths")),
    (
      "max_output_rows",
      construction.add(Number(limits.max_join_output_rows.to_double())),
    ),
  ]
  match edge.label {
    Some(label) => {
      if label_field is None {
        raise Abort(UnsupportedGraph)
      }
      traversal.push(
        ("edge_types", construction.array([construction.text(label.value)])),
      )
    }
    None => ()
  }
  seed.push(
    construction.object([
      ("from", construction.text(input.name)),
      ("traverse", construction.object(traversal)),
      ("as", construction.text("aql_graph_paths")),
    ]),
  )
  let path_fields = ["start_id", "end_id", "hop_count", "node_ids", "edge_ids"]
  let path_prefix = "aql_path_"
  seed.push(
    construction.object([
      ("from", construction.text("aql_graph_paths")),
      ("select", graph_renamed_fields(construction, path_fields, path_prefix)),
      ("as", construction.text("aql_graph_path_rows")),
    ]),
  )
  let bindings : Array[GraphBinding] = []
  let mut fields = path_fields.map(field => path_prefix + field)
  let same_endpoint_variable = match
    (pattern.nodes[0].variable, pattern.nodes[1].variable) {
    (Some(start_name), Some(end_name)) => same_name(start_name, end_name)
    _ => false
  }
  for index in 0..<2 {
    let prefix = "aql_n" + index.to_string() + "_"
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
        if bindings.any(binding => same_name(binding.variable, variable)) {
          if !same_endpoint_variable {
            raise Abort(AmbiguousColumn)
          }
        } else {
          bindings.push({
            variable,
            prefix,
            fields: input.node_fields,
            kind: Node,
            hops: 0,
            label_field: None,
          })
        }
      None => ()
    }
  }
  let first_fields = input.node_fields.map(field => "aql_n0_" + field)
  let first = "aql_graph_start_binding"
  seed.push(
    graph_join_step(
      construction,
      "aql_graph_path_rows",
      "aql_graph_n0",
      "aql_path_start_id",
      "aql_n0_id",
      fields,
      first_fields,
      first,
      limits.max_join_output_rows,
    ),
  )
  fields = fields + first_fields
  let end_fields = input.node_fields.map(field => "aql_n1_" + field)
  let second = "aql_graph_end_binding"
  seed.push(
    graph_join_step(
      construction,
      first,
      "aql_graph_n1",
      "aql_path_end_id",
      "aql_n1_id",
      fields,
      end_fields,
      second,
      limits.max_join_output_rows,
    ),
  )
  fields = fields + end_fields
  let mut current = second
  if same_endpoint_variable {
    current = "aql_graph_same_endpoint"
    seed.push(
      graph_filter_step(
        construction,
        second,
        construction.object([
          (
            "not",
            graph_distinct(construction, "aql_path_start_id", "aql_path_end_id"),
          ),
        ]),
        current,
      ),
    )
  }
  match
    graph_node_predicate(
      construction,
      graph,
      pattern.nodes[1],
      input.node_fields,
      "aql_n1_",
      limits.max_expression_work,
    ) {
    Some(predicate) => {
      let source = current
      current = "aql_graph_selected_end"
      seed.push(graph_filter_step(construction, source, predicate, current))
    }
    None => ()
  }
  match pattern.path_name {
    Some(variable) => {
      if bindings.any(binding => same_name(binding.variable, variable)) {
        raise Abort(AmbiguousColumn)
      }
      bindings.push({
        variable,
        prefix: path_prefix,
        fields: ["hop_count"],
        kind: Path,
        hops: 0,
        label_field: None,
      })
    }
    None => ()
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
  let bounded = pattern.edges.length() == 1 && pattern.edges[0].quantified
  if pattern.nodes.length() != pattern.edges.length() + 1 ||
    (pattern.edges.any(edge => edge.quantified) && !bounded) ||
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
  let label_field = graph_label_role(input)
  if input.name == "" ||
    !input.node_fields.contains("id") ||
    (
      !pattern.edges.is_empty() &&
      (!input.edge_fields.contains("src") || !input.edge_fields.contains("dst"))
    ) {
    return Err(InvalidContext)
  }
  match label_field {
    Some(role) if !input.edge_fields.contains(role) =>
      return Err(InvalidContext)
    _ => ()
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
          bindings.push({
            variable,
            prefix: "",
            fields: input.node_fields,
            kind: Node,
            hops: 0,
            label_field: None,
          })
        None => ()
      }
      (relation_alias, input.node_fields, bindings)
    } else if bounded {
      graph_bounded_pattern(
        construction, graph, pattern, input, label_field, limits, seed,
      )
    } else {
      graph_fixed_pattern(
        construction, graph, pattern, input, label_field, limits, seed,
      )
    }
    match pattern.path_name {
      Some(variable) =>
        if !bounded {
          if graph_bindings.any(binding => same_name(binding.variable, variable)) {
            raise Abort(AmbiguousColumn)
          }
          graph_bindings.push({
            variable,
            prefix: "",
            fields: [],
            kind: Path,
            hops: pattern.edges.length(),
            label_field: None,
          })
        }
      None => ()
    }
    let order_keys : Array[String] = []
    if bounded {
      order_keys.push("aql_path_start_id")
      order_keys.push("aql_path_end_id")
      order_keys.push("aql_path_hop_count")
    } else if pattern.edges.is_empty() {
      order_keys.push("id")
    } else {
      for index in 0..<pattern.nodes.length() {
        order_keys.push("aql_n" + index.to_string() + "_id")
        if index < pattern.edges.length() {
          order_keys.push("aql_e" + index.to_string() + "_src")
          order_keys.push("aql_e" + index.to_string() + "_dst")
          match label_field {
            Some(role) =>
              order_keys.push("aql_e" + index.to_string() + "_" + role)
            None => ()
          }
        }
      }
    }
    let sorted_source = if pattern.edges.is_empty() || bounded {
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
    let retained : Array[RetainedResult] = []
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
      graph_bindings_only=!pattern.edges.is_empty(),
      retained=Some(retained),
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
        retained_stage_results(
          construction,
          context.stage_result,
          construction.object([
            ("from", construction.text(result_alias)),
            (
              "fields",
              construction.array(output.map(field => construction.text(field))),
            ),
          ]),
          retained,
        ),
      ),
    ])
    let root = program_root(
      construction,
      context,
      [stage],
      result_exports=retained_result_exports(context, retained),
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
