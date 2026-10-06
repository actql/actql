///|
// A definition-scoped match preserves heterogeneous schema knowledge. Bindings
// are normalized field aliases selected by the caller, not reserved properties.
priv struct PropertyMatchScope {
  definition : Int
  name : String
  properties : @carrier.Knowledge
  bindings : Array[(String, @row.FieldName)]
  label : String?
  scope : CheckedScope
}

///|
fn check_property_match_scope(
  entity : EntityKind,
  source : @decode.Cursor,
  root : @decode.ObjectView,
  graph : @carrier.Graph,
  b : Budget,
) -> PropertyMatchScope raise Stop {
  let profile = @carrier.graph_definition(graph)
  let name_source = decoded(@decode.required(root, "definition"))
  let name = decoded(@decode.text(name_source))
  let definitions = if entity == Nodes {
    @carrier.graph_node_count(profile)
  } else {
    @carrier.graph_edge_count(profile)
  }
  let mut found = None
  spend(b, name_source, definitions)
  for index in 0..<definitions {
    let definition = if entity == Nodes {
      @carrier.graph_node_at(profile, index).unwrap()
    } else {
      @carrier.graph_edge_element(
        @carrier.graph_edge_at(profile, index).unwrap(),
      )
    }
    if @carrier.graph_element_definition_name(definition).to_lower() ==
      name.to_lower() {
      found = Some((index, definition))
    }
  }
  guard found is Some((index, definition)) else {
    fail(name_source, InvalidName(name))
  }
  let label = @decode.lookup(root, "label").map(at => decoded(@decode.text(at)))
  let mut properties = @carrier.graph_element_definition_properties(definition)
  if label is Some(label) {
    let labels = @carrier.graph_element_definition_label_properties(definition)
    spend(b, source, labels.length())
    let mut found = None
    for (candidate, selected) in labels {
      if candidate.to_lower() == label.to_lower() {
        found = Some(selected)
      }
    }
    guard found is Some(selected) else { fail(source, InvalidName(label)) }
    properties = selected
  }
  let bindings = []
  let fields = []
  if @decode.lookup(root, "bindings") is Some(at) {
    let object = decoded(
      @decode.closed_object(
        at,
        if entity == Nodes {
          ["identity"]
        } else {
          ["identity", "source", "target"]
        },
      ),
    )
    for role in ["identity", "source", "target"] {
      if @decode.lookup(object, role) is Some(at) {
        let field_name = decoded(@decode.text(at))
        charge(b, at, field_name)
        if field_name.is_empty() ||
          @canonical.normalize_nfc_lf(field_name) != Ok(field_name) {
          fail(at, InvalidName(field_name))
        }
        let field = @row.Unqualified(field_name)
        bindings.push((role, field))
        fields.push((field, Some(@carrier.graph_identity(graph))))
      }
    }
  }
  spend(b, source, fields.length())
  let count = @carrier.field_count(properties)
  spend(b, source, count)
  for index in 0..<count {
    let field = @carrier.field_at(properties, index).unwrap()
    charge(b, source, @row.reference_name(field.name))
    fields.push((field.name, field.contract))
  }
  let seen : Map[String, Bool] = Map([])
  spend(b, source, fields.length())
  for (name, _) in fields {
    let folded = @row.reference_name(name).to_lower()
    if seen.contains(folded) {
      fail(source, ScopeCollision(@row.reference_name(name)))
    }
    seen[folded] = true
  }
  let rows = match
    @carrier.rows(
      fields,
      field_set=Closed,
      max_fields=fields.length(),
      max_name_bytes=b.limits.max_text_bytes,
    ) {
    Ok(rows) => rows
    Err(@row.DuplicateField(name)) =>
      fail(source, ScopeCollision(@row.reference_name(name)))
    Err(_) => fail(source, BudgetExceeded)
  }
  {
    definition: index,
    name: @carrier.graph_element_definition_name(definition),
    properties: @carrier.graph_element_definition_properties(definition),
    bindings,
    label,
    scope: { fields: rows, usage: { work: 0, nodes: 0, text_bytes: 0, }, },
  }
}

///|
pub fn match_property_definition(c : CheckedMatch) -> Int {
  c.property_scope.definition
}

///|
pub fn match_graph_element_definition_name(c : CheckedMatch) -> String {
  c.property_scope.name
}

///|
pub fn match_property_label(c : CheckedMatch) -> String? {
  c.property_scope.label
}

///|
pub fn match_property_schema(c : CheckedMatch) -> @carrier.Knowledge {
  c.property_scope.properties
}

///|
pub fn match_graph_binding(c : CheckedMatch, role : String) -> @row.FieldName? {
  for (candidate, name) in c.property_scope.bindings {
    if candidate == role {
      return Some(name)
    }
  }
  None
}

///|
pub fn match_property_scope_fields(c : CheckedMatch) -> @carrier.Knowledge {
  c.property_scope.scope.fields
}
