///|
test "scalar batch bound covers escaped and non-ASCII text bytes" {
  let contract = @contract.string_contract(nullable=false).unwrap()
  for source in ["é😀", "\u0000\n\"\\", "plain"] {
    let checked = @admitted.checked_text_value(source, contract).unwrap()
    let bound = checked_scalar_wire_upper_bound(checked, 100).unwrap()
    let writer = @encode.writer(100, 2, 1)
    @admitted.emit_wire_value(checked.value, writer)
    let encoded = @encode.finish(writer)
    let actual = @scalar.admit_utf8_length(encoded, 100).unwrap()
    assert_true(bound >= actual)
    assert_true(checked_scalar_wire_upper_bound(checked, bound - 1) is None)
  }
}
