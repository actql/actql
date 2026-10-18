///|
test "original non-null signed64 evidence supplies exact scalar and canonical keys" {
  for nullable in [false, true] {
    let input = @carrier.relation(
      @carrier.rows(
        [
          (
            Unqualified("number"),
            Some(@contract.primitive(Signed64Type, nullable~)),
          ),
        ],
        field_set=Closed,
        max_fields=1,
        max_name_bytes=6,
      ).unwrap(),
    )
    if nullable {
      assert_true(
        @relation_evidence.declare_primary_key(cursor("[\"number\"]"), input, {
          max_fields: 10,
          max_name_bytes: 100,
        })
        is Err(_),
      )
      continue
    }
    let set = @relation_evidence.collect_keys(
      cursor("null"),
      input,
      [key(input, "[\"number\"]")],
      { max_keys: 1, max_work: 100, max_name_bytes: 100, },
    ).unwrap()
    for
      usage in [
        @relation_evidence.CanonicalOrder,
        @relation_evidence.ScalarIdentity,
      ] {
      let selected = @relation_evidence.select_key(cursor("null"), set, usage, {
        max_work: 100,
        max_name_bytes: 100,
      }).unwrap()
      assert_eq(selected.key is Some(_), !nullable)
      if selected.key is Some(original) {
        assert_eq(
          @relation_evidence.key_field_at(original, 0).unwrap().name,
          Unqualified("number"),
        )
      }
    }
  }
}
