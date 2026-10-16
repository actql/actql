///|
// The GCS domain stays Int64. Its exact non-floating carrier uses the existing
// Decimal(19,0) contract, not a public String alias or a wider GCS integer range.
test "GCS original page integers reach real Decimal admission and wire without binary64" {
  let wire =
    #|{"kind":"storage#objects","items":[{"bucket":"bucket","name":"in/é%2F","generation":"9007199254740993","metageneration":"9223372036854775807","size":"0"}]}
  let page = @gcs.admit_object_metadata_page(
    @utf8.encode(wire),
    "bucket",
    "in/",
    1,
    {
      max_bytes: 8192,
      max_nodes: 1000,
      max_depth: 16,
      max_metadata_entries: 10,
    },
  ).unwrap()
  let row = @gcs.object_metadata_page_at(page, 0).unwrap()
  let contract = @value.decimal_contract(19, 0, nullable=false).unwrap()
  for
    (integer, expected) in [
      (row.generation, "9007199254740993"),
      (row.metageneration, "9223372036854775807"),
      (row.size, "0"),
    ] {
    let source = @source.parse_json("\"" + integer.to_string() + "\"", {
      max_input_bytes: 100,
      max_nodes: 10,
      max_depth: 4,
    }).unwrap()
    let cursor = @decode.admit(source, {
      max_nodes: 10,
      max_depth: 4,
      max_string_bytes: 100,
      max_total_string_bytes: 100,
    }).unwrap()
    let checked = @admitted.admit(contract, cursor, {
      max_nodes: 10,
      max_depth: 4,
      max_text_bytes: 100,
    }).unwrap()
    guard checked.value is @admitted.Decimal(decimal) else {
      abort("exact Decimal, not Text or Number")
    }
    assert_eq(decimal.coefficient, expected)
    assert_eq(decimal.precision, 19)
    assert_eq(decimal.scale, 0)
    assert_true(checked.contract.shape is @value.Decimal(precision=19, scale=0))
    let writer = @encode.writer(100, 10, 4)
    @admitted.emit_checked_wire_value(checked, writer)
    assert_eq(@encode.finish(writer), "\"" + expected + "\"")
  }
  // Decimal(19,0) could represent this coefficient, but GCS Int64 cannot.
  // The original provider Owner rejects it before any decimal projection.
  assert_true(
    @admitted.decimal_from_coefficient("9223372036854775808", 19, 0) is Some(_),
  )
  assert_true(
    @gcs.admit_object_metadata_page(
      @utf8.encode(
        wire.replace(old="9223372036854775807", new="9223372036854775808"),
      ),
      "bucket",
      "in/",
      1,
      {
        max_bytes: 8192,
        max_nodes: 1000,
        max_depth: 16,
        max_metadata_entries: 10,
      },
    )
    is Err(@gcs.InvalidMetadata),
  )
}
