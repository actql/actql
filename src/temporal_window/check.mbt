///|
pub(all) enum Obligation {
  BindMilliseconds(String, Domain)
  ValidateTimeValues
  CheckedWindowArithmetic
  ResolveMembershipBound
  ResolvePublicationResources
} derive(Eq, Debug)

///|
/// Only a successfully checked window operation constructs these roles.
struct WindowRoles {
  start : @row.FieldName
  end : @row.FieldName
}

///|
struct CheckedWindow {
  source : @decode.Cursor
  input : @carrier.Carrier
  output : @carrier.Carrier
  options : Options
  time : @row.FieldName
  timestamp : Bool
  roles : WindowRoles
  pending : Array[Obligation]
  usage : Usage
}

///|
/// Check row_window or window_events against structural Carrier knowledge.
/// The input field set must prove that generated boundaries do not collide;
/// unrelated field types can remain unknown and are shared without traversal.
pub fn check(
  source : @decode.Cursor,
  input : @carrier.Carrier,
  parameters : @parameter.Declarations?,
  limits : Limits,
) -> Result[CheckedWindow, Issue] {
  try {
    let relation = input is @carrier.Relation(_)
    let records = match input {
      @carrier.Relation(k) => k
      @carrier.EventValue(e) => e.records
      _ => fail(source, WrongCarrier)
    }
    let options = match read_options(source, relation~, parameters, limits) {
      Ok(o) => o
      Err(e) => raise Stop(e)
    }
    let b : Budget = {
      limits,
      work: limits.max_work - options.usage.work,
      nodes: limits.max_nodes - options.usage.nodes,
      text: limits.max_text_bytes - options.usage.text_bytes,
    }
    let count = @carrier.field_count(records)
    spend(b, source, count)
    let fields : Array[(@row.FieldName, @contract.Contract?)] = []
    for i in 0..<count {
      let f = @carrier.field_at(records, i).unwrap()
      charge(b, source, @row.reference_name(f.name))
      fields.push((f.name, f.contract))
    }
    let (time, timestamp) = match input {
      @carrier.EventValue(e) => (e.time.name, false)
      _ => {
        let c = options.time.unwrap()
        let name = match @decode.text(c) {
          Ok(s) => s
          Err(_) => fail(c, InvalidBody)
        }
        let mut found = None
        for (key, ty) in fields {
          if @row.reference_name(key) == name {
            found = Some((key, ty))
          }
        }
        let (key, ty) = match found {
          Some((key, Some(ty))) => (key, ty)
          _ => fail(c, UnknownTime(name))
        }
        if ty.nullable {
          fail(c, InvalidTime(name))
        }
        match ty.shape {
          @contract.Number => (key, false)
          @contract.Timestamp => (key, true)
          _ => fail(c, InvalidTime(name))
        }
      }
    }
    let start = if relation { "window_start" } else { "window_start_ms" }
    let end = if relation { "window_end" } else { "window_end_ms" }
    for name in [start, end] {
      match @carrier.lookup(records, Unqualified(name)) {
        @carrier.Absent => ()
        @carrier.Present(_) => fail(source, OutputCollision(name))
        @carrier.Unknown => fail(source, UnknownOutputFields)
      }
      spend(b, source, 1)
      charge(b, source, name)
      fields.push(
        (
          Unqualified(name),
          Some(@contract.primitive(NumberType, nullable=false)),
        ),
      )
    }
    let output_records = match
      @carrier.rows(
        fields,
        field_set=@carrier.field_set(records),
        max_fields=fields.length(),
        max_name_bytes=limits.max_text_bytes,
      ) {
      Ok(k) => k
      Err(_) => fail(source, BudgetExceeded)
    }
    let output = match input {
      @carrier.EventValue(e) =>
        match
          @carrier.events(output_records, id=e.identity.name, time=e.time.name) {
          Ok(c) => c
          Err(_) => fail(source, WrongCarrier)
        }
      _ => @carrier.relation(output_records)
    }
    let pending : Array[Obligation] = [
      ValidateTimeValues,
      CheckedWindowArithmetic,
      ResolveMembershipBound,
      ResolvePublicationResources,
    ]
    let ms = [options.size, options.offset]
    if options.step is Some(s) {
      ms.push(s)
    }
    for value in ms {
      if value is Parameter(name, domain~, ..) {
        pending.push(BindMilliseconds(name, domain))
      }
    }
    Ok({
      source,
      input,
      output,
      options,
      time,
      timestamp,
      roles: { start: Unqualified(start), end: Unqualified(end), },
      pending,
      usage: {
        nodes: options.usage.nodes,
        text_bytes: limits.max_text_bytes - b.text,
        work: limits.max_work - b.work,
      },
    })
  } catch {
    Stop(issue) => Err(issue)
  }
}

///|
pub fn output(value : CheckedWindow) -> @carrier.Carrier {
  value.output
}

///|
pub fn source(value : CheckedWindow) -> @decode.Cursor {
  value.source
}

///|
pub fn input(value : CheckedWindow) -> @carrier.Carrier {
  value.input
}

///|
pub fn options(value : CheckedWindow) -> Options {
  value.options
}

///|
pub fn time_field(value : CheckedWindow) -> @row.FieldName {
  value.time
}

///|
pub fn requires_epoch_milliseconds(value : CheckedWindow) -> Bool {
  value.timestamp
}

///|
pub fn window_roles(value : CheckedWindow) -> WindowRoles {
  value.roles
}

///|
pub fn boundary_fields(value : WindowRoles) -> (@row.FieldName, @row.FieldName) {
  (value.start, value.end)
}

///|
pub fn pending_validations(value : CheckedWindow) -> Array[Obligation] {
  value.pending.copy()
}

///|
pub fn check_usage(value : CheckedWindow) -> Usage {
  value.usage
}
