///|
/// An admitted checked contract. Construction is private; views are read-only.
pub struct Contract {
  nullable : Bool
  shape : Shape
}

///|
pub enum Shape {
  Text(TextLimits)
  Number
  Boolean
  Timestamp
  Date
  Json
  Decimal(precision~ : Int, scale~ : Int)
  Array(Contract, max_items~ : Int64?)
  Object(Fields)
  Vector(dimensions~ : Double)
  ResourceRef(resource_kind~ : String)
  ArtifactRef(media_type~ : String?)
}

///|
pub struct TextLimits {
  min_length : Int64?
  max_codepoints : Int64?
  max_utf8_bytes : Int64?
} derive(Eq, Debug)

///|
pub struct Field {
  name : String
  contract : Contract
}

///|
struct Fields {
  values : Array[Field]
}

///|
pub fn fields(value : Fields) -> Array[Field] {
  value.values.copy()
}

///|
pub(all) struct Limits {
  max_nodes : Int
  max_depth : Int
  max_text_bytes : Int
} derive(Eq, Debug)

///|
pub(all) enum ContractIssue {
  UnknownType(String)
  InvalidFieldName(String)
  NonCanonicalText
  InvalidUnicode
  InvalidFixedField
  InvalidRange
  BudgetExceeded
} derive(Eq, Debug)

///|
pub(all) enum AdmissionError {
  InvalidLimits
  Decode(@decode.Issue)
  ContractIssue(
    ContractIssue,
    path~ : Array[@decode.PathSegment],
    span~ : @span.Span
  )
} derive(Eq, Debug)

///|
priv suberror Abort {
  Abort(AdmissionError)
}

///|
pub(all) suberror RelationError {
  InvalidRelationLimit
  RelationLimit
} derive(Eq, Debug)
