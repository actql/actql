///|
priv struct GraphRowField {
  name : String
  mut contract : @value.Contract
  mut definitions : Int
  key_alias : Bool
}

///|
/// A finite union of admitted definition columns, not sampled row knowledge.
/// Display spelling is selected in canonical definition-name order so contract
/// serialization/reload cannot change the selected spelling or schema identity.
fn check_graph_rows(
  operation : Operation,
  source : @decode.Cursor,
  input : @carrier.Carrier,
  limits : Limits,
) -> Result[CheckedProjection, Issue] {
  guard input is @carrier.GraphValue(graph) else {
    return Err(issue(source, IncompleteGraph))
  }
  let profile = @carrier.graph_property_definition(graph)
  let definitions = if operation == NodeRows {
    @carrier.property_graph_node_definitions(profile)
  } else {
    @carrier.property_graph_edge_definitions(profile).map(
      @carrier.property_edge_element,
    )
  }
  if definitions.length() > limits.max_work - 1 ||
    definitions.length() > limits.max_nodes - 1 {
    return Err(issue(source, BudgetExceeded))
  }
  let mut work = limits.max_work - 1 - definitions.length()
  // Spelling selection needs deterministic order, but sorting is not free work.
  // Stop as soon as the existing check budget cannot cover another comparison.
  for index in 1..<definitions.length() {
    let mut current = index
    while current > 0 {
      if work == 0 {
        return Err(issue(source, BudgetExceeded))
      }
      work -= 1
      if @canonical.compare_utf16(
          @carrier.property_definition_name(definitions[current - 1]),
          @carrier.property_definition_name(definitions[current]),
        ) <=
        0 {
        break
      }
      let earlier = definitions[current - 1]
      definitions[current - 1] = definitions[current]
      definitions[current] = earlier
      current -= 1
    }
  }
  let roles = if operation == NodeRows {
    ["id", "labels"]
  } else {
    ["id", "src", "dst", "labels"]
  }
  let known : Map[String, GraphRowField] = Map([])
  let mut text = limits.max_text_bytes
  let mut nodes = limits.max_nodes - 1 - definitions.length()
  for definition in definitions {
    let definition_names : Map[String, Bool] = Map([])
    let properties = @carrier.property_definition_properties(definition)
    let key_count = @carrier.property_definition_key_count(definition)
    let field_count = @carrier.field_count(properties)
    if key_count > work || field_count > work - key_count {
      return Err(issue(source, BudgetExceeded))
    }
    for index in 0..<(key_count + field_count) {
      work -= 1
      let (name, contract) = if index < key_count {
        match @carrier.property_definition_key_column_at(definition, index) {
          None => continue
          Some(name) =>
            (
              name,
              @carrier.property_definition_key_at(definition, index).unwrap(),
            )
        }
      } else {
        let field = @carrier.field_at(properties, index - key_count).unwrap()
        (@row.reference_name(field.name), field.contract.unwrap())
      }
      let folded = @carrier.property_name_identity(name)
      if roles.contains(folded) || definition_names.contains(folded) {
        return Err(issue(source, OutputCollision(@row.Unqualified(name))))
      }
      definition_names[folded] = true
      match @scalar.admit_utf8_length(name, text) {
        Ok(size) => text -= size
        Err(_) => return Err(issue(source, BudgetExceeded))
      }
      match known.get(folded) {
        None => {
          if nodes == 0 {
            return Err(issue(source, BudgetExceeded))
          }
          nodes -= 1
          known[folded] = {
            name,
            contract,
            definitions: 1,
            key_alias: index < key_count,
          }
        }
        Some(previous) =>
          try {
            if previous.key_alias != (index < key_count) {
              return Err(issue(source, OutputCollision(@row.Unqualified(name))))
            }
            let (joined, used) = @value.join_nullability_usage(
              previous.contract,
              contract,
              work,
            )
            work -= used
            guard joined is Some(joined) else {
              return Err(
                issue(source, OutputTypeConflict(@row.Unqualified(name))),
              )
            }
            previous.contract = joined
            previous.definitions += 1
          } catch {
            _ => return Err(issue(source, BudgetExceeded))
          }
      }
    }
  }
  let fields = []
  for role in roles {
    if work == 0 || nodes == 0 {
      return Err(issue(source, BudgetExceeded))
    }
    work -= 1
    nodes -= 1
    match @scalar.admit_utf8_length(role, text) {
      Ok(size) => text -= size
      Err(_) => return Err(issue(source, BudgetExceeded))
    }
    let contract = if role == "labels" {
      @value.array_contract(
        @value.primitive(StringType, nullable=false),
        nullable=false,
      ).unwrap()
    } else {
      @carrier.graph_identity(graph)
    }
    fields.push((@row.Unqualified(role), contract, @row.Required))
  }
  for (_, field) in known {
    fields.push(
      (
        @row.Unqualified(field.name),
        field.contract,
        if field.definitions == definitions.length() {
          @row.Required
        } else {
          @row.Conditional
        },
      ),
    )
  }
  let schema = match
    @row.from_presence_fields(
      fields,
      max_fields=limits.max_nodes,
      max_name_bytes=limits.max_text_bytes,
    ) {
    Ok(schema) => schema
    Err(_) => return Err(issue(source, BudgetExceeded))
  }
  Ok({
    operation,
    source,
    input,
    output: @carrier.relation(@carrier.typed_rows(schema)),
    usage: {
      work: limits.max_work - work,
      nodes: limits.max_nodes - nodes,
      text_bytes: limits.max_text_bytes - text,
    },
  })
}
