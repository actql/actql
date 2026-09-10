///|
struct SortCompletion {
  key : @evidence.KeyedRelation
  appended : Array[@schema.FieldName]
}

///|
pub fn order_sort_completion(order : LogicalOrder) -> SortCompletion? {
  order.completion
}

///|
pub fn sort_completion_key(c : SortCompletion) -> @evidence.KeyedRelation {
  c.key
}

///|
pub fn sort_completion_count(c : SortCompletion) -> Int {
  c.appended.length()
}

///|
/// Appended identity terms are ascending with nulls last, not authored keys.
pub fn sort_completion_field(
  c : SortCompletion,
  index : Int,
) -> @schema.FieldName? {
  c.appended.get(index)
}

///|
fn order_field_key(f : @schema.FieldName) -> String {
  match f {
    Unqualified(n) => "u:" + n
    Qualified(Left, n) => "l:" + n
    Qualified(Right, n) => "r:" + n
  }
}

///|
fn complete_sort(
  b : Budget,
  op : @relation.CheckedOperation,
  keys : @evidence.KeySet?,
) -> SortCompletion? raise Stop {
  guard keys is Some(keys) else { return None }
  let source = @relation.source(op)
  guard @carrier.complete_schema(@evidence.key_set_records(keys)) is Some(input) &&
    physical_equal(input, @relation.input_schema(op)) else {
    fail(source, KeyEvidence(InputContractMismatch))
  }
  let selected = match
    @evidence.select_key(source, keys, CanonicalOrder, {
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
  guard selected.key is Some(key) else { return None }
  let seen : Map[String, Bool] = Map([])
  let n = @relation.sort_term_count(op)
  spend(b, source, n)
  for i in 0..<n {
    let term = @relation.sort_term_at(op, i).unwrap()
    charge(b, term.source, @schema.reference_name(term.field))
    seen[order_field_key(term.field)] = true
  }
  let appended : Array[@schema.FieldName] = []
  spend(b, source, @evidence.key_field_count(key))
  for i in 0..<@evidence.key_field_count(key) {
    let mut covered = false
    let aliases = @evidence.key_alias_count(key, i)
    spend(b, source, aliases)
    for j in 0..<aliases {
      let field = @evidence.key_alias_at(key, i, j).unwrap().name
      charge(b, source, @schema.reference_name(field))
      if seen.contains(order_field_key(field)) {
        covered = true
      }
    }
    if !covered {
      let field = @evidence.key_field_at(key, i).unwrap().name
      charge(b, source, @schema.reference_name(field))
      appended.push(field)
    }
  }
  Some({ key, appended, })
}
