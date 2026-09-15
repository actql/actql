///|
test "window demand retains unpublished input bounds and imported producers" {
  for generated in [false, true] {
    let (text, _, environment, _, limits) = public_input_fixture(generated~)
    let source = text
      .replace(
        old="{\"take\":1,\"as\":\"selected\"}",
        new=(if generated { "" } else { "{\"take\":3}," }) +
          "{\"row_window\":{\"time\":\"id\",\"kind\":\"sliding\",\"size\":10,\"step\":3},\"as\":\"windowed\"}",
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
    let retained = @program_check.unit_window_limit_at(program, 1, 0).unwrap()
    let expected = if generated { 4L } else { 12L }
    assert_eq(@program_check.window_limit_selection(retained).maximum, expected)
    assert_true(@program_check.window_limit_proof_count(retained) > 0)
    let proof = @program_check.window_limit_proof_at(retained, 0).unwrap()
    assert_eq(
      @wire.value(
        @wire.program_proof_witness(
          @program_check.window_input_proof_claim(proof),
        ),
      ),
      expected,
    )
  }
}
