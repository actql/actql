///|
test "same generated Source rule constructor has independently counted full normative inventory" {
  // Independent schema roles:26 objects/108 fields/73 Text/8 Boolean/
  //8 Array/2 integer,51 literal choices. Raw233H331R278W,99 Arrays/159items.
  assert_eq(source_view_rule_construction(), {
    record_headers: 530L,
    reference_slots: 2095L,
    scalar_words: 476L,
  })
}
