///|
test "Output report ACK is exact, closed and cannot authorize execution" {
  let (output, payload, _, transfer) = output_result_fixture()
  let result = prepare_remote_output_result(
    output,
    payload,
    cid("eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"),
    transfer,
  ).unwrap()
  let original = remote_output_result_json(result).unwrap()
  let ack = remote_output_report_reply_json(result, Accepted).unwrap()
  assert_eq(admit_remote_output_report_reply_json(ack, result), Ok(Accepted))
  assert_eq(remote_output_result_json(result), Ok(original))
  for
    body in [
      "",
      "{}",
      "{\"accepted\":true}",
      ack.replace(
        old=remote_output_result_identity(result),
        new=cid(
          "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
        ),
      ),
      ack.replace(old="accepted", new="unknown"),
    ] {
    assert_eq(
      admit_remote_output_report_reply_json(body, result),
      Err(InvalidDispatch),
    )
  }
  let refusal = remote_output_report_reply_json(
    result,
    Refused("report_conflict"),
  ).unwrap()
  assert_eq(
    admit_remote_output_report_reply_json(refusal, result),
    Ok(Refused("report_conflict")),
  )
  assert_eq(
    remote_output_report_reply_json(result, Refused("private_secret")),
    Err(InvalidDispatch),
  )
}
