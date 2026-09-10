///|
pub(all) enum Kind {
  RelationKind
  GraphKind
  EventsKind
  VectorsKind
} derive(Eq, Debug)

///|
pub(all) enum Issue {
  InvalidLimits
  LimitExceeded
  UnknownRole(@row.FieldName)
  InvalidRole(@row.FieldName)
  DuplicateRole(@row.FieldName)
  InvalidIdentity
  InvalidProperties
  InvalidLabel(String)
  DuplicateLabel(String)
} derive(Eq, Debug)

///|
struct Graph {
  identity : @value.Contract
  node_properties : Knowledge
  edge_properties : Knowledge
  // None means no closed label domain, not proof that a label role exists.
  labels : Array[String]?
}

///|
pub(all) enum ClockEncoding {
  Milliseconds
  UtcTimestamp
} derive(Eq, Debug)

///|
pub struct Events {
  records : Knowledge
  identity : Field
  time : Field
  clock_encoding : ClockEncoding
}

///|
struct Vectors {
  records : Knowledge
  identities : Array[Field]
  components : Field
  dimensions : Double
}

///|
/// Structural constraints only. These do not assert admitted data, unique
/// identities, stable order, policy, profile availability or resource bounds.
pub enum Carrier {
  Relation(Knowledge)
  GraphValue(Graph)
  EventValue(Events)
  VectorValue(Vectors)
  Opaque(Kind)
}

///|
pub fn kind(carrier : Carrier) -> Kind {
  match carrier {
    Relation(_) => RelationKind
    GraphValue(_) => GraphKind
    EventValue(_) => EventsKind
    VectorValue(_) => VectorsKind
    Opaque(kind) => kind
  }
}

///|
pub fn relation(rows : Knowledge) -> Carrier {
  Relation(rows)
}

///|
pub fn unknown_carrier(kind : Kind) -> Carrier {
  if kind == RelationKind {
    Relation(unknown_rows())
  } else {
    Opaque(kind)
  }
}

///|
pub fn relation_rows(carrier : Carrier) -> Knowledge? {
  match carrier {
    Relation(rows) => Some(rows)
    _ => None
  }
}

///|
fn identity_domain(contract : @value.Contract) -> Bool {
  !contract.nullable && @value.key_comparable(contract, contract)
}

///|
fn typed_role(
  records : Knowledge,
  name : @row.FieldName,
) -> Result[Field, Issue] {
  match lookup(records, name) {
    Present(field) =>
      if field.contract is Some(_) {
        Ok(field)
      } else {
        Err(UnknownRole(name))
      }
    _ => Err(UnknownRole(name))
  }
}

///|
/// Labels are a closed domain only when supplied. This constructor does not
/// establish actual graph membership, edge endpoints or observed uniqueness.
pub fn graph(
  identity : @value.Contract,
  node_properties : Knowledge,
  edge_properties : Knowledge,
  labels~ : Array[String]?,
  max_labels~ : Int,
  max_label_bytes~ : Int,
) -> Result[Carrier, Issue] {
  if max_labels < 0 || max_label_bytes < 0 {
    return Err(InvalidLimits)
  }
  if !identity_domain(identity) {
    return Err(InvalidIdentity)
  }
  if node_properties.has_qualified_fields ||
    edge_properties.has_qualified_fields {
    return Err(InvalidProperties)
  }
  let admitted = match labels {
    None => None
    Some(input) => {
      if input.length() > max_labels {
        return Err(LimitExceeded)
      }
      let mut remaining = max_label_bytes
      let seen : Map[String, Bool] = Map([])
      let output : Array[String] = []
      for label in input {
        let size = match @scalar.admit_utf8_length(label, remaining) {
          Ok(size) => size
          Err(@scalar.MalformedUtf16(_)) => return Err(InvalidLabel(label))
          Err(_) => return Err(LimitExceeded)
        }
        remaining -= size
        if @canonical.normalize_nfc_lf(label) != Ok(label) {
          return Err(InvalidLabel(label))
        }
        if seen.contains(label) {
          return Err(DuplicateLabel(label))
        }
        seen[label] = true
        output.push(label)
      }
      output.sort_by(@canonical.compare_utf16)
      Some(output)
    }
  }
  Ok(
    GraphValue({ identity, node_properties, edge_properties, labels: admitted, }),
  )
}

///|
pub fn graph_labels(graph : Graph) -> Array[String]? {
  graph.labels.map(labels => labels.copy())
}

///|
pub fn graph_label_count(graph : Graph) -> Int? {
  graph.labels.map(labels => labels.length())
}

///|
pub fn graph_label_at(graph : Graph, index : Int) -> String? {
  match graph.labels {
    Some(labels) =>
      if index < 0 || index >= labels.length() {
        None
      } else {
        Some(labels[index])
      }
    None => None
  }
}

///|
/// Retain the authored clock source and its required interpretation. Timestamp
/// encoding requires UTC-millisecond conversion at execution; this constructor
/// validates contracts only and never claims converted or admitted data.
pub fn events(
  records : Knowledge,
  id~ : @row.FieldName,
  time~ : @row.FieldName,
) -> Result[Carrier, Issue] {
  let identity = match typed_role(records, id) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  if !identity_domain(identity.contract.unwrap()) {
    return Err(InvalidRole(id))
  }
  let clock = match typed_role(records, time) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let contract = clock.contract.unwrap()
  if contract.nullable {
    return Err(InvalidRole(time))
  }
  let clock_encoding = match contract.shape {
    @value.Number => Milliseconds
    @value.Timestamp => UtcTimestamp
    _ => return Err(InvalidRole(time))
  }
  Ok(EventValue({ records, identity, time: clock, clock_encoding, }))
}

///|
/// Multiple identity fields describe an ordered semantic tuple, not a fabricated
/// scalar ID or proof that actual records are unique.
pub fn vectors(
  records : Knowledge,
  ids~ : Array[@row.FieldName],
  components~ : @row.FieldName,
  max_identity_fields~ : Int,
) -> Result[Carrier, Issue] {
  if max_identity_fields < 0 {
    return Err(InvalidLimits)
  }
  if ids.is_empty() {
    return Err(InvalidIdentity)
  }
  if ids.length() > max_identity_fields {
    return Err(LimitExceeded)
  }
  let identities : Array[Field] = []
  let seen : Map[String, Bool] = Map([])
  for name in ids {
    let spelling = @row.reference_name(name)
    if seen.contains(spelling) || name == components {
      return Err(DuplicateRole(name))
    }
    seen[spelling] = true
    let field = match typed_role(records, name) {
      Ok(v) => v
      Err(e) => return Err(e)
    }
    if !identity_domain(field.contract.unwrap()) {
      return Err(InvalidRole(name))
    }
    identities.push(field)
  }
  let vector = match typed_role(records, components) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let contract = vector.contract.unwrap()
  let dimensions = match contract.shape {
    @value.Vector(dimensions~) if !contract.nullable => dimensions
    _ => return Err(InvalidRole(components))
  }
  Ok(VectorValue({ records, identities, components: vector, dimensions, }))
}

///|
pub fn vector_identities(vector : Vectors) -> Array[Field] {
  vector.identities.copy()
}

///|
pub fn graph_identity(graph : Graph) -> @value.Contract {
  graph.identity
}

///|
pub fn graph_node_properties(graph : Graph) -> Knowledge {
  graph.node_properties
}

///|
pub fn graph_edge_properties(graph : Graph) -> Knowledge {
  graph.edge_properties
}

///|
pub fn vector_records(vector : Vectors) -> Knowledge {
  vector.records
}

///|
pub fn vector_components(vector : Vectors) -> Field {
  vector.components
}

///|
pub fn vector_dimensions(vector : Vectors) -> Double {
  vector.dimensions
}
