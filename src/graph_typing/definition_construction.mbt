///|
/// Checked column mappings, not a row evaluator or an execution owner.
struct GraphElementConstruction {
  input : String
  definition : @carrier.GraphNodeDefinition
  keys : Array[@row.FieldName]
  properties : Array[(@row.FieldName, @row.FieldName)]
}

///|
struct GraphEdgeConstruction {
  element : GraphElementConstruction
  source_definition : String
  target_definition : String
  source_keys : Array[@row.FieldName]
  target_keys : Array[@row.FieldName]
}

///|
struct CheckedGraphConstruction {
  source : @decode.Cursor
  nodes : Array[GraphElementConstruction]
  edges : Array[GraphEdgeConstruction]
  output : @carrier.Carrier
  usage : Usage
}

///|
fn property_rows(
  inputs : Map[String, @carrier.Knowledge],
  at : @decode.Cursor,
) -> (String, @carrier.Knowledge) raise Stop {
  let name = construction_name(at)
  match inputs.get(name) {
    Some(rows) => (name, rows)
    None => fail(at, UnknownConstructionField(name))
  }
}

///|
fn property_keys(
  b : Budget,
  rows : @carrier.Knowledge,
  at : @decode.Cursor,
) -> Array[@carrier.Field] raise Stop {
  let items = decoded(@decode.elements(at))
  if items.is_empty() {
    fail(at, InvalidConstructionIdentity)
  }
  spend(b, at, items.length())
  let keys = []
  let seen : Map[String, Bool] = Map([])
  for item in items {
    let field = construction_field(rows, item)
    guard field.contract is Some(contract) &&
      @contract.key_comparable(contract, contract) else {
      fail(item, InvalidConstructionIdentity)
    }
    let name = @row.reference_name(field.name)
    charge(b, item, name)
    if seen.contains(name) {
      fail(item, DuplicateConstructionField(name))
    }
    seen[name] = true
    keys.push(field)
  }
  keys
}

///|
fn property_columns(
  b : Budget,
  rows : @carrier.Knowledge,
  at : @decode.Cursor,
  selector : @decode.Cursor?,
) -> Array[(@carrier.Field, @row.FieldName)] raise Stop {
  let selected = []
  let mut all = true
  let excluded : Map[String, Bool] = Map([])
  if selector is Some(selector) {
    let config = decoded(
      @decode.closed_object(selector, ["mode", "columns", "except"]),
    )
    let mode_at = decoded(@decode.required(config, "mode"))
    let mode = decoded(@decode.text(mode_at))
    all = mode == "all_columns" || mode == "all_columns_except"
    if mode == "no_properties" || mode == "all_columns" {
      if @decode.lookup(config, "columns") is Some(_) ||
        @decode.lookup(config, "except") is Some(_) {
        fail(selector, InvalidBody)
      }
    } else if mode == "columns" {
      if @decode.lookup(config, "except") is Some(_) {
        fail(selector, InvalidBody)
      }
      let list = decoded(@decode.required(config, "columns"))
      let columns = decoded(@decode.elements(list))
      spend(b, list, columns.length())
      for column in columns {
        let object = decoded(@decode.closed_object(column, ["from", "to"]))
        let field = construction_field(
          rows,
          decoded(@decode.required(object, "from")),
        )
        if field.contract is None {
          fail(column, IncompleteGraph)
        }
        let name = construction_name(decoded(@decode.required(object, "to")))
        charge(b, column, name)
        selected.push((field, @row.Unqualified(name)))
      }
    } else if mode == "all_columns_except" {
      if @decode.lookup(config, "columns") is Some(_) {
        fail(selector, InvalidBody)
      }
      let list = decoded(@decode.required(config, "except"))
      let columns = decoded(@decode.elements(list))
      spend(b, list, columns.length())
      for column in columns {
        let field = construction_field(rows, column)
        let name = @row.reference_name(field.name)
        if excluded.contains(name) {
          fail(column, DuplicateConstructionField(name))
        }
        excluded[name] = true
      }
    } else {
      fail(mode_at, InvalidBody)
    }
  }
  if all {
    spend(b, at, @carrier.field_count(rows))
    for index in 0..<@carrier.field_count(rows) {
      let field = @carrier.field_at(rows, index).unwrap()
      if excluded.contains(@row.reference_name(field.name)) {
        continue
      }
      guard field.name is @row.Unqualified(name) && field.contract is Some(_) else {
        fail(at, IncompleteGraph)
      }
      charge(b, at, name)
      selected.push((field, field.name))
    }
  }
  let seen : Map[String, Bool] = Map([])
  for (_, output) in selected {
    let name = @row.reference_name(output).to_lower()
    if seen.contains(name) {
      fail(at, DuplicateConstructionField(name))
    }
    seen[name] = true
  }
  selected
}

///|
fn graph_element(
  b : Budget,
  inputs : Map[String, @carrier.Knowledge],
  at : @decode.Cursor,
  object : @decode.ObjectView,
) -> GraphElementConstruction raise Stop {
  let name = construction_name(decoded(@decode.required(object, "name")))
  charge(b, at, name)
  let (input, rows) = property_rows(
    inputs,
    decoded(@decode.required(object, "from")),
  )
  let keys = property_keys(b, rows, decoded(@decode.required(object, "key")))
  let labels = []
  let label_properties = []
  let mappings : Map[String, (@carrier.Field, @row.FieldName)] = Map([])
  let label_configs = match @decode.lookup(object, "labels") {
    None => [(name, at, None)]
    Some(list) => {
      let items = decoded(@decode.elements(list))
      spend(b, list, items.length())
      items.map(item => {
        let config = decoded(
          @decode.closed_object(item, ["name", "properties"]),
        )
        let label = construction_name(decoded(@decode.required(config, "name")))
        (label, item, @decode.lookup(config, "properties"))
      })
    }
  }
  for (label, location, selector) in label_configs {
    charge(b, location, label)
    labels.push(label)
    let selected = property_columns(b, rows, location, selector)
    let fields = []
    for (field, output) in selected {
      let folded = @row.reference_name(output).to_lower()
      let canonical_output = match mappings.get(folded) {
        None => {
          mappings[folded] = (field, output)
          output
        }
        Some((prior, prior_output)) => {
          if prior.name != field.name {
            fail(location, DuplicateConstructionField(folded))
          }
          prior_output
        }
      }
      fields.push((canonical_output, field.contract))
    }
    let schema = match
      @carrier.rows(
        fields,
        field_set=@carrier.Closed,
        max_fields=b.limits.max_nodes,
        max_name_bytes=b.limits.max_text_bytes,
      ) {
      Ok(schema) => schema
      Err(_) => fail(location, BudgetExceeded)
    }
    label_properties.push((label, schema))
  }
  let fields = []
  for (_, (field, output)) in mappings {
    fields.push((output, field.contract))
  }
  let properties = match
    @carrier.rows(
      fields,
      field_set=@carrier.Closed,
      max_fields=b.limits.max_nodes,
      max_name_bytes=b.limits.max_text_bytes,
    ) {
    Ok(schema) => schema
    Err(_) => fail(at, BudgetExceeded)
  }
  let (definition, used) = match
    @carrier.graph_node_definition_usage(
      name,
      keys.map(field => field.contract.unwrap()),
      properties,
      labels,
      label_properties~,
      key_columns=keys.map(field => @row.reference_name(field.name)),
      max_fields=b.limits.max_nodes,
      max_name_bytes=b.limits.max_text_bytes,
      max_contract_work=b.work,
    ) {
    Ok(pair) => pair
    Err(@carrier.LimitExceeded) => fail(at, BudgetExceeded)
    Err(_) => fail(at, InvalidBody)
  }
  spend(b, at, used)
  let ordered = []
  for index in 0..<@carrier.field_count(properties) {
    let output = @carrier.field_at(properties, index).unwrap().name
    let (field, _) = mappings
      .get(@row.reference_name(output).to_lower())
      .unwrap()
    ordered.push((field.name, output))
  }
  {
    input,
    definition,
    keys: keys.map(field => field.name),
    properties: ordered,
  }
}

///|
fn property_endpoint(
  b : Budget,
  rows : @carrier.Knowledge,
  nodes : Map[String, GraphElementConstruction],
  at : @decode.Cursor,
) -> (String, Array[@row.FieldName]) raise Stop {
  let object = decoded(
    @decode.closed_object(at, ["definition", "key", "references_key"]),
  )
  let name_at = decoded(@decode.required(object, "definition"))
  let name = construction_name(name_at)
  let node = match nodes.get(name.to_lower()) {
    Some(node) => node
    None => fail(name_at, UnknownConstructionField(name))
  }
  let keys = property_keys(b, rows, decoded(@decode.required(object, "key")))
  let expected = @carrier.graph_element_definition_keys(node.definition)
  if keys.length() != expected.length() {
    fail(at, InvalidConstructionIdentity)
  }
  for index in 0..<keys.length() {
    spend(b, at, 1)
    let source = keys[index].contract.unwrap()
    let target = expected[index]
    // A nullable source column is valid: NULL excludes the edge at admission.
    // Precision/scale and reference kind remain part of the semantic key type.
    let compatible = match (source.shape, target.shape) {
      (@contract.Text(_), @contract.Text(_)) => true
      _ =>
        @contract.type_equal(
          @contract.with_nullability(source, false),
          target,
          1,
        ) catch {
          _ => false
        }
    }
    if !compatible {
      fail(at, InvalidConstructionIdentity)
    }
  }
  if @decode.lookup(object, "references_key") is Some(list) {
    let names = decoded(@decode.elements(list))
    if names.length() != node.keys.length() {
      fail(list, InvalidConstructionIdentity)
    }
    spend(b, list, names.length())
    for index, item in names {
      let reference = construction_reference(item)
      if reference != node.keys[index] {
        fail(item, InvalidConstructionIdentity)
      }
    }
  }
  (
    @carrier.graph_element_definition_name(node.definition),
    keys.map(field => field.name),
  )
}

///|
/// Structural constructor admission. The Program checking context issues the
/// domain; source JSON cannot supply a domain or refresh it using runtime data.
/// This value alone grants neither execution nor access to input rows.
pub fn check_graph_construction(
  source : @decode.Cursor,
  inputs : Array[(String, @carrier.Carrier)],
  domain : String,
  limits : Limits,
) -> Result[CheckedGraphConstruction, Issue] {
  try {
    if limits.max_work < 0 ||
      limits.max_nodes < 0 ||
      limits.max_depth < 0 ||
      limits.max_text_bytes < 0 {
      fail(source, InvalidLimits)
    }
    let b : Budget = {
      limits,
      work: limits.max_work,
      nodes: limits.max_nodes,
      text: limits.max_text_bytes,
    }
    scan(b, source)
    let root = decoded(
      @decode.closed_object(source, ["version", "nodes", "edges"]),
    )
    if decoded(@decode.text(decoded(@decode.required(root, "version")))) !=
      "actql-graph-constructor/0.1" {
      fail(source, InvalidBody)
    }
    let available : Map[String, @carrier.Knowledge] = Map([])
    spend(b, source, inputs.length())
    for (name, carrier) in inputs {
      if available.contains(name) {
        fail(source, DuplicateConstructionField(name))
      }
      guard carrier is @carrier.Relation(rows) &&
        @carrier.complete_schema(rows) is Some(_) else {
        fail(source, IncompleteGraph)
      }
      available[name] = rows
    }
    let nodes = []
    let names : Map[String, GraphElementConstruction] = Map([])
    let node_list = decoded(@decode.required(root, "nodes"))
    let entries = decoded(@decode.elements(node_list))
    spend(b, node_list, entries.length())
    for at in entries {
      let object = decoded(
        @decode.closed_object(at, ["name", "from", "key", "labels"]),
      )
      let node = graph_element(b, available, at, object)
      let name = @carrier.graph_element_definition_name(node.definition).to_lower()
      if names.contains(name) {
        fail(at, DuplicateConstructionField(name))
      }
      names[name] = node
      nodes.push(node)
    }
    let edges = []
    let edge_names : Map[String, Bool] = Map([])
    let edge_list = decoded(@decode.required(root, "edges"))
    let entries = decoded(@decode.elements(edge_list))
    spend(b, edge_list, entries.length())
    for at in entries {
      let object = decoded(
        @decode.closed_object(at, [
          "name", "from", "key", "labels", "source", "target",
        ]),
      )
      let element = graph_element(b, available, at, object)
      let name = @carrier.graph_element_definition_name(element.definition).to_lower()
      if names.contains(name) || edge_names.contains(name) {
        fail(at, DuplicateConstructionField(name))
      }
      edge_names[name] = true
      let rows = available.get(element.input).unwrap()
      let (source_definition, source_keys) = property_endpoint(
        b,
        rows,
        names,
        decoded(@decode.required(object, "source")),
      )
      let (target_definition, target_keys) = property_endpoint(
        b,
        rows,
        names,
        decoded(@decode.required(object, "target")),
      )
      edges.push({
        element,
        source_definition,
        target_definition,
        source_keys,
        target_keys,
      })
    }
    let (output, used) = match
      @carrier.graph_usage(
        domain,
        nodes.map(node => node.definition),
        edges.map(edge => {
          @carrier.graph_edge_definition(
            edge.element.definition,
            edge.source_definition,
            edge.target_definition,
          ).unwrap()
        }),
        max_definitions=limits.max_nodes,
        max_contract_work=b.work,
      ) {
      Ok(pair) => pair
      Err(@carrier.LimitExceeded) => fail(source, BudgetExceeded)
      Err(_) => fail(source, InvalidBody)
    }
    spend(b, source, used)
    Ok({
      source,
      nodes,
      edges,
      output,
      usage: {
        work: limits.max_work - b.work,
        nodes: limits.max_nodes - b.nodes,
        text_bytes: limits.max_text_bytes - b.text,
      },
    })
  } catch {
    Stop(issue) => Err(issue)
  }
}

///|
pub fn construction_output(
  value : CheckedGraphConstruction,
) -> @carrier.Carrier {
  value.output
}

///|
pub fn construction_source(value : CheckedGraphConstruction) -> @decode.Cursor {
  value.source
}

///|
pub fn construction_pending_count(_value : CheckedGraphConstruction) -> Int {
  5
}

///|
pub fn construction_pending_at(
  _value : CheckedGraphConstruction,
  index : Int,
) -> ConstructionObligation? {
  match index {
    0 => Some(AdmitGraphInputRows)
    1 => Some(RejectDuplicateDefinitionKeys)
    2 => Some(ExcludeNullKeysAndMissingEndpoints)
    3 => Some(ResolveGraphConstructionResources)
    4 => Some(ResolveGraphProfile)
    _ => None
  }
}

///|
pub fn construction_usage(value : CheckedGraphConstruction) -> Usage {
  value.usage
}

///|
pub fn construction_node_count(value : CheckedGraphConstruction) -> Int {
  value.nodes.length()
}

///|
pub fn construction_edge_count(value : CheckedGraphConstruction) -> Int {
  value.edges.length()
}

///|
pub fn construction_node_at(
  value : CheckedGraphConstruction,
  index : Int,
) -> GraphElementConstruction? {
  value.nodes.get(index)
}

///|
pub fn construction_edge_at(
  value : CheckedGraphConstruction,
  index : Int,
) -> GraphEdgeConstruction? {
  value.edges.get(index)
}

///|
pub fn graph_element_input(value : GraphElementConstruction) -> String {
  value.input
}

///|
pub fn graph_element_definition(
  value : GraphElementConstruction,
) -> @carrier.GraphNodeDefinition {
  value.definition
}

///|
pub fn graph_element_keys(
  value : GraphElementConstruction,
) -> Array[@row.FieldName] {
  value.keys.copy()
}

///|
pub fn graph_element_properties(
  value : GraphElementConstruction,
) -> Array[(@row.FieldName, @row.FieldName)] {
  value.properties.copy()
}

///|
pub fn graph_edge_element(
  value : GraphEdgeConstruction,
) -> GraphElementConstruction {
  value.element
}

///|
pub fn graph_edge_keys(
  value : GraphEdgeConstruction,
) -> (Array[@row.FieldName], Array[@row.FieldName]) {
  (value.source_keys.copy(), value.target_keys.copy())
}

///|
pub fn graph_edge_definitions(
  value : GraphEdgeConstruction,
) -> (String, String) {
  (value.source_definition, value.target_definition)
}
