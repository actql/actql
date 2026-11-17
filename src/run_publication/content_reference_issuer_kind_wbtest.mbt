///|
test "stored Content issuer family requires complete canonical envelope and both self identities" {
  let limits = content_reference_test_limits()
  let binding = content_reference_test_binding()
  let generated = prepare_generated_content_reference(
    content_reference_empty_encoder(),
    binding,
    limits,
  ).unwrap()
  let wire = generated_content_reference_wire(generated)
  assert_eq(
    recovered_content_issuer_kind(wire, limits),
    Ok("content_derivation"),
  )
  let captured = prepare_captured_content_reference(
    binding,
    "text/plain",
    "sha256:" + "7".repeat(64),
    0,
    limits,
  ).unwrap()
  let source = captured_content_reference_wire(captured)
  assert_eq(
    recovered_content_issuer_kind(source, limits),
    Ok("connector_capture"),
  )
  for
    changed in [
      source.replace(old="connector_capture", new="content_derivation"),
      source.replace(old="text/plain", new="text/csv"),
      source.replace(
        old="sha256:" + "7".repeat(64),
        new="sha256:" + "8".repeat(64),
      ),
      source + " ",
    ] {
    assert_true(recovered_content_issuer_kind(changed, limits) is Err(_))
  }
  assert_true(
    recovered_content_issuer_kind(source, { ..limits, max_nodes: 1, }) is Err(_),
  )
}
