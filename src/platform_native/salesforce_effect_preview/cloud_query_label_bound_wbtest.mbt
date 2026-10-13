///|
test "Cloud query labels preserve the UTF8 ceiling after the allocation precheck" {
  for label in [
    "x".repeat(256),
    "é".repeat(128),
    "😀".repeat(64),
    "e\u{301}",
    "é",
  ] {
    assert_true(cloud_resume_query_label(label))
  }
  for label in [
    "",
    "x".repeat(257),
    "é".repeat(129),
    "😀".repeat(65),
    "e\u{301}".repeat(86),
    "x\n",
    "x\u{7f}",
  ] {
    assert_false(cloud_resume_query_label(label))
  }
}

///|
test "Cloud identity query refuses oversized labels and preserves independent exact wire" {
  let label = "\\".repeat(256)
  let body = cloud_host_identity_query(
    cloud_host_test_expected(),
    label,
    cloud_host_test_limits(),
  ).unwrap()
  let expected = "{\"version\":\"actql-cloud-effect-host-identity-query/0.1\",\"queryId\":\"" +
    "\\\\".repeat(256) +
    "\",\"dispatchCid\":\"sha256:" +
    "d".repeat(64) +
    "\"}"
  assert_eq(body, @utf8.encode(expected))
  assert_true(
    cloud_host_identity_query(
      cloud_host_test_expected(),
      "x".repeat(257),
      cloud_host_test_limits(),
    )
    is None,
  )
}
