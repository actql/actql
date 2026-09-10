///|
pub(all) struct Limits {
  max_rows : Int
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
pub(all) enum IssueKind {
  InvalidLimits
  BudgetExceeded
  InvalidBody
  EmptySchema
  ForbiddenValueType
  InvalidParameterName(String)
  UnknownParameter(String)
  IncompatibleParameter(String)
  Decode(@decode.IssueKind)
  Contract(@contract.ContractIssue)
  Value(@value.IssueKind)
} derive(Eq, Debug)

///|
pub struct Issue {
  kind : IssueKind
  source : @decode.Cursor
  path : Array[@decode.PathSegment]
  span : @span.Span
}

///|
/// Quoting is removed exactly once; a literal's nested structure stays opaque.
pub enum Cell {
  Literal(@value.CheckedValue, source~ : @decode.Cursor)
  Parameter(String, contract~ : @contract.Contract, source~ : @decode.Cursor)
}

///|
struct Row {
  source : @decode.Cursor
  cells : Array[Cell]
}

///|
struct CheckedValues {
  source : @decode.Cursor
  schema : @schema.Schema
  rows : Array[Row]
  pending : Array[Obligation]
  usage : Usage
}

///|
pub(all) enum Obligation {
  BindCell(String)
  ResolvePublicationResources
} derive(Eq, Debug)

///|
pub fn source(v : CheckedValues) -> @decode.Cursor {
  v.source
}

///|
pub fn output_schema(v : CheckedValues) -> @schema.Schema {
  v.schema
}

///|
pub fn row_count(v : CheckedValues) -> Int {
  v.rows.length()
}

///|
pub fn row_at(v : CheckedValues, i : Int) -> Row? {
  if i < 0 || i >= v.rows.length() {
    None
  } else {
    Some(v.rows[i])
  }
}

///|
pub fn row_source(v : Row) -> @decode.Cursor {
  v.source
}

///|
pub fn cell_at(v : Row, i : Int) -> Cell? {
  if i < 0 || i >= v.cells.length() {
    None
  } else {
    Some(v.cells[i])
  }
}

///|
pub fn cells(v : Row) -> Array[Cell] {
  v.cells.copy()
}

///|
pub fn usage(v : CheckedValues) -> Usage {
  v.usage
}

///|
pub fn pending_validations(v : CheckedValues) -> Array[Obligation] {
  v.pending.copy()
}

///|
priv struct Budget {
  limits : Limits
  mut work : Int
  mut nodes : Int
  mut text : Int
}

///|
priv suberror Stop {
  Stop(Issue)
}

///|
fn[T] fail(s : @decode.Cursor, kind : IssueKind) -> T raise Stop {
  raise Stop({
    kind,
    source: s,
    path: @decode.cursor_path(s),
    span: @decode.cursor_span(s),
  })
}

///|
fn[T] decoded(
  result : Result[T, @decode.Issue],
  source : @decode.Cursor,
) -> T raise Stop {
  match result {
    Ok(v) => v
    Err(e) =>
      raise Stop({
        kind: Decode(e.kind),
        source,
        path: e.path.copy(),
        span: e.span,
      })
  }
}

///|
fn spend(b : Budget, s : @decode.Cursor, n : Int) -> Unit raise Stop {
  if n < 0 || n > b.work {
    fail(s, BudgetExceeded)
  }
  b.work -= n
}

///|
fn charge(b : Budget, s : @decode.Cursor, text : String) -> Unit raise Stop {
  match @scalar.admit_utf8_length(text, b.text) {
    Ok(n) => b.text -= n
    Err(_) => fail(s, BudgetExceeded)
  }
}

///|
// Charges an iterative source walk and returns its measured traversal envelope.
fn scan(b : Budget, source : @decode.Cursor) -> Usage raise Stop {
  let (work, nodes, text) = (b.work, b.nodes, b.text)
  let stack = [(source, 0)]
  while stack.pop() is Some((s, depth)) {
    spend(b, s, 1)
    if b.nodes == 0 {
      fail(s, BudgetExceeded)
    }
    b.nodes -= 1
    match @decode.view(s) {
      TextValue(t) => charge(b, s, t)
      ArrayValue(items) => {
        if depth >= b.limits.max_depth {
          fail(s, BudgetExceeded)
        }
        spend(b, s, items.length())
        for item in items {
          stack.push((item, depth + 1))
        }
      }
      ObjectValue(obj) => {
        if depth >= b.limits.max_depth {
          fail(s, BudgetExceeded)
        }
        let names = @decode.object_field_names(s).unwrap()
        spend(b, s, names.length())
        for name in names {
          charge(b, s, name)
          stack.push((@decode.lookup(obj, name).unwrap(), depth + 1))
        }
      }
      _ => ()
    }
  }
  { work: work - b.work, nodes: nodes - b.nodes, text_bytes: text - b.text, }
}

///|
fn reserve(
  b : Budget,
  source : @decode.Cursor,
  used : Usage,
) -> Unit raise Stop {
  spend(b, source, used.work)
  if used.nodes > b.nodes || used.text_bytes > b.text {
    fail(source, BudgetExceeded)
  }
  b.nodes -= used.nodes
  b.text -= used.text_bytes
}

///|
fn contract_walk(
  b : Budget,
  source : @decode.Cursor,
  root : @contract.Contract,
  constructing : Bool,
) -> Int raise Stop {
  let before = b.work
  let stack = [(root, 0)]
  while stack.pop() is Some((c, depth)) {
    spend(b, source, 1)
    if depth > b.limits.max_depth {
      fail(source, BudgetExceeded)
    }
    match c.shape {
      @contract.Json | @contract.ResourceRef(..) | @contract.ArtifactRef(..) => {
        if constructing {
          fail(source, ForbiddenValueType)
        }
        match c.shape {
          @contract.ResourceRef(resource_kind~) =>
            charge(b, source, resource_kind)
          @contract.ArtifactRef(media_type=Some(media)) =>
            charge(b, source, media)
          _ => ()
        }
      }
      @contract.Array(item, ..) => stack.push((item, depth + 1))
      @contract.Object(fields) => {
        let n = @contract.field_count(fields)
        spend(b, source, n)
        for i in 0..<n {
          let f = @contract.field_at(fields, i).unwrap()
          charge(b, source, f.name)
          stack.push((f.contract, depth + 1))
        }
      }
      _ => ()
    }
  }
  before - b.work
}
