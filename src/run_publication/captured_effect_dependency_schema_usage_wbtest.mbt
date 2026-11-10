///|
test "schema body keeps original encoder nodes when only a column label grows" {
  let short =
    #|{"a":{"nullable":false,"type":"string"}}
  let long = "{\"" +
    "a".repeat(4096) +
    "\":{\"nullable\":false,\"type\":\"string\"}}"
  let a = admit_hashed_effect_dependency_body(
    "relation_schema", "sha256:a6fdd6aaeebbc3e1e731b017de57774622d432d2a6408ce2768a86aa35c8fb3c",
    short, 8192, 32, 8,
  ).unwrap()
  let cursor = material_cursor(long, 8192, 32, 8).unwrap()
  let b = admit_hashed_effect_dependency_body(
    "relation_schema",
    "sha256:8e9ef3eacadac4b4dfc1a06fc2261297b280328b00cb946a8f61f87bd18467e3",
    long,
    8192,
    32,
    8,
    cursor=Some(cursor),
  ).unwrap()
  let (ab, an, ad) = captured_effect_dependency_body_wire_usage(a).unwrap()
  let (bb, bn, bd) = captured_effect_dependency_body_wire_usage(b).unwrap()
  assert_true(bb > ab)
  assert_eq(an, 4)
  assert_eq(bn, an)
  assert_eq(ad, 2)
  assert_eq(bd, ad)
  assert_eq(captured_effect_dependency_body_field_count(a), Some(1))
  assert_eq(captured_effect_dependency_body_field_count(b), Some(1))
}

///|
test "schema cursor cannot replace the original canonical body or identity" {
  let wire =
    #|{"a":{"nullable":false,"type":"string"}}
  let cursor = material_cursor(wire, 8192, 32, 8).unwrap()
  assert_true(
    admit_hashed_effect_dependency_body(
      "relation_schema",
      "sha256:" + "0".repeat(64),
      wire,
      8192,
      32,
      8,
      cursor=Some(cursor),
    )
    is Err(InvalidBody),
  )
  assert_true(
    admit_hashed_effect_dependency_body(
      "relation_schema",
      "sha256:a6fdd6aaeebbc3e1e731b017de57774622d432d2a6408ce2768a86aa35c8fb3c",
      "{}",
      8192,
      32,
      8,
      cursor=Some(cursor),
    )
    is Err(InvalidBody),
  )
}
