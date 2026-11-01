///|
test "imported child funding refusal remains an explicit private explanation" {
  let writer = @encode.writer(1024, 32, 8)
  emit_strategy_assessment(writer, {
    position: 0,
    duration: @cost.Unknown,
    rejection: Some(@resources.ChildFundingUnavailable),
    transfer_bytes: 0L,
    retained_bytes: 0L,
    execution_bytes: 0L,
  })
  assert_eq(
    @encode.finish(writer),
    "{\"position\":0,\"estimated_milliseconds\":null,\"transfer_bytes\":\"0\",\"retained_bytes\":\"0\",\"execution_bytes\":\"0\",\"rejection\":\"child_funding_unavailable\"}",
  )
}
