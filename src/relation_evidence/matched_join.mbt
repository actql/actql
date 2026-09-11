///|
priv enum MatchedJoin {
  Equality(@join.CheckedJoin)
  Temporal(@join.CheckedIntervalJoin)
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
