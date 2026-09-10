///|
pub(all) enum IssueKind {
  Options(@options.IssueKind)
  MissingProfile
  UnknownTimezone(String)
  WrongInput
  MissingField(String)
  UnknownFieldType(String)
  InvalidTime(String)
  UnknownOutputFields
  OutputCollision(String)
  BudgetExceeded
} derive(Eq, Debug)

///|
pub struct Issue {
  kind : IssueKind
  path : Array[@decode.PathSegment]
  span : @span.Span
}

///|
pub(all) enum Obligation {
  ValidateCalendarValues
  ValidateBoundaryDomain
  ResolveResources
  BindTimestamp(String)
  ValidateBoundRange
} derive(Eq, Debug)

///|
pub(all) enum Cardinality {
  PreserveInput
  AtMost(Int)
} derive(Eq, Debug)

///|
struct CheckedCalendar {
  input : @carrier.Carrier?
  options : @options.Options
  profile : @profile.Profile
  output : @carrier.Carrier
  usage : @options.Usage
  cardinality : Cardinality
}

///|
priv suberror Stop {
  Stop(Issue)
}

///|
fn[T] fail(source : @decode.Cursor, kind : IssueKind) -> T raise Stop {
  raise Stop({
    kind,
    path: @decode.cursor_path(source),
    span: @decode.cursor_span(source),
  })
}

///|
pub fn check(
  operation : @options.Operation,
  source : @decode.Cursor,
  input : @carrier.Carrier?,
  parameters : @parameter.Declarations?,
  profile : @profile.Profile?,
  limits : @options.Limits,
) -> Result[CheckedCalendar, Issue] {
  try {
    let options = match @options.read(operation, source, parameters, limits) {
      Ok(v) => v
      Err(e) =>
        raise Stop({ kind: Options(e.kind), path: e.path.copy(), span: e.span, })
    }
    let selected = match profile {
      Some(p) => p
      None => fail(source, MissingProfile)
    }
    let object = @decode.open_object(source).unwrap()
    let zone = @options.timezone(options)
    if @profile.zone(selected, zone) is None {
      fail(@decode.lookup(object, "timezone").unwrap(), UnknownTimezone(zone))
    }
    let used = @options.usage(options)
    let mut work = limits.max_work - used.work
    let mut text = limits.max_text_bytes - used.text_bytes
    let mut nodes = limits.max_nodes - used.nodes
    let timestamp = @contract.primitive(TimestampType, nullable=false)
    let fields : Array[(@row.FieldName, @contract.Contract?)] = []
    let mut cardinality = PreserveInput
    match @options.input(options) {
      Field(time~, into~) => {
        let rows = match input {
          Some(@carrier.Relation(r)) => r
          _ => fail(source, WrongInput)
        }
        let name : @row.FieldName = if time.has_prefix("left.") ||
          time.has_prefix("right.") {
          let parts = time.split(".").to_array()
          Qualified(
            if parts[0] == "left" {
              Left
            } else {
              Right
            },
            parts[1].to_owned(),
          )
        } else {
          Unqualified(time)
        }
        let at = @decode.lookup(object, "time").unwrap()
        match @carrier.lookup(rows, name) {
          Present({ contract: Some(c), .. }) =>
            if c.nullable || !(c.shape is @contract.Timestamp) {
              fail(at, InvalidTime(time))
            }
          Present(_) | Unknown => fail(at, UnknownFieldType(time))
          Absent => fail(at, MissingField(time))
        }
        let target = @decode.lookup(object, "into").unwrap()
        match @carrier.lookup(rows, Unqualified(into)) {
          Present(_) => fail(target, OutputCollision(into))
          Unknown => fail(target, UnknownOutputFields)
          Absent => ()
        }
        let count = @carrier.field_count(rows)
        if count > work || count > nodes {
          fail(source, BudgetExceeded)
        }
        work -= count
        nodes -= count
        for i in 0..<count {
          let f = @carrier.field_at(rows, i).unwrap()
          fields.push((f.name, f.contract))
        }
        let interval = @contract.object_contract(
          [("start", timestamp), ("end", timestamp)],
          nullable=false,
          max_fields=2,
          max_name_bytes=8,
        ).unwrap()
        fields.push((Unqualified(into), Some(interval)))
      }
      Range(start~, end~) => {
        if input is Some(_) {
          fail(source, WrongInput)
        }
        fields.push((Unqualified("start"), Some(timestamp)))
        fields.push((Unqualified("end"), Some(timestamp)))
        // At most one start per civil unit, plus conservative edge allowance.
        // Folds select one instant; gaps and coincident boundaries cannot add starts.
        let bound = match @options.unit(options) {
          Day => 3652059 + 2
          Week => (3652059 + 6) / 7 + 2
          Month => 9999 * 12 + 2
          Quarter => 9999 * 4 + 2
          Year => 9999 + 2
        }
        cardinality = AtMost(
          if start is Literal(a) && end is Literal(b) && a == b {
            0
          } else {
            bound
          },
        )
      }
    }
    if fields.length() > work || fields.length() > nodes {
      fail(source, BudgetExceeded)
    }
    work -= fields.length()
    nodes -= fields.length()
    for (name, _) in fields {
      match @scalar.admit_utf8_length(@row.reference_name(name), text) {
        Ok(n) => text -= n
        Err(_) => fail(source, BudgetExceeded)
      }
    }
    let rows = match
      @carrier.rows(
        fields,
        field_set=Closed,
        max_fields=fields.length(),
        max_name_bytes=limits.max_text_bytes,
      ) {
      Ok(r) => r
      Err(_) => fail(source, BudgetExceeded)
    }
    Ok({
      input,
      options,
      profile: selected,
      output: @carrier.relation(rows),
      cardinality,
      usage: {
        work: limits.max_work - work,
        nodes: limits.max_nodes - nodes,
        text_bytes: limits.max_text_bytes - text,
      },
    })
  } catch {
    Stop(e) => Err(e)
  }
}

///|
pub fn output(v : CheckedCalendar) -> @carrier.Carrier {
  v.output
}

///|
/// Original bound input; series has no input and cannot transfer row evidence.
pub fn input(v : CheckedCalendar) -> @carrier.Carrier? {
  v.input
}

///|
pub fn source(v : CheckedCalendar) -> @decode.Cursor {
  @options.source(v.options)
}

///|
pub fn options(v : CheckedCalendar) -> @options.Options {
  v.options
}

///|
pub fn profile(v : CheckedCalendar) -> @profile.Profile {
  v.profile
}

///|
pub fn usage(v : CheckedCalendar) -> @options.Usage {
  v.usage
}

///|
pub fn cardinality(v : CheckedCalendar) -> Cardinality {
  v.cardinality
}

///|
pub fn pending_validations(v : CheckedCalendar) -> Array[Obligation] {
  let result : Array[Obligation] = [
    ValidateCalendarValues,
    ValidateBoundaryDomain,
    ResolveResources,
  ]
  if @options.input(v.options) is Range(start~, end~) {
    let mut bound = false
    for endpoint in [start, end] {
      if endpoint is Parameter(name) {
        result.push(BindTimestamp(name))
        bound = true
      }
    }
    if bound {
      result.push(ValidateBoundRange)
    }
  }
  result
}
