///|
pub(all) struct Limits {
  max_steps : Int
  max_work : Int
  max_text_bytes : Int
  max_nodes : Int
  max_tokens : Int
  max_depth : Int
} derive(Eq, Debug)

///|
pub(all) struct Usage {
  work : Int
  text_bytes : Int
  nodes : Int
  tokens : Int
} derive(Eq, Debug)

///|
/// Indices in the retained input list or authored step array; not semantic IDs.
pub(all) enum Target {
  Input(Int)
  Step(Int)
} derive(Eq, Debug)

///|
pub(all) enum IssueKind {
  InvalidLimits
  BudgetExceeded
  InvalidBody
  InvalidInputSchema(String)
  InvalidName(String)
  DuplicateName(String)
  UnknownName(String)
  MissingCurrent
  UnsupportedOperation(String)
  InvalidMetadata
  ReservedMetadataKey(String)
  Operation(@relation.IssueKind)
} derive(Eq, Debug)

///|
pub struct Issue {
  kind : IssueKind
  source : @decode.Cursor
  path : Array[@decode.PathSegment]
  span : @span.Span
  range : @text.Range?
}

///|
pub struct CheckedStep {
  source : @decode.Cursor
  input : Target
  binding_name : String?
  metadata : @decode.Cursor?
  operation : @relation.CheckedOperation
}

///|
struct CheckedPipeline {
  source : @decode.Cursor
  initial_from : @decode.Cursor?
  inputs : Array[(String, @contract.Contract)]
  steps : Array[CheckedStep]
  names : Map[String, Target]
  current : Target
  output : @contract.Contract
  parameters : @parameter.Declarations?
  usage : Usage
}

///|
pub fn source(value : CheckedPipeline) -> @decode.Cursor {
  value.source
}

///|
pub fn initial_from(value : CheckedPipeline) -> @decode.Cursor? {
  value.initial_from
}

///|
pub fn inputs(value : CheckedPipeline) -> Array[(String, @contract.Contract)] {
  value.inputs.copy()
}

///|
pub fn step_count(value : CheckedPipeline) -> Int {
  value.steps.length()
}

///|
pub fn step_at(value : CheckedPipeline, index : Int) -> CheckedStep? {
  if index < 0 || index >= value.steps.length() {
    None
  } else {
    Some(value.steps[index])
  }
}

///|
pub fn lookup(value : CheckedPipeline, name : String) -> Target? {
  value.names.get(name)
}

///|
pub fn current(value : CheckedPipeline) -> Target {
  value.current
}

///|
pub fn output_schema(value : CheckedPipeline) -> @contract.Contract {
  value.output
}

///|
pub fn parameters(value : CheckedPipeline) -> @parameter.Declarations? {
  value.parameters
}

///|
pub fn usage(value : CheckedPipeline) -> Usage {
  value.usage
}

///|
priv suberror Stop {
  Stop(Issue)
}

///|
fn[T] fail(source : @decode.Cursor, kind : IssueKind) -> T raise Stop {
  raise Stop({
    kind,
    source,
    path: @decode.cursor_path(source),
    span: @decode.cursor_span(source),
    range: None,
  })
}

///|
priv struct Budget {
  limits : Limits
  mut work : Int
  mut text : Int
  mut nodes : Int
  mut tokens : Int
}

///|
fn spend(b : Budget, source : @decode.Cursor, amount : Int) -> Unit raise Stop {
  if amount < 0 || amount > b.work {
    fail(source, BudgetExceeded)
  }
  b.work -= amount
}

///|
fn charge(
  b : Budget,
  source : @decode.Cursor,
  text : String,
) -> Unit raise Stop {
  match @scalar.admit_utf8_length(text, b.text) {
    Ok(n) => b.text -= n
    Err(_) => fail(source, BudgetExceeded)
  }
}

///|
fn name(b : Budget, source : @decode.Cursor, value : String) -> Unit raise Stop {
  spend(b, source, 1)
  charge(b, source, value)
  if value == "" || @canonical.normalize_nfc_lf(value) != Ok(value) {
    fail(source, InvalidName(value))
  }
}

///|
fn read_name(b : Budget, source : @decode.Cursor) -> String raise Stop {
  let value = match @decode.text(source) {
    Ok(v) => v
    Err(_) => fail(source, InvalidBody)
  }
  name(b, source, value)
  value
}

///|
fn preflight(
  b : Budget,
  source : @decode.Cursor,
  root : @contract.Contract,
) -> Unit raise Stop {
  let work = [(root, 0)]
  while work.pop() is Some((c, depth)) {
    spend(b, source, 1)
    if depth > b.limits.max_depth {
      fail(source, BudgetExceeded)
    }
    match c.shape {
      @contract.Array(item, ..) => work.push((item, depth + 1))
      @contract.Object(fields) => {
        let count = @contract.field_count(fields)
        spend(b, source, count)
        for i in 0..<count {
          let f = @contract.field_at(fields, i).unwrap()
          charge(b, source, f.name)
          work.push((f.contract, depth + 1))
        }
      }
      @contract.ResourceRef(resource_kind~) => charge(b, source, resource_kind)
      @contract.ArtifactRef(media_type=Some(media)) => charge(b, source, media)
      _ => ()
    }
  }
}

///|
fn schema(
  target : Target,
  inputs : Array[(String, @contract.Contract)],
  steps : Array[CheckedStep],
) -> @contract.Contract {
  match target {
    Input(i) => inputs[i].1
    Step(i) => @relation.output_schema(steps[i].operation)
  }
}
