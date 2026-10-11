///|
test "checked inventory owns aliases tasks and exact Result definitions" {
  let program = "sha256:" + "1".repeat(64)
  let inventory = prepare_checked_publication_inventory(
    program,
    ["first", "second"],
    [1, 1],
  ).unwrap()
  assert_eq(checked_publication_inventory_program_cid(inventory), program)
  assert_eq(checked_publication_inventory_count(inventory), 2)
  assert_eq(checked_publication_inventory_name(inventory, 0).unwrap(), "first")
  assert_eq(checked_publication_inventory_task(inventory, 0).unwrap(), 1)
  assert_eq(
    checked_publication_inventory_definition_cid(inventory, 0).unwrap(),
    "sha256:33cc81bf0c5e877d80d3dacf71d80fb8ef5472d6e224c83efac057853e67d966",
  )
  assert_eq(
    checked_publication_inventory_definition_cid(inventory, 1).unwrap(),
    "sha256:e11eba03bcf3d0704ba0f54930d687a118b5a14875f160a46ccc189e142b2ae2",
  )
  assert_eq(
    publication_contract_identity(
      checked_publication_inventory_definition(inventory, 0).unwrap(),
    ),
    "sha256:33cc81bf0c5e877d80d3dacf71d80fb8ef5472d6e224c83efac057853e67d966",
  )
  assert_true(
    checked_publication_inventory_definition(inventory, -1) is Err(InvalidIndex),
  )
  assert_true(
    checked_publication_inventory_definition(inventory, 2) is Err(InvalidIndex),
  )
}

///|
test "Effect-only checked inventory is empty without inventing Result occurrences" {
  let program = "sha256:" + "1".repeat(64)
  let inventory = prepare_checked_publication_inventory(program, [], []).unwrap()
  assert_eq(checked_publication_inventory_count(inventory), 0)
  assert_eq(checked_publication_inventory_program_cid(inventory), program)
  assert_true(
    prepare_checked_publication_inventory(program, [], [1])
    is Err(LengthMismatch),
  )
}

///|
test "checked inventory rejects duplicate or unaligned subsets" {
  let program = "sha256:" + "1".repeat(64)
  assert_true(
    prepare_checked_publication_inventory(program, ["answer"], [])
    is Err(LengthMismatch),
  )
  assert_true(
    prepare_checked_publication_inventory(program, ["answer", "answer"], [1, 2])
    is Err(DuplicateResult("answer")),
  )
  assert_true(
    prepare_checked_publication_inventory(program, ["answer"], [-1])
    is Err(InvalidTask(-1)),
  )
}
