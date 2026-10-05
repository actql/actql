///|
pub type Span = @span.Span

///|
/// Editable syntax data, not proof of canonical or domain admission.
pub(all) enum Value {
  Null
  Bool(Bool)
  Number(Double)
  String(String)
  Array(Array[Node])
  Object(Array[Field])
} derive(Debug)

///|
pub(all) struct Node {
  value : Value
  span : Span
} derive(Debug)

///|
pub(all) struct Field {
  key : String
  key_span : Span
  value : Node
} derive(Debug)

///|
pub(all) struct ParseLimits {
  max_input_bytes : Int
  max_nodes : Int
  max_depth : Int
} derive(Eq, Debug)

///|
/// Successful parser measurements, before any consumer's tree admission.
/// Input bytes include BOM, whitespace and comments; depth counts containers.
pub(all) struct ParseUsage {
  input_bytes : Int
  nodes : Int
  depth : Int
} derive(Eq, Debug)

///|
/// Editable syntax plus measurements of the original parse. Editing the Node
/// does not update these measurements or make it admitted consumer input.
pub(all) struct ParsedSource {
  node : Node
  usage : ParseUsage
}

///|
pub(all) enum PathSegment {
  Key(String)
  Index(Int)
} derive(Eq, Debug)

///|
pub(all) enum ParseIssue {
  InvalidLimits
  InputLimit
  InvalidUtf8
  InvalidUtf16
  NodeLimit
  DepthLimit
  UnexpectedEnd
  UnexpectedToken
  InvalidString
  InvalidEscape
  InvalidUnicodeEscape
  InvalidNumber
  NumberOutOfRange
  NumberPrecisionLoss
  NegativeZero
  ExpectedColon
  ExpectedArraySeparator
  ExpectedObjectSeparator
  DuplicateKey(String)
  TrailingContent
  InvalidYamlIndentation
  InvalidYamlScalar
  InvalidYamlDirective
  MultipleDocuments
  ForbiddenYamlFeature
  NonStringKey
} derive(Eq, Debug)

///|
/// Preflight errors expose only coordinates already known, never guessed lines.
pub(all) enum ParseLocation {
  Source(Span)
  ByteOffset(Int)
  Utf16Offset(Int)
  Unavailable
} derive(Eq, Debug)

///|
/// None means no structural path is known; Some([]) denotes the root value.
pub(all) struct ParseError {
  issue : ParseIssue
  source_path : String
  location : ParseLocation
  path : Array[PathSegment]?
} derive(Eq, Debug)

///|
priv suberror ParseAbort {
  ParseAbort(ParseError)
}
