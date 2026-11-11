///|
fn native_transport_fixture() -> PublicationContract {
  let body =
    #|{"physical_source_view_contract_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","projection":{"content_utf8_field":"notes","identity_field":"id","items_path":["items"],"key_path":["id"],"media_type_field":"mime","name_field":"name","path_field":null,"version_field":"version"},"request_schema_cid":"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","response_schema_cid":"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd","source_view_contract_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","version":"actql-native-file-content-read/0.1"}
  seal_publication_contract("native_file_content_read", body, 16384, 1024, 20).unwrap()
}

///|
test "Native transport retains measured static DATA and its independent original identity" {
  let profile = native_transport_fixture()
  let w = @encode.writer(4096, 100, 10)
  @encode.begin_object(w)
  @encode.key(w, "e\u0301")
  @encode.string_value(w, "kept")
  @encode.end_object(w)
  let document = @encode.finish_document(w)
  assert_eq(@encode.document_usage(document), (14, 2, 1))
  let transport = issue_native_file_lookup_transport(
    profile, document, 16384, 1024, 20,
  ).unwrap()
  // Independent Python standard-library SHA-256 of the authored canonical body.
  assert_eq(
    transport.identity,
    "sha256:da5687c140aeadef2f836335f62bf3e3d986d293d88156230c7c04ecd8e84bc7",
  )
  assert_true(transport.wire.contains("e\u0301"))
  assert_false(transport.wire.contains("é"))
  assert_eq(
    admit_publication_contract(
      "native_file_lookup_transport",
      transport.wire,
      16384,
      1024,
      20,
    ).unwrap().identity,
    transport.identity,
  )
  assert_true(
    admit_publication_contract(
      "native_file_lookup_transport",
      transport.wire.replace(old="kept", new="changed"),
      16384,
      1024,
      20,
    )
    is Err(IdentityMismatch),
  )
}

///|
test "Native transport refuses unsupported batching pagination retry and a foreign profile purpose" {
  let w = @encode.writer(100, 10, 10)
  @encode.begin_object(w)
  @encode.end_object(w)
  let document = @encode.finish_document(w)
  let transport = issue_native_file_lookup_transport(
    native_transport_fixture(),
    document,
    16384,
    1024,
    20,
  ).unwrap()
  let body = @json.stringify_value(
    @json.object_without_field(transport.value, "self_cid").unwrap(),
    16384,
    1024,
    20,
  )
  for
    (old, replacement) in [
      ("\"single\"", "\"native\""),
      ("\"max_keys_per_batch\":1", "\"max_keys_per_batch\":2"),
      ("\"none\"", "\"cursor\""),
      (
        "\"max_network_attempts_per_request\":1", "\"max_network_attempts_per_request\":2",
      ),
      ("\"retryable_error_codes\":[]", "\"retryable_error_codes\":[\"x\"]"),
    ] {
    assert_true(
      seal_publication_contract(
        "native_file_lookup_transport",
        body.replace(old~, new=replacement),
        16384,
        1024,
        20,
      )
      is Err(_),
    )
  }
  assert_true(
    issue_native_file_lookup_transport(transport, document, 16384, 1024, 20)
    is Err(InvalidField("native_file_read_profile")),
  )
  assert_true(
    issue_native_file_lookup_transport(
      native_transport_fixture(),
      document,
      1,
      1024,
      20,
    )
    is Err(_),
  )
}
