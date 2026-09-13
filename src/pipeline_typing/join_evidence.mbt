///|
/// Conditional uniqueness: retain the actual operand and its witness obligations.
pub struct JoinEvidence {
  left : @evidence.KeyedRelation?
  right : @evidence.KeyedRelation?
  assertion : @join.Cardinality?
  cardinality : @join.Cardinality?
}

///|
fn join_uniqueness(v : JoinEvidence) -> (Bool, Bool) {
  (
    v.left is Some(_) || v.assertion is Some(OneToOne | OneToMany),
    v.right is Some(_) || v.assertion is Some(OneToOne | ManyToOne),
  )
}

///|
fn covered_join_side(
  b : Budget,
  op : CheckedOperation,
  side : @schema.Side,
  keys : @evidence.KeySet?,
) -> @evidence.KeyedRelation? raise Stop {
  let limits : @evidence.TransferLimits = {
    max_work: b.work,
    max_name_bytes: b.text,
  }
  let (source, result) = match op {
    Join(checked~, ..) =>
      (
        @join.source(checked),
        @evidence.select_join_key(checked, side, keys, limits),
      )
    IntervalJoin(checked~, ..) =>
      (
        @join.interval_source(checked),
        @evidence.select_interval_join_key(checked, side, keys, limits),
      )
    _ => return None
  }
  let selected = match result {
    Ok(v) => v
    Err(e) =>
      raise Stop({
        kind: KeyEvidence(e.kind),
        source,
        path: e.path.copy(),
        span: e.span,
        range: None,
      })
  }
  b.work -= selected.work
  b.text -= selected.name_bytes
  selected.key
}

///|
fn derive_join_evidence(
  b : Budget,
  steps : Array[CheckedStep],
  inputs : Array[@evidence.KeySet?],
  keys : Array[@evidence.KeySet?],
) -> Array[JoinEvidence?] raise Stop {
  let result : Array[JoinEvidence?] = []
  for step in steps {
    spend(b, step.source, 1)
    let value = match step.operation {
      Join(right~, ..) | IntervalJoin(right~, ..) => {
        let left = covered_join_side(
          b,
          step.operation,
          Left,
          step.input.bind(t => key_at(t, inputs, keys)),
        )
        let right = covered_join_side(
          b,
          step.operation,
          Right,
          key_at(right, inputs, keys),
        )
        let assertion = match step.operation {
          Join(checked~, ..) => @join.assertion(checked)
          _ => None
        }
        let initial : JoinEvidence = {
          left,
          right,
          assertion,
          cardinality: None,
        }
        let (l, r) = join_uniqueness(initial)
        Some({
          ..initial,
          cardinality: if l && r {
            Some(OneToOne)
          } else if l {
            Some(OneToMany)
          } else if r {
            Some(ManyToOne)
          } else {
            None
          },
        })
      }
      _ => None
    }
    result.push(value)
  }
  result
}

///|
/// Returns operand-bound witnesses, not an assertion that runtime data passed.
pub fn join_evidence(value : CheckedPipeline, index : Int) -> JoinEvidence? {
  guard value.steps.get(index) is Some({ operation: Join(_), .. }) else {
    return None
  }
  value.join_evidence.get(index).bind(v => v)
}

///|
/// Equality-correlation coverage for the exact temporal operands. Assertion is
/// always absent; endpoint and right-scope validation remain producer duties.
pub fn interval_join_evidence(
  value : CheckedPipeline,
  index : Int,
) -> JoinEvidence? {
  guard value.steps.get(index) is Some({ operation: IntervalJoin(_), .. }) else {
    return None
  }
  value.join_evidence.get(index).bind(v => v)
}
