///|
priv struct TraversalEndpointProperty {
  at_start : Bool
  property : String
  name : String
  contract : @contract.Contract
  // Indexed by the definition of the actual retained endpoint occurrence.
  positions : Array[Int]
}

///|
priv struct TraversalEndpointProperties {
  properties : Array[TraversalEndpointProperty]
  indices : Map[String, Int]
}

///|
fn endpoint_property_name_matches(
  b : Budget,
  at : @decode.Cursor,
  candidate : String,
  property : String,
  property_key : String,
) -> Bool raise Stop {
  spend(b, at, candidate.length())
  if candidate == property {
    return true
  }
  // Structured traversal follows the admitted Graph name identity. SQL
  // resolves its own authored names before emitting the declared spelling.
  charge(b, at, candidate)
  @carrier.graph_name_identity(candidate) == property_key
}

///|
fn traversal_endpoint_properties(
  graph : @carrier.Graph,
  source : @decode.Cursor,
  hop : TraversalHop,
  b : Budget,
) -> TraversalEndpointProperties raise Stop {
  let root = decoded(@decode.closed_object(source, ["start", "end"]))
  let profile = @carrier.graph_definition(graph)
  let definitions = @carrier.graph_node_count(profile)
  let properties : Array[TraversalEndpointProperty] = []
  let indices : Map[String, Int] = Map([])
  for role in ["start", "end"] {
    guard @decode.lookup(root, role) is Some(at) else { continue }
    let requested = decoded(@decode.elements(at))
    if requested.is_empty() {
      fail(at, InvalidBody)
    }
    let at_start = role == "start"
    let direction = if at_start {
      match hop.direction {
        Incoming => Outgoing
        Outgoing => Incoming
        Both => Both
      }
    } else {
      hop.direction
    }
    let (_, candidates) = traversal_hop_candidates(
      graph,
      at,
      direction,
      hop.types,
      b,
    )
    for request in requested {
      let object = decoded(@decode.closed_object(request, ["property", "as"]))
      let property = decoded(
        @decode.text(decoded(@decode.required(object, "property"))),
      )
      let name = decoded(@decode.text(decoded(@decode.required(object, "as"))))
      charge(b, request, property)
      charge(b, request, name)
      spend(b, request, property.length())
      let property_key = @carrier.graph_name_identity(property)
      if indices.contains(name) {
        fail(request, InvalidBody)
      }
      if definitions >= b.nodes - 1 {
        fail(request, BudgetExceeded)
      }
      b.nodes -= definitions + 2
      spend(b, request, definitions + 2)
      let positions = Array::make(definitions, -1)
      let mut merged = None
      for definition in candidates {
        let scope = traversal_definition_properties(profile, Nodes, definition)
        let mut matched = None
        for index in 0..<@carrier.field_count(scope) {
          spend(b, request, 1)
          let field = @carrier.field_at(scope, index).unwrap()
          let field_name = @row.reference_name(field.name)
          if endpoint_property_name_matches(
              b, request, field_name, property, property_key,
            ) {
            matched = Some((index, field.contract.unwrap()))
            break
          }
        }
        guard matched is Some((index, contract)) else {
          fail(request, InvalidBody)
        }
        positions[definition] = index
        if merged is Some(previous) {
          let (next, work) = @contract.join_nullability_usage(
            previous,
            contract,
            b.work,
          ) catch {
            _ => fail(request, BudgetExceeded)
          }
          spend(b, request, work)
          guard next is Some(_) else { fail(request, InvalidBody) }
          merged = next
        } else {
          merged = Some(contract)
        }
      }
      guard merged is Some(contract) else { fail(request, InvalidBody) }
      indices[name] = properties.length()
      properties.push({ at_start, property, name, contract, positions, })
    }
  }
  if properties.is_empty() {
    fail(source, InvalidBody)
  }
  { properties, indices, }
}

///|
pub fn traverse_endpoint_property_count(c : CheckedTraverse) -> Int {
  c.endpoint_properties.map(set => set.properties.length()).unwrap_or(0)
}

///|
pub fn traverse_endpoint_property_at(
  c : CheckedTraverse,
  index : Int,
) -> (Bool, String, String)? {
  c.endpoint_properties
  .bind(set => set.properties.get(index))
  .map(property => (property.at_start, property.property, property.name))
}

///|
pub fn traverse_endpoint_property_index(
  c : CheckedTraverse,
  field : @row.FieldName,
) -> Int? {
  guard field is Unqualified(name) else { return None }
  c.endpoint_properties.bind(set => set.indices.get(name))
}

///|
pub fn traverse_endpoint_property_position(
  c : CheckedTraverse,
  index : Int,
  definition : Int,
) -> Int? {
  c.endpoint_properties
  .bind(set => set.properties.get(index))
  .bind(property => {
    match property.positions.get(definition) {
      Some(position) if position >= 0 => Some(position)
      _ => None
    }
  })
}
