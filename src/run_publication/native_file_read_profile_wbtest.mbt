///|
test "Native file read profile seals actual projection and rejects HTTP or tampered wire" {
  let body =
    #|{"physical_source_view_contract_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","projection":{"content_utf8_field":"notes","identity_field":"id","items_path":["items"],"key_path":["id"],"media_type_field":"mime","name_field":"name","path_field":null,"version_field":"version"},"request_schema_cid":"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","response_schema_cid":"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd","source_view_contract_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","version":"actql-native-file-content-read/0.1"}
  let profile = seal_publication_contract(
    "native_file_content_read", body, 16384, 1024, 20,
  ).unwrap()
  // Independent SHA-256 of the authored canonical preimage.
  assert_eq(
    publication_contract_identity(profile),
    "sha256:6ccc82532f36f49c503d3d63b1b335143c753a5b9509cf98fc598b1314674c7c",
  )
  let wire = publication_contract_json(profile)
  let restored = admit_publication_contract(
    "native_file_content_read", wire, 16384, 1024, 20,
  ).unwrap()
  assert_eq(
    publication_contract_identity(restored),
    publication_contract_identity(profile),
  )
  assert_true(
    admit_publication_contract(
      "native_file_content_read",
      wire.replace(old="notes", new="other"),
      16384,
      1024,
      20,
    )
    is Err(IdentityMismatch),
  )
  assert_true(
    seal_publication_contract(
      "native_file_content_read",
      body.replace(old="items_path", new="http_method"),
      16384,
      1024,
      20,
    )
    is Err(_),
  )
  assert_true(
    seal_publication_contract(
      "native_file_content_read",
      body.replace(
        old="actql-native-file-content-read/0.1",
        new="actql-http-read/0.1",
      ),
      16384,
      1024,
      20,
    )
    is Err(_),
  )
}
