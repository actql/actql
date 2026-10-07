///|
#borrow(map)
extern "C" fn map_layout(map : Map[String, Int], selector : Int) -> UInt64 = "actql_proof_map_layout"

///|
#borrow(input, binding, projection)
extern "C" fn map_json(
  input : Map[String, Int],
  binding : Map[String, Int],
  projection : Map[String, Int],
) -> String = "actql_proof_map_json"

///|
test "native Map extent and backing identity come from actual objects" {
  let mut fields : Map[String, Int] = Map([])
  let other : Map[String, Int] = Map([])
  // Independent ABI derivation: header = two 32-bit words; the Map has two
  // references and five Int fields, padded to pointer alignment. Entry has
  // two references and four Int fields. Declared field order creates internal
  // padding: prev at 0, next at 8, psl at 16, hash at 20, key at 24, value at 32.
  // Tail padding makes its payload 40 bytes, plus an eight-byte header.
  // Borrowed key String objects are separate.
  assert_eq(map_layout(fields, 7), 8UL)
  assert_eq(map_layout(fields, 8), 8UL)
  assert_eq(map_layout(fields, 0), 48UL)
  assert_eq(map_layout(fields, 2), 8UL)
  assert_eq(map_layout(fields, 3), 72UL)
  assert_eq(map_layout(fields, 4), 0UL)
  assert_eq(map_layout(fields, 6), 120UL)
  let table = map_layout(fields, 1)
  assert_true(table != map_layout(other, 1))
  assert_true(map_layout(fields, 9) != map_layout(other, 9))
  for i, name in ["k", "extra", "tag"] {
    fields[name] = i
  }
  assert_eq(map_layout(fields, 1), table)
  assert_eq(map_layout(fields, 4), 3UL)
  assert_eq(map_layout(fields, 5), 144UL)
  assert_eq(map_layout(fields, 6), 264UL)
  assert_true(
    map_json(fields, other, Map([])).contains(
      "\"requestedBytes\":\"264\"",
    ),
  )
  fields["k"] = 42
  assert_eq(map_layout(fields, 6), 264UL)
  fields.clear()
  assert_eq(map_layout(fields, 1), table)
  assert_eq(map_layout(fields, 4), 0UL)
  assert_eq(map_layout(fields, 6), 120UL)
  // This deliberate holder belongs to the test, not the scalar observer.
  let old = fields
  fields = Map([])
  assert_true(map_layout(fields, 1) != map_layout(old, 1))
  assert_eq(map_layout(fields, 6) + map_layout(old, 6), 240UL)
  println(
    "ACTQL_BACKING_CORE:{\"target\":\"native\",\"case\":\"native-map\",\"headerBytes\":8,\"pointerBytes\":8,\"mapBytes\":48,\"tableBytes\":72,\"entryBytes\":48,\"emptyBytes\":120,\"threeKeysBytes\":264,\"replacementBytes\":240}",
  )
}

///|
#borrow(array)
extern "C" fn int_array_layout(
  array : Array[Int],
  element : Int,
  selector : Int,
) -> UInt64 = "actql_proof_array_layout"

///|
#borrow(array)
extern "C" fn names_array_json(array : Array[String], element : Int) -> String = "actql_proof_array_json"

///|
test "native Array extents distinguish owners, static empty buffers and growth" {
  let values : Array[Int] = []
  let other : Array[Int] = []
  assert_eq(int_array_layout(values, 1, 0), 24UL)
  assert_eq(int_array_layout(values, 1, 2), 0UL)
  assert_eq(int_array_layout(values, 1, 3), 8UL)
  assert_eq(int_array_layout(values, 1, 7), 1UL)
  assert_eq(int_array_layout(values, 1, 1), int_array_layout(other, 1, 1))
  assert_true(int_array_layout(values, 1, 6) != int_array_layout(other, 1, 6))
  for i in 0..<8 {
    values.push(i)
  }
  let old = int_array_layout(values, 1, 1)
  let same_array = values
  let holder = values.view()
  assert_eq(int_array_layout(values, 1, 2), 8UL)
  assert_eq(int_array_layout(values, 1, 3), 40UL)
  assert_eq(int_array_layout(values, 1, 7), 0UL)
  values.push(8)
  assert_true(int_array_layout(values, 1, 1) != old)
  assert_eq(int_array_layout(values, 1, 6), int_array_layout(same_array, 1, 6))
  assert_eq(int_array_layout(values, 1, 3), 72UL)
  assert_eq(holder[7], 7)
  let grown = int_array_layout(values, 1, 1)
  values.clear()
  assert_eq(int_array_layout(values, 1, 1), grown)
  assert_eq(int_array_layout(values, 1, 4), 0UL)
  assert_eq(int_array_layout(values, 1, 3), 72UL)
  let names = Array::makei(3, i => i.to_string())
  assert_true(names_array_json(names, 2).contains("\"backingBytes\":\"32\""))
  assert_true(names_array_json(names, 2).contains("\"elementBytes\":8"))
  println(
    "ACTQL_BACKING_CORE:{\"target\":\"native\",\"case\":\"native-array\",\"ownerBytes\":24,\"emptyBackingBytes\":8,\"int8BackingBytes\":40,\"int16BackingBytes\":72,\"names3BackingBytes\":32}",
  )
}
