///|
test "sink progress distinguishes offered and confirmed bytes" {
  let progress = prepare_delivery_sink_progress(6L).unwrap()
  progress.offer(b"abc", false).unwrap()
  assert_eq(progress.confirmed_bytes(), 0L)
  assert_true(progress.offer(b"def", true) is Err(DeliverySinkChunkOutstanding))
  assert_eq(progress.confirm_chunk(), Ok(3L))
  progress.offer(b"def", true).unwrap()
  assert_eq(progress.confirm_chunk(), Ok(6L))
  let summary = progress.confirm_finished().unwrap()
  assert_eq(summary.confirmed_bytes, 6L)
  assert_eq(
    summary.delivered_sha256,
    "sha256:bef57ec7f53a6d40beb640a780a639c83bc29ac8a9816f1fc6c5c6dcd93c4721",
  )
  assert_eq(progress.confirm_finished(), Ok(summary))
}

///|
test "empty delivery requires explicit sink completion" {
  let progress = prepare_delivery_sink_progress(0L).unwrap()
  assert_true(progress.confirm_finished() is Err(DeliverySinkSourceIncomplete))
  progress.offer(b"", true).unwrap()
  let summary = progress.confirm_finished().unwrap()
  assert_eq(summary.confirmed_bytes, 0L)
  assert_eq(
    summary.delivered_sha256,
    "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  )
}

///|
test "partial sink failure cannot become a successful delivery" {
  let progress = prepare_delivery_sink_progress(8L).unwrap()
  progress.offer(b"abcdef", true).unwrap()
  assert_eq(progress.fail_chunk(2), Ok(2L))
  assert_true(progress.confirm_finished() is Err(DeliverySinkClosed))
  assert_true(progress.offer(b"gh", true) is Err(DeliverySinkClosed))
}

///|
test "delivery limit is enforced before a chunk is exposed" {
  let progress = prepare_delivery_sink_progress(3L).unwrap()
  assert_true(progress.offer(b"abcd", true) is Err(DeliverySinkLimitExceeded))
  assert_eq(progress.confirmed_bytes(), 0L)
}
///|
test "empty delivery output observation preserves progress and rejects outstanding bytes" {
  let sink = prepare_delivery_sink_progress(10L).unwrap()
  sink.offer(b"", false).unwrap() |> ignore
  assert_eq(sink.observe_empty_output(), Ok(0L))
  assert_eq(sink.confirm_chunk(), Err(DeliverySinkNoOutstandingChunk))
  sink.offer(b"a", false).unwrap() |> ignore
  assert_eq(sink.observe_empty_output(), Err(DeliverySinkChunkOutstanding))
  assert_eq(sink.confirm_chunk(), Ok(1L))
  sink.offer(b"", true).unwrap() |> ignore
  assert_eq(sink.observe_empty_output(), Ok(1L))
  let summary = sink.confirm_finished().unwrap()
  assert_eq(summary.confirmed_bytes, 1L)
  assert_eq(
    summary.delivered_sha256,
    "sha256:ca978112ca1bbdcafac231b39a23dc4da786eff8147c4e72b9807785afee48bb",
  )
  assert_eq(sink.observe_empty_output(), Err(DeliverySinkClosed))
}

///|
test "empty delivery output observation cannot acknowledge a failed sink" {
  let sink = prepare_delivery_sink_progress(10L).unwrap()
  sink.offer(b"a", false).unwrap() |> ignore
  assert_eq(sink.fail_chunk(0), Ok(0L))
  assert_eq(sink.observe_empty_output(), Err(DeliverySinkClosed))
  assert_eq(sink.confirmed_bytes(), 0L)
}

