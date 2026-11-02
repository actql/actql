///|
test "Table announced body owns native parse snapshot and rejecting recursion before any page exists" {
  // Independently authored vector for B=4/depth=2: each span-free tree is
  // 30H82R16W; only the first owns its four decoded units. The four live
  // recursion/descriptor frames plus parent Set are 31H90R101W. Raw/text and
  // scalar/index temporaries add6H2R1W/40UTF16/4wire. No returned quote supplies
  // these expectations or an admission limit.
  let inventory = installed_table_body_construction_inventory(4, 2).unwrap()
  assert_eq(inventory.record_headers, 97L)
  assert_eq(inventory.reference_slots, 256L)
  assert_eq(inventory.scalar_words, 134L)
  assert_eq(inventory.owned_utf16_units, 44L)
  assert_eq(inventory.owned_wire_bytes, 4L)
  assert_eq(@execution.preparation_representation_cost(inventory), Some(4764L))
  let previous = @execution.execution_capacity(17L, 23L).unwrap()
  let body = installed_table_source_body_capacity(previous, 4, 2).unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(body), 4781L)
  assert_eq(@execution.execution_capacity_execution_bytes(body), 4787L)
  let next = installed_table_source_body_capacity(body, 4, 2).unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(next), 9545L)
  assert_eq(@execution.execution_capacity_execution_bytes(next), 9551L)
  // Two bodies are not assumed to have non-overlapping metadata/failed-child
  // lifetimes. This pure DATA fold releases/refunds nothing.
  assert_eq(@execution.execution_capacity_retained_bytes(previous), 17L)
  assert_eq(@execution.execution_capacity_execution_bytes(previous), 23L)
}

///|
test "Table body inventory uses actual announced bytes before snapshot limits and keeps original boundaries" {
  assert_true(installed_table_body_construction_inventory(0, 2) is None)
  assert_true(installed_table_body_construction_inventory(-1, 2) is None)
  assert_true(installed_table_body_construction_inventory(4, 0) is None)
  // A body with many shallow native values exists before maxNodes rejects it.
  // Max depth bounds only the explicit snapshot call chain, not that tree.
  let small = installed_table_body_construction_inventory(8, 1).unwrap()
  let large = installed_table_body_construction_inventory(16, 1).unwrap()
  assert_true(large.record_headers > small.record_headers)
  assert_true(large.reference_slots > small.reference_slots)
  assert_true(large.owned_utf16_units > small.owned_utf16_units)
  assert_eq(large.owned_wire_bytes, 16L)
  assert_true(
    installed_table_body_construction_inventory(1, 1) ==
    installed_table_body_construction_inventory(1, 2147483647),
  )
  // Int bounds cannot overflow the Int64 shared tariff or depth+2 arithmetic;
  // this quotes DATA only and does not allocate the described huge body.
  assert_true(
    installed_table_body_construction_inventory(2147483647, 2147483647)
    is Some(_),
  )
}

///|
test "Table initial reader reuses common controls original profile stages and separate output constructors" {
  // Existing common fixed envelope46H189R20W=2408. Table selected frame
  //22H62R9W=920; original live-reader Set11H29R34W=680. The SAME shared
  // constructor/quotation workspace is1408+688=2096. Three original outbound
  // profile stages retain23 each; these are independent authored quantities.
  let profile = @execution.execution_capacity(17L, 23L).unwrap()
  let initial = installed_table_source_reader_capacity(2, profile).unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(initial), 4077L)
  assert_eq(@execution.execution_capacity_execution_bytes(initial), 6173L)
  assert_true(installed_table_source_reader_capacity(0, profile) is None)
  let body = installed_table_source_serialization_capacity(profile, 4).unwrap()
  // 130 UTF16 units and two130-byte Buffers +3H2R2W=600, before stringify.
  assert_eq(@execution.execution_capacity_retained_bytes(body), 617L)
  assert_eq(@execution.execution_capacity_execution_bytes(body), 623L)
  assert_true(installed_table_source_serialization_capacity(profile, 0) is None)
}
