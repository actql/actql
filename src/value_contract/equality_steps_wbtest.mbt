///|
fn[T] equality_raises(
  action : () -> T raise RelationError,
  expected : RelationError,
) -> Bool {
  try {
    action() |> ignore
    false
  } catch {
    issue => issue == expected
  }
}

///|
fn drain_equality_steps(
  cursor : TypeEquality,
  limit : Int,
) -> (Bool?, Int) raise RelationError {
  let mut result = None
  let mut polls = 0
  for _ in 0..<limit {
    if result is None {
      polls += 1
      result = advance_type_equality(cursor)
    }
  }
  (result, polls)
}

///|
test "type equality yields across wide objects without changing pair limits" {
  let number = primitive(NumberType, nullable=false)
  let fields = Array::makei(129, i => ("k" + (1000 + i).to_string(), number))
  let left = object_contract(
    fields,
    nullable=false,
    max_fields=129,
    max_name_bytes=645,
  ).unwrap()
  let right = object_contract(
    fields,
    nullable=false,
    max_fields=129,
    max_name_bytes=645,
  ).unwrap()
  // One root, all 129 reverse name checks, then 129 child scheduling and
  // 129 pair visits. Logical contract usage is only root+129=130 pairs.
  let cursor = start_type_equality(left, right, 130)
  let mut peak = 0
  for _ in 0..<387 {
    peak = peak.max(type_equality_next_frames(cursor))
    assert_eq(advance_type_equality(cursor), None)
  }
  assert_eq(advance_type_equality(cursor), Some(true))
  assert_eq(peak, 2)
  assert_eq(cursor.remaining, 0)
  assert_eq(cursor.pending.length(), 0)
  assert_eq(compare(left, right, 130, Equal), (true, 130))
  let short = start_type_equality(left, right, 129)
  assert_true(
    equality_raises(() => advance_type_equality(short), RelationLimit),
  )
  assert_true(
    equality_raises(() => type_equal(left, right, 129), RelationLimit),
  )
  assert_eq(short.pending.length(), 0)
}

///|
test "type equality scans exact object and reference names without normalization" {
  let number = primitive(NumberType, nullable=false)
  let prefix = String::make(129, 'a')
  let left = object_contract(
    [(prefix + "a", number)],
    nullable=false,
    max_fields=1,
    max_name_bytes=130,
  ).unwrap()
  let equal = object_contract(
    [(prefix + "a", number)],
    nullable=false,
    max_fields=1,
    max_name_bytes=130,
  ).unwrap()
  let unequal = object_contract(
    [(prefix + "b", number)],
    nullable=false,
    max_fields=1,
    max_name_bytes=130,
  ).unwrap()
  assert_eq(
    drain_equality_steps(start_type_equality(left, equal, 2), 6),
    (Some(true), 6),
  )
  let cursor = start_type_equality(left, unequal, 2)
  assert_eq(drain_equality_steps(cursor, 4), (Some(false), 4))
  assert_eq(cursor.remaining, 1)
  // The canonical field spelling is not compared with NFC-equivalent data.
  for
    (a, b, equal) in [
      ("é", "e\u{0301}", false),
      ("\r\n", "\n", false),
      (prefix + "😀", prefix + "😀", true),
    ] {
    let left : Contract = {
      nullable: false,
      shape: ResourceRef(resource_kind=a),
    }
    let right : Contract = {
      nullable: false,
      shape: ResourceRef(resource_kind=b),
    }
    assert_eq(
      drain_equality_steps(start_type_equality(left, right, 1), 10).0,
      Some(equal),
    )
    assert_eq(type_equal(left, right, 1), equal)
  }
}

///|
test "type equality preserves eager object-name and scheduled-pair precedence" {
  let number = primitive(NumberType, nullable=false)
  let array = array_contract(number, nullable=false).unwrap()
  let left = object_contract(
    [("a", array), ("z", number)],
    nullable=false,
    max_fields=2,
    max_name_bytes=2,
  ).unwrap()
  let right = object_contract(
    [("a", array), ("y", number)],
    nullable=false,
    max_fields=2,
    max_name_bytes=2,
  ).unwrap()
  // Root+two immediate children fit 3, but the first array's child would not.
  // The unequal last name is observed first, not a later RelationLimit.
  assert_eq(compare(left, right, 3, Equal), (false, 1))
  assert_eq(
    drain_equality_steps(start_type_equality(left, right, 3), 2),
    (Some(false), 2),
  )
  assert_true(equality_raises(() => type_equal(left, right, 2), RelationLimit))
  assert_true(equality_raises(() => type_equal(left, left, 3), RelationLimit))
  assert_true(type_equal(left, left, 4))
}

///|
test "type equality cancellation drops borrowed frames and rejects terminal reuse" {
  let number = primitive(NumberType, nullable=false)
  let name = String::make(1024, 'a')
  let object = object_contract(
    [(name, number)],
    nullable=false,
    max_fields=1,
    max_name_bytes=1024,
  ).unwrap()
  let cursor = start_type_equality(object, object, 2)
  assert_eq(advance_type_equality(cursor), None)
  assert_eq(advance_type_equality(cursor), None)
  assert_eq(cursor.pending.length(), 2)
  cancel_type_equality(cursor)
  cancel_type_equality(cursor)
  assert_eq(type_equality_next_frames(cursor), 0)
  assert_eq(cursor.pending.length(), 0)
  assert_true(
    equality_raises(() => advance_type_equality(cursor), InvalidRelationLimit),
  )
  assert_true(type_equal(object, object, 2))
  assert_true(
    equality_raises(
      () => start_type_equality(number, number, -1),
      InvalidRelationLimit,
    ),
  )
  assert_true(
    equality_raises(() => type_equal(number, number, 0), RelationLimit),
  )
}
