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
pub(all) enum ContractSegment {
  Item
  Field(String)
} derive(Eq, Debug)

///|
pub(all) enum IssueKind {
  InvalidLimits
  BudgetExceeded
  InvalidBody
  InvalidName(String)
  MissingField(@schema.Side, @schema.FieldName)
  IncompatibleContracts(@schema.FieldName, Array[ContractSegment])
} derive(Eq, Debug)

///|
pub struct Issue {
  kind : IssueKind
  source : @decode.Cursor
  path : Array[@decode.PathSegment]
  span : @span.Span
}

///|
pub(all) enum Obligation {
  ValidateInputRows
  PreserveLeftThenRightOrder
  ResolveOutputEnvelope
  ResolveIdentityAndCompleteness
} derive(Eq, Debug)

///|
/// Local schema positions, not physical row offsets or semantic identities.
pub struct Alignment {
  field : @schema.FieldName
  left_index : Int
  right_index : Int
}

///|
struct CheckedAppend {
  source : @decode.Cursor
  with_name : String
  left : @schema.Schema
  right : @schema.Schema
  output : @schema.Schema
  alignment : Array[Alignment]
  usage : Usage
}

///|
pub fn source(v : CheckedAppend) -> @decode.Cursor {
  v.source
}

///|
pub fn with_name(v : CheckedAppend) -> String {
  v.with_name
}

///|
pub fn input_schema(v : CheckedAppend, side : @schema.Side) -> @schema.Schema {
  if side == Left {
    v.left
  } else {
    v.right
  }
}

///|
pub fn output_schema(v : CheckedAppend) -> @schema.Schema {
  v.output
}

///|
pub fn alignment(v : CheckedAppend) -> Array[Alignment] {
  v.alignment.copy()
}

///|
pub fn usage(v : CheckedAppend) -> Usage {
  v.usage
}

///|
pub fn pending_validations(_v : CheckedAppend) -> Array[Obligation] {
  let out = []
  for i in 0..<pending_validation_count(_v) {
    out.push(pending_validation_at(_v, i).unwrap())
  }
  out
}

///|
/// O(1), without materializing the obligation array.
pub fn pending_validation_count(_v : CheckedAppend) -> Int {
  4
}

///|
/// O(1); invalid indices return None. Retains authored obligation order.
pub fn pending_validation_at(_v : CheckedAppend, index : Int) -> Obligation? {
  match index {
    0 => Some(ValidateInputRows)
    1 => Some(PreserveLeftThenRightOrder)
    2 => Some(ResolveOutputEnvelope)
    3 => Some(ResolveIdentityAndCompleteness)
    _ => None
  }
}

///|
priv struct Budget {
  limits : Limits
  mut work : Int
  mut text : Int
  mut nodes : Int
}

///|
priv suberror Stop {
  Stop(Issue)
}

///|
fn[T] fail(s : @decode.Cursor, kind : IssueKind) -> T raise Stop {
  raise Stop({
    source: s,
    kind,
    path: @decode.cursor_path(s),
    span: @decode.cursor_span(s),
  })
}

///|
fn spend(b : Budget, s : @decode.Cursor, n? : Int = 1) -> Unit raise Stop {
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
