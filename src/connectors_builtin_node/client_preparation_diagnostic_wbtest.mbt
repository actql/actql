///|
// These are explicit typed diagnostic fixtures. The GCS installed consumer
// separately supplies the actual checked Program/Host policy rejection.
test "original lookup rejection projection preserves stage and join step without compiler tags" {
  let original = @program_check.source_requests_diagnostic(
    @context.Capacity(@context.Stage(0, @acquisition.DecodedResponseLimit(2))),
  )
  let outcome = Rejected(Preparation(Check(original)))
  assert_eq(
    client_program_preparation_decoded_response_limit_json(outcome),
    Some("{\"stageIndex\":0,\"stepIndex\":2}"),
  )
  let other = Rejected(
    Preparation(
      Check(
        @program_check.source_requests_diagnostic(
          @context.Capacity(
            @context.Stage(3, @acquisition.DecodedResponseLimit(7)),
          ),
        ),
      ),
    ),
  )
  assert_eq(
    client_program_preparation_decoded_response_limit_json(other),
    Some("{\"stageIndex\":3,\"stepIndex\":7}"),
  )
  assert_true(client_program_preparation_ready(outcome) is None)
  assert_true(client_program_preparation_ready(other) is None)
}

///|
test "original lookup rejection projection refuses unrelated causes and a genuinely ready preparation" {
  for
    issue in [
      @context.Capacity(@context.Stage(0, @acquisition.WorkLimit)),
      @context.Capacity(@context.Stage(0, @acquisition.UnrepresentableBound(2))),
      @context.BudgetExceeded,
    ] {
    let outcome = Rejected(
      Preparation(Check(@program_check.source_requests_diagnostic(issue))),
    )
    assert_true(
      client_program_preparation_decoded_response_limit_json(outcome) is None,
    )
  }
  assert_true(
    client_program_preparation_decoded_response_limit_json(
      Rejected(InvalidFormat),
    )
    is None,
  )
  let ready = client_program_prepare_effect_free_with_parameters(
    (
      #|{"version":"actql/0.1","id":"lookup_diagnostic.ready","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"value":{"type":"number","nullable":false}},"rows":[{"value":1}]},"as":"rows"}],"results":{"rows":{"from":"rows","fields":["value"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    "json",
    store_public_bridge_fixture("collection"),
    None,
  )
  assert_true(client_program_preparation_ready(ready) is Some(_))
  assert_true(
    client_program_preparation_decoded_response_limit_json(ready) is None,
  )
}
