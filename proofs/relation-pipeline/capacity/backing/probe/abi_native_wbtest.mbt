///|
#borrow(map)
extern "C" fn map_layout(map : Map[String, Int], selector : Int) -> UInt64 = "actql_proof_map_layout"

///|
#borrow(input, binding, projection, snapshot)
extern "C" fn map_json(
  input : Map[String, Int],
  binding : Map[String, Int],
  projection : Map[String, Int],
  snapshot : Map[String, Int],
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
    map_json(fields, other, Map([]), Map([])).contains(
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
