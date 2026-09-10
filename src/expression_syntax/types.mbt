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
pub(all) struct ParameterReference {
  name : String
  path : Array[@source.PathSegment]
  span : @source.Span
  range : @text.Range?
} derive(Eq, Debug)

///|
struct Expression {
  cursor : @decode.Cursor
  references : Array[ParameterReference]
}

///|
pub fn tree(expression : Expression) -> @decode.Cursor {
  expression.cursor
}

///|
/// Syntactic occurrences only, in source order, with duplicates retained.
pub fn parameter_references(
  expression : Expression,
) -> Array[ParameterReference] {
  expression.references.map(r => { ..r, path: r.path.copy(), })
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
  TextDecoded(@decode.Cursor, @text.Range)
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
    TextDecoded(slot, range) => (slot, Some(range))
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
        TextDecoded(slot, range) =>
          raise Stop({
            kind: Decode(issue.kind),
            path: @decode.cursor_path(slot),
            span: @decode.cursor_span(slot),
            range: Some(range),
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
fn node(value : @source.Value, cursor : @decode.Cursor) -> @source.Node {
  { value, span: @decode.cursor_span(cursor), }
}

///|
fn form(
  tag : String,
  body : @source.Node,
  cursor : @decode.Cursor,
) -> @source.Node {
  node(
    @source.Object([
      { key: tag, key_span: @decode.cursor_span(cursor), value: body, },
    ]),
    cursor,
  )
}

///|
fn named(
  fields : Array[(String, @source.Node)],
  cursor : @decode.Cursor,
) -> @source.Node {
  node(
    @source.Object(
      fields.map(f => {
        key: f.0,
        key_span: @decode.cursor_span(cursor),
        value: f.1,
      }),
    ),
    cursor,
  )
}
