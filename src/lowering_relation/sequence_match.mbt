///|
/// Owner-bound lowering material for one checked finite sequence match.
/// Predicates are lowered once in authored pattern order.
struct PreparedSequenceMatch {
  owner : BoundPrepared
  step : Int
  checked : @relation.CheckedSequence
  predicates : Array[Expression]
  within : Int64
  per_key_limit : Int64?
  output_limit : Int64?
}

///|
pub(all) enum SequenceMatchIssue {
  InvalidSequenceMatchLimits
  InvalidSequenceMatchWiring
  SequenceMatchPreparationLimit
  SequenceMatchExpression(ExpressionIssue)
  MissingSequenceMatchParameter(String)
  InvalidSequenceMatchParameter(String)
}

///|
fn resolve_sequence_count(
  owner : BoundPrepared,
  value : @relation.CountValue?,
  remaining_names : Int,
) -> Result[(Int64?, Int, Int), SequenceMatchIssue] {
  match value {
    None => Ok((None, 0, 0))
    Some(@relation.Literal(value)) => Ok((Some(value), 0, 0))
    Some(@relation.Parameter(name)) => {
      let bytes = @utf8.encode(name).length()
      if bytes > remaining_names {
        return Err(SequenceMatchPreparationLimit)
      }
      guard parameter_value(owner, name) is Some(bound) else {
        return Err(MissingSequenceMatchParameter(name))
      }
      guard bound.value is @value.Number(number) &&
        @scalar.read_safe_integer(number) is Some(value) &&
        value >= 1L else {
        return Err(InvalidSequenceMatchParameter(name))
      }
      Ok((Some(value), 1, bytes))
    }
  }
}

///|
fn prepare_sequence_match(
  owner : BoundPrepared,
  step : Int,
  max_entries~ : Int,
  max_name_bytes~ : Int,
  expressions~ : ExpressionLimits,
) -> Result[
  (PreparedSequenceMatch, Int, Int, ExpressionLimits),
  SequenceMatchIssue,
] {
  if max_entries < 0 || max_name_bytes < 0 {
    return Err(InvalidSequenceMatchLimits)
  }
  guard owner.prepared.nodes.get(step) is Some(node) &&
    node.payload is SequenceRows(checked) &&
    node.inputs.length() == 1 else {
    return Err(InvalidSequenceMatchWiring)
  }
  let pattern_count = @relation.sequence_pattern_count(checked)
  let key_count = @relation.sequence_keys(checked).length()
  let mut entries = key_count + 2 + pattern_count
  if entries > max_entries {
    return Err(SequenceMatchPreparationLimit)
  }
  let mut names = 0
  let spend = fn(name : String) -> Bool {
    let bytes = @utf8.encode(name).length()
    if bytes > max_name_bytes - names {
      return false
    }
    names += bytes
    true
  }
  for key in @relation.sequence_keys(checked) {
    if !spend(@schema.reference_name(key.field)) {
      return Err(SequenceMatchPreparationLimit)
    }
  }
  if !spend(@schema.reference_name(@relation.sequence_identity(checked))) ||
    !spend(@schema.reference_name(@relation.sequence_time(checked))) {
    return Err(SequenceMatchPreparationLimit)
  }
  let mut remaining = expressions
  let predicates : Array[Expression] = []
  for index in 0..<pattern_count {
    let pattern = @relation.sequence_pattern_at(checked, index).unwrap()
    if !spend(pattern.label) {
      return Err(SequenceMatchPreparationLimit)
    }
    let (expression, usage) = match
      lower_expression_measured(owner, step, index, remaining) {
      Ok(value) => value
      Err(issue) => return Err(SequenceMatchExpression(issue))
    }
    remaining = {
      ..remaining,
      max_nodes: remaining.max_nodes - usage.nodes,
      max_work: remaining.max_work - usage.work,
      max_literal_nodes: remaining.max_literal_nodes - usage.literal_nodes,
      max_literal_text_bytes: remaining.max_literal_text_bytes -
      usage.literal_bytes,
    }
    predicates.push(expression)
  }
  let (within, within_names) = match
    resolve_window_milliseconds(
      owner,
      @relation.sequence_within(checked),
      max_name_bytes - names,
    ) {
    Ok(value) => value
    Err(MissingWindowParameter(name)) =>
      return Err(MissingSequenceMatchParameter(name))
    Err(InvalidWindowParameter(name)) =>
      return Err(InvalidSequenceMatchParameter(name))
    Err(_) => return Err(SequenceMatchPreparationLimit)
  }
  names += within_names
  let (per_key_limit, per_key_entries, per_key_names) = match
    resolve_sequence_count(
      owner,
      @relation.sequence_per_key_guard(checked),
      max_name_bytes - names,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  entries += per_key_entries
  names += per_key_names
  let (output_limit, output_entries, output_names) = match
    resolve_sequence_count(
      owner,
      @relation.sequence_output_guard(checked),
      max_name_bytes - names,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  entries += output_entries
  names += output_names
  if entries > max_entries || within <= 0L {
    return Err(SequenceMatchPreparationLimit)
  }
  Ok(
    (
      { owner, step, checked, predicates, within, per_key_limit, output_limit, },
      entries,
      names,
      remaining,
    ),
  )
}

///|
pub fn sequence_match_owner(value : PreparedSequenceMatch) -> BoundPrepared {
  value.owner
}

///|
pub fn sequence_match_step(value : PreparedSequenceMatch) -> Int {
  value.step
}

///|
pub fn sequence_match_input(value : PreparedSequenceMatch) -> String {
  value.owner.prepared.nodes[value.step].inputs[0]
}

///|
pub fn sequence_match_key_count(value : PreparedSequenceMatch) -> Int {
  @relation.sequence_keys(value.checked).length()
}

///|
pub fn sequence_match_key_at(
  value : PreparedSequenceMatch,
  index : Int,
) -> @schema.FieldName? {
  @relation.sequence_keys(value.checked).get(index).map(key => key.field)
}

///|
pub fn sequence_match_identity(
  value : PreparedSequenceMatch,
) -> @schema.FieldName {
  @relation.sequence_identity(value.checked)
}

///|
pub fn sequence_match_time(value : PreparedSequenceMatch) -> @schema.FieldName {
  @relation.sequence_time(value.checked)
}

///|
pub fn sequence_match_uses_timestamp(value : PreparedSequenceMatch) -> Bool {
  @relation.sequence_requires_timestamp_conversion(value.checked)
}

///|
pub fn sequence_match_pattern_count(value : PreparedSequenceMatch) -> Int {
  value.predicates.length()
}

///|
pub fn sequence_match_pattern_label(
  value : PreparedSequenceMatch,
  index : Int,
) -> String? {
  @relation.sequence_pattern_at(value.checked, index).map(part => part.label)
}

///|
pub fn sequence_match_predicate(
  value : PreparedSequenceMatch,
  index : Int,
) -> Expression? {
  value.predicates.get(index)
}

///|
pub fn sequence_match_within(value : PreparedSequenceMatch) -> Int64 {
  value.within
}

///|
pub fn sequence_match_overlap(
  value : PreparedSequenceMatch,
) -> @relation.SequenceOverlap {
  @relation.sequence_overlap(value.checked)
}

///|
pub fn sequence_match_contiguity(
  value : PreparedSequenceMatch,
) -> @relation.SequenceContiguity {
  @relation.sequence_contiguity(value.checked)
}

///|
pub fn sequence_match_per_key_limit(value : PreparedSequenceMatch) -> Int64? {
  value.per_key_limit
}

///|
pub fn sequence_match_output_limit(value : PreparedSequenceMatch) -> Int64? {
  value.output_limit
}

///|
pub fn sequence_match_output_schema(
  value : PreparedSequenceMatch,
) -> @schema.Schema {
  @relation.sequence_output(value.checked)
}

///|
fn emit_sequence_match(
  value : PreparedSequenceMatch,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  let node = value.owner.prepared.nodes[value.step]
  @encode.begin_object(out)
  @encode.key(out, "id")
  @encode.string_value(out, node.id)
  @encode.key(out, "in")
  @encode.begin_array(out)
  @encode.string_value(out, node.inputs[0])
  @encode.end_array(out)
  @encode.key(out, "op")
  @encode.string_value(out, "TEA.sequence.match")
  @encode.key(out, "params")
  @encode.begin_object(out)
  @encode.key(out, "by")
  @encode.begin_array(out)
  for key in @relation.sequence_keys(value.checked) {
    @encode.string_value(out, @schema.reference_name(key.field))
  }
  @encode.end_array(out)
  @encode.key(out, "contiguity")
  @encode.string_value(
    out,
    if @relation.sequence_contiguity(value.checked) ==
      @relation.SequenceContiguity::Adjacent {
      "adjacent"
    } else {
      "subsequence"
    },
  )
  @encode.key(out, "id")
  @encode.string_value(
    out,
    @schema.reference_name(@relation.sequence_identity(value.checked)),
  )
  if value.per_key_limit is Some(limit) {
    @encode.key(out, "max_matches_per_key")
    @encode.number_value(out, limit.to_double())
  }
  if value.output_limit is Some(limit) {
    @encode.key(out, "max_output_rows")
    @encode.number_value(out, limit.to_double())
  }
  @encode.key(out, "overlap")
  @encode.string_value(
    out,
    if @relation.sequence_overlap(value.checked) ==
      @relation.SequenceOverlap::Allow {
      "allow"
    } else {
      "disallow"
    },
  )
  @encode.key(out, "pattern")
  @encode.begin_array(out)
  for index in 0..<value.predicates.length() {
    @encode.begin_object(out)
    @encode.key(out, "as")
    @encode.string_value(
      out,
      @relation.sequence_pattern_at(value.checked, index).unwrap().label,
    )
    @encode.key(out, "where")
    emit_expression(value.predicates[index], out)
    @encode.end_object(out)
  }
  @encode.end_array(out)
  @encode.key(out, "time")
  @encode.string_value(
    out,
    @schema.reference_name(@relation.sequence_time(value.checked)),
  )
  @encode.key(out, "time_domain")
  @encode.string_value(
    out,
    if @relation.sequence_requires_timestamp_conversion(value.checked) {
      "timestamp"
    } else {
      "utc_milliseconds"
    },
  )
  @encode.key(out, "within_ms")
  @encode.number_value(out, value.within.to_double())
  @encode.end_object(out)
  @encode.end_object(out)
}
