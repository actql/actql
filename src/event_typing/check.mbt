///|
pub(all) enum Policy {
  Drop
  Mark
} derive(Eq, Debug)

///|
pub(all) enum Obligation {
  ValidateEventValues
  ValidateUniqueIdentities
  ResolveTeaProfile
  ResolveEventResources
  WatermarkClassification
} derive(Eq, Debug)

///|
pub(all) enum IssueKind {
  InvalidLimits
  BudgetExceeded
  InvalidBody
  Decode(@decode.IssueKind)
  WrongCarrier(@carrier.Kind)
  UnknownOutputFields
  OutputCollision(String)
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
} derive(Eq, Debug)

///|
struct CheckedEvent {
  source : @decode.Cursor
  input : @carrier.Carrier
  output : @carrier.Carrier
  watermark : Double
  policy : Policy
  usage : Usage
}

///|
pub fn check_watermark(
  source : @decode.Cursor,
  input : @carrier.Carrier,
  limits : Limits,
) -> Result[CheckedEvent, Issue] {
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
    if @carrier.kind(input) != @carrier.EventsKind {
      fail(source, WrongCarrier(@carrier.kind(input)))
    }
    let object = decoded(
      @decode.closed_object(source, ["watermark_ms", "policy"]),
    )
    let watermark = decoded(
      @decode.finite_number(decoded(@decode.required(object, "watermark_ms"))),
    )
    let policy_source = decoded(@decode.required(object, "policy"))
    let policy = match decoded(@decode.text(policy_source)) {
      "drop" => Drop
      "mark" => Mark
      _ => fail(policy_source, InvalidBody)
    }
    guard input is @carrier.EventValue(e) else {
      fail(source, UnknownOutputFields)
    }
    let generated = [
      ("watermark_ms", @contract.NumberType),
      ("late", @contract.BooleanType),
      ("watermark_decision", @contract.StringType),
    ]
    for (name, _) in generated {
      spend(b, source, 1)
      match @carrier.lookup(e.records, Unqualified(name)) {
        Absent => ()
        Present(_) => fail(source, OutputCollision(name))
        Unknown => fail(source, UnknownOutputFields)
      }
    }
    let fields = []
    let n = @carrier.field_count(e.records)
    spend(b, source, n)
    for i in 0..<n {
      let f = @carrier.field_at(e.records, i).unwrap()
      charge(b, source, @row.reference_name(f.name))
      fields.push((f.name, f.contract))
    }
    for (name, kind) in generated {
      charge(b, source, name)
      fields.push(
        (Unqualified(name), Some(@contract.primitive(kind, nullable=false))),
      )
    }
    let records = match
      @carrier.rows(
        fields,
        field_set=@carrier.field_set(e.records),
        max_fields=fields.length(),
        max_name_bytes=limits.max_text_bytes,
      ) {
      Ok(r) => r
      Err(_) => fail(source, BudgetExceeded)
    }
    let output = match
      @carrier.events(records, id=e.identity.name, time=e.time.name) {
      Ok(c) => c
      Err(_) => fail(source, InvalidBody)
    }
    Ok({
      source,
      input,
      output,
      watermark,
      policy,
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
pub fn source(v : CheckedEvent) -> @decode.Cursor {
  v.source
}

///|
pub fn input(v : CheckedEvent) -> @carrier.Carrier {
  v.input
}

///|
pub fn output(v : CheckedEvent) -> @carrier.Carrier {
  v.output
}

///|
pub fn watermark(v : CheckedEvent) -> Double {
  v.watermark
}

///|
pub fn policy(v : CheckedEvent) -> Policy {
  v.policy
}

///|
pub fn usage(v : CheckedEvent) -> Usage {
  v.usage
}

///|
pub fn pending_validations(_v : CheckedEvent) -> Array[Obligation] {
  [
    ValidateEventValues,
    ValidateUniqueIdentities,
    ResolveTeaProfile,
    ResolveEventResources,
    WatermarkClassification,
  ]
}
