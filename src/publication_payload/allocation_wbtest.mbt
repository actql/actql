///|
test "portable allocation codec preserves independent original name and bodies" {
  let request = payload_request()
  let name = "alloc-" + "3".repeat(64) + "-1"
  let owned_body = name + "|41|73"
  assert_eq(
    publication_payload_allocation_namespace(),
    "publication_payload_allocation",
  )
  assert_eq(PUBLICATION_PAYLOAD_ALLOCATION_FILE, "payload")
  assert_eq(prepare_publication_payload_allocation_name(request, 1L), name)
  assert_eq(
    encode_publication_payload_allocation(name, None),
    @utf8.encode(name),
  )
  assert_eq(
    encode_publication_payload_allocation(
      name,
      Some({ device: 41UL, inode: 73UL, }),
    ),
    @utf8.encode(owned_body),
  )
  let intent = admit_publication_payload_allocation(request, @utf8.encode(name)).unwrap()
  assert_eq(publication_payload_allocation_name(intent), name)
  assert_eq(publication_payload_allocation_ownership(intent), None)
  let owned = admit_publication_payload_allocation(
    request,
    @utf8.encode(owned_body),
  ).unwrap()
  assert_eq(publication_payload_allocation_name(owned), name)
  assert_eq(
    publication_payload_allocation_ownership(owned),
    Some({ device: 41UL, inode: 73UL, }),
  )
  assert_eq(
    next_publication_payload_allocation_ordinal(request, name).unwrap(),
    2L,
  )
}

///|
test "portable allocation codec preserves original decimal acceptance without inventing ownership" {
  let request = payload_request()
  let prefix = "alloc-" + "3".repeat(64) + "-"
  let intent = admit_publication_payload_allocation(
    request,
    @utf8.encode(prefix + "0"),
  ).unwrap()
  assert_eq(publication_payload_allocation_ownership(intent), None)
  assert_eq(
    next_publication_payload_allocation_ordinal(request, prefix + "0").unwrap(),
    1L,
  )
  let owned = admit_publication_payload_allocation(
    request,
    @utf8.encode(prefix + "001|00041|073"),
  ).unwrap()
  assert_eq(publication_payload_allocation_name(owned), prefix + "001")
  assert_eq(
    publication_payload_allocation_ownership(owned),
    Some({ device: 41UL, inode: 73UL, }),
  )
  assert_eq(
    next_publication_payload_allocation_ordinal(request, prefix + "001").unwrap(),
    2L,
  )
  let edge = admit_publication_payload_allocation(
    request,
    @utf8.encode(prefix + "1000000000000009|1000000000000009|0"),
  ).unwrap()
  assert_eq(
    publication_payload_allocation_ownership(edge),
    Some({ device: 1000000000000009UL, inode: 0UL, }),
  )
  assert_eq(
    next_publication_payload_allocation_ordinal(
      request,
      prefix + "1000000000000009",
    ).unwrap(),
    1000000000000010L,
  )
}

///|
test "portable allocation codec rejects foreign keys malformed bodies and original range overflow" {
  let request = payload_request()
  let prefix = "alloc-" + "3".repeat(64) + "-"
  for
    body in [
      "",
      "alloc-" + "a".repeat(64) + "-1",
      prefix,
      prefix + "-1",
      prefix + "+1",
      prefix + "1|41",
      prefix + "1|41|73|extra",
      prefix + "1||73",
      prefix + "1|41|-73",
      prefix + "1|41|+73",
      prefix + "1|4e1|73",
      prefix + "1000000000000010",
      prefix + "1|1000000000000010|73",
      prefix + "1|41|18446744073709551615",
      prefix + "1\n",
      prefix + "1|41|73\n",
    ] {
    assert_true(
      admit_publication_payload_allocation(request, @utf8.encode(body))
      is Err(StateCollision),
    )
  }
  for
    name in [
      "alloc-" + "a".repeat(64) + "-1",
      prefix + "-1",
      prefix + "1|41|73",
    ] {
    assert_true(
      next_publication_payload_allocation_ordinal(request, name)
      is Err(StateCollision),
    )
  }
  assert_true(
    admit_publication_payload_allocation(request, b"\xff")
    is Err(StateCollision),
  )
}
