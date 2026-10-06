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
  UnsupportedGraphProfile
} derive(Eq, Debug)

///|
struct Graph {
  graph : GraphDefinition
  identity : @value.Contract
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
      if field.presence != @row.Required {
        Err(InvalidRole(name))
      } else if field.contract is Some(_) {
        Ok(field)
      } else {
        Err(UnknownRole(name))
      }
    _ => Err(UnknownRole(name))
  }
}

///|
/// Rewrap an already admitted opaque Graph without copying its domains.
pub fn graph_carrier(graph : Graph) -> Carrier {
  GraphValue(graph)
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
pub fn event_records(events : Events) -> Knowledge {
  events.records
}

///|
pub fn event_identity(events : Events) -> Field {
  events.identity
}

///|
pub fn event_time(events : Events) -> Field {
  events.time
}

///|
pub fn event_clock_encoding(events : Events) -> ClockEncoding {
  events.clock_encoding
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
pub fn vector_identity_count(vector : Vectors) -> Int {
  vector.identities.length()
}

///|
pub fn vector_identity_at(vector : Vectors, index : Int) -> Field? {
  vector.identities.get(index)
}

///|
pub fn graph_identity(graph : Graph) -> @value.Contract {
  graph.identity
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
