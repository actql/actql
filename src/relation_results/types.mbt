///|
pub(all) struct Limits {
  max_results : Int
  max_work : Int
  max_nodes : Int
  max_text_bytes : Int
  max_depth : Int
} derive(Eq, Debug)

///|
pub(all) struct Usage {
  work : Int
  nodes : Int
  text_bytes : Int
} derive(Eq, Debug)

///|
pub type Direction = @order.Direction

///|
pub type NullPlacement = @order.NullPlacement

///|
pub struct OrderKey {
  field : String
  direction : Direction
  nulls : NullPlacement
  explicit_nulls : Bool
  source : @decode.Cursor
}

///|
/// This is an obligation, never an assertion that an order has been proved.
pub(all) enum Obligation {
  TotalDeterministicOrder
} derive(Eq, Debug)

///|
pub(all) enum IssueKind {
  UnresolvedOrder
  InvalidLimits
  BudgetExceeded
  InvalidBody
  InvalidName(String)
  UnknownSource(String)
  WrongCarrier(@carrier.Kind)
  IncompleteSchema
  UnknownField(String)
  PresenceRequired(String)
  DuplicateField(String)
  InvalidOrder
  NotAuthorOrderable(String)
  InvalidMetadata
  ReservedMetadataKey(String)
  Decode(@decode.IssueKind)
} derive(Eq, Debug)

///|
pub struct Issue {
  kind : IssueKind
  source : @decode.Cursor
  path : Array[@decode.PathSegment]
  span : @span.Span
}

///|
struct ResultDefinition {
  name : String
  source : @decode.Cursor
  target : @pipeline.Target
  schema : @schema.Schema
  fields : Array[String]
  order : Array[OrderKey]?
  metadata : @decode.Cursor?
}

///|
struct CheckedResults {
  pipeline : @pipeline.CheckedPipeline
  source : @decode.Cursor
  definitions : Array[ResultDefinition]
  names : Map[String, Int]
  usage : Usage
}

///|
pub fn pipeline(value : CheckedResults) -> @pipeline.CheckedPipeline {
  value.pipeline
}

///|
pub fn source(value : CheckedResults) -> @decode.Cursor {
  value.source
}

///|
pub fn count(value : CheckedResults) -> Int {
  value.definitions.length()
}

///|
pub fn result_at(value : CheckedResults, index : Int) -> ResultDefinition? {
  if index < 0 || index >= value.definitions.length() {
    None
  } else {
    Some(value.definitions[index])
  }
}

///|
pub fn lookup(value : CheckedResults, name : String) -> ResultDefinition? {
  value.names.get(name).map(i => value.definitions[i])
}

///|
pub fn usage(value : CheckedResults) -> Usage {
  value.usage
}

///|
pub fn name(value : ResultDefinition) -> String {
  value.name
}

///|
pub fn definition_source(value : ResultDefinition) -> @decode.Cursor {
  value.source
}

///|
pub fn target(value : ResultDefinition) -> @pipeline.Target {
  value.target
}

///|
pub fn output_schema(value : ResultDefinition) -> @schema.Schema {
  value.schema
}

///|
pub fn fields(value : ResultDefinition) -> Array[String] {
  value.fields.copy()
}

///|
pub fn order_by(value : ResultDefinition) -> Array[OrderKey]? {
  value.order.map(xs => xs.copy())
}

///|
pub fn metadata(value : ResultDefinition) -> @decode.Cursor? {
  value.metadata
}

///|
pub fn pending_validations(_value : ResultDefinition) -> Array[Obligation] {
  [TotalDeterministicOrder]
}

///|
priv suberror Stop {
  Stop(Issue)
}

///|
priv struct Budget {
  limits : Limits
  mut work : Int
  mut nodes : Int
  mut text : Int
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
    Err(e) =>
      raise Stop({
        source,
        kind: Decode(e.kind),
        path: e.path.copy(),
        span: e.span,
      })
  }
}

///|
fn spend(b : Budget, source : @decode.Cursor, amount : Int) -> Unit raise Stop {
  if amount < 0 || amount > b.work {
    fail(source, BudgetExceeded)
  }
  b.work -= amount
}

///|
fn charge(
  b : Budget,
  source : @decode.Cursor,
  value : String,
) -> Unit raise Stop {
  match @scalar.admit_utf8_length(value, b.text) {
    Ok(n) => b.text -= n
    Err(_) => fail(source, BudgetExceeded)
  }
}

///|
fn valid_name(source : @decode.Cursor, value : String) -> Unit raise Stop {
  if value == "" || @canonical.normalize_nfc_lf(value) != Ok(value) {
    fail(source, InvalidName(value))
  }
}
