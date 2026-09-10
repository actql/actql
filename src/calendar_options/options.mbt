///|
pub(all) enum Operation {
  Bucket
  Series
} derive(Eq, Debug)

///|
pub(all) enum CalendarUnit {
  Day
  Week
  Month
  Quarter
  Year
} derive(Eq, Debug)

///|
pub(all) enum WeekStart {
  Monday
  Sunday
} derive(Eq, Debug)

///|
pub enum Endpoint {
  Literal(String)
  Parameter(String)
}

///|
pub enum Input {
  Field(time~ : String, into~ : String)
  Range(start~ : Endpoint, end~ : Endpoint)
}

///|
pub(all) enum IssueKind {
  InvalidLimits
  BudgetExceeded
  InvalidBody
  Decode(@decode.IssueKind)
  InvalidUnit
  InvalidWeekStart
  EmptyTimezone
  InvalidField(String)
  InvalidTimestamp
  UnknownParameter(String)
  IncompatibleParameter(String)
  ReversedRange
} derive(Eq, Debug)

///|
pub struct Issue {
  kind : IssueKind
  path : Array[@decode.PathSegment]
  span : @span.Span
}

///|
pub(all) struct Limits {
  max_work : Int
  max_nodes : Int
  max_depth : Int
  max_text_bytes : Int
}

///|
pub(all) struct Usage {
  work : Int
  nodes : Int
  text_bytes : Int
}

///|
struct Options {
  operation : Operation
  source : @decode.Cursor
  unit : CalendarUnit
  timezone : String
  week_start : WeekStart?
  input : Input
  usage : Usage
}

///|
fn endpoint(
  b : Budget,
  c : @decode.Cursor,
  params : Map[String, @contract.ParameterType],
) -> Endpoint raise Stop {
  spend(b, c, 1)
  if @decode.view(c) is TextValue(text) {
    if @value.admit(@contract.primitive(TimestampType, nullable=false), c, {
        max_nodes: 1,
        max_depth: 0,
        max_text_bytes: 24,
      })
      is Err(_) ||
      text.has_prefix("0000-") {
      fail(c, InvalidTimestamp)
    }
    return Literal(text)
  }
  let o = decoded(@decode.closed_object(c, ["$param"]))
  let s = decoded(@decode.required(o, "$param"))
  let name = decoded(@decode.text(s))
  let ty = match params.get(name) {
    Some(t) => t
    None => fail(s, UnknownParameter(name))
  }
  if ty.contract.nullable || !(ty.contract.shape is @contract.Timestamp) {
    fail(s, IncompatibleParameter(name))
  }
  Parameter(name)
}

///|
fn field(b : Budget, c : @decode.Cursor, reference : Bool) -> String raise Stop {
  let name = decoded(@decode.text(c))
  let bytes = b.text
  charge(b, c, name)
  spend(b, c, 1)
  let checked_name = if reference &&
    (name.has_prefix("left.") || name.has_prefix("right.")) {
    let parts = name.split(".").to_array()
    if parts.length() != 2 {
      fail(c, InvalidField(name))
    }
    parts[1].to_owned()
  } else {
    name
  }
  if @contract.object_contract(
      [(checked_name, @contract.primitive(NumberType, nullable=false))],
      nullable=false,
      max_fields=1,
      max_name_bytes=bytes,
    )
    is Err(_) {
    fail(c, InvalidField(name))
  }
  name
}

///|
/// Admits source options only. A timezone spelling is not TZDB membership proof.
/// Calendar checking must additionally validate the selected pinned profile.
pub fn read(
  operation : Operation,
  source : @decode.Cursor,
  parameters : @parameter.Declarations?,
  limits : Limits,
) -> Result[Options, Issue] {
  try {
    if limits.max_work < 0 ||
      limits.max_nodes < 0 ||
      limits.max_depth < 0 ||
      limits.max_text_bytes < 0 {
      fail(source, InvalidLimits)
    }
    let b : Budget = {
      limits,
      work: limits.max_work,
      nodes: limits.max_nodes,
      text: limits.max_text_bytes,
    }
    scan(b, source)
    let object = decoded(
      @decode.closed_object(
        source,
        if operation == Bucket {
          ["time", "into", "unit", "timezone", "week_start"]
        } else {
          ["start", "end", "unit", "timezone", "week_start"]
        },
      ),
    )
    let us = decoded(@decode.required(object, "unit"))
    let unit = match decoded(@decode.text(us)) {
      "day" => Day
      "week" => Week
      "month" => Month
      "quarter" => Quarter
      "year" => Year
      _ => fail(us, InvalidUnit)
    }
    let zs = decoded(@decode.required(object, "timezone"))
    let timezone = decoded(@decode.text(zs))
    if timezone.is_empty() {
      fail(zs, EmptyTimezone)
    }
    let week_start = match @decode.lookup(object, "week_start") {
      None => if unit == Week { fail(us, InvalidWeekStart) } else { None }
      Some(s) => {
        if unit != Week {
          fail(s, InvalidWeekStart)
        }
        Some(
          match decoded(@decode.text(s)) {
            "monday" => Monday
            "sunday" => Sunday
            _ => fail(s, InvalidWeekStart)
          },
        )
      }
    }
    let input = if operation == Bucket {
      let time = field(b, decoded(@decode.required(object, "time")), true)
      let into = field(b, decoded(@decode.required(object, "into")), false)
      Field(time~, into~)
    } else {
      let params : Map[String, @contract.ParameterType] = Map([])
      if parameters is Some(p) {
        let n = @parameter.declaration_count(p)
        spend(b, source, n)
        for i in 0..<n {
          let d = @parameter.declaration_at(p, i).unwrap()
          charge(b, source, d.name)
          params[d.name] = d.parameter_type
        }
      }
      let start = endpoint(
        b,
        decoded(@decode.required(object, "start")),
        params,
      )
      let es = decoded(@decode.required(object, "end"))
      let end = endpoint(b, es, params)
      if start is Literal(a) &&
        end is Literal(z) &&
        @canonical.compare_utf16(a, z) > 0 {
        fail(es, ReversedRange)
      }
      Range(start~, end~)
    }
    Ok({
      operation,
      source,
      unit,
      timezone,
      week_start,
      input,
      usage: {
        work: limits.max_work - b.work,
        nodes: limits.max_nodes - b.nodes,
        text_bytes: limits.max_text_bytes - b.text,
      },
    })
  } catch {
    Stop(e) => Err(e)
  }
}

///|
pub fn operation(v : Options) -> Operation {
  v.operation
}

///|
pub fn source(v : Options) -> @decode.Cursor {
  v.source
}

///|
pub fn unit(v : Options) -> CalendarUnit {
  v.unit
}

///|
pub fn timezone(v : Options) -> String {
  v.timezone
}

///|
pub fn week_start(v : Options) -> WeekStart? {
  v.week_start
}

///|
pub fn input(v : Options) -> Input {
  v.input
}

///|
pub fn usage(v : Options) -> Usage {
  v.usage
}
