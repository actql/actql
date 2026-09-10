///|
pub(all) enum Kind {
  Inner
  Left
  Full
  Semi
  Anti
} derive(Eq, Debug)

///|
pub(all) enum NullKey {
  NoMatch
  Fail
} derive(Eq, Debug)

///|
pub(all) enum Cardinality {
  OneToOne
  ManyToOne
  OneToMany
} derive(Eq, Debug)

///|
pub(all) enum Guard {
  Literal(Int64)
  Parameter(String)
} derive(Eq, Debug)

///|
pub(all) enum Obligation {
  ResolveCardinality
  ResolveOutputLimit
  PreserveRowOrder
  StableIdentity(@schema.Side)
  ValidateCardinality(Cardinality)
  RejectNullKeys
  BindGuard(String)
} derive(Eq, Debug)

///|
pub(all) struct Limits {
  max_work : Int
  max_text_bytes : Int
  max_nodes : Int
  max_depth : Int
} derive(Eq, Debug)

///|
pub(all) struct Usage {
  work : Int
  text_bytes : Int
  nodes : Int
} derive(Eq, Debug)

///|
pub(all) enum IssueKind {
  InvalidLimits
  BudgetExceeded
  InvalidBody
  EmptyBody
  InvalidName(String)
  UnknownField(@schema.Side, String)
  IncomparableKeys(String, String)
  QualifiedInput(@schema.Side)
  InvalidProjection(String)
  InvalidGuard
  UnknownParameter(String)
} derive(Eq, Debug)

///|
pub struct Issue {
  kind : IssueKind
  source : @decode.Cursor
  path : Array[@decode.PathSegment]
  span : @span.Span
}

///|
pub struct KeyPair {
  left : @schema.FieldName
  right : @schema.FieldName
  source : @decode.Cursor
}

///|
pub struct Projection {
  output : @schema.FieldName
  input : @schema.FieldName
  source : @decode.Cursor
}

///|
struct CheckedJoin {
  source : @decode.Cursor
  left : @schema.Schema
  right : @schema.Schema
  output : @schema.Schema
  kind : Kind
  null_key : NullKey
  keys : Array[KeyPair]
  projection : Array[Projection]?
  assertion : Cardinality?
  output_guard : Guard?
  pending : Array[Obligation]
  usage : Usage
}

///|
pub fn source(v : CheckedJoin) -> @decode.Cursor {
  v.source
}

///|
pub fn input_schema(v : CheckedJoin, side : @schema.Side) -> @schema.Schema {
  if side == Left {
    v.left
  } else {
    v.right
  }
}

///|
pub fn output_schema(v : CheckedJoin) -> @schema.Schema {
  v.output
}

///|
pub fn kind(v : CheckedJoin) -> Kind {
  v.kind
}

///|
pub fn null_key(v : CheckedJoin) -> NullKey {
  v.null_key
}

///|
pub fn keys(v : CheckedJoin) -> Array[KeyPair] {
  v.keys.copy()
}

///|
pub fn projection(v : CheckedJoin) -> Array[Projection]? {
  v.projection.map(p => p.copy())
}

///|
pub fn assertion(v : CheckedJoin) -> Cardinality? {
  v.assertion
}

///|
pub fn output_guard(v : CheckedJoin) -> Guard? {
  v.output_guard
}

///|
pub fn pending_validations(v : CheckedJoin) -> Array[Obligation] {
  v.pending.copy()
}

///|
pub fn usage(v : CheckedJoin) -> Usage {
  v.usage
}

///|
priv suberror Stop {
  Stop(Issue)
}

///|
priv struct Budget {
  limits : Limits
  mut work : Int
  mut text : Int
  mut nodes : Int
}

///|
fn[T] fail(source : @decode.Cursor, kind : IssueKind) -> T raise Stop {
  raise Stop({
    source,
    kind,
    path: @decode.cursor_path(source),
    span: @decode.cursor_span(source),
  })
}

///|
fn[T] decoded(
  value : Result[T, @decode.Issue],
  source : @decode.Cursor,
) -> T raise Stop {
  match value {
    Ok(v) => v
    Err(_) => fail(source, InvalidBody)
  }
}

///|
fn spend(b : Budget, source : @decode.Cursor, n? : Int = 1) -> Unit raise Stop {
  if n < 0 || n > b.work {
    fail(source, BudgetExceeded)
  }
  b.work -= n
}

///|
fn charge(
  b : Budget,
  source : @decode.Cursor,
  name : String,
) -> Unit raise Stop {
  match @scalar.admit_utf8_length(name, b.text) {
    Ok(n) => b.text -= n
    Err(_) => fail(source, BudgetExceeded)
  }
}

///|
fn field_name(
  b : Budget,
  source : @decode.Cursor,
  name : String,
) -> Unit raise Stop {
  spend(b, source)
  let bytes = b.text
  charge(b, source, name)
  match
    @contract.object_contract(
      [(name, @contract.primitive(NumberType, nullable=false))],
      nullable=false,
      max_fields=1,
      max_name_bytes=bytes,
    ) {
    Ok(_) => ()
    Err(_) => fail(source, InvalidName(name))
  }
}

///|
fn dataflow_name(source : @decode.Cursor) -> String raise Stop {
  let name = decoded(@decode.text(source), source)
  if name == "" || @canonical.normalize_nfc_lf(name) != Ok(name) {
    fail(source, InvalidName(name))
  }
  name
}

///|
fn source_preflight(b : Budget, root : @decode.Cursor) -> Unit raise Stop {
  let work = [(root, 0)]
  while work.pop() is Some((source, depth)) {
    spend(b, source)
    if b.nodes == 0 {
      fail(source, BudgetExceeded)
    }
    b.nodes -= 1
    match @decode.view(source) {
      TextValue(v) => charge(b, source, v)
      ArrayValue(items) => {
        if depth >= b.limits.max_depth {
          fail(source, BudgetExceeded)
        }
        spend(b, source, n=items.length())
        for item in items {
          work.push((item, depth + 1))
        }
      }
      ObjectValue(obj) => {
        if depth >= b.limits.max_depth {
          fail(source, BudgetExceeded)
        }
        let names = @decode.object_field_names(source).unwrap()
        spend(b, source, n=names.length())
        for name in names {
          charge(b, source, name)
          work.push((@decode.lookup(obj, name).unwrap(), depth + 1))
        }
      }
      _ => ()
    }
  }
}

///|
fn contract_preflight(
  b : Budget,
  source : @decode.Cursor,
  root : @contract.Contract,
  depth? : Int = 0,
) -> Unit raise Stop {
  let work = [(root, depth)]
  while work.pop() is Some((c, depth)) {
    spend(b, source)
    if depth > b.limits.max_depth {
      fail(source, BudgetExceeded)
    }
    match c.shape {
      @contract.Array(item, ..) => work.push((item, depth + 1))
      @contract.Object(fields) => {
        let n = @contract.field_count(fields)
        spend(b, source, n~)
        for i in 0..<n {
          let f = @contract.field_at(fields, i).unwrap()
          charge(b, source, f.name)
          work.push((f.contract, depth + 1))
        }
      }
      @contract.ResourceRef(resource_kind~) => charge(b, source, resource_kind)
      @contract.ArtifactRef(media_type=Some(media)) => charge(b, source, media)
      _ => ()
    }
  }
}
