///|
/// Private state of the SAME original Carrier preflight, never a Resource Owner.
priv enum CarrierPreflightState {
  Pending
  Complete
  Rejected(Issue)
  Cleared
}

///|
priv enum CarrierPreflightStep {
  Start
  Contract
  RowsStart
  RowsField
  RowsNext
  GraphDomain
  GraphElement
  GraphElementHeader
  GraphKey
  GraphKeyNext
  GraphProperties
  GraphLabels
  GraphLabel
  GraphLabelNext
  GraphEndpoints
  EventColumns
  VectorIdentitiesStart
  VectorIdentity
  VectorComponents
}

///|
priv struct CarrierPreflightRead {
  b : Budget
  source : @decode.Cursor
  original : @carrier.Carrier
  mut state : CarrierPreflightState
  mut step : CarrierPreflightStep
  mut after_contract : CarrierPreflightStep
  mut after_rows : CarrierPreflightStep
  mut graph : @carrier.GraphDefinition?
  mut element : @carrier.GraphNodeDefinition?
  mut edge : @carrier.GraphEdgeDefinition?
  mut rows : @carrier.Knowledge?
  mut contract : ContractPreflightRead?
  mut nodes : Int
  mut edges : Int
  mut element_index : Int
  mut keys : Int
  mut key_index : Int
  mut labels : Int
  mut label_index : Int
  mut fields : Int
  mut field_index : Int
}

///|
fn begin_carrier_preflight_read(
  b : Budget,
  source : @decode.Cursor,
  original : @carrier.Carrier,
) -> CarrierPreflightRead {
  {
    b,
    source,
    original,
    state: Pending,
    step: Start,
    after_contract: Start,
    after_rows: Start,
    graph: None,
    element: None,
    edge: None,
    rows: None,
    contract: None,
    nodes: 0,
    edges: 0,
    element_index: 0,
    keys: 0,
    key_index: 0,
    labels: 0,
    label_index: 0,
    fields: 0,
    field_index: 0,
  }
}

///|
fn advance_carrier_preflight_read(read : CarrierPreflightRead) -> Unit {
  if !(read.state is Pending) {
    return
  }
  advance_carrier_preflight_read_owned(read) catch {
    Stop(issue) => read.state = Rejected(issue)
  }
}

///|
fn advance_carrier_preflight_read_owned(
  read : CarrierPreflightRead,
) -> Unit raise Stop {
  let b = read.b
  let source = read.source
  match read.step {
    Start =>
      match read.original {
        @carrier.Relation(rows) => {
          read.rows = Some(rows)
          read.after_rows = Start
          read.step = RowsStart
        }
        @carrier.Opaque(_) => {
          spend(b, source, 1)
          read.state = Complete
        }
        @carrier.GraphValue(graph) => {
          spend(b, source, 1)
          read.contract = Some(
            begin_contract_preflight_read(
              b,
              source,
              @carrier.graph_identity(graph),
              0,
            ),
          )
          read.after_contract = GraphDomain
          read.step = Contract
        }
        @carrier.EventValue(events) => {
          read.rows = Some(events.records)
          read.after_rows = EventColumns
          read.step = RowsStart
        }
        @carrier.VectorValue(vectors) => {
          read.rows = Some(@carrier.vector_records(vectors))
          read.after_rows = VectorIdentitiesStart
          read.step = RowsStart
        }
      }
    Contract => {
      let original = read.contract.unwrap()
      advance_contract_preflight_read(original)
      match original.state {
        Pending => ()
        Complete => {
          clear_contract_preflight_read(original)
          read.contract = None
          read.step = read.after_contract
        }
        Rejected(issue) => raise Stop(issue)
        Cleared =>
          abort("original Contract preflight was retired before its Carrier")
      }
    }
    RowsStart => {
      let rows = read.rows.unwrap()
      spend(b, source, 1)
      let count = @carrier.field_count(rows)
      spend(b, source, count)
      read.fields = count
      read.field_index = 0
      read.step = RowsField
    }
    RowsField =>
      if read.field_index < read.fields {
        let field = @carrier.field_at(read.rows.unwrap(), read.field_index).unwrap()
        charge(b, source, @schema.reference_name(field.name))
        match field.contract {
          Some(contract) => {
            read.contract = Some(
              begin_contract_preflight_read(b, source, contract, 1),
            )
            read.after_contract = RowsNext
            read.step = Contract
          }
          None => read.field_index += 1
        }
      } else {
        read.rows = None
        if read.after_rows is Start {
          read.state = Complete
        } else {
          read.step = read.after_rows
        }
      }
    RowsNext => {
      read.field_index += 1
      read.step = RowsField
    }
    GraphDomain => {
      guard read.original is @carrier.GraphValue(graph) else {
        abort("original Graph Carrier expected")
      }
      let definition = @carrier.graph_definition(graph)
      charge(b, source, @carrier.graph_domain(definition))
      let nodes = @carrier.graph_node_count(definition)
      let edges = @carrier.graph_edge_count(definition)
      spend(b, source, nodes)
      spend(b, source, edges)
      read.graph = Some(definition)
      read.nodes = nodes
      read.edges = edges
      read.element_index = 0
      read.step = GraphElement
    }
    GraphElement =>
      if read.element_index < read.nodes {
        read.element = @carrier.graph_node_at(
          read.graph.unwrap(),
          read.element_index,
        )
        read.edge = None
        read.step = GraphElementHeader
      } else if read.element_index - read.nodes < read.edges {
        let edge = @carrier.graph_edge_at(
          read.graph.unwrap(),
          read.element_index - read.nodes,
        ).unwrap()
        read.edge = Some(edge)
        read.element = Some(@carrier.graph_edge_element(edge))
        read.step = GraphElementHeader
      } else {
        read.graph = None
        read.state = Complete
      }
    GraphElementHeader => {
      let original = read.element.unwrap()
      spend(b, source, 1)
      charge(b, source, @carrier.graph_element_definition_name(original))
      let count = @carrier.graph_element_definition_key_count(original)
      spend(b, source, count)
      read.keys = count
      read.key_index = 0
      read.step = GraphKey
    }
    GraphKey =>
      if read.key_index < read.keys {
        let contract = @carrier.graph_element_definition_key_at(
          read.element.unwrap(),
          read.key_index,
        ).unwrap()
        read.contract = Some(
          begin_contract_preflight_read(b, source, contract, 0),
        )
        read.after_contract = GraphKeyNext
        read.step = Contract
      } else {
        read.step = GraphProperties
      }
    GraphKeyNext => {
      read.key_index += 1
      read.step = GraphKey
    }
    GraphProperties => {
      read.rows = Some(
        @carrier.graph_element_definition_properties(read.element.unwrap()),
      )
      read.after_rows = GraphLabels
      read.step = RowsStart
    }
    GraphLabels => {
      let count = @carrier.graph_element_definition_label_count(
        read.element.unwrap(),
      )
      spend(b, source, count)
      read.labels = count
      read.label_index = 0
      read.step = GraphLabel
    }
    GraphLabel =>
      if read.label_index < read.labels {
        let (label, properties) = @carrier.graph_element_definition_label_at(
          read.element.unwrap(),
          read.label_index,
        ).unwrap()
        charge(b, source, label)
        read.rows = Some(properties)
        read.after_rows = GraphLabelNext
        read.step = RowsStart
      } else if read.edge is Some(_) {
        read.step = GraphEndpoints
      } else {
        read.element = None
        read.element_index += 1
        read.step = GraphElement
      }
    GraphLabelNext => {
      read.label_index += 1
      read.step = GraphLabel
    }
    GraphEndpoints => {
      let (from, to) = @carrier.graph_edge_endpoints(read.edge.unwrap())
      spend(b, source, 2)
      charge(b, source, from)
      charge(b, source, to)
      read.element = None
      read.edge = None
      read.element_index += 1
      read.step = GraphElement
    }
    EventColumns => {
      guard read.original is @carrier.EventValue(events) else {
        abort("original Event Carrier expected")
      }
      spend(b, source, 2)
      charge(b, source, @schema.reference_name(events.identity.name))
      charge(b, source, @schema.reference_name(events.time.name))
      read.state = Complete
    }
    VectorIdentitiesStart => {
      guard read.original is @carrier.VectorValue(vectors) else {
        abort("original Vector Carrier expected")
      }
      let count = @carrier.vector_identity_count(vectors)
      spend(b, source, count)
      read.fields = count
      read.field_index = 0
      read.step = VectorIdentity
    }
    VectorIdentity => {
      guard read.original is @carrier.VectorValue(vectors) else {
        abort("original Vector Carrier expected")
      }
      if read.field_index < read.fields {
        let field = @carrier.vector_identity_at(vectors, read.field_index).unwrap()
        charge(b, source, @schema.reference_name(field.name))
        read.field_index += 1
      } else {
        read.step = VectorComponents
      }
    }
    VectorComponents => {
      guard read.original is @carrier.VectorValue(vectors) else {
        abort("original Vector Carrier expected")
      }
      spend(b, source, 1)
      charge(
        b,
        source,
        @schema.reference_name(@carrier.vector_components(vectors).name),
      )
      read.state = Complete
    }
  }
}

///|
fn clear_carrier_preflight_read(read : CarrierPreflightRead) -> Unit {
  if read.contract is Some(original) {
    clear_contract_preflight_read(original)
  }
  read.contract = None
  read.rows = None
  read.graph = None
  read.element = None
  read.edge = None
  read.state = Cleared
}
