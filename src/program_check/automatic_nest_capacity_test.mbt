///|
test "nest demands parent and child bounds independently of publication" {
  let (text, _, environment, _, limits) = public_input_fixture()
  let source = text
    .replace(
      old="{\"take\":1,\"as\":\"selected\"}",
      new="{\"take\":3,\"as\":\"children\"},{\"from\":\"rows\",\"take\":2,\"as\":\"parents\"},{\"nest\":{\"with\":\"children\",\"on\":[{\"left\":\"id\",\"right\":\"id\"}],\"into\":\"items\",\"fields\":[\"id\",\"value\"],\"max_items\":20},\"as\":\"nested\"}",
    )
    .replace(old="\"from\":\"selected\"", new="\"from\":\"rows\"")
  let program = public_checked(
    @program_check.check_document(
      source,
      environment,
      None,
      limits,
      format=Json,
    ),
  )
  let retained = @program_check.unit_nest_limit_at(program, 1, 0).unwrap()
  let envelope = @program_check.nest_limits_envelope(retained)
  assert_eq(envelope.items.maximum, 3L)
  assert_eq(@context.nest_item_candidate_count(envelope.items), 1)
  assert_eq(@context.nest_parent_candidate_count(envelope), 1)
  let parent = @context.nest_parent_candidate_at(envelope, 0).unwrap()
  assert_eq(
    @step_bounds.target_rows_value(@capacity.target_membership_rows(parent)),
    2L,
  )
  let publication = @program_check.unit_publication_at(program, 1, 0).unwrap()
  assert_eq(
    @context.publication_row_limit_maximum(
      @program_check.publication_selection(publication),
    ),
    1000L,
  )
}
