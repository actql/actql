///|
pub struct Declaration {
  name : String
  parameter_type : @contract.ParameterType
  metadata : @decode.Cursor?
  priv source : @decode.Cursor
  priv default_cursor : @decode.Cursor?
  priv default_value : @value.CheckedValue?
}

///|
struct Declarations {
  entries : Array[Declaration]
  usage : (Int, Int)
}

///|
/// Source preflight nodes and UTF-8 text bytes (keys, defaults and metadata
/// included). This is admission accounting, not CPU work or serialized size.
pub fn declaration_usage(value : Declarations) -> (Int, Int) {
  value.usage
}

///|
pub fn declarations(value : Declarations) -> Array[Declaration] {
  value.entries.copy()
}

///|
pub fn declaration_count(value : Declarations) -> Int {
  value.entries.length()
}

///|
pub fn declaration_at(value : Declarations, index : Int) -> Declaration? {
  if index < 0 || index >= value.entries.length() {
    None
  } else {
    Some(value.entries[index])
  }
}

///|
pub fn has_default(value : Declaration) -> Bool {
  value.default_value is Some(_)
}

///|
pub fn declaration_source(value : Declaration) -> @decode.Cursor {
  value.source
}

///|
pub enum Origin {
  Supplied
  Default
} derive(Eq, Debug)

///|
pub struct BoundParameter {
  name : String
  value : @value.CheckedValue
  origin : Origin
  priv parameter_type : @contract.ParameterType
}

///|
struct BoundValues {
  declarations : Declarations
  entries : Array[BoundParameter]
  usage : (Int, Int)
}

///|
/// The declaration type retained by this admitted parameter value.
pub fn bound_parameter_type(value : BoundParameter) -> @contract.ParameterType {
  value.parameter_type
}

///|
/// Exact declaration owner used to admit these bindings.
pub fn bound_declarations(value : BoundValues) -> Declarations {
  value.declarations
}

///|
pub fn bound_value_count(value : BoundValues) -> Int {
  value.entries.length()
}

///|
pub fn bound_value_at(value : BoundValues, index : Int) -> BoundParameter? {
  value.entries.get(index)
}

///|
pub fn bound_values(value : BoundValues) -> Array[BoundParameter] {
  value.entries.copy()
}

///|
pub enum BindingResult {
  Ready(BoundValues)
  NeedsBindings(MissingNames)
}

///|
struct MissingNames {
  declarations : Declarations
  entries : Array[Declaration]
  usage : (Int, Int)
}

///|
/// Selected-value preflight nodes and UTF-8 text bytes, including selected
/// parameter names. Defaults are charged too; absent values are not. The
/// supplied outer map is not a value node. NeedsBindings retains spent usage
/// without exposing a partially ready value set.
pub fn binding_usage(value : BindingResult) -> (Int, Int) {
  match value {
    Ready(values) => values.usage
    NeedsBindings(missing) => missing.usage
  }
}

///|
pub fn missing_names(value : MissingNames) -> Array[String] {
  value.entries.map(entry => entry.name)
}

///|
/// Read retained missing declarations without copying the inventory or
/// re-admitting their type contracts. These are not partially bound values.
pub fn missing_count(value : MissingNames) -> Int {
  value.entries.length()
}

///|
pub fn missing_at(value : MissingNames, index : Int) -> Declaration? {
  value.entries.get(index)
}

///|
pub fn missing_declaration_owner(value : MissingNames) -> Declarations {
  value.declarations
}

///|
pub(all) struct DeclarationLimits {
  max_parameters : Int
  max_nodes : Int
  max_depth : Int
  max_text_bytes : Int
} derive(Eq, Debug)

///|
pub(all) enum IssueKind {
  InvalidLimits
  EmptyDeclarations
  InvalidName
  ParameterLimit
  InvalidMetadata
  ReservedMetadataKey
  InvalidUnicode
  NonCanonicalText
  InvalidNumber
  NumericConstraint
  DurationConstraint
  LengthConstraint
  BudgetExceeded
} derive(Eq, Debug)

///|
pub(all) enum Issue {
  BindingInput(Origin, Issue)
  Decode(@decode.Issue)
  Contract(@contract.AdmissionError)
  Value(@value.Issue)
  ParameterIssue(
    IssueKind,
    path~ : Array[@decode.PathSegment],
    span~ : @span.Span
  )
  InvalidLimits
} derive(Eq, Debug)

///|
priv suberror Abort {
  Abort(Issue)
}

///|
priv struct Budget {
  mut nodes : Int
  mut text : Int
  depth : Int
}
