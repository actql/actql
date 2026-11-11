///|
test "declared-file read profile retains its independent identity and refuses the Native entrance" {
  let body =
    #|{"physical_source_view_contract_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","projection":{"content_utf8_field":"notes","identity_field":"id","items_path":["items"],"key_path":["id"],"media_type_field":"mime","name_field":"name","path_field":null,"version_field":"version"},"request_schema_cid":"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","response_schema_cid":"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd","source_view_contract_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","version":"actql-declared-file-content-read/0.1"}
  let profile = seal_publication_contract(
    "declared_file_content_read", body, 16384, 1024, 20,
  ).unwrap()
  // Independent standard-library SHA-256 of the authored canonical preimage.
  assert_eq(
    publication_contract_identity(profile),
    "sha256:715e84575b45d5c3cba0330d2384f026b74b3736721f3396e74943ab750c36b0",
  )
  assert_true(native_file_read_profile_contract_bindings(profile) is None)
  assert_true(file_read_profile_contract_bindings(profile) is Some(_))
  let writer = @encode.writer(100, 10, 10)
  @encode.begin_object(writer)
  @encode.end_object(writer)
  let static_request = @encode.finish_document(writer)
  assert_true(
    issue_native_file_lookup_transport(profile, static_request, 16384, 1024, 20)
    is Err(_),
  )
  let transport = issue_file_lookup_transport(
    profile, static_request, 16384, 1024, 20,
  ).unwrap()
  assert_true(transport.wire.contains(publication_contract_identity(profile)))
  let restored = admit_publication_contract(
    "declared_file_content_read",
    profile.wire,
    16384,
    1024,
    20,
  ).unwrap()
  assert_eq(restored.identity, profile.identity)
  assert_true(
    admit_publication_contract(
      "native_file_content_read",
      profile.wire,
      16384,
      1024,
      20,
    )
    is Err(_),
  )
  assert_true(
    admit_publication_contract(
      "declared_file_content_read",
      profile.wire.replace(old="notes", new="other"),
      16384,
      1024,
      20,
    )
    is Err(IdentityMismatch),
  )
}
