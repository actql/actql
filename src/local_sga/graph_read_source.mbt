///|
/// A completed Graph can be read from its producing task or through an exact
/// managed handoff. Neither form transfers ownership of the retained graph.
priv enum GraphReadSource {
  Stored(@graph.ProducerRead)
  Viewed(@lifecycle.ProducerView)
}

///|
fn graph_read_available(source : GraphReadSource) -> Bool {
  match source {
    Stored(read) => @graph.producer_read_available(read)
    Viewed(view) =>
      @lifecycle.producer_read_reference_available(
        @lifecycle.producer_view_read_reference(view),
      )
  }
}

///|
fn graph_read_node_count(source : GraphReadSource) -> Int? {
  match source {
    Stored(read) => @graph.producer_read_storage(read).map(@storage.node_count)
    Viewed(view) => @lifecycle.producer_view_node_count(view)
  }
}

///|
fn graph_read_edge_count(source : GraphReadSource) -> Int? {
  match source {
    Stored(read) => @graph.producer_read_storage(read).map(@storage.edge_count)
    Viewed(view) => @lifecycle.producer_view_edge_count(view)
  }
}

///|
fn graph_read_node_identity(
  source : GraphReadSource,
  node : Int,
) -> @value.CheckedValue? {
  match source {
    Stored(read) =>
      @graph.producer_read_storage(read).bind(storage => {
        @storage.node_identity(storage, node)
      })
    Viewed(view) =>
      @lifecycle.producer_view_node_identity(view, node).to_option()
  }
}

///|
fn graph_read_node_property(
  source : GraphReadSource,
  node : Int,
  property : Int,
) -> @value.CheckedValue? {
  match source {
    Stored(read) =>
      @graph.producer_read_storage(read).bind(storage => {
        @storage.node_property(storage, node, property)
      })
    Viewed(view) =>
      @lifecycle.producer_view_node_property(view, node, property).to_option()
  }
}

///|
fn graph_read_node_index(
  source : GraphReadSource,
  identity : @value.CheckedValue,
) -> Result[Int?, Unit] {
  match source {
    Stored(read) =>
      match @graph.producer_read_storage(read) {
        Some(storage) => @storage.node_index(storage, identity).map_err(_ => ())
        None => Err(())
      }
    Viewed(view) =>
      @lifecycle.producer_view_node_index(view, identity).map_err(_ => ())
  }
}

///|
fn graph_read_edge_endpoints(
  source : GraphReadSource,
  edge : Int,
) -> (Int, Int)? {
  match source {
    Stored(read) =>
      @graph.producer_read_storage(read).bind(storage => {
        @storage.edge_endpoints(storage, edge)
      })
    Viewed(view) =>
      @lifecycle.producer_view_edge_endpoints(view, edge).to_option()
  }
}

///|
fn graph_read_edge_label(
  source : GraphReadSource,
  edge : Int,
) -> @value.CheckedValue?? {
  match source {
    Stored(read) =>
      @graph.producer_read_storage(read).bind(storage => {
        @storage.edge_label(storage, edge)
      })
    Viewed(view) => @lifecycle.producer_view_edge_label(view, edge).to_option()
  }
}

///|
fn graph_read_edge_property(
  source : GraphReadSource,
  edge : Int,
  property : Int,
) -> @value.CheckedValue? {
  match source {
    Stored(read) =>
      @graph.producer_read_storage(read).bind(storage => {
        @storage.edge_property(storage, edge, property)
      })
    Viewed(view) =>
      @lifecycle.producer_view_edge_property(view, edge, property).to_option()
  }
}

///|
fn graph_read_edge_index(
  source : GraphReadSource,
  from : @value.CheckedValue,
  to : @value.CheckedValue,
  label : @value.CheckedValue?,
) -> Result[Int?, Unit] {
  match source {
    Stored(read) =>
      match @graph.producer_read_storage(read) {
        Some(storage) =>
          @storage.edge_index(storage, from, to, label).map_err(_ => ())
        None => Err(())
      }
    Viewed(view) =>
      @lifecycle.producer_view_edge_index(view, from, to, label).map_err(_ => ())
  }
}
