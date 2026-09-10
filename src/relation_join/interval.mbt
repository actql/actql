///|
pub(all) enum IntervalMode {
  PointInInterval
  Overlap
} derive(Eq, Debug)

///|
pub(all) enum TemporalOperand {
  Point(@schema.FieldName)
  Interval(@schema.FieldName, @schema.FieldName)
} derive(Eq, Debug)

///|
struct CheckedIntervalJoin {
  source : @decode.Cursor
  output : @schema.Schema
  kind : Kind
  mode : IntervalMode
  left : TemporalOperand
  right : TemporalOperand
  timestamp : Bool
  keys : Array[KeyPair]
  projection : Array[Projection]?
  output_guard : Guard?
  pending : Array[Obligation]
  usage : Usage
}

///|
fn temporal_field(
  b : Budget,
  source : @decode.Cursor,
  schema : @schema.Schema,
  side : @schema.Side,
) -> (@schema.FieldName, Bool) raise Stop {
  let name = decoded(@decode.text(source), source)
  field_name(b, source, name)
  let c = match @schema.lookup(schema, Unqualified(name)) {
    Some(c) => c
    None => fail(source, UnknownField(side, name))
  }
  if c.nullable {
    fail(source, InvalidTemporalField(side, name))
  }
  let timestamp = match c.shape {
    Number => false
    Timestamp => true
    _ => fail(source, InvalidTemporalField(side, name))
  }
  (Unqualified(name), timestamp)
}

///|
pub fn check_interval(
  body : @decode.Cursor,
  left : @schema.Schema,
  right : @schema.Schema,
  parameters : @parameter.Declarations?,
  limits : Limits,
) -> Result[CheckedIntervalJoin, Issue] {
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
    for (side, schema) in [(@schema.Left, left), (@schema.Right, right)] {
      let row = match @schema.as_object(schema) {
        Some(c) => c
        None => fail(body, QualifiedInput(side))
      }
      contract_preflight(b, body, row)
    }
    let params : Map[String, @contract.ParameterType] = Map([])
    if parameters is Some(p) {
      let n = @parameter.declaration_count(p)
      spend(b, body, n~)
      for i in 0..<n {
        let d = @parameter.declaration_at(p, i).unwrap()
        charge(b, body, d.name)
        contract_preflight(b, body, d.parameter_type.contract)
        params[d.name] = d.parameter_type
      }
    }
    let obj = decoded(
      @decode.closed_object(body, [
        "with", "kind", "mode", "on", "left", "right", "select", "max_output_rows",
      ]),
      body,
    )
    ignore(dataflow_name(decoded(@decode.required(obj, "with"), body)))
    let ks = decoded(@decode.required(obj, "kind"), body)
    let kind = match decoded(@decode.text(ks), ks) {
      "inner" => Inner
      "left" => Left
      "semi" => Semi
      "anti" => Anti
      _ => fail(ks, InvalidBody)
    }
    let ms = decoded(@decode.required(obj, "mode"), body)
    let mode = match decoded(@decode.text(ms), ms) {
      "point_in_interval" => PointInInterval
      "overlap" => Overlap
      _ => fail(ms, InvalidBody)
    }
    let on = decoded(@decode.required(obj, "on"), body)
    let pairs = decoded(@decode.elements(on), on)
    spend(b, on, n=pairs.length())
    let keys : Array[KeyPair] = []
    for pair in pairs {
      let p = decoded(@decode.closed_object(pair, ["left", "right"]), pair)
      let ls = decoded(@decode.required(p, "left"), pair)
      let rs = decoded(@decode.required(p, "right"), pair)
      let ln = decoded(@decode.text(ls), ls)
      let rn = decoded(@decode.text(rs), rs)
      field_name(b, ls, ln)
      field_name(b, rs, rn)
      let lc = match @schema.lookup(left, Unqualified(ln)) {
        Some(c) => c
        None => fail(ls, UnknownField(@schema.Left, ln))
      }
      let rc = match @schema.lookup(right, Unqualified(rn)) {
        Some(c) => c
        None => fail(rs, UnknownField(@schema.Right, rn))
      }
      if !@contract.key_comparable(lc, rc) {
        fail(pair, IncomparableKeys(ln, rn))
      }
      keys.push({ left: Unqualified(ln), right: Unqualified(rn), source: pair, })
    }
    let ls = decoded(@decode.required(obj, "left"), body)
    let lo = decoded(
      @decode.closed_object(
        ls,
        if mode == PointInInterval {
          ["time"]
        } else {
          ["start", "end"]
        },
      ),
      ls,
    )
    let first = decoded(
      @decode.required(
        lo,
        if mode == PointInInterval {
          "time"
        } else {
          "start"
        },
      ),
      ls,
    )
    let (lf, timestamp) = temporal_field(b, first, left, @schema.Left)
    let left_operand = if mode == PointInInterval {
      Point(lf)
    } else {
      let es = decoded(@decode.required(lo, "end"), ls)
      let (ef, domain) = temporal_field(b, es, left, @schema.Left)
      if domain != timestamp {
        fail(es, MixedTimeDomains)
      }
      Interval(lf, ef)
    }
    let rs = decoded(@decode.required(obj, "right"), body)
    let ro = decoded(@decode.closed_object(rs, ["start", "end"]), rs)
    let ss = decoded(@decode.required(ro, "start"), rs)
    let es = decoded(@decode.required(ro, "end"), rs)
    let (sf, sd) = temporal_field(b, ss, right, @schema.Right)
    let (ef, ed) = temporal_field(b, es, right, @schema.Right)
    if sd != timestamp {
      fail(ss, MixedTimeDomains)
    }
    if ed != timestamp {
      fail(es, MixedTimeDomains)
    }
    let pending : Array[Obligation] = [
      ValidateIntervalEndpoints,
      ResolveProductBound,
      ResolveOutputLimit,
      ResolveSearchWork,
      PreserveRowOrder,
    ]
    if !timestamp {
      pending.push(ValidateSafeIntegerClocks)
    }
    let output_guard = read_guard(
      @decode.lookup(obj, "max_output_rows"),
      params,
      pending,
    )
    let (output, projection) = join_output(
      b,
      body,
      @decode.lookup(obj, "select"),
      left,
      right,
      kind,
    )
    Ok({
      source: body,
      output,
      kind,
      mode,
      left: left_operand,
      right: Interval(sf, ef),
      timestamp,
      keys,
      projection,
      output_guard,
      pending,
      usage: {
        work: limits.max_work - b.work,
        text_bytes: limits.max_text_bytes - b.text,
        nodes: limits.max_nodes - b.nodes,
      },
    })
  } catch {
    Stop(issue) => Err(issue)
  }
}

///|
pub fn interval_output_schema(v : CheckedIntervalJoin) -> @schema.Schema {
  v.output
}

///|
pub fn interval_source(v : CheckedIntervalJoin) -> @decode.Cursor {
  v.source
}

///|
pub fn interval_kind(v : CheckedIntervalJoin) -> Kind {
  v.kind
}

///|
pub fn interval_mode(v : CheckedIntervalJoin) -> IntervalMode {
  v.mode
}

///|
pub fn interval_operand(
  v : CheckedIntervalJoin,
  side : @schema.Side,
) -> TemporalOperand {
  if side == Left {
    v.left
  } else {
    v.right
  }
}

///|
pub fn interval_uses_timestamps(v : CheckedIntervalJoin) -> Bool {
  v.timestamp
}

///|
pub fn interval_keys(v : CheckedIntervalJoin) -> Array[KeyPair] {
  v.keys.copy()
}

///|
pub fn interval_projection(v : CheckedIntervalJoin) -> Array[Projection]? {
  v.projection.map(p => p.copy())
}

///|
pub fn interval_output_guard(v : CheckedIntervalJoin) -> Guard? {
  v.output_guard
}

///|
pub fn interval_pending_validations(
  v : CheckedIntervalJoin,
) -> Array[Obligation] {
  v.pending.copy()
}

///|
pub fn interval_usage(v : CheckedIntervalJoin) -> Usage {
  v.usage
}
