///|
test "original Signed64 keys satisfy the adopted AuthorOrderable domain" {
  for nullable in [false, true] {
    assert_true(
      author_orderable(@contract.primitive(@contract.Signed64Type, nullable~)),
    )
    assert_true(
      author_orderable(@contract.primitive(@contract.NumberType, nullable~)),
    )
    assert_true(
      author_orderable(@contract.primitive(@contract.TimestampType, nullable~)),
    )
    assert_false(
      author_orderable(
        @contract.array_contract(
          @contract.primitive(@contract.Signed64Type, nullable=false),
          nullable~,
        ).unwrap(),
      ),
    )
    assert_false(
      author_orderable(@contract.primitive(@contract.JsonType, nullable~)),
    )
  }
}
