///|
priv enum MatchedJoin {
  Equality(@join.CheckedJoin)
  Temporal(@join.CheckedIntervalJoin)
}

///|
fn select_matched_key(
  op : MatchedJoin,
  side : @row.Side,
  keys : KeySet?,
  limits : TransferLimits,
) -> Result[KeySelection, Issue] {
  try {
    let source = matched_source(op)
    if limits.max_work < 0 || limits.max_name_bytes < 0 {
      fail(source, InvalidLimits)
    }
    if keys is Some(keys) {
      guard @carrier.complete_schema(keys.records) is Some(schema) &&
        physical_equal(schema, matched_input_schema(op, side)) else {
        fail(source, InputContractMismatch)
      }
    }
    let b : TransferBudget = {
      work: limits.max_work,
      text: limits.max_name_bytes,
    }
    let key = join_covered(op, side, keys, b)
    Ok({
      key,
      work: limits.max_work - b.work,
      name_bytes: limits.max_name_bytes - b.text,
    })
  } catch {
    Stop(e) => Err(e)
  }
}

///|
/// Uses the same operand-bound coverage rule as output-key transfer.
pub fn select_join_key(
  op : @join.CheckedJoin,
  side : @row.Side,
  keys : KeySet?,
  limits : TransferLimits,
) -> Result[KeySelection, Issue] {
  select_matched_key(Equality(op), side, keys, limits)
}

///|
/// Temporal predicates do not add uniqueness; only equality coverage is used.
pub fn select_interval_join_key(
  op : @join.CheckedIntervalJoin,
  side : @row.Side,
  keys : KeySet?,
  limits : TransferLimits,
) -> Result[KeySelection, Issue] {
  select_matched_key(Temporal(op), side, keys, limits)
}

///|
fn matched_source(op : MatchedJoin) -> @decode.Cursor {
  match op {
    Equality(v) => @join.source(v)
    Temporal(v) => @join.interval_source(v)
  }
}

///|
fn matched_input_schema(op : MatchedJoin, side : @row.Side) -> @row.Schema {
  match op {
    Equality(v) => @join.input_schema(v, side)
    Temporal(v) => @join.interval_input_schema(v, side)
  }
}

///|
fn matched_output_schema(op : MatchedJoin) -> @row.Schema {
  match op {
    Equality(v) => @join.output_schema(v)
    Temporal(v) => @join.interval_output_schema(v)
  }
}

///|
fn matched_projection(op : MatchedJoin) -> Array[@join.Projection]? {
  match op {
    Equality(v) => @join.projection(v)
    Temporal(v) => @join.interval_projection(v)
  }
}

///|
fn matched_key_count(op : MatchedJoin) -> Int {
  match op {
    Equality(v) => @join.key_count(v)
    Temporal(v) => @join.interval_key_count(v)
  }
}

///|
fn matched_key_at(op : MatchedJoin, index : Int) -> @join.KeyPair? {
  match op {
    Equality(v) => @join.key_at(v, index)
    Temporal(v) => @join.interval_key_at(v, index)
  }
}

///|
fn matched_kind(op : MatchedJoin) -> @join.Kind {
  match op {
    Equality(v) => @join.kind(v)
    Temporal(v) => @join.interval_kind(v)
  }
}

///|
fn matched_assertion(op : MatchedJoin) -> @join.Cardinality? {
  match op {
    Equality(v) => @join.assertion(v)
    Temporal(_) => None
  }
}

///|
pub fn transfer_join_keys(
  left : KeySet?,
  right : KeySet?,
  op : @join.CheckedJoin,
  limits : TransferLimits,
) -> Result[KeySetTransfer, Issue] {
  transfer_matched_keys(left, right, Equality(op), limits)
}

///|
pub fn transfer_interval_join_keys(
  left : KeySet?,
  right : KeySet?,
  op : @join.CheckedIntervalJoin,
  limits : TransferLimits,
) -> Result[KeySetTransfer, Issue] {
  transfer_matched_keys(left, right, Temporal(op), limits)
}

///|
pub fn key_interval_join_producer(
  key : KeyedRelation,
) -> @join.CheckedIntervalJoin? {
  match key.producer {
    Some(IntervalJoinProducer(op, _)) => Some(op)
    _ => None
  }
}

///|
pub fn key_interval_join_dependency_count(key : KeyedRelation) -> Int {
  match key.producer {
    Some(IntervalJoinProducer(_, parents)) => parents.length()
    _ => 0
  }
}

///|
pub fn key_interval_join_dependency_at(
  key : KeyedRelation,
  index : Int,
) -> KeyedRelation? {
  match key.producer {
    Some(IntervalJoinProducer(_, parents)) => parents.get(index).map(p => p.1)
    _ => None
  }
}

///|
pub fn key_interval_join_dependency_side(
  key : KeyedRelation,
  index : Int,
) -> @row.Side? {
  match key.producer {
    Some(IntervalJoinProducer(_, parents)) => parents.get(index).map(p => p.0)
    _ => None
  }
}
