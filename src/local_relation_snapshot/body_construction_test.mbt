///|
fn check_member_body_quantity(body : String) -> Unit raise {
  let environment = wire_environment("[" + body + "]", "[]")
  let original = @environment.member_at(environment, SchemaSnapshots, 0).unwrap()
  let quoted = member_read_construction_inventory(original).unwrap()
  let kept = quoted.retained
  let peak = quoted.peak
  assert_true(peak.record_headers >= kept.record_headers)
  assert_true(peak.reference_slots >= kept.reference_slots)
  assert_true(peak.scalar_words >= kept.scalar_words)
  assert_true(peak.owned_utf16_units >= kept.owned_utf16_units)
  assert_true(peak.owned_wire_bytes >= kept.owned_wire_bytes)
  assert_true(quoted.inspection_work > 0L)
  assert_eq(member_read_construction_inventory(original), Some(quoted))
  let (read, emitted) = observe_read_member(original, caps())
  let attached = read.unwrap()
  assert_true(physical_equal(environment_member(attached), original))
  assert_eq(emitted.unwrap().0, @utf8.encode(body).length())
  assert_eq(
    peak.owned_wire_bytes >= @utf8.encode(body).length().to_int64(),
    true,
  )
}

///|
test "Snapshot body quote uses original valid empty Unicode enum and retained score shapes" {
  check_member_body_quantity(base())
  let unicode =
    #|{"output_carrier":"relation","schema":{"additional_properties":false,"fields":{"東京":{"enum":["é",""],"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"source_ref":"source:local/s/rows","version":"actql-local-input-schema/0.1"}
  check_member_body_quantity(unicode)
  let score =
    #|{"column_presence":{"score":"conditional"},"output_carrier":"relation","schema":{"additional_properties":false,"fields":{"score":{"nullable":false,"type":"number"}},"nullable":false,"type":"object"},"score_contracts":{"score":{"domain":"raw","normalization":"identity","range":[0,1]}},"source_ref":"source:local/s/rows","version":"actql-local-input-schema/0.1"}
  check_member_body_quantity(score)
}

///|
test "Snapshot quantity does not turn malformed domain DATA into admission" {
  let malformed = base().replace(
    old="\"nullable\":false",
    new="\"nullable\":\"no\"",
  )
  let environment = wire_environment("[" + malformed + "]", "[]")
  let original = @environment.member_at(environment, SchemaSnapshots, 0).unwrap()
  assert_true(member_read_construction_inventory(original) is Some(_))
  assert_true(
    read_member(original, caps()) is Err(InvalidSnapshot(TypeContract(_))),
  )
  let wrong = @environment.member_at(
    wire_environment("[]", "[" + base() + "]"),
    MappingContracts,
    0,
  ).unwrap()
  assert_true(member_read_construction_inventory(wrong) is None)
  assert_true(read_member(wrong, caps()) is Err(WrongSection))
}
