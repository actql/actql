///|
pub(all) struct PortLimits {
  max_results : Int
  max_work : Int
  max_nodes : Int
  max_text_bytes : Int
  max_depth : Int
} derive(Eq, Debug)

///|
pub enum PortIssue {
  InvalidLimits
  BudgetExceeded
  Projection(Int, @relation.Issue)
  Transfer(Int, @pipeline.Issue)
}

///|
struct ResultPort {
  orders : CheckedOrders
  index : Int
  publication : @pipeline.PublishedInput
}

///|
struct ResultPorts {
  orders : CheckedOrders
  entries : Array[ResultPort]
  usage : Usage
}

///|
/// Prepare every named Result with its exact publication strategy and projected
/// producer. This is conditional static evidence, not a runtime import handle.
pub fn prepare_ports(
  orders : CheckedOrders,
  limits : PortLimits,
) -> Result[ResultPorts, PortIssue] {
  if limits.max_results < 0 ||
    limits.max_work < 0 ||
    limits.max_nodes < 0 ||
    limits.max_text_bytes < 0 ||
    limits.max_depth < 0 {
    return Err(InvalidLimits)
  }
  let results = orders.publication.results
  let (prior_work, prior_text) = checked_orders_usage(orders)
  if results.definitions.length() > limits.max_results ||
    prior_work > limits.max_work ||
    prior_text > limits.max_text_bytes {
    return Err(BudgetExceeded)
  }
  let mut work = limits.max_work - prior_work
  let mut nodes = limits.max_nodes
  let mut text = limits.max_text_bytes - prior_text
  let entries : Array[ResultPort] = []
  for i in 0..<results.definitions.length() {
    if work == 0 {
      return Err(BudgetExceeded)
    }
    work -= 1
    let definition = results.definitions[i]
    let object = @decode.open_object(definition.source).unwrap()
    let fields = @decode.required(object, "fields").unwrap()
    let schema = @pipeline.schema_at(results.pipeline, definition.target).unwrap()
    let projection = match
      @relation.check(Select, fields, schema, None, {
        max_work: work,
        max_nodes: nodes,
        max_text_bytes: text,
        max_tokens: 0,
        max_depth: limits.max_depth,
      }) {
      Err(e) => return Err(Projection(i, e))
      Ok(v) => v
    }
    work -= @relation.work_used(projection)
    nodes -= @relation.nodes_used(projection)
    text -= @relation.text_bytes_used(projection)
    let prepared = match
      @pipeline.publish_produced_input(
        results.pipeline,
        definition.target,
        projection,
        @decode.lookup(object, "order_by"),
        {
          max_steps: 0,
          max_work: work,
          max_nodes: nodes,
          max_text_bytes: text,
          max_tokens: 0,
          max_depth: limits.max_depth,
        },
      ) {
      Err(e) => return Err(Transfer(i, e))
      Ok(v) => v
    }
    let used = @pipeline.published_input_usage(prepared)
    work -= used.work
    nodes -= used.nodes
    text -= used.text_bytes
    entries.push({ orders, index: i, publication: prepared, })
  }
  Ok({
    orders,
    entries,
    usage: {
      work: limits.max_work - work,
      nodes: limits.max_nodes - nodes,
      text_bytes: limits.max_text_bytes - text,
    },
  })
}

///|
pub fn ports_orders(ports : ResultPorts) -> CheckedOrders {
  ports.orders
}

///|
pub fn ports_usage(ports : ResultPorts) -> Usage {
  ports.usage
}

///|
pub fn port_count(ports : ResultPorts) -> Int {
  ports.entries.length()
}

///|
pub fn port_at(ports : ResultPorts, index : Int) -> ResultPort? {
  ports.entries.get(index)
}

///|
pub fn lookup_port(ports : ResultPorts, name : String) -> ResultPort? {
  ports.orders.publication.results.names.get(name).map(i => ports.entries[i])
}

///|
pub fn port_orders(port : ResultPort) -> CheckedOrders {
  port.orders
}

///|
pub fn port_result(port : ResultPort) -> ResultDefinition {
  port.orders.publication.results.definitions[port.index]
}

///|
pub fn port_order(port : ResultPort) -> PublicationOrder {
  port.orders.publication.orders[port.index]
}

///|
pub fn port_schema(port : ResultPort) -> @schema.Schema {
  @relation.output_schema(
    @pipeline.producer_projection(port_input(port)).unwrap(),
  )
}

///|
/// Conditional producer input with this Result's projection and publication
/// order. Source-stage membership and runtime completion are separate checks.
pub fn port_input(port : ResultPort) -> @pipeline.ProducedInput {
  @pipeline.published_input(port.publication)
}

///|
pub fn port_publication(port : ResultPort) -> @pipeline.ResultPublication {
  @pipeline.input_publication(port.publication)
}
