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
  op : @join.CheckedJoin,
  side : @schema.Side,
  keys : @evidence.KeySet?,
) -> @evidence.KeyedRelation? raise Stop {
  guard keys is Some(keys) else { return None }
  let source = @join.source(op)
  // Operand binding is pointer-based: structurally similar foreign rows are
  // not allowed to donate a primary-key assertion.
  guard @carrier.complete_schema(@evidence.key_set_records(keys))
    is Some(schema) &&
    physical_equal(schema, @join.input_schema(op, side)) else {
    fail(source, KeyEvidence(InputContractMismatch))
  }
  let n = @join.key_count(op)
  spend(b, source, n)
  let fields = Array::makei(n, i => {
    let pair = @join.key_at(op, i).unwrap()
    if side == Left {
      pair.left
    } else {
      pair.right
    }
  })
  let selected = match
    @evidence.select_covered_key(source, keys, fields, {
      max_work: b.work,
      max_name_bytes: b.text,
    }) {
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
      Join(right~, checked~) => {
        let left = covered_join_side(
          b,
          checked,
          Left,
          step.input.bind(t => key_at(t, inputs, keys)),
        )
        let right = covered_join_side(
          b,
          checked,
          Right,
          key_at(right, inputs, keys),
        )
        let assertion = @join.assertion(checked)
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
  value.join_evidence.get(index).bind(v => v)
}
