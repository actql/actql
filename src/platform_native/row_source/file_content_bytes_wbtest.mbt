///|
let file_content_first_version = "sha256:6df0c833b85e3417b5b3ba80ac25b48da0b2fc09287c54015e6e76d34c141b3a"

///|
fn file_content_fixture_document(
  provider : NativeRelationFilePreparedProvider,
  body : String,
) -> @rows.RelationDocument {
  let wire = "{\"items\":[{\"id\":\"first\",\"name\":\"Acme🌱\",\"version\":\"label\",\"media_type\":\"text/plain\",\"body\":" +
    Json::string(body).stringify() +
    ",\"path\":null}]}"
  @rows.admit_relation_document(
    @utf8.encode(wire),
    provider.limits.page,
    provider.limits.max_work,
  ).unwrap()
}

///|
test "Native file Content extracts exact bytes only for the original listing version" {
  let (provider, document, fields) = file_listing_page_fixture()
  let (media, bytes) = project_native_relation_file_content_bytes(
    provider, document, fields, "body", "first", file_content_first_version, 11,
  ).unwrap()
  assert_eq(media, "text/plain")
  assert_eq(bytes, b"first\nnotes")
  assert_eq(bytes.length(), 11)
  // The projection returns DATA, never a ContentRef or a consumed response.
  assert_true(@rows.relation_document_usage(document) is Some(_))
  assert_true(@rows.discard_relation_document_original(document))
}

///|
test "Native file Content rejects a changed row even when its authored label is unchanged" {
  let (provider, initial, fields) = file_listing_page_fixture()
  assert_true(@rows.discard_relation_document_original(initial))
  let changed = file_content_fixture_document(provider, "changed notes")
  assert_true(
    project_native_relation_file_content_bytes(
      provider, changed, fields, "body", "first", file_content_first_version, 100,
    )
    is Err(ForeignOriginal),
  )
  assert_true(@rows.relation_document_usage(changed) is Some(_))
  assert_true(@rows.discard_relation_document_original(changed))
}

///|
test "Native file Content preserves decomposed Unicode CRLF empty bytes and the exact byte ceiling" {
  let (provider, initial, fields) = file_listing_page_fixture()
  assert_true(@rows.discard_relation_document_original(initial))
  let unicode = file_content_fixture_document(provider, "e\u{0301}\r\n🌱")
  // Independent canonical row + exposed-version SHA-256, authored from this
  // literal fixture without reading product output or normalizing its text.
  let version = "sha256:25989464d87c409458e41d644e269169628fdd6d4c68205d7b768790ad2ed28a"
  assert_true(
    project_native_relation_file_content_bytes(
      provider, unicode, fields, "body", "first", version, 8,
    )
    is Err(FileLimit),
  )
  let (_, bytes) = project_native_relation_file_content_bytes(
    provider, unicode, fields, "body", "first", version, 9,
  ).unwrap()
  assert_eq(
    bytes,
    Bytes::from_array([101, 204, 129, 13, 10, 240, 159, 140, 177]),
  )
  assert_true(@rows.discard_relation_document_original(unicode))
  let empty = file_content_fixture_document(provider, "")
  let (_, bytes) = project_native_relation_file_content_bytes(
    provider, empty, fields, "body", "first", "sha256:3e6321d460cccd0ea0f9f3df37fd7868fdb7e5d77cf5b7839b77082798f232c8",
    0,
  ).unwrap()
  assert_eq(bytes, b"")
  assert_true(@rows.discard_relation_document_original(empty))
}

///|
test "Native file Content refuses unavailable fields retired originals and invalid constructor bounds" {
  let (provider, document, fields) = file_listing_page_fixture()
  assert_true(
    project_native_relation_file_content_bytes(
      provider, document, fields, "absent", "first", file_content_first_version,
      11,
    )
    is Err(InvalidInput),
  )
  assert_true(
    project_native_relation_file_content_bytes(
      provider, document, fields, "body", "absent", file_content_first_version, 11,
    )
    is Err(Document(_)),
  )
  for invalid in [-1, provider.limits.page.max_bytes + 1] {
    assert_true(
      native_relation_file_content_construction_inventory(provider, invalid)
      is None,
    )
    assert_true(
      project_native_relation_file_content_bytes(
        provider, document, fields, "body", "first", file_content_first_version,
        invalid,
      )
      is Err(InvalidInput),
    )
  }
  let lower = native_relation_file_content_construction_inventory(provider, 0).unwrap()
  let upper = native_relation_file_content_construction_inventory(provider, 1).unwrap()
  assert_eq(upper.owned_wire_bytes - lower.owned_wire_bytes, 1L)
  assert_eq(upper.record_headers, lower.record_headers)
  assert_eq(upper.reference_slots, lower.reference_slots)
  assert_eq(upper.scalar_words, lower.scalar_words)
  assert_eq(upper.owned_utf16_units, lower.owned_utf16_units)
  assert_eq(
    @execution.preparation_representation_cost(upper).unwrap() -
    @execution.preparation_representation_cost(lower).unwrap(),
    1L,
  )
  assert_true(@rows.discard_relation_document_original(document))
  assert_true(
    project_native_relation_file_content_bytes(
      provider, document, fields, "body", "first", file_content_first_version, 11,
    )
    is Err(Document(_)),
  )
}
