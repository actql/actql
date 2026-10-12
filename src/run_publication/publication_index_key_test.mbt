///|
/// Independent literal preimages are retained in the companion fixture.
test "public index key independent raw namespace vectors" {
  let authority = "sha256:4444444444444444444444444444444444444444444444444444444444444444"
  let run = "sha256:3333333333333333333333333333333333333333333333333333333333333333"
  assert_eq(
    publication_index_scope_storage_key("local", authority, run, 32768, 256, 16).unwrap(),
    "1d1daf4340a0b94e94c40af7329fa6f3f99e139ed8a009ef4b7c4d76c0c85e33",
  )
  assert_eq(
    publication_index_scope_storage_key(
      "é/~😀", authority, run, 32768, 256, 16,
    ).unwrap(),
    "a3daec031e0d628b113f6545c2dcb943d909807652ef7cdb202693b0cdb63e38",
  )
  assert_eq(
    publication_index_scope_storage_key(
      "é/~😀", authority, run, 32768, 256, 16,
    ).unwrap(),
    "3388ea28f2524f0dfa70e50a329cb8446ecd3d4d6fbe3944705547ba0122fba9",
  )
  assert_eq(
    publication_index_scope_storage_key(
      "line\r\nend", authority, run, 32768, 256, 16,
    ).unwrap(),
    "09c9e020c4130a43741cbafbce5117d32f09e3957754ebf421c190733b56715b",
  )
}

///|
test "original index key matches the independently fixed scope" {
  let (index, _, _) = delivery_test_root()
  assert_eq(
    publication_index_storage_key(index, 32768, 256, 16).unwrap(),
    "d167a9d157f68cfd462313a94337c5db45da403a5ad2f39e305e8abe5318bd47",
  )
}

///|
test "index key refusal preserves bounded encoding and scope validation" {
  let authority = "sha256:4444444444444444444444444444444444444444444444444444444444444444"
  let run = "sha256:3333333333333333333333333333333333333333333333333333333333333333"
  assert_true(
    publication_index_scope_storage_key("", authority, run, 32768, 256, 16)
    is Err(_),
  )
  assert_true(
    publication_index_scope_storage_key("local", "invalid", run, 32768, 256, 16)
    is Err(_),
  )
  assert_true(
    publication_index_scope_storage_key("local", authority, run, 1, 256, 16)
    is Err(_),
  )
  assert_true(
    publication_index_scope_storage_key("local", authority, run, 32768, 1, 16)
    is Err(_),
  )
  assert_true(
    publication_index_scope_storage_key("local", authority, run, 32768, 256, 0)
    is Err(_),
  )
}
