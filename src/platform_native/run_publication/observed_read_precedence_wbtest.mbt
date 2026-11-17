///|
// Result precedence only. No Store, physical ACK, captured original or Read
// authority is synthesized by these callback observations.
test "read observation preserves consumer primary while always attempting view cleanup" {
  let calls = Ref(0)
  let result : Result[Int, NativeRunStateReadConsumerIssue[String]] = finish_run_state_read_consumer(
    Err("original-consumer"),
    () => {
      calls.val += 1
      Err(Unavailable)
    },
  )
  assert_eq(calls.val, 1)
  assert_true(result is Err(ConsumerFailure("original-consumer")))
}

///|
test "read observation retains cleanup refusal after a successful consumer" {
  let calls = Ref(0)
  let result : Result[Int, NativeRunStateReadConsumerIssue[String]] = finish_run_state_read_consumer(
    Ok(17),
    () => {
      calls.val += 1
      Err(Unavailable)
    },
  )
  assert_eq(calls.val, 1)
  assert_true(result is Err(CandidateFailure(Unavailable)))
}

///|
test "read observation returns DATA only after its cleanup callback completes" {
  let completed = Ref(false)
  let result : Result[Int, NativeRunStateReadConsumerIssue[String]] = finish_run_state_read_consumer(
    Ok(17),
    () => {
      completed.val = true
      Ok(())
    },
  )
  assert_true(completed.val)
  assert_true(result is Ok(17))
}
