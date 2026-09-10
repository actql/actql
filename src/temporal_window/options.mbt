///|
pub(all) enum Kind {
  Fixed
  Sliding
} derive(Eq, Debug)

///|
pub(all) enum Domain {
  PositiveMilliseconds
  SignedMilliseconds
} derive(Eq, Debug)

///|
pub enum Milliseconds {
  Literal(Int64)
  Parameter(String, duration~ : Bool, domain~ : Domain)
}

///|
pub(all) struct Limits {
  max_nodes : Int
  max_depth : Int
  max_text_bytes : Int
  max_work : Int
}

///|
pub(all) struct Usage {
  nodes : Int
  text_bytes : Int
  work : Int
}

///|
pub(all) enum IssueKind {
  InvalidLimits
  BudgetExceeded
  InvalidBody
  InvalidMilliseconds
  UnknownParameter(String)
  IncompatibleParameter(String)
  WrongCarrier
  UnknownTime(String)
  InvalidTime(String)
  OutputCollision(String)
  UnknownOutputFields
} derive(Eq, Debug)

///|
pub struct Issue {
  kind : IssueKind
  path : Array[@decode.PathSegment]
  span : @span.Span
}

///|
struct Options {
  kind : Kind
  size : Milliseconds
  step : Milliseconds?
  offset : Milliseconds
  time : @decode.Cursor?
  usage : Usage
}

///|
priv struct Budget {
  limits : Limits
  mut nodes : Int
  mut text : Int
  mut work : Int
}

///|
priv suberror Stop {
  Stop(Issue)
}

///|
fn[T] fail(c : @decode.Cursor, kind : IssueKind) -> T raise Stop {
  raise Stop({
    kind,
    path: @decode.cursor_path(c),
    span: @decode.cursor_span(c),
  })
}

///|
fn charge(b : Budget, c : @decode.Cursor, text : String) -> Unit raise Stop {
  match @scalar.admit_utf8_length(text, b.text) {
    Ok(n) => b.text -= n
    Err(_) => fail(c, BudgetExceeded)
  }
}

///|
fn spend(b : Budget, c : @decode.Cursor, n : Int) -> Unit raise Stop {
  if n > b.work {
    fail(c, BudgetExceeded)
  }
  b.work -= n
}

///|
fn scan(b : Budget, root : @decode.Cursor) -> Unit raise Stop {
  let stack = [(root, 0)]
  while !stack.is_empty() {
    let (c, depth) = stack.pop().unwrap()
    if b.nodes == 0 {
      fail(c, BudgetExceeded)
    }
    b.nodes -= 1
    spend(b, c, 1)
    match @decode.view(c) {
      @decode.TextValue(s) => charge(b, c, s)
      @decode.ArrayValue(xs) => {
        if depth >= b.limits.max_depth || xs.length() > b.nodes {
          fail(c, BudgetExceeded)
        }
        for x in xs.rev_iter() {
          stack.push((x, depth + 1))
        }
      }
      @decode.ObjectValue(o) => {
        let names = @decode.object_field_names(c).unwrap()
        if depth >= b.limits.max_depth || names.length() > b.nodes {
          fail(c, BudgetExceeded)
        }
        for name in names.rev_iter() {
          charge(b, c, name)
          stack.push((@decode.lookup(o, name).unwrap(), depth + 1))
        }
      }
      _ => ()
    }
  }
}

///|
fn read_ms(
  c : @decode.Cursor,
  domain : Domain,
  params : Map[String, @contract.ParameterType],
) -> Milliseconds raise Stop {
  match @decode.view(c) {
    @decode.NumberValue(v) => {
      let n = match @scalar.read_safe_integer(v) {
        Some(n) => n
        None => fail(c, InvalidMilliseconds)
      }
      if (v == 0.0 && 1.0 / v < 0.0) ||
        (domain == PositiveMilliseconds && n <= 0L) {
        fail(c, InvalidMilliseconds)
      }
      Literal(n)
    }
    @decode.TextValue(s) =>
      match @scalar.read_duration_ms(s) {
        Some(n) => Literal(n)
        None => fail(c, InvalidMilliseconds)
      }
    @decode.ObjectValue(_) => {
      let o = match @decode.closed_object(c, ["$param"]) {
        Ok(o) => o
        Err(_) => fail(c, InvalidMilliseconds)
      }
      let name = match @decode.lookup(o, "$param") {
        Some(v) =>
          match @decode.text(v) {
            Ok(n) => n
            Err(_) => fail(v, InvalidMilliseconds)
          }
        None => fail(c, InvalidMilliseconds)
      }
      let p = match params.get(name) {
        Some(p) => p
        None => fail(c, UnknownParameter(name))
      }
      if p.contract.nullable {
        fail(c, IncompatibleParameter(name))
      }
      let duration = p.rule is @contract.Duration
      if !duration && !(p.contract.shape is @contract.Number) {
        fail(c, IncompatibleParameter(name))
      }
      Parameter(name, duration~, domain~)
    }
    _ => fail(c, InvalidMilliseconds)
  }
}

///|
/// Read window arguments without claiming that the input Carrier or its time
/// field has been checked. Parameter defaults are not bound at this boundary.
pub fn read_options(
  source : @decode.Cursor,
  relation~ : Bool,
  parameters : @parameter.Declarations?,
  limits : Limits,
) -> Result[Options, Issue] {
  try {
    if limits.max_nodes < 0 ||
      limits.max_depth < 0 ||
      limits.max_text_bytes < 0 ||
      limits.max_work < 0 {
      fail(source, InvalidLimits)
    }
    let b : Budget = {
      limits,
      nodes: limits.max_nodes,
      text: limits.max_text_bytes,
      work: limits.max_work,
    }
    scan(b, source)
    let params : Map[String, @contract.ParameterType] = Map([])
    if parameters is Some(ds) {
      let count = @parameter.declaration_count(ds)
      spend(b, source, count)
      for i in 0..<count {
        let d = @parameter.declaration_at(ds, i).unwrap()
        charge(b, source, d.name)
        params[d.name] = d.parameter_type
      }
    }
    let allowed = if relation {
      ["kind", "time", "size", "step", "offset"]
    } else {
      ["kind", "size", "step", "offset"]
    }
    let o = match @decode.closed_object(source, allowed) {
      Ok(o) => o
      Err(_) => fail(source, InvalidBody)
    }
    let required = fn(name) raise Stop {
      match @decode.lookup(o, name) {
        Some(c) => c
        None => fail(source, InvalidBody)
      }
    }
    let kind_source = required("kind")
    let kind = match @decode.text(kind_source) {
      Ok("fixed") => Fixed
      Ok("sliding") => Sliding
      _ => fail(kind_source, InvalidBody)
    }
    let time = if relation { Some(required("time")) } else { None }
    let size = read_ms(required("size"), PositiveMilliseconds, params)
    let step = if kind == Sliding {
      Some(read_ms(required("step"), PositiveMilliseconds, params))
    } else {
      match @decode.lookup(o, "step") {
        Some(c) => Some(read_ms(c, PositiveMilliseconds, params))
        None => None
      }
    }
    let offset = match @decode.lookup(o, "offset") {
      Some(c) => read_ms(c, SignedMilliseconds, params)
      None => Literal(0L)
    }
    Ok({
      kind,
      size,
      step,
      offset,
      time,
      usage: {
        nodes: limits.max_nodes - b.nodes,
        text_bytes: limits.max_text_bytes - b.text,
        work: limits.max_work - b.work,
      },
    })
  } catch {
    Stop(issue) => Err(issue)
  }
}

///|
pub fn kind(value : Options) -> Kind {
  value.kind
}

///|
pub fn size(value : Options) -> Milliseconds {
  value.size
}

///|
pub fn step(value : Options) -> Milliseconds? {
  value.step
}

///|
pub fn offset(value : Options) -> Milliseconds {
  value.offset
}

///|
pub fn time_source(value : Options) -> @decode.Cursor? {
  value.time
}

///|
pub fn usage(value : Options) -> Usage {
  value.usage
}
