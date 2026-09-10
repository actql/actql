///|
/// Parser work budgets and independent limits on the retained structured tree.
/// max_depth counts active expression continuations, starting at one.
pub(all) struct Limits {
  max_input_bytes : Int
  max_tokens : Int
  max_nodes : Int
  max_depth : Int
  tree : @decode.Limits
} derive(Eq, Debug)

///|
/// Half-open Unicode scalar offsets in the decoded expression string, before
/// token payload normalization. These are not offsets in JSON or YAML source.
pub(all) struct Range {
  start : Int
  end : Int
} derive(Eq, Debug)

///|
pub(all) enum IssueKind {
  InvalidLimits
  Lexical(LexicalProblem)
  Syntax
  UnknownFunction
  InvalidArguments
  CapacityExceeded
  TreeAdmission(@decode.IssueKind)
} derive(Eq, Debug)

///|
pub(all) struct Issue {
  kind : IssueKind
  range : Range
  enclosing_span : @value.Span?
} derive(Eq, Debug)

///|
pub(all) struct ParameterReference {
  name : String
  range : Range
} derive(Eq, Debug)

///|
pub(all) struct FieldReference {
  name : String
  range : Range
} derive(Eq, Debug)

///|
/// Actual work consumed by a successful parse; EOF does not count as a token.
pub(all) struct Usage {
  input_bytes : Int
  tokens : Int
  nodes : Int
} derive(Eq, Debug)

///|
/// The owned cursor is the common structured Expression tree, not a second AST.
struct Expression {
  field_references : Array[FieldReference]
  cursor : @decode.Cursor
  references : Array[ParameterReference]
  enclosing_span : @value.Span?
  usage : Usage
}

///|
/// Successful parser work, including temporary nodes. Callers can share one
/// cumulative budget across fragments without resetting it for every child.
pub fn usage(expression : Expression) -> Usage {
  expression.usage
}

///|
pub fn tree(expression : Expression) -> @decode.Cursor {
  expression.cursor
}

///|
/// Occurrences in source order, including repeated names; literals are opaque.
pub fn parameter_references(
  expression : Expression,
) -> Array[ParameterReference] {
  expression.references.copy()
}

///|
/// Ordinary field tokens, not function names, property names, join fields or
/// literal contents. Whole-field aliases are normalized by expression_syntax.
pub fn field_references(expression : Expression) -> Array[FieldReference] {
  expression.field_references.copy()
}

///|
pub fn enclosing_span(expression : Expression) -> @value.Span? {
  expression.enclosing_span
}

///|
fn decoded_span(source : String, source_path : String) -> @value.Span {
  let mut bytes = 0
  let mut line = 1
  let mut column = 1
  let mut cr = false
  for ch in source.iter() {
    let point = ch.to_int()
    bytes += if point < 0x80 {
      1
    } else if point < 0x800 {
      2
    } else if point < 0x10000 {
      3
    } else {
      4
    }
    if ch == '\r' {
      line += 1
      column = 1
    } else if ch == '\n' {
      if !cr {
        line += 1
      }
      column = 1
    } else {
      column += 1
    }
    cr = ch == '\r'
  }
  {
    start_byte: 0,
    end_byte: bytes,
    start_line: 1,
    start_column: 1,
    end_line: line,
    end_column: column,
    source_path,
  }
}

///|
/// Admit syntax only. source_path names the decoded expression coordinate space;
/// enclosing_span separately identifies its containing Program scalar, if any.
/// Tree nodes carry the whole decoded expression span; diagnostics and parameter
/// occurrences additionally carry precise scalar ranges.
pub fn parse(
  source : String,
  limits : Limits,
  source_path? : String = "<expression>",
  enclosing_span? : @value.Span,
) -> Result[Expression, Issue] {
  if limits.max_input_bytes < 0 ||
    limits.max_tokens < 0 ||
    limits.max_nodes < 0 ||
    limits.max_depth < 0 ||
    limits.tree.max_nodes < 0 ||
    limits.tree.max_depth < 0 ||
    limits.tree.max_string_bytes < 0 ||
    limits.tree.max_total_string_bytes < 0 {
    return Err({
      kind: InvalidLimits,
      range: { start: 0, end: 0, },
      enclosing_span,
    })
  }
  let tokens = lex(
    source,
    max_bytes=limits.max_input_bytes,
    max_tokens=limits.max_tokens,
  ) catch {
    LexicalError(problem, start, end) =>
      return Err({
        kind: Lexical(problem),
        range: { start, end, },
        enclosing_span,
      })
  }
  let parser : Parser = {
    field_references: [],
    tokens,
    span: decoded_span(source, source_path),
    pos: 0,
    nodes: 0,
    max_depth: limits.max_depth,
    max_nodes: limits.max_nodes,
  }
  let node = parser.expression() catch {
    SyntaxFailure(start, end) =>
      return Err({ kind: Syntax, range: { start, end, }, enclosing_span, })
    UnknownFunction(start, end) =>
      return Err({
        kind: UnknownFunction,
        range: { start, end, },
        enclosing_span,
      })
    InvalidArguments(start, end) =>
      return Err({
        kind: InvalidArguments,
        range: { start, end, },
        enclosing_span,
      })
    CapacityExceeded(start, end) =>
      return Err({
        kind: CapacityExceeded,
        range: { start, end, },
        enclosing_span,
      })
  }
  let cursor = match @decode.admit(node, limits.tree) {
    Ok(cursor) => cursor
    Err(issue) =>
      return Err({
        kind: TreeAdmission(issue.kind),
        range: { start: 0, end: tokens[tokens.length() - 1].end, },
        enclosing_span,
      })
  }
  let references : Array[ParameterReference] = []
  for token in tokens {
    if token.kind is Parameter(name) {
      references.push({ name, range: { start: token.start, end: token.end, }, })
    }
  }
  Ok({
    cursor,
    references,
    field_references: parser.field_references,
    enclosing_span,
    usage: {
      input_bytes: parser.span.end_byte,
      tokens: tokens.length() - 1,
      nodes: parser.nodes,
    },
  })
}
