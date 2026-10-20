///|
fn captured_content_media_schema(
  media_types : Array[String?],
) -> @schema.Schema {
  let fields = media_types.mapi((index, media_type) => {
    (
      @schema.Unqualified("content_" + index.to_string()),
      { nullable: false, shape: @contract.ContentRef(media_type~), },
    )
  })
  @schema.from_fields(fields, max_fields=8, max_name_bytes=256).unwrap()
}

///|
test "captured Content accepts an actual MIME under an unrefined Source contract" {
  let schema = captured_content_media_schema([None])
  for media_type in ["text/plain", "application/pdf", "image/png"] {
    assert_true(
      client_captured_content_schema_media_matches(schema, media_type),
    )
  }
  let reported = "Text/Plain;LABEL=OpaqueValue"
  let observed = @contract.normalize_content_media_type_case(reported, 256).unwrap()
  assert_eq(observed, "text/plain;label=OpaqueValue")
  assert_true(client_captured_content_schema_media_matches(schema, observed))
  // Schema compatibility neither rewrites the original report nor issues a Ref.
  assert_eq(reported, "Text/Plain;LABEL=OpaqueValue")
}

///|
test "captured Content keeps the exact declared MIME refinement" {
  let schema = captured_content_media_schema([Some("application/pdf")])
  assert_true(
    client_captured_content_schema_media_matches(schema, "application/pdf"),
  )
  assert_false(
    client_captured_content_schema_media_matches(schema, "text/plain"),
  )
  assert_false(
    client_captured_content_schema_media_matches(
      schema, "application/pdf;profile=A",
    ),
  )
  let parameter = captured_content_media_schema([
    Some("text/plain;label=OpaqueValue"),
  ])
  assert_true(
    client_captured_content_schema_media_matches(
      parameter, "text/plain;label=OpaqueValue",
    ),
  )
  assert_false(
    client_captured_content_schema_media_matches(
      parameter, "text/plain;label=opaquevalue",
    ),
  )
}

///|
test "captured Content still requires one unambiguous typed Source column" {
  for
    media_types in [
      [],
      [None, None],
      [None, Some("application/pdf")],
      [Some("application/pdf"), Some("application/pdf")],
    ] {
    assert_false(
      client_captured_content_schema_media_matches(
        captured_content_media_schema(media_types),
        "application/pdf",
      ),
    )
  }
}
