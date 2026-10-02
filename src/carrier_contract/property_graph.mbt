///|
/// Checked schema knowledge, not admitted rows, uniqueness or execution rights.
struct PropertyNodeDefinition {
  name : String
  key_contracts : Array[@value.Contract]
  properties : Knowledge
  labels : Array[String]
  label_properties : Array[(String, Knowledge)]
  label_membership : Map[String, Bool]
}

///|
struct PropertyEdgeDefinition {
  element : PropertyNodeDefinition
  source_definition : String
  target_definition : String
}

///|
struct PropertyGraphDefinition {
  domain : String
  nodes : Array[PropertyNodeDefinition]
  edges : Array[PropertyEdgeDefinition]
  node_names : Map[String, Int]
  edge_names : Map[String, Int]
}

///|
pub(all) enum PropertyGraphIssue {
  InvalidLimits
  InvalidName
  InvalidKey
  IncompleteProperties
  InvalidLabel
  DuplicateLabel
  DuplicateDefinition
  UnknownEndpointDefinition
  LabelPropertyConflict
  PropertyTypeConflict
  LimitExceeded
  InvalidDomain
} derive(Eq, Debug)

///|
fn property_name(value : String) -> Bool {
  !value.is_empty() && @canonical.normalize_nfc_lf(value) == Ok(value)
}

///|
fn property_name_key(value : String) -> String {
  value.to_lower()
}

///|
pub fn property_node_definition(
  name : String,
  key_contracts : Array[@value.Contract],
  properties : Knowledge,
  labels : Array[String],
  max_fields~ : Int,
  max_name_bytes~ : Int,
  label_properties? : Array[(String, Knowledge)] = [],
  max_contract_work? : Int = 10000,
) -> Result[PropertyNodeDefinition, PropertyGraphIssue] {
  property_node_definition_usage(
    name,
    key_contracts,
    properties,
    labels,
    max_fields~,
    max_name_bytes~,
    label_properties~,
    max_contract_work~,
  ).map(pair => pair.0)
}

///|
/// Validation shares its remaining work budget with the enclosing checker.
pub fn property_node_definition_usage(
  name : String,
  key_contracts : Array[@value.Contract],
  properties : Knowledge,
  labels : Array[String],
  max_fields~ : Int,
  max_name_bytes~ : Int,
  label_properties? : Array[(String, Knowledge)] = [],
  max_contract_work? : Int = 10000,
) -> Result[(PropertyNodeDefinition, Int), PropertyGraphIssue] {
  if max_fields < 0 || max_name_bytes < 0 || max_contract_work < 0 {
    return Err(InvalidLimits)
  }
  if !property_name(name) {
    return Err(InvalidName)
  }
  if key_contracts.is_empty() {
    return Err(InvalidKey)
  }
  if key_contracts.length() > max_fields ||
    field_count(properties) > max_fields ||
    labels.length() > max_fields {
    return Err(LimitExceeded)
  }
  let mut work = max_contract_work
  for contract in key_contracts {
    if work == 0 {
      return Err(LimitExceeded)
    }
    work -= 1
    if !@value.key_comparable(contract, contract) {
      return Err(InvalidKey)
    }
  }
  if field_set(properties) != Closed || properties.has_qualified_fields {
    return Err(IncompleteProperties)
  }
  let property_names : Map[String, Bool] = Map([])
  for index in 0..<field_count(properties) {
    if work == 0 {
      return Err(LimitExceeded)
    }
    work -= 1
    let field = field_at(properties, index).unwrap()
    if field.contract is None {
      return Err(IncompleteProperties)
    }
    let folded = property_name_key(@row.reference_name(field.name))
    if property_names.contains(folded) {
      return Err(IncompleteProperties)
    }
    property_names[folded] = true
  }
  let seen : Map[String, Bool] = Map([])
  let mut bytes = max_name_bytes
  for text in [name, ..labels] {
    if work == 0 {
      return Err(LimitExceeded)
    }
    work -= 1
    let size = match @scalar.admit_utf8_length(text, bytes) {
      Ok(size) => size
      Err(_) => return Err(LimitExceeded)
    }
    bytes -= size
  }
  let admitted : Array[String] = []
  for label in labels {
    if work == 0 {
      return Err(LimitExceeded)
    }
    work -= 1
    if !property_name(label) {
      return Err(InvalidLabel)
    }
    let folded = property_name_key(label)
    if seen.contains(folded) {
      return Err(DuplicateLabel)
    }
    seen[folded] = true
    admitted.push(label)
  }
  admitted.sort_by(@canonical.compare_utf16)
  let scoped : Array[(String, Knowledge)] = []
  if !label_properties.is_empty() &&
    label_properties.length() != admitted.length() {
    return Err(IncompleteProperties)
  }
  for label in admitted {
    let mut selected = None
    if label_properties.is_empty() {
      selected = Some(properties)
    } else {
      for (candidate, knowledge) in label_properties {
        if work == 0 {
          return Err(LimitExceeded)
        }
        work -= 1
        if property_name_key(candidate) == property_name_key(label) {
          if selected is Some(_) {
            return Err(DuplicateLabel)
          }
          selected = Some(knowledge)
        }
      }
    }
    guard selected is Some(selected) &&
      field_set(selected) == Closed &&
      !selected.has_qualified_fields else {
      return Err(IncompleteProperties)
    }
    let selected_names : Map[String, Bool] = Map([])
    for index in 0..<field_count(selected) {
      let field = field_at(selected, index).unwrap()
      let folded = property_name_key(@row.reference_name(field.name))
      if selected_names.contains(folded) || field.contract is None {
        return Err(IncompleteProperties)
      }
      selected_names[folded] = true
      let mut expected = None
      for parent in 0..<field_count(properties) {
        if work == 0 {
          return Err(LimitExceeded)
        }
        work -= 1
        let parent = field_at(properties, parent).unwrap()
        if property_name_key(@row.reference_name(parent.name)) == folded {
          expected = parent.contract
          break
        }
      }
      guard expected is Some(expected) else { return Err(IncompleteProperties) }
      try {
        let (forward, used) = @value.assignable_usage(
          field.contract.unwrap(),
          expected,
          work,
        )
        work -= used
        let (backward, used) = @value.assignable_usage(
          expected,
          field.contract.unwrap(),
          work,
        )
        work -= used
        if !forward || !backward {
          return Err(IncompleteProperties)
        }
      } catch {
        _ => return Err(LimitExceeded)
      }
    }
    scoped.push((label, selected))
  }
  Ok(
    (
      {
        name,
        key_contracts: key_contracts.map(contract => {
          @value.with_nullability(contract, false)
        }),
        properties,
        labels: admitted,
        label_properties: scoped,
        label_membership: seen,
      },
      max_contract_work - work,
    ),
  )
}

///|
pub fn property_edge_definition(
  element : PropertyNodeDefinition,
  source_definition : String,
  target_definition : String,
) -> Result[PropertyEdgeDefinition, PropertyGraphIssue] {
  if !property_name(source_definition) || !property_name(target_definition) {
    return Err(InvalidName)
  }
  Ok({ element, source_definition, target_definition, })
}

///|
/// New Graph profile. The domain is a definition-provenance CID supplied by
/// the checking context; this structural constructor does not issue that CID
/// or certify that an arbitrary caller has established its provenance.
pub fn property_graph(
  domain : String,
  nodes : Array[PropertyNodeDefinition],
  edges : Array[PropertyEdgeDefinition],
  max_definitions~ : Int,
  max_contract_work~ : Int,
) -> Result[Carrier, PropertyGraphIssue] {
  property_graph_usage(
    domain,
    nodes,
    edges,
    max_definitions~,
    max_contract_work~,
  ).map(pair => pair.0)
}

///|
pub fn property_graph_usage(
  domain : String,
  nodes : Array[PropertyNodeDefinition],
  edges : Array[PropertyEdgeDefinition],
  max_definitions~ : Int,
  max_contract_work~ : Int,
) -> Result[(Carrier, Int), PropertyGraphIssue] {
  if max_definitions < 0 || max_contract_work < 0 {
    return Err(InvalidLimits)
  }
  if !domain.has_prefix("sha256:") || domain.length() != 71 {
    return Err(InvalidDomain)
  }
  for character in domain.to_array()[7:] {
    if !(character >= '0' && character <= '9') &&
      !(character >= 'a' && character <= 'f') {
      return Err(InvalidDomain)
    }
  }
  if nodes.length() > max_definitions ||
    edges.length() > max_definitions - nodes.length() {
    return Err(LimitExceeded)
  }
  let node_names : Map[String, Int] = Map([])
  let names : Map[String, Bool] = Map([])
  let mut work = max_contract_work
  for index, node in nodes {
    if work == 0 {
      return Err(LimitExceeded)
    }
    work -= 1
    let key = property_name_key(node.name)
    if names.contains(key) {
      return Err(DuplicateDefinition)
    }
    names[key] = true
    node_names[key] = index
  }
  let edge_names : Map[String, Int] = Map([])
  for index, edge in edges {
    if work == 0 {
      return Err(LimitExceeded)
    }
    work -= 1
    let key = property_name_key(edge.element.name)
    if names.contains(key) {
      return Err(DuplicateDefinition)
    }
    names[key] = true
    edge_names[key] = index
    if !node_names.contains(property_name_key(edge.source_definition)) ||
      !node_names.contains(property_name_key(edge.target_definition)) {
      return Err(UnknownEndpointDefinition)
    }
  }
  // One label namespace spans both element families. Its exposed property set
  // is a separate obligation from graph-wide value-type compatibility below.
  let known : Map[String, Knowledge] = Map([])
  for kind in 0..<2 {
    let selected = if kind == 0 {
      nodes
    } else {
      edges.map(edge => edge.element)
    }
    for definition in selected {
      for (label, exposed_properties) in definition.label_properties {
        if work == 0 {
          return Err(LimitExceeded)
        }
        work -= 1
        let folded = property_name_key(label)
        match known.get(folded) {
          None => known[folded] = exposed_properties
          Some(previous) => {
            if field_count(previous) != field_count(exposed_properties) {
              return Err(LabelPropertyConflict)
            }
            for index in 0..<field_count(previous) {
              let field = field_at(previous, index).unwrap()
              let mut current = None
              for candidate in 0..<field_count(exposed_properties) {
                if work == 0 {
                  return Err(LimitExceeded)
                }
                work -= 1
                let candidate = field_at(exposed_properties, candidate).unwrap()
                if property_name_key(@row.reference_name(field.name)) ==
                  property_name_key(@row.reference_name(candidate.name)) {
                  current = candidate.contract
                  break
                }
              }
              guard current is Some(current) else {
                return Err(LabelPropertyConflict)
              }
              try {
                let (joined, used) = @value.join_nullability_usage(
                  field.contract.unwrap(),
                  current,
                  work,
                )
                work -= used
                if joined is None {
                  return Err(LabelPropertyConflict)
                }
              } catch {
                _ => return Err(LimitExceeded)
              }
            }
          }
        }
      }
    }
  }
  // Property names have graph-wide value types, even under different labels.
  // Joining checks existing value compatibility without replacing any
  // definition's declared nullability or creating a homogeneous Graph schema.
  let property_types : Map[String, @value.Contract] = Map([])
  for kind in 0..<2 {
    let selected = if kind == 0 {
      nodes
    } else {
      edges.map(edge => edge.element)
    }
    for definition in selected {
      for index in 0..<field_count(definition.properties) {
        if work == 0 {
          return Err(LimitExceeded)
        }
        work -= 1
        let field = field_at(definition.properties, index).unwrap()
        let folded = property_name_key(@row.reference_name(field.name))
        let contract = field.contract.unwrap()
        match property_types.get(folded) {
          None => property_types[folded] = contract
          Some(previous) =>
            try {
              let (joined, used) = @value.join_nullability_usage(
                previous, contract, work,
              )
              work -= used
              guard joined is Some(joined) else {
                return Err(PropertyTypeConflict)
              }
              property_types[folded] = joined
            } catch {
              _ => return Err(LimitExceeded)
            }
        }
      }
    }
  }
  let json = @value.primitive(JsonType, nullable=false)
  Ok(
    (
      GraphValue({
        property_graph: {
          domain,
          nodes: nodes.copy(),
          edges: edges.copy(),
          node_names,
          edge_names,
        },
        identity: json,
        // There is no homogeneous property schema. Legacy consumers must not
        // mistake one representative definition for the complete new graph.
        node_properties: unknown_rows(),
        edge_properties: unknown_rows(),
        semantic_label: None,
        row_names: None,
        labels: None,
      }),
      max_contract_work - work,
    ),
  )
}

///|
pub fn graph_property_definition(graph : Graph) -> PropertyGraphDefinition {
  graph.property_graph
}

///|
pub fn property_graph_domain(value : PropertyGraphDefinition) -> String {
  value.domain
}

///|
pub fn property_graph_node_definitions(
  value : PropertyGraphDefinition,
) -> Array[PropertyNodeDefinition] {
  value.nodes.copy()
}

///|
pub fn property_graph_edge_definitions(
  value : PropertyGraphDefinition,
) -> Array[PropertyEdgeDefinition] {
  value.edges.copy()
}

///|
pub fn property_graph_node_at(
  value : PropertyGraphDefinition,
  index : Int,
) -> PropertyNodeDefinition? {
  value.nodes.get(index)
}

///|
pub fn property_graph_node_named(
  value : PropertyGraphDefinition,
  name : String,
) -> PropertyNodeDefinition? {
  value.node_names
  .get(property_name_key(name))
  .bind(index => value.nodes.get(index))
}

///|
pub fn property_graph_edge_at(
  value : PropertyGraphDefinition,
  index : Int,
) -> PropertyEdgeDefinition? {
  value.edges.get(index)
}

///|
pub fn property_graph_edge_named(
  value : PropertyGraphDefinition,
  name : String,
) -> PropertyEdgeDefinition? {
  value.edge_names
  .get(property_name_key(name))
  .bind(index => value.edges.get(index))
}

///|
pub fn property_graph_node_count(value : PropertyGraphDefinition) -> Int {
  value.nodes.length()
}

///|
pub fn property_graph_edge_count(value : PropertyGraphDefinition) -> Int {
  value.edges.length()
}

///|
pub fn property_definition_name(value : PropertyNodeDefinition) -> String {
  value.name
}

///|
pub fn property_definition_key_count(value : PropertyNodeDefinition) -> Int {
  value.key_contracts.length()
}

///|
pub fn property_definition_keys(
  value : PropertyNodeDefinition,
) -> Array[@value.Contract] {
  value.key_contracts.copy()
}

///|
pub fn property_definition_properties(
  value : PropertyNodeDefinition,
) -> Knowledge {
  value.properties
}

///|
pub fn property_definition_labels(
  value : PropertyNodeDefinition,
) -> Array[String] {
  value.labels.copy()
}

///|
pub fn property_definition_label_properties(
  value : PropertyNodeDefinition,
) -> Array[(String, Knowledge)] {
  value.label_properties.copy()
}

///|
/// Membership comes from admitted static labels, never from property values.
pub fn property_definition_has_label(
  value : PropertyNodeDefinition,
  label : String,
) -> Bool {
  value.label_membership.contains(property_name_key(label))
}

///|
pub fn property_edge_element(
  value : PropertyEdgeDefinition,
) -> PropertyNodeDefinition {
  value.element
}

///|
pub fn property_edge_endpoints(
  value : PropertyEdgeDefinition,
) -> (String, String) {
  (value.source_definition, value.target_definition)
}
