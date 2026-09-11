///|
pub(all) enum AsOfDirection {
  Backward
  Forward
  Nearest
} derive(Eq, Debug)

///|
struct CheckedAsOf {
  left_records : @carrier.Knowledge
  right_records : @carrier.Knowledge
  left_key : KeyedRelation?
  right_key : KeyedRelation?
  completed_ties : Array[@row.FieldName]
  source : @decode.Cursor
  output : @row.Schema
  kind : @join.Kind
  direction : AsOfDirection
  identity : Array[@row.FieldName]
  left_time : @row.FieldName
  right_time : @row.FieldName
  left_timestamp : Bool
  right_timestamp : Bool
  tolerance : @window.Milliseconds
  keys : Array[@join.KeyPair]
  ties : Array[@row.FieldName]?
  projection : Array[@join.Projection]
  pending : Array[@join.Obligation]
  usage : @join.Usage
}

///|
pub(all) enum AsOfSource {
  CarrierSource(@carrier.Carrier)
  KeySource(KeySet)
}

///|
fn asof_source_parts(value : AsOfSource) -> (@carrier.Carrier, KeySet?) {
  match value {
    CarrierSource(c) => (c, None)
    KeySource(k) => (@carrier.relation(key_set_records(k)), Some(k))
  }
}

///|
fn asof_choose_key(
  b : @join.Budget,
  source : @decode.Cursor,
  keys : KeySet?,
) -> KeyedRelation? raise @join.Stop {
  guard keys is Some(keys) else { return None }
  let selection = match
    select_key(source, keys, CanonicalOrder, {
      max_work: b.work,
      max_name_bytes: b.text,
    }) {
    Ok(v) => v
    Err(_) => @join.fail(source, BudgetExceeded)
  }
  b.work -= selection.work
  b.text -= selection.name_bytes
  selection.key
}

///|
fn asof_field(
  b : @join.Budget,
  s : @decode.Cursor,
  rows : @carrier.Knowledge,
  side : @row.Side,
) -> (@row.FieldName, @contract.Contract) raise @join.Stop {
  let name = @join.decoded(@decode.text(s), s)
  @join.field_name(b, s, name)
  let field = @row.Unqualified(name)
  match @carrier.lookup(rows, field) {
    Present({ contract: Some(c), .. }) => (field, c)
    Present(_) => @join.fail(s, UnknownFieldType(side, name))
    Unknown => @join.fail(s, UnknownFieldType(side, name))
    Absent => @join.fail(s, UnknownField(side, name))
  }
}

///|
fn asof_clock(
  c : @contract.Contract,
  field : @row.FieldName,
  s : @decode.Cursor,
  side : @row.Side,
) -> Bool raise @join.Stop {
  if c.nullable {
    @join.fail(s, InvalidTemporalField(side, @row.reference_name(field)))
  }
  match c.shape {
    Number => false
    Timestamp => true
    _ => @join.fail(s, InvalidTemporalField(side, @row.reference_name(field)))
  }
}

///|
/// Snapshot only known field types. Unknown unselected payload is not guessed.
fn asof_known(
  b : @join.Budget,
  s : @decode.Cursor,
  rows : @carrier.Knowledge,
) -> @row.Schema raise @join.Stop {
  let fields = []
  let n = @carrier.field_count(rows)
  @join.spend(b, s, n~)
  for i in 0..<n {
    let f = @carrier.field_at(rows, i).unwrap()
    @join.charge(b, s, @row.reference_name(f.name))
    if f.contract is Some(c) {
      @join.contract_preflight(b, s, c)
      fields.push((f.name, c))
    }
  }
  @join.make_schema(b, s, fields)
}

///|
pub fn check_asof(
  body : @decode.Cursor,
  left : @carrier.Carrier,
  right : @carrier.Carrier,
  parameters : @parameter.Declarations?,
  limits : @join.Limits,
) -> Result[CheckedAsOf, @join.Issue] {
  check_asof_sources(
    body,
    CarrierSource(left),
    CarrierSource(right),
    parameters,
    limits,
  )
}

///|
pub fn check_asof_sources(
  body : @decode.Cursor,
  left_source : AsOfSource,
  right_source : AsOfSource,
  parameters : @parameter.Declarations?,
  limits : @join.Limits,
) -> Result[CheckedAsOf, @join.Issue] {
  try {
    if limits.max_work < 0 ||
      limits.max_text_bytes < 0 ||
      limits.max_nodes < 0 ||
      limits.max_depth < 0 {
      @join.fail(body, InvalidLimits)
    }
    let b : @join.Budget = {
      limits,
      work: limits.max_work,
      text: limits.max_text_bytes,
      nodes: limits.max_nodes,
    }
    @join.source_preflight(b, body)
    let obj = @join.decoded(
      @decode.closed_object(body, [
        "with", "kind", "by", "left_id", "left_time", "right_time", "direction",
        "tolerance", "right_tie_break", "select",
      ]),
      body,
    )
    let with_source = @join.decoded(@decode.required(obj, "with"), body)
    ignore(@join.dataflow_name(with_source))
    let (left, left_keys) = asof_source_parts(left_source)
    let (right, right_keys) = asof_source_parts(right_source)
    let (left_rows, event_identity) = match left {
      Relation(rows) => (rows, None)
      EventValue(e) => (e.records, Some(e.identity.name))
      _ => @join.fail(body, WrongCarrier(@row.Left, @carrier.kind(left)))
    }
    let right_rows = match right {
      Relation(rows) => rows
      _ =>
        @join.fail(with_source, WrongCarrier(@row.Right, @carrier.kind(right)))
    }
    let left_schema = asof_known(b, body, left_rows)
    let right_schema = asof_known(b, with_source, right_rows)
    let ks = @join.decoded(@decode.required(obj, "kind"), body)
    let kind = match @join.decoded(@decode.text(ks), ks) {
      "left" => @join.Left
      "inner" => @join.Inner
      _ => @join.fail(ks, InvalidBody)
    }
    let ds = @join.decoded(@decode.required(obj, "direction"), body)
    let direction = match @join.decoded(@decode.text(ds), ds) {
      "backward" => Backward
      "forward" => Forward
      "nearest" => Nearest
      _ => @join.fail(ds, InvalidBody)
    }
    let mut left_key = None
    let identity = match @decode.lookup(obj, "left_id") {
      Some(s) => {
        let (f, c) = asof_field(b, s, left_rows, @row.Left)
        if c.nullable || !@contract.key_comparable(c, c) {
          @join.fail(s, InvalidLeftIdentity)
        }
        if event_identity is Some(expected) && expected != f {
          @join.fail(s, InvalidLeftIdentity)
        }
        [f]
      }
      None =>
        match event_identity {
          Some(f) => [f]
          None => {
            guard asof_choose_key(b, body, left_keys) is Some(key) else {
              @join.fail(body, MissingLeftIdentity)
            }
            left_key = Some(key)
            let count = key_field_count(key)
            @join.spend(b, body, n=count)
            Array::makei(count, i => key_field_at(key, i).unwrap().name)
          }
        }
    }
    let ls = @join.decoded(@decode.required(obj, "left_time"), body)
    let rs = @join.decoded(@decode.required(obj, "right_time"), body)
    let (left_time, lc) = asof_field(b, ls, left_rows, @row.Left)
    let (right_time, rc) = asof_field(b, rs, right_rows, @row.Right)
    let left_timestamp = asof_clock(lc, left_time, ls, @row.Left)
    let right_timestamp = asof_clock(rc, right_time, rs, @row.Right)
    let by = @join.decoded(@decode.required(obj, "by"), body)
    let pairs = @join.decoded(@decode.elements(by), by)
    @join.spend(b, by, n=pairs.length())
    let keys : Array[@join.KeyPair] = []
    for pair in pairs {
      let p = @join.decoded(
        @decode.closed_object(pair, ["left", "right"]),
        pair,
      )
      let (lf, lc) = asof_field(
        b,
        @join.decoded(@decode.required(p, "left"), pair),
        left_rows,
        @row.Left,
      )
      let (rf, rc) = asof_field(
        b,
        @join.decoded(@decode.required(p, "right"), pair),
        right_rows,
        @row.Right,
      )
      if !@contract.key_comparable(lc, rc) {
        @join.fail(
          pair,
          IncomparableKeys(@row.reference_name(lf), @row.reference_name(rf)),
        )
      }
      keys.push({ left: lf, right: rf, source: pair, })
    }
    let ties = match @decode.lookup(obj, "right_tie_break") {
      None => None
      Some(s) => {
        let terms = @join.decoded(@decode.elements(s), s)
        @join.spend(b, s, n=terms.length())
        let fields = []
        for term in terms {
          let (f, c) = asof_field(b, term, right_rows, @row.Right)
          if !@order.author_orderable(c) {
            @join.fail(term, InvalidTieField(@row.reference_name(f)))
          }
          fields.push(f)
        }
        Some(fields)
      }
    }
    let right_key = asof_choose_key(b, with_source, right_keys)
    let completed_ties = ties.map(fields => fields.copy()).unwrap_or([])
    @join.spend(b, body, n=completed_ties.length())
    let seen : Map[String, Bool] = Map([])
    for field in completed_ties {
      seen[@row.reference_name(field)] = true
    }
    let mut appended = false
    if right_key is Some(key) {
      @join.spend(b, body, n=key_field_count(key))
      for i in 0..<key_field_count(key) {
        let field = key_field_at(key, i).unwrap().name
        let name = @row.reference_name(field)
        @join.charge(b, body, name)
        if !seen.contains(name) {
          completed_ties.push(field)
          seen[name] = true
          appended = true
        }
      }
    }
    let ts = @join.decoded(@decode.required(obj, "tolerance"), body)
    let tolerance = match
      @window.read_milliseconds(ts, PositiveMilliseconds, parameters, {
        max_work: b.work,
        max_nodes: b.nodes,
        max_text_bytes: b.text,
        max_depth: limits.max_depth,
      }) {
      Ok(v) => v
      Err(e) =>
        raise @join.Stop({
          kind: Temporal(e.kind),
          source: ts,
          path: e.path.copy(),
          span: e.span,
        })
    }
    let used = @window.milliseconds_usage(tolerance)
    b.work -= used.work
    b.nodes -= used.nodes
    b.text -= used.text_bytes
    let tolerance = @window.milliseconds_value(tolerance)
    let selected = @join.decoded(@decode.required(obj, "select"), body)
    let (output, projection) = @join.join_output(
      b,
      body,
      Some(selected),
      left_schema,
      right_schema,
      kind,
    )
    let pending : Array[@join.Obligation] = [
      ValidateAsOfValues,
      StableIdentity(@row.Left),
      RejectAsOfTies,
      ResolveAsOfOrder,
      ResolveSearchWork,
      ResolveOutputLimit,
      ResolveTeaProfile,
    ]
    if tolerance is @window.Parameter(name, ..) {
      pending.push(BindTolerance(name))
    }
    for (side, key) in [(@row.Left, left_key), (@row.Right, right_key)] {
      if key is Some(key) {
        for obligation in key_pending(key) {
          pending.push(ValidateAsOfKey(side, obligation))
        }
      }
    }
    if left_key is Some(_) {
      pending.push(JournalAsOfKeyCompletion(@row.Left))
    }
    if appended {
      pending.push(JournalAsOfKeyCompletion(@row.Right))
    }
    Ok({
      left_records: left_rows,
      right_records: right_rows,
      left_key,
      right_key,
      completed_ties,
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
    @join.Stop(e) => Err(e)
  }
}

///|
pub fn asof_output_schema(v : CheckedAsOf) -> @row.Schema {
  v.output
}

///|
/// Original input knowledge, not the typed-only snapshot used for projection.
/// Retains exact source binding and unknown/untyped field distinctions.
pub fn asof_input_records(
  v : CheckedAsOf,
  side : @row.Side,
) -> @carrier.Knowledge {
  if side == Left {
    v.left_records
  } else {
    v.right_records
  }
}

///|
pub fn asof_projection_count(v : CheckedAsOf) -> Int {
  v.projection.length()
}

///|
pub fn asof_projection_at(v : CheckedAsOf, index : Int) -> @join.Projection? {
  v.projection.get(index)
}

///|
pub fn asof_kind(v : CheckedAsOf) -> @join.Kind {
  v.kind
}

///|
pub fn asof_direction(v : CheckedAsOf) -> AsOfDirection {
  v.direction
}

///|
pub fn asof_identity(v : CheckedAsOf) -> Array[@row.FieldName] {
  v.identity.copy()
}

///|
pub fn asof_time(v : CheckedAsOf, side : @row.Side) -> @row.FieldName {
  if side == Left {
    v.left_time
  } else {
    v.right_time
  }
}

///|
pub fn asof_uses_timestamp(v : CheckedAsOf, side : @row.Side) -> Bool {
  if side == Left {
    v.left_timestamp
  } else {
    v.right_timestamp
  }
}

///|
pub fn asof_tolerance(v : CheckedAsOf) -> @window.Milliseconds {
  v.tolerance
}

///|
pub fn asof_keys(v : CheckedAsOf) -> Array[@join.KeyPair] {
  v.keys.copy()
}

///|
pub fn asof_tie_break(v : CheckedAsOf) -> Array[@row.FieldName]? {
  v.ties.map(a => a.copy())
}

///|
/// Authored terms followed by missing canonical key fields; internal Ref order
/// is not exposed as an authored order option.
pub fn asof_completed_tie_break(v : CheckedAsOf) -> Array[@row.FieldName] {
  v.completed_ties.copy()
}

///|
pub fn asof_key_completion(v : CheckedAsOf, side : @row.Side) -> KeyedRelation? {
  if side == Left {
    v.left_key
  } else {
    v.right_key
  }
}

///|
pub fn asof_projection(v : CheckedAsOf) -> Array[@join.Projection] {
  v.projection.copy()
}

///|
pub fn asof_pending_validations(v : CheckedAsOf) -> Array[@join.Obligation] {
  v.pending.copy()
}

///|
pub fn asof_usage(v : CheckedAsOf) -> @join.Usage {
  v.usage
}

///|
pub fn asof_source(v : CheckedAsOf) -> @decode.Cursor {
  v.source
}
