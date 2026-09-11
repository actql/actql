///|
pub(all) struct Limits {
  max_nodes : Int
  max_depth : Int
  max_text_bytes : Int
}

///|
pub enum Issue {
  InvalidLimits
  BudgetExceeded
  NonCanonicalSource(@decode.Cursor)
  Decode(@decode.Issue)
  UnsupportedCarrier(String)
  InvalidMetadata
  InvalidName(String)
  DuplicateColumn(String)
  MissingColumn(String)
  Contract(@contract.AdmissionError)
  Schema(@schema.Issue)
  PrimaryKey(@evidence.Issue)
  InvalidDuplicates
  Order(@order.Issue)
  InvalidOrderField(String)
}

///|
struct Checked {
  source : @decode.Cursor
  carrier : @carrier.Carrier
  expected : Array[String]
  key : @evidence.KeyedRelation?
  order : Array[@order.Key]?
  used : Usage
}

///|
pub(all) struct Usage {
  nodes : Int
  text_bytes : Int
} derive(Eq, Debug)

///|
priv suberror Stop {
  Stop(Issue)
}

///|
fn[T] unwrap(result : Result[T, @decode.Issue]) -> T raise Stop {
  match result {
    Ok(v) => v
    Err(e) => raise Stop(Decode(e))
  }
}

///|
fn canonical_text(at : @decode.Cursor, text : String) -> Unit raise Stop {
  match @canonical.normalize_nfc_lf(text) {
    Ok(value) => if value != text { raise Stop(NonCanonicalSource(at)) }
    Err(_) => raise Stop(NonCanonicalSource(at))
  }
}

///|
// Bound the whole owned source, including annotations and all recursive types.
// Readers below reuse these bounds; they cannot reset a per-field input allowance.
fn preflight(source : @decode.Cursor, limits : Limits) -> Usage raise Stop {
  let mut nodes = limits.max_nodes
  let mut text = limits.max_text_bytes
  let pending = [(source, 0)]
  while pending.pop() is Some((at, depth)) {
    if nodes == 0 {
      raise Stop(BudgetExceeded)
    }
    nodes -= 1
    match @decode.view(at) {
      TextValue(v) => {
        text -= match @scalar.admit_utf8_length(v, text) {
          Ok(n) => n
          Err(_) => raise Stop(BudgetExceeded)
        }
        canonical_text(at, v)
      }
      NumberValue(n) => {
        let _ = unwrap(@decode.finite_number(at))
        if n == 0.0 && 1.0 / n < 0.0 {
          raise Stop(NonCanonicalSource(at))
        }
      }
      ArrayValue(items) => {
        if depth >= limits.max_depth || items.length() > nodes {
          raise Stop(BudgetExceeded)
        }
        for item in items {
          pending.push((item, depth + 1))
        }
      }
      ObjectValue(_) => {
        let count = @decode.object_length(at).unwrap()
        if depth >= limits.max_depth || count > nodes {
          raise Stop(BudgetExceeded)
        }
        for i in 0..<count {
          let (name, child) = @decode.field_at(at, i).unwrap()
          text -= match @scalar.admit_utf8_length(name, text) {
            Ok(n) => n
            Err(_) => raise Stop(BudgetExceeded)
          }
          canonical_text(child, name)
          pending.push((child, depth + 1))
        }
      }
      _ => ()
    }
  }
  { nodes: limits.max_nodes - nodes, text_bytes: limits.max_text_bytes - text, }
}

///|
fn names(source : @decode.Cursor) -> Array[String] raise Stop {
  let items = unwrap(@decode.elements(source))
  let seen : Map[String, Bool] = Map([])
  let result = []
  for at in items {
    let name = unwrap(@decode.text(at))
    if name.is_empty() {
      raise Stop(InvalidName(name))
    }
    if seen.contains(name) {
      raise Stop(DuplicateColumn(name))
    }
    seen[name] = true
    result.push(name)
  }
  result
}

///|
/// Read local Relation declarations only. This is not Host evidence admission,
/// duplicate normalization, SourceView resolution or execution authorization.
pub fn read(source : @decode.Cursor, limits : Limits) -> Result[Checked, Issue] {
  if limits.max_nodes < 0 || limits.max_depth < 0 || limits.max_text_bytes < 0 {
    return Err(InvalidLimits)
  }
  try {
    let used = preflight(source, limits)
    if @decode.view(source) is TextValue(name) {
      if name != "relation" {
        raise Stop(UnsupportedCarrier(name))
      }
      return Ok({
        source,
        carrier: @carrier.relation(@carrier.unknown_rows()),
        expected: [],
        key: None,
        order: None,
        used,
      })
    }
    let body = unwrap(
      @decode.closed_object(source, [
        "carrier", "expected_columns", "schema", "primary_key", "duplicates", "meta",
      ]),
    )
    let name = unwrap(@decode.text(unwrap(@decode.required(body, "carrier"))))
    if name != "relation" {
      raise Stop(UnsupportedCarrier(name))
    }
    if @decode.lookup(body, "meta") is Some(meta) {
      let _ = unwrap(@decode.open_object(meta))
      let count = @decode.object_length(meta).unwrap()
      if count == 0 {
        raise Stop(InvalidMetadata)
      }
      for i in 0..<count {
        let (key, _) = @decode.field_at(meta, i).unwrap()
        if key.has_prefix("actql_") {
          raise Stop(InvalidMetadata)
        }
      }
    }
    let expected = match @decode.lookup(body, "expected_columns") {
      None => []
      Some(v) => names(v)
    }
    let records = match @decode.lookup(body, "schema") {
      None => {
        // Empty expected_columns, like absence, proves no fields or types.
        let fields = expected.map(n => (@schema.Unqualified(n), None))
        match
          @carrier.rows(
            fields,
            field_set=Open,
            max_fields=limits.max_nodes,
            max_name_bytes=limits.max_text_bytes,
          ) {
          Ok(v) => v
          Err(e) => raise Stop(Schema(e))
        }
      }
      Some(schema) => {
        let _ = unwrap(@decode.open_object(schema))
        let fields = []
        for i in 0..<@decode.object_length(schema).unwrap() {
          let (name, at) = @decode.field_at(schema, i).unwrap()
          let c = match
            @contract.read_author(at, {
              max_nodes: limits.max_nodes,
              max_depth: limits.max_depth,
              max_text_bytes: limits.max_text_bytes,
            }) {
            Ok(v) => v
            Err(e) => raise Stop(Contract(e))
          }
          fields.push((@schema.Unqualified(name), c))
        }
        let schema = match
          @schema.from_fields(
            fields,
            max_fields=limits.max_nodes,
            max_name_bytes=limits.max_text_bytes,
          ) {
          Ok(v) => v
          Err(e) => raise Stop(Schema(e))
        }
        for name in expected {
          if @schema.lookup(schema, @schema.Unqualified(name)) is None {
            raise Stop(MissingColumn(name))
          }
        }
        @carrier.typed_rows(schema)
      }
    }
    let carrier = @carrier.relation(records)
    let key = match @decode.lookup(body, "primary_key") {
      None => None
      Some(at) =>
        Some(
          match
            @evidence.declare_primary_key(at, carrier, {
              max_fields: limits.max_nodes,
              max_name_bytes: limits.max_text_bytes,
            }) {
            Ok(v) => v
            Err(e) => raise Stop(PrimaryKey(e))
          },
        )
    }
    let order = match @decode.lookup(body, "duplicates") {
      None => None
      Some(at) =>
        if @decode.view(at) is TextValue("reject") {
          None
        } else {
          let outer = unwrap(@decode.closed_object(at, ["first_by_order"]))
          let inner = unwrap(
            @decode.closed_object(
              unwrap(@decode.required(outer, "first_by_order")),
              ["order_by"],
            ),
          )
          let terms = unwrap(
            @decode.elements(unwrap(@decode.required(inner, "order_by"))),
          )
          if terms.is_empty() {
            raise Stop(InvalidDuplicates)
          }
          let keys = []
          for at in terms {
            let term = match @order.read(at) {
              Ok(v) => v
              Err(e) => raise Stop(Order(e))
            }
            match @carrier.lookup(records, @schema.Unqualified(term.field)) {
              Absent => raise Stop(MissingColumn(term.field))
              Present(f) =>
                if f.contract is Some(c) && !@order.author_orderable(c) {
                  raise Stop(InvalidOrderField(term.field))
                }
              Unknown => ()
            }
            keys.push(term)
          }
          Some(keys)
        }
    }
    Ok({ source, carrier, expected, key, order, used, })
  } catch {
    Stop(e) => Err(e)
  }
}

///|
pub fn source(v : Checked) -> @decode.Cursor {
  v.source
}

///|
pub fn usage(v : Checked) -> Usage {
  v.used
}

///|
pub fn carrier(v : Checked) -> @carrier.Carrier {
  v.carrier
}

///|
pub fn expected_columns(v : Checked) -> Array[String] {
  v.expected.copy()
}

///|
pub fn primary_key(v : Checked) -> @evidence.KeyedRelation? {
  v.key
}

///|
/// None denotes reject. Some retains authored terms, not proof of total order.
pub fn first_by_order(v : Checked) -> Array[@order.Key]? {
  v.order.map(xs => xs.copy())
}
