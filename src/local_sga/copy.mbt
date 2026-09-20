///|
priv enum GraphCopyIssue {
  Unavailable
  Output(@graph.Issue)
}

///|
fn copy_graph_node(
  source : @storage.Storage,
  output : @graph.OutputBuilder,
  field_count : Int,
  index : Int,
) -> Result[Unit, GraphCopyIssue] {
  guard @storage.node_identity(source, index) is Some(identity) else {
    return Err(Unavailable)
  }
  let properties = []
  for field in 0..<field_count {
    guard @storage.node_property(source, index, field) is Some(value) else {
      return Err(Unavailable)
    }
    properties.push(value)
  }
  @graph.append_node(output, identity, properties).map_err(issue => {
    Output(issue)
  })
}

///|
fn copy_graph_edge(
  source : @storage.Storage,
  output : @graph.OutputBuilder,
  field_count : Int,
  index : Int,
) -> Result[Unit, GraphCopyIssue] {
  guard @storage.edge_endpoints(source, index)
    is Some((source_node, target_node)) &&
    @storage.node_identity(source, source_node) is Some(source_id) &&
    @storage.node_identity(source, target_node) is Some(target_id) &&
    @storage.edge_label(source, index) is Some(label) else {
    return Err(Unavailable)
  }
  let properties = []
  for field in 0..<field_count {
    guard @storage.edge_property(source, index, field) is Some(value) else {
      return Err(Unavailable)
    }
    properties.push(value)
  }
  @graph.append_edge(output, source_id, target_id, label, properties).map_err(issue => {
    Output(issue)
  })
}

///|
fn copy_graph_view_node(
  source : @lifecycle.ProducerView,
  output : @graph.OutputBuilder,
  field_count : Int,
  index : Int,
) -> Result[Unit, GraphCopyIssue] {
  let identity = match @lifecycle.producer_view_node_identity(source, index) {
    Ok(value) => value
    Err(_) => return Err(Unavailable)
  }
  let properties = []
  for field in 0..<field_count {
    match @lifecycle.producer_view_node_property(source, index, field) {
      Ok(value) => properties.push(value)
      Err(_) => return Err(Unavailable)
    }
  }
  @graph.append_node(output, identity, properties).map_err(issue => {
    Output(issue)
  })
}

///|
fn copy_graph_view_edge(
  source : @lifecycle.ProducerView,
  output : @graph.OutputBuilder,
  field_count : Int,
  index : Int,
) -> Result[Unit, GraphCopyIssue] {
  let (source_node, target_node) = match
    @lifecycle.producer_view_edge_endpoints(source, index) {
    Ok(value) => value
    Err(_) => return Err(Unavailable)
  }
  let source_id = match
    @lifecycle.producer_view_node_identity(source, source_node) {
    Ok(value) => value
    Err(_) => return Err(Unavailable)
  }
  let target_id = match
    @lifecycle.producer_view_node_identity(source, target_node) {
    Ok(value) => value
    Err(_) => return Err(Unavailable)
  }
  let label = match @lifecycle.producer_view_edge_label(source, index) {
    Ok(value) => value
    Err(_) => return Err(Unavailable)
  }
  let properties = []
  for field in 0..<field_count {
    match @lifecycle.producer_view_edge_property(source, index, field) {
      Ok(value) => properties.push(value)
      Err(_) => return Err(Unavailable)
    }
  }
  @graph.append_edge(output, source_id, target_id, label, properties).map_err(issue => {
    Output(issue)
  })
}
