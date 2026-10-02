///|
pub fn property_law_cid() -> String {
  "sha256:654315b04dd9391454d0b5ffdf1a559d2bf5cae57eebfcf18c5cc4de2cad66dc"
}

///|
fn properties(
  rows : @carrier.Knowledge,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(out)
  for index in 0..<@carrier.field_count(rows) {
    let field = @carrier.field_at(rows, index).unwrap()
    @encode.key(out, @row.reference_name(field.name))
    @value.emit_checked(field.contract.unwrap(), out)
  }
  @encode.end_object(out)
}

///|
fn emit_property_definition(
  definition : @carrier.PropertyNodeDefinition,
  endpoints : (String, String)?,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(out)
  @encode.key(out, "key_contracts")
  @encode.begin_array(out)
  for contract in @carrier.property_definition_keys(definition) {
    @value.emit_checked(contract, out)
  }
  @encode.end_array(out)
  @encode.key(out, "labels")
  @encode.begin_object(out)
  for
    (label, selected) in @carrier.property_definition_label_properties(
      definition,
    ) {
    @encode.key(out, label)
    @encode.begin_array(out)
    for index in 0..<@carrier.field_count(selected) {
      @encode.string_value(
        out,
        @row.reference_name(@carrier.field_at(selected, index).unwrap().name),
      )
    }
    @encode.end_array(out)
  }
  @encode.end_object(out)
  @encode.key(out, "name")
  @encode.string_value(out, @carrier.property_definition_name(definition))
  @encode.key(out, "properties")
  properties(@carrier.property_definition_properties(definition), out)
  if endpoints is Some((source, _)) {
    @encode.key(out, "source_definition")
    @encode.string_value(out, source)
  }
  if endpoints is Some((_, target)) {
    @encode.key(out, "target_definition")
    @encode.string_value(out, target)
  }
  @encode.end_object(out)
}

///|
fn emit_property_graph(
  graph : @carrier.Graph,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  guard @carrier.graph_property_definition(graph) is Some(profile) else {
    raise @encode.InvalidStructure
  }
  let nodes = @carrier.property_graph_node_definitions(profile)
  let edges = @carrier.property_graph_edge_definitions(profile)
  nodes.sort_by((a, b) => {
    @unicode.compare_utf16(
      @carrier.property_definition_name(a),
      @carrier.property_definition_name(b),
    )
  })
  edges.sort_by((a, b) => {
    @unicode.compare_utf16(
      @carrier.property_definition_name(@carrier.property_edge_element(a)),
      @carrier.property_definition_name(@carrier.property_edge_element(b)),
    )
  })
  @encode.begin_object(out)
  @encode.key(out, "domain")
  @encode.string_value(out, @carrier.property_graph_domain(profile))
  @encode.key(out, "edge_definitions")
  @encode.begin_array(out)
  for edge in edges {
    emit_property_definition(
      @carrier.property_edge_element(edge),
      Some(@carrier.property_edge_endpoints(edge)),
      out,
    )
  }
  @encode.end_array(out)
  @encode.key(out, "identity_law_cid")
  @encode.string_value(out, property_law_cid())
  @encode.key(out, "node_definitions")
  @encode.begin_array(out)
  for node in nodes {
    emit_property_definition(node, None, out)
  }
  @encode.end_array(out)
  @encode.key(out, "value_law_cid")
  @encode.string_value(out, property_law_cid())
  @encode.key(out, "version")
  @encode.string_value(out, "actql-property-graph-contract/0.1")
  @encode.end_object(out)
}

///|
/// Schema admission does not issue definition provenance or execute rows.
pub fn admit_property_graph(
  input : @carrier.Carrier,
  limits : Limits,
) -> Result[CheckedContract, Issue] {
  if limits.max_bytes < 0 || limits.max_nodes < 0 || limits.max_depth < 0 {
    return Err(InvalidLimits)
  }
  guard input is @carrier.GraphValue(graph) &&
    @carrier.graph_property_definition(graph) is Some(profile) else {
    return Err(IncompleteGraph)
  }
  let count = @carrier.property_graph_node_count(profile)
  if count > limits.max_nodes ||
    @carrier.property_graph_edge_count(profile) > limits.max_nodes - count {
    return Err(BudgetExceeded)
  }
  try {
    let out = @encode.hashing_writer(
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    emit_property_graph(graph, out)
    let (hex, bytes, nodes) = @encode.finish_hash_usage(out)
    Ok({ graph, cid: "sha256:" + hex, bytes, nodes, })
  } catch {
    _ => Err(BudgetExceeded)
  }
}

///|
pub fn property_cid(value : CheckedContract) -> String {
  value.cid
}

///|
pub fn property_bytes(value : CheckedContract) -> Int {
  value.bytes
}

///|
pub fn property_nodes(value : CheckedContract) -> Int {
  value.nodes
}

///|
pub fn property_graph(value : CheckedContract) -> @carrier.Graph {
  value.graph
}

///|
/// Reuse the admitted profile codec when composing an enclosing contract.
pub fn emit_checked_property_graph(
  value : CheckedContract,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  emit_property_graph(value.graph, out)
}

///|
pub fn stringify_property_graph(
  value : CheckedContract,
  limits : Limits,
) -> String raise @encode.EncodeFailure {
  let out = @encode.writer(limits.max_bytes, limits.max_nodes, limits.max_depth)
  emit_property_graph(value.graph, out)
  @encode.finish(out)
}

///|
fn read_property_text(
  cursor : @decode.Cursor,
  budget : ReadBudget,
) -> String raise ReadStop {
  charge_nodes(budget, 1)
  text_value(cursor, budget)
}

///|
fn read_property_definition(
  cursor : @decode.Cursor,
  edge : Bool,
  budget : ReadBudget,
  limits : Limits,
  validation_work : Ref[Int],
) -> (@carrier.PropertyNodeDefinition, (String, String)?) raise ReadStop {
  charge_nodes(budget, 1)
  let names = ["name", "key_contracts", "properties", "labels"]
  if edge {
    names.push("source_definition")
    names.push("target_definition")
  }
  if @decode.object_length(cursor) != Some(names.length()) {
    stop(InvalidBody)
  }
  let object = match @decode.closed_object(cursor, names) {
    Ok(value) => value
    Err(_) => stop(InvalidBody)
  }
  let name = read_property_text(required(object, "name"), budget)
  let keys_at = required(object, "key_contracts")
  charge_nodes(budget, 1)
  let count = match @decode.array_length(keys_at) {
    Some(value) => value
    None => stop(InvalidBody)
  }
  if count > budget.nodes {
    stop(BudgetExceeded)
  }
  let keys = []
  for index in 0..<count {
    let key = read_type(@decode.element_at(keys_at, index).unwrap(), budget)
    // Constructor inputs may be nullable, but an emitted element identity
    // contract is non-null. Reading it must not silently change the body.
    if @value.contract_nullable(key) {
      stop(InvalidStructure)
    }
    keys.push(key)
  }
  let props = read_properties(required(object, "properties"), budget, limits)
  let labels_at = required(object, "labels")
  charge_nodes(budget, 1)
  let count = match @decode.object_length(labels_at) {
    Some(value) => value
    None => stop(InvalidBody)
  }
  if count > budget.nodes {
    stop(BudgetExceeded)
  }
  let labels = []
  let exposed = []
  for index in 0..<count {
    let (label, fields_at) = @decode.field_at(labels_at, index).unwrap()
    charge_text(budget, label)
    labels.push(label)
    charge_nodes(budget, 1)
    let fields = match @decode.array_length(fields_at) {
      Some(value) => value
      None => stop(InvalidBody)
    }
    if fields > budget.nodes {
      stop(BudgetExceeded)
    }
    let selected = []
    for field in 0..<fields {
      let name = read_property_text(
        @decode.element_at(fields_at, field).unwrap(),
        budget,
      )
      let mut found = None
      // Exact display names are canonical schema references, not values.
      for property in 0..<@carrier.field_count(props) {
        if validation_work.val == 0 {
          stop(BudgetExceeded)
        }
        validation_work.val -= 1
        let candidate = @carrier.field_at(props, property).unwrap()
        if @row.reference_name(candidate.name) == name {
          found = Some(candidate)
          break
        }
      }
      guard found is Some(found) else { stop(InvalidStructure) }
      selected.push((found.name, found.contract))
    }
    let knowledge = match
      @carrier.rows(
        selected,
        field_set=Closed,
        max_fields=limits.max_nodes,
        max_name_bytes=limits.max_bytes,
      ) {
      Ok(value) => value
      Err(_) => stop(InvalidStructure)
    }
    exposed.push((label, knowledge))
  }
  let definition = match
    @carrier.property_node_definition_usage(
      name,
      keys,
      props,
      labels,
      label_properties=exposed,
      max_fields=limits.max_nodes,
      max_name_bytes=limits.max_bytes,
      max_contract_work=validation_work.val,
    ) {
    Ok((value, used)) => {
      validation_work.val -= used
      value
    }
    Err(LimitExceeded) => stop(BudgetExceeded)
    Err(_) => stop(InvalidStructure)
  }
  let endpoints = if edge {
    Some(
      (
        read_property_text(required(object, "source_definition"), budget),
        read_property_text(required(object, "target_definition"), budget),
      ),
    )
  } else {
    None
  }
  (definition, endpoints)
}

///|
pub fn read_property_graph_cursor(
  root : @decode.Cursor,
  limits : Limits,
) -> Result[CheckedContract, ReadIssue] {
  read_property_graph_cursor_usage(
    root,
    limits,
    max_contract_work=limits.max_nodes,
  ).map(pair => pair.0)
}

///|
/// Structural nodes and repeated type/label comparisons are separate bounds.
/// The enclosing admission owner charges the returned comparison work once.
pub fn read_property_graph_cursor_usage(
  root : @decode.Cursor,
  limits : Limits,
  max_contract_work~ : Int,
) -> Result[(CheckedContract, Int), ReadIssue] {
  if limits.max_bytes < 0 ||
    limits.max_nodes < 0 ||
    limits.max_depth < 0 ||
    max_contract_work < 0 {
    return Err(InvalidLimits)
  }
  try {
    let budget = {
      nodes: limits.max_nodes,
      text: limits.max_bytes,
      depth: limits.max_depth,
    }
    let validation_work = Ref(max_contract_work)
    charge_nodes(budget, 1)
    if @decode.object_length(root) != Some(6) {
      stop(InvalidBody)
    }
    let object = match
      @decode.closed_object(root, [
        "domain", "edge_definitions", "identity_law_cid", "node_definitions", "value_law_cid",
        "version",
      ]) {
      Ok(value) => value
      Err(_) => stop(InvalidBody)
    }
    if read_property_text(required(object, "version"), budget) !=
      "actql-property-graph-contract/0.1" {
      stop(InvalidBody)
    }
    for name in ["identity_law_cid", "value_law_cid"] {
      if read_property_text(required(object, name), budget) !=
        property_law_cid() {
        stop(LawMismatch)
      }
    }
    let domain = read_property_text(required(object, "domain"), budget)
    let nodes = []
    let edges = []
    for
      (name, edge) in [("node_definitions", false), ("edge_definitions", true)] {
      let at = required(object, name)
      charge_nodes(budget, 1)
      let count = match @decode.array_length(at) {
        Some(value) => value
        None => stop(InvalidBody)
      }
      if count > budget.nodes {
        stop(BudgetExceeded)
      }
      for index in 0..<count {
        let (definition, endpoints) = read_property_definition(
          @decode.element_at(at, index).unwrap(),
          edge,
          budget,
          limits,
          validation_work,
        )
        match endpoints {
          None => nodes.push(definition)
          Some((source, target)) =>
            match
              @carrier.property_edge_definition(definition, source, target) {
              Ok(value) => edges.push(value)
              Err(_) => stop(InvalidStructure)
            }
        }
      }
    }
    let input = match
      @carrier.property_graph_usage(
        domain,
        nodes,
        edges,
        max_definitions=limits.max_nodes,
        max_contract_work=validation_work.val,
      ) {
      Ok((value, used)) => {
        validation_work.val -= used
        value
      }
      Err(LimitExceeded) => stop(BudgetExceeded)
      Err(_) => stop(InvalidStructure)
    }
    match admit_property_graph(input, limits) {
      Ok(value) => Ok((value, max_contract_work - validation_work.val))
      Err(_) => stop(BudgetExceeded)
    }
  } catch {
    ReadStop(issue) => Err(issue)
  }
}
