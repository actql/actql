///|
/// Opt in explicitly: legacy prepare and tuple-key access remain unchanged.
pub fn prepare_property(
  storage : @storage.Storage,
  limits : Limits,
) -> Result[Preparation, Issue] {
  prepare_source(Stored(storage), "", limits, property_profile=true)
}

///|
pub fn prepare_property_view(
  view : @lifecycle.ProducerView,
  graph : @carrier.Graph,
  limits : Limits,
) -> Result[Preparation, Issue] {
  if !valid_snapshot_limits(limits) {
    return Err(InvalidLimits)
  }
  let caps : @contract_graph.Limits = {
    max_bytes: limits.max_identity_bytes,
    max_nodes: limits.max_identity_nodes,
    max_depth: limits.max_identity_depth,
  }
  // A caller's schema is an expectation, not permission to relabel the view.
  guard @lifecycle.producer_view_property_graph_definition(view) is Ok(actual) &&
    @contract_graph.admit_property_graph(@carrier.graph_carrier(graph), caps)
    is Ok(expected) &&
    @carrier.property_graph(
      @carrier.property_graph_domain(actual),
      @carrier.property_graph_node_definitions(actual),
      @carrier.property_graph_edge_definitions(actual),
      max_definitions=limits.max_identity_nodes,
      max_contract_work=limits.max_identity_nodes,
    )
    is Ok(actual_carrier) &&
    @contract_graph.admit_property_graph(actual_carrier, caps)
    is Ok(actual_contract) &&
    @contract_graph.property_cid(actual_contract) ==
    @contract_graph.property_cid(expected) else {
    return Err(InvalidGraph)
  }
  prepare_source(Viewed(view, graph), "", limits, property_profile=true)
}

///|
/// Drain into the consumer's existing provisional writer. Publication requires
/// Complete plus successful storage finalization, not receipt of these bytes.
pub fn take_property_output(value : Preparation) -> Result[String, Issue] {
  if !value.property_profile {
    return Err(InvalidGraph)
  }
  if value.phase == Finished {
    guard value.output_tail is Some(tail) else { return Err(Terminal) }
    value.output_tail = None
    return Ok(tail)
  }
  guard value.builder is Some(builder) else { return Err(Terminal) }
  @identity.drain_property_output(builder).map_err(issue => Identity(issue))
}

///|
pub fn property_edge_key_at(value : Snapshot, index : Int) -> String? {
  if !value.property_profile {
    return None
  }
  @sort.key_component_at(value.edge_sort, index, 0)
}

///|
fn source_property_definition(
  source : SnapshotSource,
  index : Int,
  edge~ : Bool,
) -> Int? {
  match source {
    Stored(storage) =>
      if edge {
        @storage.edge_definition_index(storage, index)
      } else {
        @storage.node_definition_index(storage, index)
      }
    Viewed(view, _) => {
      let result = if edge {
        @lifecycle.producer_view_edge_definition(view, index)
      } else {
        @lifecycle.producer_view_node_definition(view, index)
      }
      match result {
        Ok(value) => Some(value)
        Err(_) => None
      }
    }
  }
}

///|
fn source_element_definition(
  source : SnapshotSource,
  graph : @carrier.Graph,
  index : Int,
  edge~ : Bool,
) -> @carrier.PropertyNodeDefinition? {
  guard @carrier.graph_property_definition(graph) is Some(profile) &&
    source_property_definition(source, index, edge~) is Some(definition) else {
    return None
  }
  if edge {
    @carrier.property_graph_edge_at(profile, definition).map(
      @carrier.property_edge_element,
    )
  } else {
    @carrier.property_graph_node_at(profile, definition)
  }
}

///|
fn source_properties(
  source : SnapshotSource,
  graph : @carrier.Graph,
  index : Int,
  edge~ : Bool,
) -> @carrier.Knowledge? {
  if @carrier.graph_property_definition(graph) is Some(_) {
    source_element_definition(source, graph, index, edge~).map(
      @carrier.property_definition_properties,
    )
  } else {
    Some(
      if edge {
        @carrier.graph_edge_properties(graph)
      } else {
        @carrier.graph_node_properties(graph)
      },
    )
  }
}

///|
fn source_property_keys(
  source : SnapshotSource,
  graph : @carrier.Graph,
  index : Int,
  edge~ : Bool,
) -> Result[Array[@value.CheckedValue], Issue] {
  guard source_element_definition(source, graph, index, edge~)
    is Some(definition) else {
    return Err(InvalidGraph)
  }
  let keys = []
  for component in 0..<@carrier.property_definition_key_count(definition) {
    let key = match source {
      Stored(storage) =>
        if edge {
          @storage.edge_typed_key_at(storage, index, component)
        } else {
          @storage.node_typed_key_at(storage, index, component)
        }
      Viewed(view, _) => {
        let key = if edge {
          @lifecycle.producer_view_edge_key(view, index, component)
        } else {
          @lifecycle.producer_view_node_key(view, index, component)
        }
        match key {
          Ok(value) => Some(value)
          Err(_) => None
        }
      }
    }
    guard key is Some(key) else { return Err(InvalidGraph) }
    keys.push(key)
  }
  Ok(keys)
}

///|
fn source_property_order_key(
  source : SnapshotSource,
  index : Int,
  edge~ : Bool,
) -> Result[String, Issue] {
  let key = match source {
    Stored(storage) =>
      if edge {
        @storage.edge_identity_order_key(storage, index)
      } else {
        @storage.node_identity_order_key(storage, index)
      }
    Viewed(view, _) => {
      let key = if edge {
        @lifecycle.producer_view_edge_identity_order_key(view, index)
      } else {
        @lifecycle.producer_view_node_identity_order_key(view, index)
      }
      match key {
        Ok(value) => Some(value)
        Err(_) => None
      }
    }
  }
  match key {
    Some(value) => Ok(value)
    None => Err(InvalidGraph)
  }
}

///|
fn source_property_edge_identity(
  source : SnapshotSource,
  index : Int,
) -> @value.CheckedValue? {
  match source {
    Stored(storage) => @storage.edge_identity(storage, index)
    Viewed(view, _) =>
      match @lifecycle.producer_view_edge_identity(view, index) {
        Ok(value) => Some(value)
        Err(_) => None
      }
  }
}
