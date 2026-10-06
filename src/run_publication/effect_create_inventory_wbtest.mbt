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

///|
test "create content identities preserve JSON keys and nested envelope data" {
  // Independent SHA-256 of {"value":AFTER,"version":"actql-effect-content-row/0.1"}.
  // AFTER is {"state":"present","value":{"j":{"$json":PAYLOAD}}}, with
  // each exact canonical payload below. Expected identities are not generated
  // from the inventory implementation.
  for
    (payload, cid) in [
      (
        (
          #|{"é":2,"é":1}
        ),
        "sha256:0f965d8384f59e7c1a34806ae0b67a3f5cef060a1c886bab899ab12c53fe5d8a",
      ),
      (
        (
          #|{"é":2}
        ),
        "sha256:040955451d7b8ce492eef9be4ba9feb27fcf3a34f7ad369a5e5421cb9cacdabb",
      ),
      (
        (
          #|{"é":2}
        ),
        "sha256:73b68908e7c7300bc62eb254fbfe792057df69cdc4425bba4eedf7e3ea8347ae",
      ),
      (
        (
          #|{"$json":null,"é":2,"line":"a\r\nb","é":1}
        ),
        "sha256:2c9a665f80ddbfdc3fae674feb44579fb13983008d6a1bbe83c108f99b1466a0",
      ),
    ] {
    let after = "{\"state\":\"present\",\"value\":{\"j\":{\"$json\":" +
      payload +
      "}}}"
    let rows = derive_effect_create_row_inventory([after], 1, 4096, 128, 16).unwrap()
    assert_eq(rows, [(0, "{\"content_cid\":\"" + cid + "\",\"occurrence\":0}")])
  }
  // Preserving data keys does not permit duplicate exact JSON members.
  assert_true(
    derive_effect_create_row_inventory(
      [
        (
          #|{"state":"present","value":{"j":{"$json":{"é":1,"é":2}}}}
        ),
      ],
      1,
      4096,
      128,
      16,
    )
    is Err(InvalidMember),
  )
}
