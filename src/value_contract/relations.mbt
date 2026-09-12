///|
priv enum Relation {
  Equal
  Assign
  Join
}

///|
fn upper_assign(actual : Int64?, expected : Int64?) -> Bool {
  match (actual, expected) {
    (_, None) => true
    (Some(a), Some(b)) => a <= b
    _ => false
  }
}

///|
fn lower_assign(actual : Int64?, expected : Int64?) -> Bool {
  match (actual, expected) {
    (_, None) => true
    (Some(a), Some(b)) => a >= b
    _ => false
  }
}

///|
fn upper_join(a : Int64?, b : Int64?) -> Int64? {
  match (a, b) {
    (Some(a), Some(b)) => Some(if a > b { a } else { b })
    _ => None
  }
}

///|
fn lower_join(a : Int64?, b : Int64?) -> Int64? {
  match (a, b) {
    (Some(a), Some(b)) => Some(if a < b { a } else { b })
    _ => None
  }
}

///|
fn compatible(a : Contract, b : Contract, relation : Relation) -> Bool {
  match relation {
    Equal => if a.nullable != b.nullable { return false }
    Assign => if a.nullable && !b.nullable { return false }
    Join => ()
  }
  match (a.shape, b.shape) {
    (Text(x), Text(y)) =>
      match relation {
        Equal => x == y
        Assign =>
          lower_assign(x.min_length, y.min_length) &&
          upper_assign(x.max_codepoints, y.max_codepoints) &&
          upper_assign(x.max_utf8_bytes, y.max_utf8_bytes)
        Join => true
      }
    (Array(_, max_items=x), Array(_, max_items=y)) =>
      match relation {
        Equal => x == y
        Assign => upper_assign(x, y)
        Join => true
      }
    (Object(x), Object(y)) => x.values.length() == y.values.length()
    (Decimal(precision=p, scale=s), Decimal(precision=q, scale=t)) =>
      p == q && s == t
    (Vector(dimensions=x), Vector(dimensions=y)) => x == y
    (ResourceRef(resource_kind=x), ResourceRef(resource_kind=y)) => x == y
    (ArtifactRef(media_type=x), ArtifactRef(media_type=y)) =>
      match relation {
        Equal => x == y
        Assign => y is None || x == y
        Join => true
      }
    (Number, Number)
    | (Boolean, Boolean)
    | (Timestamp, Timestamp)
    | (Date, Date)
    | (Json, Json) => true
    _ => false
  }
}

///|
fn child_count(value : Contract) -> Int {
  match value.shape {
    Array(_, ..) => 1
    Object(fields) => fields.values.length()
    _ => 0
  }
}

///|
fn compare(
  a : Contract,
  b : Contract,
  max_pairs : Int,
  relation : Relation,
) -> (Bool, Int) raise RelationError {
  if max_pairs < 0 {
    raise InvalidRelationLimit
  }
  let mut remaining = max_pairs
  let pending = [(a, b)]
  while !pending.is_empty() {
    if remaining == 0 {
      raise RelationLimit
    }
    remaining -= 1
    let (a, b) = pending.pop().unwrap()
    if !compatible(a, b, relation) {
      return (false, max_pairs - remaining)
    }
    if child_count(a) > remaining - pending.length() {
      raise RelationLimit
    }
    match (a.shape, b.shape) {
      (Array(x, ..), Array(y, ..)) => pending.push((x, y))
      (Object(x), Object(y)) =>
        for i = x.values.length() - 1; i >= 0; i = i - 1 {
          if x.values[i].name != y.values[i].name {
            return (false, max_pairs - remaining)
          }
          pending.push((x.values[i].contract, y.values[i].contract))
        }
      _ => ()
    }
  }
  (true, max_pairs - remaining)
}

///|
pub fn type_equal(
  a : Contract,
  b : Contract,
  max_pairs : Int,
) -> Bool raise RelationError {
  compare(a, b, max_pairs, Equal).0
}

///|
pub fn assignable(
  actual : Contract,
  expected : Contract,
  max_pairs : Int,
) -> Bool raise RelationError {
  compare(actual, expected, max_pairs, Assign).0
}

///|
/// Assignment result and consumed pair budget, including an incompatible pair.
pub fn assignable_usage(
  actual : Contract,
  expected : Contract,
  max_pairs : Int,
) -> (Bool, Int) raise RelationError {
  compare(actual, expected, max_pairs, Assign)
}

///|
priv enum JoinWork {
  Visit(Contract, Contract)
  Assemble(Contract, Contract)
}

///|
pub fn join_nullability(
  a : Contract,
  b : Contract,
  max_pairs : Int,
) -> Contract? raise RelationError {
  if max_pairs < 0 {
    raise InvalidRelationLimit
  }
  let mut remaining = max_pairs
  let pending : Array[JoinWork] = [Visit(a, b)]
  let mut scheduled = 1
  let values : Array[Contract] = []
  while !pending.is_empty() {
    match pending.pop().unwrap() {
      Visit(a, b) => {
        scheduled -= 1
        if remaining == 0 {
          raise RelationLimit
        }
        remaining -= 1
        if !compatible(a, b, Join) {
          return None
        }
        if child_count(a) > remaining - scheduled {
          raise RelationLimit
        }
        scheduled += child_count(a)
        pending.push(Assemble(a, b))
        match (a.shape, b.shape) {
          (Array(x, ..), Array(y, ..)) => pending.push(Visit(x, y))
          (Object(x), Object(y)) =>
            for i = x.values.length() - 1; i >= 0; i = i - 1 {
              if x.values[i].name != y.values[i].name {
                return None
              }
              pending.push(Visit(x.values[i].contract, y.values[i].contract))
            }
          _ => ()
        }
      }
      Assemble(a, b) => {
        let shape = match (a.shape, b.shape) {
          (Text(x), Text(y)) =>
            Text({
              min_length: lower_join(x.min_length, y.min_length),
              max_codepoints: upper_join(x.max_codepoints, y.max_codepoints),
              max_utf8_bytes: upper_join(x.max_utf8_bytes, y.max_utf8_bytes),
            })
          (Array(_, max_items=x), Array(_, max_items=y)) =>
            Array(values.pop().unwrap(), max_items=upper_join(x, y))
          (Object(x), Object(_)) => {
            let entries : Array[Field] = []
            for i = x.values.length() - 1; i >= 0; i = i - 1 {
              entries.push({
                name: x.values[i].name,
                contract: values.pop().unwrap(),
              })
            }
            // Reverse without sorting: both inputs already have canonical field order.
            let ordered = Array::makei(entries.length(), i => {
              entries[entries.length() - 1 - i]
            })
            Object({ values: ordered, })
          }
          (ArtifactRef(media_type=x), ArtifactRef(media_type=y)) =>
            ArtifactRef(media_type=if x == y { x } else { None })
          _ => a.shape
        }
        values.push({ nullable: a.nullable || b.nullable, shape, })
      }
    }
  }
  Some(values.pop().unwrap())
}

///|
/// Compares key domains only; it neither compares values nor authorizes references.
pub fn key_comparable(a : Contract, b : Contract) -> Bool {
  match (a.shape, b.shape) {
    (Text(_), Text(_))
    | (Number, Number)
    | (Boolean, Boolean)
    | (Timestamp, Timestamp)
    | (Date, Date)
    | (Decimal(..), Decimal(..))
    | (ArtifactRef(..), ArtifactRef(..)) => true
    (ResourceRef(resource_kind=x), ResourceRef(resource_kind=y)) => x == y
    _ => false
  }
}
