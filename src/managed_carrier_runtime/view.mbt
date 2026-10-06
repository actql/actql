///|
/// Read-only access to one exact managed Carrier producer occurrence. The
/// view preserves Carrier structure without exposing a family storage handle.
struct ProducerView {
  read : ProducerReadReference
  kind : @carrier.Kind
  nodes : Int
  edges : Int
  records : Int
  node_identity : (Int) -> @value.CheckedValue?
  node_property : (Int, Int) -> @value.CheckedValue?
  node_index : (@value.CheckedValue) -> Int??
  edge_endpoints : (Int) -> (Int, Int)?
  edge_property : (Int, Int) -> @value.CheckedValue?
  graph : GraphView?
  record_fields : (Int) -> Int?
  record_field : (Int, Int) -> (@schema.FieldName, @value.CheckedValue)?
}

///|
/// Additional structure on the same read occurrence, not a second retention
/// owner. Definition indices select the exact heterogeneous property schema.
priv struct GraphView {
  definition : @carrier.GraphDefinition
  node_definition : (Int) -> Int?
  edge_definition : (Int) -> Int?
  edge_identity : (Int) -> @value.CheckedValue?
  edge_identity_index : (@value.CheckedValue) -> Int??
  node_key : (Int, Int) -> @value.CheckedValue?
  edge_key : (Int, Int) -> @value.CheckedValue?
  node_identity_order_key : (Int) -> String?
  edge_identity_order_key : (Int) -> String?
}

///|
pub(all) enum ViewIssue {
  WrongCarrier
  InvalidExtent
  Unavailable
  InvalidRecord
  InvalidField
} derive(Eq, Debug)

///|
fn producer_reference_kind(value : ProducerReadReference) -> @carrier.Kind {
  completion_reference_kind(value.output)
}

///|
fn producer_view_live(value : ProducerView) -> Bool {
  producer_read_reference_available(value.read)
}

///|
/// A keyed Graph uses independent edge identities and per-definition schemas.
/// The contract comes from the exact bound output, never from callback input.
pub fn prepare_graph_producer_view(
  read : ProducerReadReference,
  nodes : Int,
  edges : Int,
  node_identity : (Int) -> @value.CheckedValue?,
  node_property : (Int, Int) -> @value.CheckedValue?,
  node_index : (@value.CheckedValue) -> Int??,
  edge_endpoints : (Int) -> (Int, Int)?,
  edge_property : (Int, Int) -> @value.CheckedValue?,
  node_definition : (Int) -> Int?,
  edge_definition : (Int) -> Int?,
  edge_identity : (Int) -> @value.CheckedValue?,
  edge_identity_index : (@value.CheckedValue) -> Int??,
  node_key : (Int, Int) -> @value.CheckedValue?,
  edge_key : (Int, Int) -> @value.CheckedValue?,
  node_identity_order_key : (Int) -> String?,
  edge_identity_order_key : (Int) -> String?,
) -> Result[ProducerView, ViewIssue] {
  guard read.output.binding.carrier is @carrier.GraphValue(graph) else {
    return Err(WrongCarrier)
  }
  let definition = @carrier.graph_definition(graph)
  if nodes < 0 || edges < 0 {
    return Err(InvalidExtent)
  }
  if !producer_read_reference_available(read) {
    return Err(Unavailable)
  }
  Ok({
    read,
    kind: @carrier.GraphKind,
    nodes,
    edges,
    records: 0,
    node_identity,
    node_property,
    node_index,
    edge_endpoints,
    edge_property,
    graph: Some({
      definition,
      node_definition,
      edge_definition,
      edge_identity,
      edge_identity_index,
      node_key,
      edge_key,
      node_identity_order_key,
      edge_identity_order_key,
    }),
    record_fields: _ => None,
    record_field: (_, _) => None,
  })
}

///|
pub fn prepare_record_producer_view(
  read : ProducerReadReference,
  records : Int,
  record_fields : (Int) -> Int?,
  record_field : (Int, Int) -> (@schema.FieldName, @value.CheckedValue)?,
) -> Result[ProducerView, ViewIssue] {
  let kind = producer_reference_kind(read)
  if kind != @carrier.EventsKind && kind != @carrier.VectorsKind {
    return Err(WrongCarrier)
  }
  if records < 0 {
    return Err(InvalidExtent)
  }
  if !producer_read_reference_available(read) {
    return Err(Unavailable)
  }
  Ok({
    read,
    kind,
    nodes: 0,
    edges: 0,
    records,
    node_identity: _ => None,
    node_property: (_, _) => None,
    node_index: _ => None,
    edge_endpoints: _ => None,
    edge_property: (_, _) => None,
    graph: None,
    record_fields,
    record_field,
  })
}

///|
pub fn producer_view_kind(value : ProducerView) -> @carrier.Kind {
  value.kind
}

///|
pub fn producer_view_graph_definition(
  value : ProducerView,
) -> Result[@carrier.GraphDefinition, ViewIssue] {
  if !producer_view_live(value) {
    return Err(Unavailable)
  }
  match value.graph {
    Some(profile) => Ok(profile.definition)
    None => Err(WrongCarrier)
  }
}

///|
pub fn producer_view_node_definition(
  value : ProducerView,
  node : Int,
) -> Result[Int, ViewIssue] {
  let definition = match producer_view_graph_definition(value) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if node < 0 || node >= value.nodes {
    return Err(InvalidRecord)
  }
  let profile = value.graph.unwrap()
  match (profile.node_definition)(node) {
    Some(index) if @carrier.graph_node_at(definition, index) is Some(_) =>
      Ok(index)
    _ => Err(InvalidRecord)
  }
}

///|
pub fn producer_view_edge_definition(
  value : ProducerView,
  edge : Int,
) -> Result[Int, ViewIssue] {
  let definition = match producer_view_graph_definition(value) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if edge < 0 || edge >= value.edges {
    return Err(InvalidRecord)
  }
  let profile = value.graph.unwrap()
  match (profile.edge_definition)(edge) {
    Some(index) if @carrier.graph_edge_at(definition, index) is Some(_) =>
      Ok(index)
    _ => Err(InvalidRecord)
  }
}

///|
pub fn producer_view_node_identity_order_key(
  value : ProducerView,
  node : Int,
) -> Result[String, ViewIssue] {
  match producer_view_node_definition(value, node) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match (value.graph.unwrap().node_identity_order_key)(node) {
    Some(key) => Ok(key)
    None => Err(InvalidRecord)
  }
}

///|
pub fn producer_view_edge_identity_order_key(
  value : ProducerView,
  edge : Int,
) -> Result[String, ViewIssue] {
  match producer_view_edge_definition(value, edge) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match (value.graph.unwrap().edge_identity_order_key)(edge) {
    Some(key) => Ok(key)
    None => Err(InvalidRecord)
  }
}

///|
pub fn producer_view_edge_identity(
  value : ProducerView,
  edge : Int,
) -> Result[@value.CheckedValue, ViewIssue] {
  match producer_view_edge_definition(value, edge) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match (value.graph.unwrap().edge_identity)(edge) {
    Some(identity) => Ok(identity)
    None => Err(InvalidRecord)
  }
}

///|
/// Original admitted key evidence on this exact read occurrence. Snapshot
/// reload must retain this evidence, not infer it from identity display bytes.
pub fn producer_view_node_key(
  value : ProducerView,
  node : Int,
  component : Int,
) -> Result[@value.CheckedValue, ViewIssue] {
  let index = match producer_view_node_definition(value, node) {
    Ok(index) => index
    Err(issue) => return Err(issue)
  }
  let profile = value.graph.unwrap()
  let definition = @carrier.graph_node_at(profile.definition, index).unwrap()
  if component < 0 ||
    component >= @carrier.graph_element_definition_key_count(definition) {
    return Err(InvalidField)
  }
  match (profile.node_key)(node, component) {
    Some(key) => Ok(key)
    None => Err(InvalidRecord)
  }
}

///|
pub fn producer_view_edge_key(
  value : ProducerView,
  edge : Int,
  component : Int,
) -> Result[@value.CheckedValue, ViewIssue] {
  let index = match producer_view_edge_definition(value, edge) {
    Ok(index) => index
    Err(issue) => return Err(issue)
  }
  let profile = value.graph.unwrap()
  let definition = @carrier.graph_edge_element(
    @carrier.graph_edge_at(profile.definition, index).unwrap(),
  )
  if component < 0 ||
    component >= @carrier.graph_element_definition_key_count(definition) {
    return Err(InvalidField)
  }
  match (profile.edge_key)(edge, component) {
    Some(key) => Ok(key)
    None => Err(InvalidRecord)
  }
}

///|
pub fn producer_view_edge_identity_index(
  value : ProducerView,
  identity : @value.CheckedValue,
) -> Result[Int?, ViewIssue] {
  match producer_view_graph_definition(value) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match (value.graph.unwrap().edge_identity_index)(identity) {
    Some(Some(index)) =>
      match producer_view_edge_definition(value, index) {
        Ok(_) => Ok(Some(index))
        Err(issue) => Err(issue)
      }
    Some(None) => Ok(None)
    None => Err(InvalidRecord)
  }
}

///|
pub fn producer_view_matches_read(
  value : ProducerView,
  read : ProducerReadReference,
) -> Bool {
  producer_read_reference_same(value.read, read) && producer_view_live(value)
}

///|
pub fn producer_view_read_reference(
  value : ProducerView,
) -> ProducerReadReference {
  value.read
}

///|
pub fn producer_view_node_count(value : ProducerView) -> Int? {
  if producer_view_live(value) && value.kind == @carrier.GraphKind {
    Some(value.nodes)
  } else {
    None
  }
}

///|
pub fn producer_view_edge_count(value : ProducerView) -> Int? {
  if producer_view_live(value) && value.kind == @carrier.GraphKind {
    Some(value.edges)
  } else {
    None
  }
}

///|
pub fn producer_view_record_count(value : ProducerView) -> Int? {
  if producer_view_live(value) &&
    (value.kind == @carrier.EventsKind || value.kind == @carrier.VectorsKind) {
    Some(value.records)
  } else {
    None
  }
}

///|
pub fn producer_view_node_identity(
  value : ProducerView,
  node : Int,
) -> Result[@value.CheckedValue, ViewIssue] {
  if !producer_view_live(value) {
    return Err(Unavailable)
  }
  if value.kind != @carrier.GraphKind {
    return Err(WrongCarrier)
  }
  if node < 0 || node >= value.nodes {
    return Err(InvalidRecord)
  }
  match (value.node_identity)(node) {
    Some(value) => Ok(value)
    None => Err(InvalidRecord)
  }
}

///|
pub fn producer_view_node_property(
  value : ProducerView,
  node : Int,
  property : Int,
) -> Result[@value.CheckedValue, ViewIssue] {
  if !producer_view_live(value) {
    return Err(Unavailable)
  }
  if value.kind != @carrier.GraphKind {
    return Err(WrongCarrier)
  }
  if node < 0 || node >= value.nodes {
    return Err(InvalidRecord)
  }
  let count = match value.graph {
    None => return Err(WrongCarrier)
    Some(profile) => {
      guard (profile.node_definition)(node) is Some(index) &&
        @carrier.graph_node_at(profile.definition, index) is Some(definition) else {
        return Err(InvalidRecord)
      }
      @carrier.field_count(
        @carrier.graph_element_definition_properties(definition),
      )
    }
  }
  if property < 0 || property >= count {
    return Err(InvalidField)
  }
  match (value.node_property)(node, property) {
    Some(value) => Ok(value)
    None => Err(InvalidField)
  }
}

///|
pub fn producer_view_node_index(
  value : ProducerView,
  identity : @value.CheckedValue,
) -> Result[Int?, ViewIssue] {
  if !producer_view_live(value) {
    return Err(Unavailable)
  }
  if value.kind != @carrier.GraphKind {
    return Err(WrongCarrier)
  }
  match (value.node_index)(identity) {
    Some(index) => Ok(index)
    None => Err(InvalidRecord)
  }
}

///|
pub fn producer_view_edge_endpoints(
  value : ProducerView,
  edge : Int,
) -> Result[(Int, Int), ViewIssue] {
  if !producer_view_live(value) {
    return Err(Unavailable)
  }
  if value.kind != @carrier.GraphKind {
    return Err(WrongCarrier)
  }
  if edge < 0 || edge >= value.edges {
    return Err(InvalidRecord)
  }
  match (value.edge_endpoints)(edge) {
    Some(value) => Ok(value)
    None => Err(InvalidRecord)
  }
}

///|
pub fn producer_view_edge_property(
  value : ProducerView,
  edge : Int,
  property : Int,
) -> Result[@value.CheckedValue, ViewIssue] {
  if !producer_view_live(value) {
    return Err(Unavailable)
  }
  if value.kind != @carrier.GraphKind {
    return Err(WrongCarrier)
  }
  if edge < 0 || edge >= value.edges {
    return Err(InvalidRecord)
  }
  let count = match value.graph {
    None => return Err(WrongCarrier)
    Some(profile) => {
      guard (profile.edge_definition)(edge) is Some(index) &&
        @carrier.graph_edge_at(profile.definition, index) is Some(definition) else {
        return Err(InvalidRecord)
      }
      @carrier.field_count(
        @carrier.graph_element_definition_properties(
          @carrier.graph_edge_element(definition),
        ),
      )
    }
  }
  if property < 0 || property >= count {
    return Err(InvalidField)
  }
  match (value.edge_property)(edge, property) {
    Some(value) => Ok(value)
    None => Err(InvalidField)
  }
}

///|
pub fn producer_view_record_field_count(
  value : ProducerView,
  record : Int,
) -> Result[Int, ViewIssue] {
  if !producer_view_live(value) {
    return Err(Unavailable)
  }
  if value.kind != @carrier.EventsKind && value.kind != @carrier.VectorsKind {
    return Err(WrongCarrier)
  }
  if record < 0 || record >= value.records {
    return Err(InvalidRecord)
  }
  match (value.record_fields)(record) {
    Some(count) if count >= 0 => Ok(count)
    _ => Err(InvalidRecord)
  }
}

///|
pub fn producer_view_record_field(
  value : ProducerView,
  record : Int,
  field : Int,
) -> Result[(@schema.FieldName, @value.CheckedValue), ViewIssue] {
  let count = match producer_view_record_field_count(value, record) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if field < 0 || field >= count {
    return Err(InvalidField)
  }
  match (value.record_field)(record, field) {
    Some(value) => Ok(value)
    None => Err(InvalidField)
  }
}
