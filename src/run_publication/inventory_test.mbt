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
}

///|
test "checked inventory rejects subsets that are empty duplicate or unaligned" {
  let program = "sha256:" + "1".repeat(64)
  assert_true(
    prepare_checked_publication_inventory(program, [], [])
    is Err(EmptyInventory),
  )
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
