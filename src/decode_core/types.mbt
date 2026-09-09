///|
pub(all) enum IssueKind {
  InvalidLimits
  MissingField
  WrongType
  UnexpectedNull
  UnknownField
  DuplicateField
  OutOfRange
  InvalidDecimal
  InvalidUnicode
  BudgetExceeded
} derive(Eq, Debug)

///|
pub type PathSegment = @source.PathSegment

///|
/// A detached structural path and supplied source span, not a public diagnostic.
pub(all) struct Issue {
  kind : IssueKind
  path : Array[PathSegment]
  span : @span.Span
} derive(Eq, Debug)

///|
pub(all) struct Limits {
  max_nodes : Int
  max_depth : Int
  max_string_bytes : Int
  max_total_string_bytes : Int
} derive(Eq, Debug)

///|
pub(all) enum Presence[T] {
  Missing
  ExplicitNull
  Present(T)
}

///|
/// An immutable-by-ownership tree handle. No source arrays escape admission.
struct Cursor {
  tree : Array[OwnedNode]
  index : Int
}

///|
struct ObjectView {
  cursor : Cursor
  fields : Map[String, Int]
}

///|
pub(all) enum ValueView {
  NullValue
  BoolValue(Bool)
  NumberValue(Double)
  TextValue(String)
  ArrayValue(Array[Cursor])
  ObjectValue(ObjectView)
}

///|
priv enum Edge {
  Root
  Element(Int)
  Field(String, @span.Span)
}

///|
priv enum OwnedValue {
  Null
  Bool(Bool)
  Number(Double)
  Text(String)
  ArrayValue(Array[Int])
  ObjectValue(Array[OwnedField])
}

///|
priv struct OwnedField {
  key : String
  span : @span.Span
  index : Int
}

///|
priv struct OwnedNode {
  value : OwnedValue
  span : @span.Span
  parent : Int
  edge : Edge
}

///|
/// Continuations retain only the active input ancestry, not all pending siblings.
priv enum Work {
  Visit(@source.Node, Int, Edge, Int)
  ArrayNext(Array[@source.Node], Int, Int, Int)
  ObjectNext(Array[@source.Field], Int, Int, Int, @shape.KeyAdmission)
}
