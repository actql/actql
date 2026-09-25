///|
test "create identities order content and preserve equal-row occurrences" {
  let a = "{\"state\":\"present\",\"value\":{\"Name\":\"A\"}}"
  let b = "{\"state\":\"present\",\"value\":{\"Name\":\"B\"}}"
  let rows = derive_effect_create_row_inventory([b, a, a], 3, 512, 32, 5).unwrap()
  let content_a = "sha256:0e66ae94947132fdf9d3e99be423a772b4d1cb82aee1bf31b3499bf047f7b6bd"
  let content_b = "sha256:a6f11a66582aca6dd58c9ca35ece44984ac715d6d0f299e4adfa51c14e2f9eb3"
  assert_eq(rows.length(), 3)
  assert_eq(
    rows[0],
    (1, "{\"content_cid\":\"" + content_a + "\",\"occurrence\":0}"),
  )
  assert_eq(
    rows[1],
    (2, "{\"content_cid\":\"" + content_a + "\",\"occurrence\":1}"),
  )
  assert_eq(
    rows[2],
    (0, "{\"content_cid\":\"" + content_b + "\",\"occurrence\":0}"),
  )
  assert_true(
    derive_effect_create_row_inventory([a], 0, 512, 32, 5) is Err(Encoding),
  )
  assert_true(
    derive_effect_create_row_inventory([a], 1, 4, 32, 5) is Err(Encoding),
  )
  assert_true(
    derive_effect_create_row_inventory(
      ["{\"state\":\"absent\"}"],
      1,
      512,
      32,
      5,
    )
    is Err(InvalidMember),
  )
}
