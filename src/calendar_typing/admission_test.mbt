///|
test "bucket preserves qualified and untyped payload evidence" {
  let rows = @carrier.rows(
    [
      (
        Qualified(Left, "time"),
        Some(@contract.primitive(TimestampType, nullable=false)),
      ),
      (Unqualified("payload"), None),
    ],
    field_set=Closed,
    max_fields=2,
    max_name_bytes=100,
  ).unwrap()
  let s = cursor(
    "{\"time\":\"left.time\",\"into\":\"bucket\",\"unit\":\"year\",\"timezone\":\"UTC\"}",
  )
  let c = @calendar_typing.check(
    Bucket,
    s,
    Some(@carrier.relation(rows)),
    None,
    Some(profile()),
    limits(),
  ).unwrap()
  let out = @carrier.relation_rows(@calendar_typing.output(c)).unwrap()
  assert_true(
    @carrier.lookup(out, Unqualified("payload"))
    is Present({ contract: None, .. }),
  )
  assert_true(@carrier.lookup(out, Qualified(Left, "time")) is Present(_))
  assert_true(@carrier.lookup(out, Unqualified("left.time")) is Absent)
  let u = @calendar_typing.usage(c)
  let exact = {
    ..limits(),
    max_work: u.work,
    max_nodes: u.nodes,
    max_text_bytes: u.text_bytes,
  }
  assert_true(
    @calendar_typing.check(
      Bucket,
      s,
      Some(@carrier.relation(rows)),
      None,
      Some(profile()),
      exact,
    )
    is Ok(_),
  )
}

///|
test "profile lookup and clock failures keep the selector location" {
  for
    (field, into, zone, issue, path) in [
      (
        "missing",
        "bucket",
        "UTC",
        @calendar_typing.MissingField("missing"),
        "time",
      ),
      ("time", "time", "UTC", @calendar_typing.OutputCollision("time"), "into"),
      (
        "time",
        "bucket",
        "utc",
        @calendar_typing.UnknownTimezone("utc"),
        "timezone",
      ),
    ] {
    let s = cursor(
      "{\"time\":\"" +
      field +
      "\",\"into\":\"" +
      into +
      "\",\"unit\":\"day\",\"timezone\":\"" +
      zone +
      "\"}",
    )
    match
      @calendar_typing.check(
        Bucket,
        s,
        Some(input(false, false)),
        None,
        Some(profile()),
        limits(),
      ) {
      Err(e) => {
        assert_eq(e.kind, issue)
        assert_eq(e.path, [Key(path)])
      }
      _ => fail("unexpected admission")
    }
  }
}

///|
test "Calendar bucket preserves conditional payload independently of NULL" {
  let schema = @row.from_presence_fields(
    [
      (
        Unqualified("time"),
        @contract.primitive(TimestampType, nullable=false),
        Required,
      ),
      (
        Unqualified("payload"),
        @contract.primitive(TextType, nullable=true),
        Conditional,
      ),
    ],
    max_fields=2,
    max_name_bytes=100,
  ).unwrap()
  let checked = @calendar_typing.check(
    Bucket,
    cursor(
      "{\"time\":\"time\",\"into\":\"bucket\",\"unit\":\"month\",\"timezone\":\"UTC\"}",
    ),
    Some(@carrier.relation(@carrier.typed_rows(schema))),
    None,
    Some(profile()),
    limits(),
  ).unwrap()
  let output = @carrier.complete_schema(
    @carrier.relation_rows(@calendar_typing.output(checked)).unwrap(),
  ).unwrap()
  let payload = @row.lookup_reference(output, "payload").unwrap()
  assert_eq(payload.presence, Conditional)
  assert_true(payload.contract.nullable)
  assert_eq(@row.lookup_reference(output, "time").unwrap().presence, Required)
  assert_eq(@row.lookup_reference(output, "bucket").unwrap().presence, Required)
}
