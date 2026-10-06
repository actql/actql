///|
priv enum EqualityFrame {
  Pair(Contract, Contract)
  Names(Fields, Fields, Int, Int)
  Children(Fields, Fields, Int)
  ParameterText(String, String, Int)
}

///|
/// Exact type equality, with the original visited-pair limit and failure
/// precedence. Object names are checked in reverse order before any child;
/// children are visited in canonical forward order. No field array is copied.
struct TypeEquality {
  pending : Array[EqualityFrame]
  mut remaining : Int
  mut scheduled : Int
  mut terminal : Bool
}

///|
pub fn start_type_equality(
  left : Contract,
  right : Contract,
  max_pairs : Int,
) -> TypeEquality raise RelationError {
  if max_pairs < 0 {
    raise InvalidRelationLimit
  }
  {
    pending: [Pair(left, right)],
    remaining: max_pairs,
    scheduled: 1,
    terminal: false,
  }
}

///|
/// Maximum live continuation count during the next advance, before allocation.
/// Callers reserve their frame custody before invoking the step.
pub fn type_equality_next_frames(cursor : TypeEquality) -> Int {
  if cursor.terminal || cursor.pending.is_empty() {
    return 0
  }
  let count = cursor.pending.length()
  match cursor.pending[count - 1] {
    Pair({ shape: Object(fields), .. }, _) =>
      if fields.values.is_empty() {
        count
      } else {
        count + 1
      }
    Children(left, _, index) =>
      if index + 1 < left.values.length() {
        count + 1
      } else {
        count
      }
    _ => count
  }
}

///|
pub fn cancel_type_equality(cursor : TypeEquality) -> Unit {
  cursor.pending.clear()
  cursor.scheduled = 0
  cursor.terminal = true
}

///|
fn equality_done(cursor : TypeEquality, equal : Bool) -> Bool? {
  cancel_type_equality(cursor)
  Some(equal)
}

///|
/// One contract/field transition or at most 64 UTF-16 units per poll. Pair
/// usage is not poll count: yielding does not consume the semantic pair budget.
pub fn advance_type_equality(
  cursor : TypeEquality,
) -> Bool? raise RelationError {
  if cursor.terminal {
    raise InvalidRelationLimit
  }
  guard cursor.pending.pop() is Some(frame) else {
    return equality_done(cursor, true)
  }
  match frame {
    Pair(left, right) => {
      cursor.scheduled -= 1
      if cursor.remaining == 0 {
        cancel_type_equality(cursor)
        raise RelationLimit
      }
      cursor.remaining -= 1
      if left.nullable != right.nullable {
        return equality_done(cursor, false)
      }
      // Reference parameter strings can be large; defer their exact match.
      match (left.shape, right.shape) {
        (ResourceRef(resource_kind=a), ResourceRef(resource_kind=b)) =>
          cursor.pending.push(ParameterText(a, b, 0))
        (ArtifactRef(media_type=Some(a)), ArtifactRef(media_type=Some(b))) =>
          cursor.pending.push(ParameterText(a, b, 0))
        _ => {
          if !compatible(left, right, Equal) {
            return equality_done(cursor, false)
          }
          let children = child_count(left)
          if children > cursor.remaining - cursor.scheduled {
            cancel_type_equality(cursor)
            raise RelationLimit
          }
          cursor.scheduled += children
          match (left.shape, right.shape) {
            (Array(a, ..), Array(b, ..)) => cursor.pending.push(Pair(a, b))
            (Object(a), Object(b)) =>
              if !a.values.is_empty() {
                cursor.pending.push(Children(a, b, 0))
                cursor.pending.push(Names(a, b, a.values.length() - 1, 0))
              }
            _ => ()
          }
        }
      }
    }
    Names(left, right, index, offset) => {
      let a = left.values[index].name
      let b = right.values[index].name
      if a.length() != b.length() {
        return equality_done(cursor, false)
      }
      let end = offset + Int::min(64, a.length() - offset)
      for position in offset..<end {
        if a[position] != b[position] {
          return equality_done(cursor, false)
        }
      }
      if end < a.length() {
        cursor.pending.push(Names(left, right, index, end))
      } else if index > 0 {
        cursor.pending.push(Names(left, right, index - 1, 0))
      }
    }
    Children(left, right, index) => {
      if index + 1 < left.values.length() {
        cursor.pending.push(Children(left, right, index + 1))
      }
      cursor.pending.push(
        Pair(left.values[index].contract, right.values[index].contract),
      )
    }
    ParameterText(left, right, offset) => {
      if left.length() != right.length() {
        return equality_done(cursor, false)
      }
      let end = offset + Int::min(64, left.length() - offset)
      for index in offset..<end {
        if left[index] != right[index] {
          return equality_done(cursor, false)
        }
      }
      if end < left.length() {
        cursor.pending.push(ParameterText(left, right, end))
      }
    }
  }
  if cursor.pending.is_empty() {
    equality_done(cursor, true)
  } else {
    None
  }
}
