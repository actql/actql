///|
/// Read-only access to one exact managed Carrier producer occurrence. The
/// view preserves Carrier structure without exposing a family storage handle.
struct ProducerView {
  read : ProducerReadReference
  kind : @carrier.Kind
  nodes : Int
  edges : Int
  records : Int
  node_properties : Int
  edge_properties : Int
  node_identity : (Int) -> @value.CheckedValue?
  node_property : (Int, Int) -> @value.CheckedValue?
  edge_endpoints : (Int) -> (Int, Int)?
  edge_label : (Int) -> @value.CheckedValue??
  edge_property : (Int, Int) -> @value.CheckedValue?
  record_fields : (Int) -> Int?
  record_field : (Int, Int) -> (@schema.FieldName, @value.CheckedValue)?
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
pub fn prepare_graph_producer_view(
  read : ProducerReadReference,
  nodes : Int,
  edges : Int,
  node_properties : Int,
  edge_properties : Int,
  node_identity : (Int) -> @value.CheckedValue?,
  node_property : (Int, Int) -> @value.CheckedValue?,
  edge_endpoints : (Int) -> (Int, Int)?,
  edge_label : (Int) -> @value.CheckedValue??,
  edge_property : (Int, Int) -> @value.CheckedValue?,
) -> Result[ProducerView, ViewIssue] {
  if producer_reference_kind(read) != @carrier.GraphKind {
    return Err(WrongCarrier)
  }
  if nodes < 0 || edges < 0 || node_properties < 0 || edge_properties < 0 {
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
    node_properties,
    edge_properties,
    node_identity,
    node_property,
    edge_endpoints,
    edge_label,
    edge_property,
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
    node_properties: 0,
    edge_properties: 0,
    node_identity: _ => None,
    node_property: (_, _) => None,
    edge_endpoints: _ => None,
    edge_label: _ => None,
    edge_property: (_, _) => None,
    record_fields,
    record_field,
  })
}

///|
pub fn producer_view_kind(value : ProducerView) -> @carrier.Kind {
  value.kind
}

///|
pub fn producer_view_matches_read(
  value : ProducerView,
  read : ProducerReadReference,
) -> Bool {
  producer_read_reference_same(value.read, read) && producer_view_live(value)
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
  if property < 0 || property >= value.node_properties {
    return Err(InvalidField)
  }
  match (value.node_property)(node, property) {
    Some(value) => Ok(value)
    None => Err(InvalidField)
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
pub fn producer_view_edge_label(
  value : ProducerView,
  edge : Int,
) -> Result[@value.CheckedValue?, ViewIssue] {
  if !producer_view_live(value) {
    return Err(Unavailable)
  }
  if value.kind != @carrier.GraphKind {
    return Err(WrongCarrier)
  }
  if edge < 0 || edge >= value.edges {
    return Err(InvalidRecord)
  }
  match (value.edge_label)(edge) {
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
  if property < 0 || property >= value.edge_properties {
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
