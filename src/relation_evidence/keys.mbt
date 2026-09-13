///|
pub(all) struct Limits {
  max_fields : Int
  max_name_bytes : Int
}

///|
pub(all) struct Usage {
  fields : Int
  name_bytes : Int
} derive(Eq, Debug)

///|
pub(all) enum IssueKind {
  InvalidLimits
  LimitExceeded
  Decode(@decode.IssueKind)
  WrongCarrier(@carrier.Kind)
  EmptyKey
  InvalidName(String)
  DuplicateKeyField(String)
  MissingKeyField(String)
  InvalidKeyType(String)
  InputContractMismatch
} derive(Eq, Debug)

///|
pub struct Issue {
  kind : IssueKind
  path : Array[@decode.PathSegment]
  span : @span.Span
}

///|
pub type KeyObligation = @key_obligation.KeyObligation

///|
pub struct KeyField {
  name : @row.FieldName
  contract : @contract.Contract?
  // Producer-bound positional domain; never inferred from an object contract.
  positional_identity : @carrier.Vectors?
}

///|
fn plain_key_field(
  name : @row.FieldName,
  contract : @contract.Contract?,
) -> KeyField {
  { name, contract, positional_identity: None, }
}

///|
pub(all) enum KeyOrigin {
  InputDeclaration
  GroupResult
  DistinctResult
  DedupeResult
  UniqueAssertion
  PivotResult
  CalendarSeriesResult
  TimeSeriesResult
  VectorProjectionResult
  GraphProjectionResult
  WindowMembershipResult
  UnnestResult
  UnpivotResult
  EventIdentityResult
  EventDedupeResult
  JoinResult
  CrossJoinResult
  IntervalJoinResult
  AsOfResult
  SequenceResult
  GraphQueryResult
  NearestResult
  RankingResult
  TextRankResult
  SetDistinctResult
} derive(Eq, Debug)

///|
priv enum KeyProducer {
  SetProducer(@set.CheckedSet)
  NearestProducer(CheckedNearest)
  RankingProducer(CheckedRanking)
  TextRankProducer(CheckedTextRank)
  GraphQueryProducer(GraphKeyOperation)
  SequenceProducer(@relation.CheckedSequence)
  AsOfProducer(CheckedAsOf, KeyedRelation?)
  RelationProducer(@relation.CheckedOperation)
  CalendarProducer(@calendar.CheckedCalendar)
  TimeSeriesProducer(@series.CheckedSeries)
  VectorProjectionProducer(@projection.CheckedProjection)
  GraphProjectionProducer(@projection.CheckedProjection)
  WindowProducer(@window.CheckedWindow, KeyedRelation)
  UnnestProducer(@relation.CheckedOperation, KeyedRelation)
  UnpivotProducer(@relation.CheckedOperation, KeyedRelation)
  EventProducer(@event.CheckedEvent)
  JoinProducer(@join.CheckedJoin, Array[(@row.Side, KeyedRelation)])
  CrossJoinProducer(@join.CheckedCrossJoin, Array[(@row.Side, KeyedRelation)])
  IntervalJoinProducer(
    @join.CheckedIntervalJoin,
    Array[(@row.Side, KeyedRelation)]
  )
}

///|
struct KeyedRelation {
  origin : KeyOrigin
  producer : KeyProducer?
  records : @carrier.Knowledge
  declared_records : @carrier.Knowledge
  declared_fields : Array[KeyField]
  source : @decode.Cursor
  fields : Array[KeyField]
  aliases : Array[Array[KeyField]]
  usage : Usage
}

///|
priv suberror Stop {
  Stop(Issue)
}

///|
fn[T] fail(at : @decode.Cursor, kind : IssueKind) -> T raise Stop {
  raise Stop({
    kind,
    path: @decode.cursor_path(at),
    span: @decode.cursor_span(at),
  })
}

///|
fn[T] decoded(value : Result[T, @decode.Issue]) -> T raise Stop {
  match value {
    Ok(v) => v
    Err(e) =>
      raise Stop({ kind: Decode(e.kind), path: e.path.copy(), span: e.span, })
  }
}

///|
/// Admits a local-input primary-key assertion, not evidence that data was tested.
/// Every consumer must retain the returned input-admission obligations.
pub fn declare_primary_key(
  source : @decode.Cursor,
  input : @carrier.Carrier,
  limits : Limits,
) -> Result[KeyedRelation, Issue] {
  try {
    if limits.max_fields < 0 || limits.max_name_bytes < 0 {
      fail(source, InvalidLimits)
    }
    let records = match @carrier.relation_rows(input) {
      Some(r) => r
      None => fail(source, WrongCarrier(@carrier.kind(input)))
    }
    let entries = decoded(@decode.elements(source))
    if entries.is_empty() {
      fail(source, EmptyKey)
    }
    if entries.length() > limits.max_fields {
      fail(source, LimitExceeded)
    }
    let fields : Array[KeyField] = []
    let seen : Map[String, Bool] = Map([])
    let mut remaining = limits.max_name_bytes
    for at in entries {
      let name = decoded(@decode.text(at))
      let bytes = match @scalar.admit_utf8_length(name, remaining) {
        Ok(n) => n
        Err(_) => fail(at, LimitExceeded)
      }
      remaining -= bytes
      match
        @contract.object_contract(
          [(name, @contract.primitive(NumberType, nullable=false))],
          nullable=false,
          max_fields=1,
          max_name_bytes=bytes,
        ) {
        Ok(_) => ()
        Err(_) => fail(at, InvalidName(name))
      }
      if seen.contains(name) {
        fail(at, DuplicateKeyField(name))
      }
      seen[name] = true
      let field_name = @row.Unqualified(name)
      let contract = match @carrier.lookup(records, field_name) {
        Absent => fail(at, MissingKeyField(name))
        Unknown => None
        Present(f) => f.contract
      }
      if contract is Some(c) && (c.nullable || !@contract.key_comparable(c, c)) {
        fail(at, InvalidKeyType(name))
      }
      fields.push(plain_key_field(field_name, contract))
    }
    Ok({
      origin: InputDeclaration,
      producer: None,
      records,
      declared_records: records,
      declared_fields: fields,
      source,
      fields,
      aliases: fields.map(f => [f]),
      usage: {
        fields: fields.length(),
        name_bytes: limits.max_name_bytes - remaining,
      },
    })
  } catch {
    Stop(e) => Err(e)
  }
}

///|
pub fn keyed_records(c : KeyedRelation) -> @carrier.Knowledge {
  c.records
}

///|
pub fn key_source(c : KeyedRelation) -> @decode.Cursor {
  c.source
}

///|
/// Contract at the key's origin: input declaration or producer output.
/// Consult key_origin/key_producer before discharging its obligations.
pub fn declared_records(c : KeyedRelation) -> @carrier.Knowledge {
  c.declared_records
}

///|
pub fn declared_key_field_at(c : KeyedRelation, index : Int) -> KeyField? {
  c.declared_fields.get(index)
}

///|
pub fn key_field_count(c : KeyedRelation) -> Int {
  c.fields.length()
}

///|
pub fn key_field_at(c : KeyedRelation, i : Int) -> KeyField? {
  c.fields.get(i)
}

///|
pub fn key_usage(c : KeyedRelation) -> Usage {
  c.usage
}

///|
pub fn key_pending(c : KeyedRelation) -> Array[KeyObligation] {
  let out = []
  key_pending_each(c, item => out.push(item))
  out
}

///|
// One bounded enumeration rule shared by copied and indexed reads.
fn key_pending_each(c : KeyedRelation, emit : (KeyObligation) -> Unit) -> Unit {
  if c.producer is Some(VectorProjectionProducer(_)) {
    emit(ValidateKeyProducer)
    emit(AdmitPresentNonNullComparableComponents)
    emit(ValidateWholeTupleUniquenessAfterInputNormalization)
    emit(RevalidateReferenceComponents)
  } else if c.producer is Some(_) {
    emit(ValidateKeyProducer)
  } else {
    emit(AdmitPresentNonNullComparableComponents)
    emit(ValidateWholeTupleUniquenessAfterInputNormalization)
    emit(RevalidateReferenceComponents)
  }
}

///|
/// O(1), independent of input data size; no obligation array is materialized.
pub fn key_pending_count(c : KeyedRelation) -> Int {
  let mut count = 0
  key_pending_each(c, _ => count += 1)
  count
}

///|
/// O(1), without copying the obligation array; invalid indices return None.
pub fn key_pending_at(c : KeyedRelation, index : Int) -> KeyObligation? {
  if index < 0 {
    return None
  }
  let mut count = 0
  let mut found = None
  key_pending_each(c, item => {
    if count == index {
      found = Some(item)
    }
    count += 1
  })
  found
}

///|
pub fn key_origin(c : KeyedRelation) -> KeyOrigin {
  c.origin
}

///|
pub fn key_producer(c : KeyedRelation) -> @relation.CheckedOperation? {
  match c.producer {
    Some(RelationProducer(op))
    | Some(UnnestProducer(op, _))
    | Some(UnpivotProducer(op, _)) => Some(op)
    _ => None
  }
}

///|
pub fn key_calendar_producer(c : KeyedRelation) -> @calendar.CheckedCalendar? {
  match c.producer {
    Some(CalendarProducer(op)) => Some(op)
    _ => None
  }
}

///|
pub fn key_time_series_producer(c : KeyedRelation) -> @series.CheckedSeries? {
  match c.producer {
    Some(TimeSeriesProducer(op)) => Some(op)
    _ => None
  }
}

///|
pub fn key_vector_projection_producer(
  c : KeyedRelation,
) -> @projection.CheckedProjection? {
  match c.producer {
    Some(VectorProjectionProducer(op)) => Some(op)
    _ => None
  }
}

///|
pub fn key_graph_projection_producer(
  c : KeyedRelation,
) -> @projection.CheckedProjection? {
  match c.producer {
    Some(GraphProjectionProducer(op)) => Some(op)
    _ => None
  }
}

///|
pub fn key_alias_count(c : KeyedRelation, component : Int) -> Int {
  c.aliases.get(component).map(a => a.length()).unwrap_or(0)
}

///|
pub fn key_alias_at(
  c : KeyedRelation,
  component : Int,
  alias_index : Int,
) -> KeyField? {
  match c.aliases.get(component) {
    Some(a) => a.get(alias_index)
    None => None
  }
}
