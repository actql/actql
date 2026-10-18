///|
test "publication fallback retains signed64 order without admitting Array values" {
  for nullable in [false, true] {
    let s = @schema.from_fields(
      [
        (
          @schema.Unqualified("number"),
          @contract.primitive(@contract.Signed64Type, nullable~),
        ),
      ],
      max_fields=1,
      max_name_bytes=6,
    ).unwrap()
    let decision = resolve(
      source(),
      s,
      s,
      ["number"],
      None,
      None,
      None,
      max_work=100,
      max_text_bytes=100,
    ).unwrap()
    guard decision.decision is Some(original) else {
      fail("signed64 is already AuthorOrderable")
    }
    assert_eq(original.strategy, ProjectedFields)
    assert_eq(original.terms[0].field, @schema.Unqualified("number"))
    assert_true(
      resolve(
        source(),
        s,
        s,
        ["number"],
        None,
        None,
        None,
        max_work=decision.work - 1,
        max_text_bytes=decision.text_bytes,
      )
      is Err(_),
    )
  }
  let array = @schema.from_fields(
    [
      (
        @schema.Unqualified("items"),
        @contract.array_contract(
          @contract.primitive(@contract.Signed64Type, nullable=false),
          nullable=false,
        ).unwrap(),
      ),
    ],
    max_fields=1,
    max_name_bytes=5,
  ).unwrap()
  let pending = resolve(
    source(),
    array,
    array,
    ["items"],
    None,
    None,
    None,
    max_work=100,
    max_text_bytes=100,
  ).unwrap()
  assert_true(pending.decision is None)
  assert_true(pending.pending is Some(_))
}
