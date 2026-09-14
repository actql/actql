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
  DuplicateOutput(String)
  InputCollision(String)
  NotConstructible(String)
  InvalidOrder
  NotAuthorOrderable(String)
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
  output : String
  input : @schema.FieldName
  source : @decode.Cursor
}

///|
pub struct OrderTerm {
  field : @schema.FieldName
  direction : @order.Direction
  nulls : @order.NullPlacement
  explicit_nulls : Bool
  source : @decode.Cursor
}

///|
pub(all) enum Guard {
  Literal(Int64)
  Parameter(String)
} derive(Eq, Debug)

///|
pub(all) enum Obligation {
  ResolveTotalOrder
  ResolveItemLimit
  ResolveNestedEnvelope
  ValidateOutputsBeforeConsumers
  PropagatePolicyAndCompleteness
  BindGuard(String)
} derive(Eq, Debug)

///|
struct CheckedNest {
  source : @decode.Cursor
  parent : @schema.Schema
  child : @schema.Schema
  output : @schema.Schema
  with_name : String
  into : String
  keys : Array[KeyPair]
  projection : Array[Projection]
  order : Array[OrderTerm]?
  item_limit : Guard?
  pending : Array[Obligation]
  usage : Usage
}

///|
pub fn source(v : CheckedNest) -> @decode.Cursor {
  v.source
}

///|
pub fn input_schema(v : CheckedNest, side : @schema.Side) -> @schema.Schema {
  if side == Left {
    v.parent
  } else {
    v.child
  }
}

///|
pub fn output_schema(v : CheckedNest) -> @schema.Schema {
  v.output
}

///|
pub fn with_name(v : CheckedNest) -> String {
  v.with_name
}

///|
pub fn into(v : CheckedNest) -> String {
  v.into
}

///|
pub fn keys(v : CheckedNest) -> Array[KeyPair] {
  v.keys.copy()
}

///|
/// O(1), retaining repeated authored correlation pairs.
pub fn key_count(v : CheckedNest) -> Int {
  v.keys.length()
}

///|
/// O(1); invalid indices return None. Does not copy the correlation array.
pub fn key_at(v : CheckedNest, index : Int) -> KeyPair? {
  v.keys.get(index)
}

///|
pub fn projection(v : CheckedNest) -> Array[Projection] {
  v.projection.copy()
}

///|
pub fn order(v : CheckedNest) -> Array[OrderTerm]? {
  v.order.map(xs => xs.copy())
}

///|
/// None denotes omitted order, not an empty authored order.
pub fn order_count(v : CheckedNest) -> Int? {
  v.order.map(xs => xs.length())
}

///|
pub fn order_at(v : CheckedNest, index : Int) -> OrderTerm? {
  v.order.bind(xs => xs.get(index))
}

///|
pub fn projection_count(v : CheckedNest) -> Int {
  v.projection.length()
}

///|
pub fn projection_at(v : CheckedNest, index : Int) -> Projection? {
  v.projection.get(index)
}

///|
pub fn item_guard(v : CheckedNest) -> Guard? {
  v.item_limit
}

///|
pub fn pending_validations(v : CheckedNest) -> Array[Obligation] {
  v.pending.copy()
}

///|
/// O(1), without materializing the obligation array.
pub fn pending_validation_count(v : CheckedNest) -> Int {
  v.pending.length()
}

///|
/// O(1); invalid indices return None. Retains authored obligation order.
pub fn pending_validation_at(v : CheckedNest, index : Int) -> Obligation? {
  v.pending.get(index)
}

///|
pub fn usage(v : CheckedNest) -> Usage {
  v.usage
}
