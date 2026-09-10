///|
pub(all) enum AsOfDirection {
  Backward
  Forward
  Nearest
} derive(Eq, Debug)

///|
struct CheckedAsOf {
  source : @decode.Cursor
  output : @schema.Schema
  kind : Kind
  direction : AsOfDirection
  identity : Array[@schema.FieldName]
  left_time : @schema.FieldName
  right_time : @schema.FieldName
  left_timestamp : Bool
  right_timestamp : Bool
  tolerance : @temporal.Milliseconds
  keys : Array[KeyPair]
  ties : Array[@schema.FieldName]?
  projection : Array[Projection]
  pending : Array[Obligation]
  usage : Usage
}

///|
fn asof_field(
  b : Budget,
  s : @decode.Cursor,
  rows : @carrier.Knowledge,
  side : @schema.Side,
) -> (@schema.FieldName, @contract.Contract) raise Stop {
  let name = decoded(@decode.text(s), s)
  field_name(b, s, name)
  let field = @schema.Unqualified(name)
  match @carrier.lookup(rows, field) {
    Present({ contract: Some(c), .. }) => (field, c)
    Present(_) => fail(s, UnknownFieldType(side, name))
    Unknown => fail(s, UnknownFieldType(side, name))
    Absent => fail(s, UnknownField(side, name))
  }
}

///|
fn asof_clock(
  c : @contract.Contract,
  field : @schema.FieldName,
  s : @decode.Cursor,
  side : @schema.Side,
) -> Bool raise Stop {
  if c.nullable {
    fail(s, InvalidTemporalField(side, @schema.reference_name(field)))
  }
  match c.shape {
    Number => false
    Timestamp => true
    _ => fail(s, InvalidTemporalField(side, @schema.reference_name(field)))
  }
}

///|
/// Snapshot only known field types. Unknown unselected payload is not guessed.
fn asof_known(
  b : Budget,
  s : @decode.Cursor,
  rows : @carrier.Knowledge,
) -> @schema.Schema raise Stop {
  let fields = []
  let n = @carrier.field_count(rows)
  spend(b, s, n~)
  for i in 0..<n {
    let f = @carrier.field_at(rows, i).unwrap()
    charge(b, s, @schema.reference_name(f.name))
    if f.contract is Some(c) {
      contract_preflight(b, s, c)
      fields.push((f.name, c))
    }
  }
  make_schema(b, s, fields)
}

///|
pub fn check_asof(
  body : @decode.Cursor,
  left : @carrier.Carrier,
  right : @carrier.Carrier,
  parameters : @parameter.Declarations?,
  limits : Limits,
) -> Result[CheckedAsOf, Issue] {
  try {
    if limits.max_work < 0 ||
      limits.max_text_bytes < 0 ||
      limits.max_nodes < 0 ||
      limits.max_depth < 0 {
      fail(body, InvalidLimits)
    }
    let b : Budget = {
      limits,
      work: limits.max_work,
      text: limits.max_text_bytes,
      nodes: limits.max_nodes,
    }
    source_preflight(b, body)
    let obj = decoded(
      @decode.closed_object(body, [
        "with", "kind", "by", "left_id", "left_time", "right_time", "direction",
        "tolerance", "right_tie_break", "select",
      ]),
      body,
    )
    let with_source = decoded(@decode.required(obj, "with"), body)
    ignore(dataflow_name(with_source))
    let (left_rows, event_identity) = match left {
      Relation(rows) => (rows, None)
      EventValue(e) => (e.records, Some(e.identity.name))
      _ => fail(body, WrongCarrier(@schema.Left, @carrier.kind(left)))
    }
    let right_rows = match right {
      Relation(rows) => rows
      _ => fail(with_source, WrongCarrier(@schema.Right, @carrier.kind(right)))
    }
    let left_schema = asof_known(b, body, left_rows)
    let right_schema = asof_known(b, with_source, right_rows)
    let ks = decoded(@decode.required(obj, "kind"), body)
    let kind = match decoded(@decode.text(ks), ks) {
      "left" => Left
      "inner" => Inner
      _ => fail(ks, InvalidBody)
    }
    let ds = decoded(@decode.required(obj, "direction"), body)
    let direction = match decoded(@decode.text(ds), ds) {
      "backward" => Backward
      "forward" => Forward
      "nearest" => Nearest
      _ => fail(ds, InvalidBody)
    }
    let identity = match @decode.lookup(obj, "left_id") {
      Some(s) => {
        let (f, c) = asof_field(b, s, left_rows, @schema.Left)
        if c.nullable || !@contract.key_comparable(c, c) {
          fail(s, InvalidLeftIdentity)
        }
        if event_identity is Some(expected) && expected != f {
          fail(s, InvalidLeftIdentity)
        }
        [f]
      }
      None =>
        match event_identity {
          Some(f) => [f]
          None => fail(body, MissingLeftIdentity)
        }
    }
    let ls = decoded(@decode.required(obj, "left_time"), body)
    let rs = decoded(@decode.required(obj, "right_time"), body)
    let (left_time, lc) = asof_field(b, ls, left_rows, @schema.Left)
    let (right_time, rc) = asof_field(b, rs, right_rows, @schema.Right)
    let left_timestamp = asof_clock(lc, left_time, ls, @schema.Left)
    let right_timestamp = asof_clock(rc, right_time, rs, @schema.Right)
    let by = decoded(@decode.required(obj, "by"), body)
    let pairs = decoded(@decode.elements(by), by)
    spend(b, by, n=pairs.length())
    let keys : Array[KeyPair] = []
    for pair in pairs {
      let p = decoded(@decode.closed_object(pair, ["left", "right"]), pair)
      let (lf, lc) = asof_field(
        b,
        decoded(@decode.required(p, "left"), pair),
        left_rows,
        @schema.Left,
      )
      let (rf, rc) = asof_field(
        b,
        decoded(@decode.required(p, "right"), pair),
        right_rows,
        @schema.Right,
      )
      if !@contract.key_comparable(lc, rc) {
        fail(
          pair,
          IncomparableKeys(
            @schema.reference_name(lf),
            @schema.reference_name(rf),
          ),
        )
      }
      keys.push({ left: lf, right: rf, source: pair, })
    }
    let ties = match @decode.lookup(obj, "right_tie_break") {
      None => None
      Some(s) => {
        let terms = decoded(@decode.elements(s), s)
        spend(b, s, n=terms.length())
        let fields = []
        for term in terms {
          let (f, c) = asof_field(b, term, right_rows, @schema.Right)
          if !@order.author_orderable(c) {
            fail(term, InvalidTieField(@schema.reference_name(f)))
          }
          fields.push(f)
        }
        Some(fields)
      }
    }
    let ts = decoded(@decode.required(obj, "tolerance"), body)
    let tolerance = match
      @temporal.read_milliseconds(ts, PositiveMilliseconds, parameters, {
        max_work: b.work,
        max_nodes: b.nodes,
        max_text_bytes: b.text,
        max_depth: limits.max_depth,
      }) {
      Ok(v) => v
      Err(e) =>
        raise Stop({
          kind: Temporal(e.kind),
          source: ts,
          path: e.path.copy(),
          span: e.span,
        })
    }
    let used = @temporal.milliseconds_usage(tolerance)
    b.work -= used.work
    b.nodes -= used.nodes
    b.text -= used.text_bytes
    let tolerance = @temporal.milliseconds_value(tolerance)
    let selected = decoded(@decode.required(obj, "select"), body)
    let (output, projection) = join_output(
      b,
      body,
      Some(selected),
      left_schema,
      right_schema,
      kind,
    )
    let pending : Array[Obligation] = [
      ValidateAsOfValues,
      StableIdentity(@schema.Left),
      RejectAsOfTies,
      ResolveAsOfOrder,
      ResolveSearchWork,
      ResolveOutputLimit,
      ResolveTeaProfile,
    ]
    if tolerance is @temporal.Parameter(name, ..) {
      pending.push(BindTolerance(name))
    }
    Ok({
      source: body,
      output,
      kind,
      direction,
      identity,
      left_time,
      right_time,
      left_timestamp,
      right_timestamp,
      tolerance,
      keys,
      ties,
      projection: projection.unwrap(),
      pending,
      usage: {
        work: limits.max_work - b.work,
        text_bytes: limits.max_text_bytes - b.text,
        nodes: limits.max_nodes - b.nodes,
      },
    })
  } catch {
    Stop(e) => Err(e)
  }
}

///|
pub fn asof_output_schema(v : CheckedAsOf) -> @schema.Schema {
  v.output
}

///|
pub fn asof_kind(v : CheckedAsOf) -> Kind {
  v.kind
}

///|
pub fn asof_direction(v : CheckedAsOf) -> AsOfDirection {
  v.direction
}

///|
pub fn asof_identity(v : CheckedAsOf) -> Array[@schema.FieldName] {
  v.identity.copy()
}

///|
pub fn asof_time(v : CheckedAsOf, side : @schema.Side) -> @schema.FieldName {
  if side == Left {
    v.left_time
  } else {
    v.right_time
  }
}

///|
pub fn asof_uses_timestamp(v : CheckedAsOf, side : @schema.Side) -> Bool {
  if side == Left {
    v.left_timestamp
  } else {
    v.right_timestamp
  }
}

///|
pub fn asof_tolerance(v : CheckedAsOf) -> @temporal.Milliseconds {
  v.tolerance
}

///|
pub fn asof_keys(v : CheckedAsOf) -> Array[KeyPair] {
  v.keys.copy()
}

///|
pub fn asof_tie_break(v : CheckedAsOf) -> Array[@schema.FieldName]? {
  v.ties.map(a => a.copy())
}

///|
pub fn asof_projection(v : CheckedAsOf) -> Array[Projection] {
  v.projection.copy()
}

///|
pub fn asof_pending_validations(v : CheckedAsOf) -> Array[Obligation] {
  v.pending.copy()
}

///|
pub fn asof_usage(v : CheckedAsOf) -> Usage {
  v.usage
}

///|
pub fn asof_source(v : CheckedAsOf) -> @decode.Cursor {
  v.source
}
