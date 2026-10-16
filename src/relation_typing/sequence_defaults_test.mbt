///|
fn sequence_authored_defaults_body(
  grouping : Bool,
  overlap : Bool,
  contiguity : Bool,
) -> String {
  "{\"id\":\"id\",\"time\":\"clock\",\"pattern\":[{\"as\":\"opened\",\"where\":{\"literal\":true}},{\"as\":\"closed\",\"where\":{\"literal\":false}}],\"within\":20" +
  (if grouping { ",\"by\":[]" } else { "" }) +
  (if overlap { ",\"overlap\":\"disallow\"" } else { "" }) +
  (if contiguity { ",\"contiguity\":\"adjacent\"" } else { "" }) +
  "}"
}

///|
test "sequence completes only omitted grouping and modes through its original checked owner" {
  for grouping in [false, true] {
    for overlap in [false, true] {
      for contiguity in [false, true] {
        let body = cursor(
          sequence_authored_defaults_body(grouping, overlap, contiguity),
        )
        let checked = @relation_typing.check_sequence(
          body,
          @carrier.relation(sequence_rows(false)),
          None,
          limits(),
        ).unwrap()
        assert_true(
          physical_equal(@relation_typing.sequence_source(checked), body),
        )
        assert_eq(@relation_typing.sequence_keys(checked).length(), 0)
        assert_eq(@relation_typing.sequence_overlap(checked), Disallow)
        assert_eq(@relation_typing.sequence_contiguity(checked), Adjacent)
        assert_true(@relation_typing.sequence_per_key_guard(checked) is None)
        assert_true(@relation_typing.sequence_output_guard(checked) is None)
        assert_eq(@relation_typing.sequence_pattern_count(checked), 2)
      }
    }
  }
}
