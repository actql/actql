///|
pub(all) enum SequenceOverlap {
  Allow
  Disallow
} derive(Eq, Debug)

///|
pub(all) enum SequenceContiguity {
  Adjacent
  Subsequence
} derive(Eq, Debug)

///|
pub(all) enum SequenceObligation {
  ValidateEventValues
  UniqueEventIdentity
  AscendingEventOrder
  BoundedMatchSearch
  AtomicMatchLimits
  TeaProfile
  BindWithin(String)
} derive(Eq, Debug)

///|
pub struct SequencePattern {
  label : String
  predicate : @typing.TypedExpression
  source : @decode.Cursor
}

///|
pub(all) struct SequenceUsage {
  work : Int
  nodes : Int
  text_bytes : Int
  tokens : Int
} derive(Eq, Debug)

///|
struct CheckedSequence {
  source : @decode.Cursor
  output : @schema.Schema
  keys : Array[KeyField]
  identity : @schema.FieldName
  time : @schema.FieldName
  timestamp : Bool
  pattern : Array[SequencePattern]
  within : @temporal.Milliseconds
  overlap : SequenceOverlap
  contiguity : SequenceContiguity
  per_key : CountValue?
  total : CountValue?
  pending : Array[PendingValidation]
  obligations : Array[SequenceObligation]
  usage : SequenceUsage
}

///|
pub fn check_sequence(
  body : @decode.Cursor,
  input : @carrier.Carrier,
  parameters : @parameter.Declarations?,
  limits : Limits,
) -> Result[CheckedSequence, Issue] {
  try {
    if limits.max_work < 0 ||
      limits.max_text_bytes < 0 ||
      limits.max_nodes < 0 ||
      limits.max_depth < 0 ||
      limits.max_tokens < 0 {
      fail(body, InvalidLimits)
    }
    let b : Budget = {
      limits,
      work: limits.max_work,
      text: limits.max_text_bytes,
      nodes: limits.max_nodes,
      tokens: limits.max_tokens,
    }
    row_source(b, body)
    let (records, event_id) = match input {
      Relation(rows) => (rows, None)
      EventValue(e) => (e.records, Some(e.identity.name))
      _ => fail(body, WrongCarrier(@carrier.kind(input)))
    }
    let visible : Map[String, (@contract.Contract, ReferenceTarget)] = Map([])
    let n = @carrier.field_count(records)
    spend(b, body, count=n)
    for i in 0..<n {
      let f = @carrier.field_at(records, i).unwrap()
      charge(b, body, @schema.reference_name(f.name))
      if f.contract is Some(c) {
        preflight(b, body, c)
        visible[@schema.reference_name(f.name)] = (c, InputField(f.name))
      }
    }
    let params : Map[String, @contract.Contract] = Map([])
    if parameters is Some(p) {
      let n = @parameter.declaration_count(p)
      spend(b, body, count=n)
      for i in 0..<n {
        let d = @parameter.declaration_at(p, i).unwrap()
        charge(b, body, d.name)
        preflight(b, body, d.parameter_type.contract)
        params[d.name] = d.parameter_type.contract
      }
    }
    let obj = decoded(
      @decode.closed_object(body, [
        "by", "time", "id", "pattern", "within", "overlap", "contiguity", "max_matches_per_key",
        "max_output_rows",
      ]),
      body,
    )
    let ids = decoded(@decode.required(obj, "id"), body)
    let id_name = decoded(@decode.text(ids), ids)
    let identity = input_reference(b, ids, id_name, visible)
    let identity_type = visible.get(id_name).unwrap().0
    if identity_type.nullable ||
      !@contract.key_comparable(identity_type, identity_type) {
      fail(ids, InvalidEventIdentity)
    }
    if event_id is Some(expected) && expected != identity {
      fail(ids, InvalidEventIdentity)
    }
    let ts = decoded(@decode.required(obj, "time"), body)
    let time_name = decoded(@decode.text(ts), ts)
    let time = input_reference(b, ts, time_name, visible)
    let time_type = visible.get(time_name).unwrap().0
    if time_type.nullable {
      fail(ts, IncompatibleColumn(time_name))
    }
    let timestamp = match time_type.shape {
      Number => false
      Timestamp if event_id is None => true
      _ => fail(ts, IncompatibleColumn(time_name))
    }
    let by = decoded(@decode.required(obj, "by"), body)
    let sources = decoded(@decode.elements(by), by)
    let keys : Array[KeyField] = []
    let output : Array[(@schema.FieldName, @contract.Contract)] = []
    let seen : Map[String, Bool] = Map([])
    for s in sources {
      let name = decoded(@decode.text(s), s)
      let field = input_reference(b, s, name, visible)
      let c = visible.get(name).unwrap().0
      if !@contract.key_comparable(c, c) {
        fail(s, NotKeyComparable(name))
      }
      keys.push({ field, source: s, })
      if !seen.contains(name) {
        seen[name] = true
        output.push((field, c))
      }
    }
    let os = decoded(@decode.required(obj, "overlap"), body)
    let overlap = match decoded(@decode.text(os), os) {
      "allow" => Allow
      "disallow" => Disallow
      _ => fail(os, InvalidBody)
    }
    let cs = decoded(@decode.required(obj, "contiguity"), body)
    let contiguity = match decoded(@decode.text(cs), cs) {
      "adjacent" => Adjacent
      "subsequence" => Subsequence
      _ => fail(cs, InvalidBody)
    }
    let ps = decoded(@decode.required(obj, "pattern"), body)
    let parts = decoded(@decode.elements(ps), ps)
    if parts.length() < 2 {
      fail(ps, InvalidBody)
    }
    spend(b, ps, count=parts.length())
    let labels : Map[String, Bool] = Map([])
    let pattern : Array[SequencePattern] = []
    let generated = [
      ("match_start_ms", @contract.primitive(NumberType, nullable=false), body),
      ("match_end_ms", @contract.primitive(NumberType, nullable=false), body),
    ]
    for part in parts {
      let p = decoded(@decode.closed_object(part, ["as", "where"]), part)
      let ls = decoded(@decode.required(p, "as"), part)
      let label = decoded(@decode.text(ls), ls)
      if label.is_empty() {
        fail(ls, InvalidName(label))
      }
      if labels.contains(label) {
        fail(ls, DuplicatePatternLabel(label))
      }
      labels[label] = true
      charge(b, ls, label)
      let where_source = decoded(@decode.required(p, "where"), part)
      let binding = expression(b, where_source, None, visible, parameters)
      if !(@typing.result_type(binding.expression).shape is @contract.Boolean) {
        fail(where_source, ExpectedBoolean)
      }
      pattern.push({ label, predicate: binding.expression, source: part, })
      generated.push((label + "_id", identity_type, ls))
      generated.push(
        (
          label + "_time_ms",
          @contract.primitive(NumberType, nullable=false),
          ls,
        ),
      )
    }
    for (name, c, s) in generated {
      field_name(b, s, name)
      if seen.contains(name) {
        fail(s, DuplicateOutput(name))
      }
      seen[name] = true
      output.push((Unqualified(name), c))
    }
    let ws = decoded(@decode.required(obj, "within"), body)
    let within = match
      @temporal.read_milliseconds(ws, PositiveMilliseconds, parameters, {
        max_work: b.work,
        max_nodes: b.nodes,
        max_text_bytes: b.text,
        max_depth: limits.max_depth,
      }) {
      Ok(v) => v
      Err(e) =>
        raise Stop({
          kind: Temporal(e.kind),
          source: ws,
          path: e.path.copy(),
          span: e.span,
          range: None,
        })
    }
    let u = @temporal.milliseconds_usage(within)
    b.work -= u.work
    b.nodes -= u.nodes
    b.text -= u.text_bytes
    let within = @temporal.milliseconds_value(within)
    let pending : Array[PendingValidation] = []
    let per_key = @decode.lookup(obj, "max_matches_per_key").map(s => {
      row_count(b, s, 1L, params, pending)
    })
    let total = @decode.lookup(obj, "max_output_rows").map(s => {
      row_count(b, s, 1L, params, pending)
    })
    let output = schema_type(b, body, output)
    let obligations : Array[SequenceObligation] = [
      ValidateEventValues,
      UniqueEventIdentity,
      AscendingEventOrder,
      BoundedMatchSearch,
      AtomicMatchLimits,
      TeaProfile,
    ]
    if within is @temporal.Parameter(name, ..) {
      obligations.push(BindWithin(name))
    }
    Ok({
      source: body,
      output,
      keys,
      identity,
      time,
      timestamp,
      pattern,
      within,
      overlap,
      contiguity,
      per_key,
      total,
      pending,
      obligations,
      usage: {
        work: limits.max_work - b.work,
        nodes: limits.max_nodes - b.nodes,
        text_bytes: limits.max_text_bytes - b.text,
        tokens: limits.max_tokens - b.tokens,
      },
    })
  } catch {
    Stop(e) => Err(e)
  }
}

///|
pub fn sequence_output(v : CheckedSequence) -> @schema.Schema {
  v.output
}

///|
pub fn sequence_source(v : CheckedSequence) -> @decode.Cursor {
  v.source
}

///|
pub fn sequence_keys(v : CheckedSequence) -> Array[KeyField] {
  v.keys.copy()
}

///|
pub fn sequence_identity(v : CheckedSequence) -> @schema.FieldName {
  v.identity
}

///|
pub fn sequence_time(v : CheckedSequence) -> @schema.FieldName {
  v.time
}

///|
pub fn sequence_requires_timestamp_conversion(v : CheckedSequence) -> Bool {
  v.timestamp
}

///|
pub fn sequence_pattern(v : CheckedSequence) -> Array[SequencePattern] {
  v.pattern.copy()
}

///|
pub fn sequence_pattern_count(v : CheckedSequence) -> Int {
  v.pattern.length()
}

///|
pub fn sequence_pattern_at(
  v : CheckedSequence,
  index : Int,
) -> SequencePattern? {
  v.pattern.get(index)
}

///|
pub fn sequence_within(v : CheckedSequence) -> @temporal.Milliseconds {
  v.within
}

///|
pub fn sequence_overlap(v : CheckedSequence) -> SequenceOverlap {
  v.overlap
}

///|
pub fn sequence_contiguity(v : CheckedSequence) -> SequenceContiguity {
  v.contiguity
}

///|
pub fn sequence_per_key_guard(v : CheckedSequence) -> CountValue? {
  v.per_key
}

///|
pub fn sequence_output_guard(v : CheckedSequence) -> CountValue? {
  v.total
}

///|
pub fn sequence_pending_validations(
  v : CheckedSequence,
) -> Array[PendingValidation] {
  v.pending.copy()
}

///|
pub fn sequence_obligations(v : CheckedSequence) -> Array[SequenceObligation] {
  v.obligations.copy()
}

///|
pub fn sequence_usage(v : CheckedSequence) -> SequenceUsage {
  v.usage
}
