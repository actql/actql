///|
/// Cumulative work budgets, independent of retained output-tree admission.
/// Nodes include visited nodes and temporary allocations inside text parsing.
pub(all) struct Limits {
  max_nodes : Int
  max_depth : Int
  max_text_bytes : Int
  max_tokens : Int
  tree : @decode.Limits
} derive(Eq, Debug)

///|
pub(all) enum IssueKind {
  InvalidLimits
  Decode(@decode.IssueKind)
  InvalidExpression
  UnknownTag(String)
  InvalidArguments
  InvalidName(String)
  NonCanonicalText
  InvalidUnicode
  InvalidNumber
  InvalidItemContract
  BudgetExceeded
  Text(@text.IssueKind)
} derive(Eq, Debug)

///|
/// range is relative to a decoded expression string, never a JSON/YAML byte
/// offset. path/span identify the original containing source slot.
pub(all) struct Issue {
  kind : IssueKind
  path : Array[@source.PathSegment]
  span : @source.Span
  range : @text.Range?
} derive(Eq, Debug)

///|
/// Original source handle. Range is decoded Unicode scalars, never file bytes.
pub struct Location {
  source : @decode.Cursor
  range : @text.Range?
}

///|
pub fn location_path(location : Location) -> Array[@source.PathSegment] {
  @decode.cursor_path(location.source)
}

///|
pub fn location_span(location : Location) -> @source.Span {
  @decode.cursor_span(location.source)
}

///|
pub struct FieldReference {
  name : String
  location : Location
}

///|
pub type ParameterReference = FieldReference

///|
type Node = @map.Node[Location]

///|
struct Expression {
  cursor : @decode.Cursor
  origins : @map.Map[Location]
  references : Array[ParameterReference]
  field_indices : Array[Int]
  relation_references : Array[FieldReference]
  usage : Usage
}

///|
pub(all) struct Usage {
  nodes : Int
  text_bytes : Int
  tokens : Int
} derive(Eq, Debug)

///|
pub fn usage(expression : Expression) -> Usage {
  expression.usage
}

///|
/// Local node-to-source sidecar lookup, never a canonical identity.
pub fn origin(expression : Expression, cursor : @decode.Cursor) -> Location? {
  @map.annotation(expression.origins, cursor)
}

///|
pub fn origin_count(expression : Expression) -> Int {
  @map.node_count(expression.origins)
}

///|
pub fn field_references(expression : Expression) -> Array[FieldReference] {
  expression.field_indices.map(i => expression.relation_references[i])
}

///|
pub fn relation_references(expression : Expression) -> Array[FieldReference] {
  expression.relation_references.copy()
}

///|
pub fn relation_reference_count(expression : Expression) -> Int {
  expression.relation_references.length()
}

///|
pub fn relation_reference_at(
  expression : Expression,
  index : Int,
) -> FieldReference? {
  if index < 0 || index >= expression.relation_references.length() {
    None
  } else {
    Some(expression.relation_references[index])
  }
}

///|
pub fn tree(expression : Expression) -> @decode.Cursor {
  expression.cursor
}

///|
pub fn parameter_references(
  expression : Expression,
) -> Array[ParameterReference] {
  expression.references.copy()
}

///|
priv suberror Stop {
  Stop(Issue)
}

///|
// Origin preserves diagnostic coordinates and occurrence provenance only;
// both origins undergo the same alias normalization and closed validation.
priv enum Origin {
  Authored
  TextDecoded(@decode.Cursor, @text.Expression)
}

///|
priv enum Role {
  Expr
  Data
  Arguments(String)
  Body(String)
  ObjectFields
  Branches
  Branch
  CastTarget
  ItemContract
  InRight
  InList
  InItem
}

///|
priv struct Budget {
  mut nodes : Int
  mut scheduled : Int
  mut bytes : Int
  mut tokens : Int
  references : Array[ParameterReference]
  field_indices : Array[Int]
  relation_references : Array[FieldReference]
}

///|
priv enum Work {
  Visit(@decode.Cursor, Role, Origin, Int)
  Finish(@decode.Cursor, Role, Origin, Int, Array[String]?)
}

///|
fn[T] invalid(
  cursor : @decode.Cursor,
  origin : Origin,
  kind : IssueKind,
) -> T raise Stop {
  let (location, range) = match origin {
    Authored => (cursor, None)
    TextDecoded(slot, expression) =>
      (slot, @text.node_range(expression, cursor))
  }
  raise Stop({
    kind,
    path: @decode.cursor_path(location),
    span: @decode.cursor_span(location),
    range,
  })
}

///|
fn[T] decoded(
  result : Result[T, @decode.Issue],
  origin : Origin,
) -> T raise Stop {
  match result {
    Ok(value) => value
    Err(issue) =>
      match origin {
        Authored =>
          raise Stop({
            kind: Decode(issue.kind),
            path: issue.path,
            span: issue.span,
            range: None,
          })
        TextDecoded(slot, expression) =>
          raise Stop({
            kind: Decode(issue.kind),
            path: @decode.cursor_path(slot),
            span: @decode.cursor_span(slot),
            range: @text.node_range(expression, @text.tree(expression)),
          })
      }
  }
}

///|
fn charge(
  text : String,
  cursor : @decode.Cursor,
  origin : Origin,
  budget : Budget,
) -> Unit raise Stop {
  match @scalar.admit_utf8_length(text, budget.bytes) {
    Ok(size) => budget.bytes -= size
    Err(@scalar.MalformedUtf16(_)) => invalid(cursor, origin, InvalidUnicode)
    Err(_) => invalid(cursor, origin, BudgetExceeded)
  }
}

///|
fn canonical(
  text : String,
  cursor : @decode.Cursor,
  origin : Origin,
) -> Unit raise Stop {
  match @canonical.normalize_nfc_lf(text) {
    Ok(value) => if value != text { invalid(cursor, origin, NonCanonicalText) }
    Err(_) => invalid(cursor, origin, InvalidUnicode)
  }
}

///|
fn location(cursor : @decode.Cursor, origin : Origin) -> Location {
  match origin {
    Authored => { source: cursor, range: None, }
    TextDecoded(slot, expression) =>
      { source: slot, range: @text.node_range(expression, cursor), }
  }
}

///|
fn node(
  value : @map.Value[Location],
  cursor : @decode.Cursor,
  origin : Origin,
) -> Node {
  {
    value,
    span: @decode.cursor_span(cursor),
    annotation: location(cursor, origin),
  }
}

///|
fn form(
  tag : String,
  body : Node,
  cursor : @decode.Cursor,
  origin : Origin,
) -> Node {
  node(
    @map.Object([
      { key: tag, key_span: @decode.cursor_span(cursor), value: body, },
    ]),
    cursor,
    origin,
  )
}

///|
fn named(
  fields : Array[(String, Node)],
  cursor : @decode.Cursor,
  origin : Origin,
) -> Node {
  node(
    @map.Object(
      fields.map(f => {
        key: f.0,
        key_span: @decode.cursor_span(cursor),
        value: f.1,
      }),
    ),
    cursor,
    origin,
  )
}
