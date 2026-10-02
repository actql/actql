///|
test "clear changes visible length without proving backing release" {
  let values : Array[Int] = []
  for i in 0..<17 {
    values.push(i)
    if backend() == "js" {
      assert_eq(values.capacity(), values.length())
    } else {
      assert_true(values.capacity() <= Int::max(8, 2 * values.length()))
    }
  }
  let before = values.capacity()
  // This holder is an explicit test operation, not an observer inserted into
  // the product pipeline. It exercises the real core retention contract.
  let holder = values.view()
  values.clear()
  assert_eq(values.length(), 0)
  if backend() == "js" {
    assert_eq(values.capacity(), 0)
  } else {
    assert_eq(values.capacity(), before)
    assert_eq(holder[16], 16)
  }
  println(
    "ACTQL_BACKING_CORE:{\"target\":\"" +
    backend() +
    "\",\"case\":\"clear\",\"before\":" +
    before.to_string() +
    ",\"after\":" +
    values.capacity().to_string() +
    "}",
  )
}

///|
test "a shared Array wrapper can acquire a different backing during growth" {
  let values : Array[Int] = []
  for i in 0..<9 {
    values.push(i)
  }
  let same_array = values
  let prior_capacity = values.capacity()
  let prior_holder = values.view()
  for i in 9..<17 {
    values.push(i)
  }
  values[0] = 99
  assert_true(physical_equal(values, same_array))
  if backend() == "js" {
    assert_eq(prior_holder[0], 99)
  } else {
    assert_eq(prior_holder[0], 0)
    assert_true(values.capacity() > prior_capacity)
  }
  println(
    "ACTQL_BACKING_CORE:{\"target\":\"" +
    backend() +
    "\",\"case\":\"growth\",\"prior\":" +
    prior_capacity.to_string() +
    ",\"current\":" +
    values.capacity().to_string() +
    "}",
  )
}

///|
test "initial reservation is separate from visible high-water length" {
  let values : Array[Int] = Array(capacity=32)
  assert_eq(values.length(), 0)
  assert_eq(values.capacity(), if backend() == "js" { 0 } else { 32 })
  values.clear()
  assert_eq(values.capacity(), if backend() == "js" { 0 } else { 32 })
}

///|
test "Map table slots survive empty and cleared contents" {
  let fields : Map[String, Int] = Map([])
  assert_eq(fields.capacity(), 8)
  for i, name in ["k", "extra", "tag"] {
    fields[name] = i
  }
  assert_eq(fields.length(), 3)
  assert_eq(fields.capacity(), 8)
  fields["k"] = 42
  assert_eq(fields.length(), 3)
  assert_eq(fields.capacity(), 8)
  assert_eq(fields.get("k"), Some(42))
  fields.clear()
  assert_eq(fields.length(), 0)
  assert_eq(fields.capacity(), 8)
  // The no-grow premise is meaningful: a seventh genuine insertion grows.
  for i in 0..<7 {
    fields[i.to_string()] = i
  }
  assert_eq(fields.length(), 7)
  assert_eq(fields.capacity(), 16)
  fields.clear()
  assert_eq(fields.length(), 0)
  assert_eq(fields.capacity(), 16)
  println(
    "ACTQL_BACKING_CORE:{\"target\":\"" +
    backend() +
    "\",\"case\":\"map\",\"default\":8,\"threeKeys\":8,\"seventhKey\":16,\"cleared\":" +
    fields.capacity().to_string() +
    "}",
  )
}
