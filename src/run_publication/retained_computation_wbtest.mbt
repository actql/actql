///|
test "retained inventories preserve order and actual contract identity" {
  let program = "sha256:" + "1".repeat(64)
  let a = result_definition_contract(
    prepare_result_definition(program, "a").unwrap(),
  )
  let b = result_definition_contract(
    prepare_result_definition(program, "b").unwrap(),
  )
  let copy = admit_publication_contract(
    "result_definition",
    a.wire,
    65536,
    4096,
    32,
  ).unwrap()
  assert_true(captured_computation_inventory_matches([a, b], [a, b]))
  assert_true(!captured_computation_inventory_matches([a, b], [b, a]))
  assert_true(!captured_computation_inventory_matches([a, b], [copy, b]))
  assert_true(!captured_computation_inventory_matches([a, b], [a, a]))
}
