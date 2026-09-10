///|
test "join cardinality bounds retain assertions and do not require both input counts" {
  for
    (assertion, expected, exact) in [
      ("many_to_one", 3L, true),
      ("one_to_one", 3L, true),
      ("one_to_many", 5L, false),
    ] {
    let p = @pipeline_typing.check_carriers(
      cursor(
        "[" +
        count_values(3, "l") +
        "," +
        count_values(3, "r") +
        ",{\"join\":{\"with\":\"r\",\"kind\":\"left\",\"on\":\"id\",\"cardinality\":\"" +
        assertion +
        "\"},\"from\":\"l\"}]",
      ),
      [],
      None,
      None,
      limits(),
    ).unwrap()
    assert_count(p, 2, expected, exact)
    guard @pipeline_typing.step_at(p, 2).unwrap().operation
      is Join(checked~, ..) else {
      abort("join")
    }
    assert_true(
      @join.pending_validations(checked).contains(
        ValidateCardinality(@join.assertion(checked).unwrap()),
      ),
    )
  }
  let input = @carrier.relation(
    @carrier.rows(
      [
        (
          Unqualified("id"),
          Some(@contract.primitive(NumberType, nullable=false)),
        ),
      ],
      field_set=Closed,
      max_fields=1,
      max_name_bytes=2,
    ).unwrap(),
  )
  for kind in ["inner", "left"] {
    let p = @pipeline_typing.check_carriers(
      cursor(
        "[" +
        count_values(3, "l") +
        ",{\"join\":{\"with\":\"external\",\"kind\":\"" +
        kind +
        "\",\"on\":\"id\",\"cardinality\":\"many_to_one\"}}]",
      ),
      [("external", input)],
      None,
      None,
      limits(),
    ).unwrap()
    assert_count(p, 1, 3L, kind == "left")
  }
}

///|
test "unique-side bounds avoid an irrelevant overflowing join product" {
  let generator = "{\"time_series\":{\"start\":\"0000-01-01T00:00:00.000Z\",\"end\":\"9999-12-31T23:59:59.999Z\",\"step\":1},\"as\":\"grid\"}"
  for
    (kind, expected, exact) in [
      ("inner", 315569519999999L, false),
      ("left", 315569519999999L, true),
      ("full", 631139039999998L, false),
    ] {
    let p = @pipeline_typing.check_carriers(
      cursor(
        "[" +
        generator +
        ",{\"join\":{\"with\":\"grid\",\"kind\":\"" +
        kind +
        "\",\"on\":\"time\",\"cardinality\":\"one_to_one\"}}]",
      ),
      [],
      None,
      None,
      limits(),
    ).unwrap()
    assert_count(p, 1, expected, exact)
  }
}
