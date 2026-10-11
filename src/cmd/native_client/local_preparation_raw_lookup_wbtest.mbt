///|
// Independently authored projection fixtures. These test metadata preservation
// and non-disclosure, not operational grant issuance or raw Store validation.
test "Local raw metadata preserves unknown independently from retained HTTP response" {
  let metadata : LocalPreparationRawMetadata = {
    use_cid: "sha256:" + "a".repeat(64),
    outcome: "unknown",
    use_status: None,
    raw_use_cid: "sha256:" + "a".repeat(64),
    raw_status: 401,
    body_bytes: 15,
    body_digest: "sha256:d510903212234c6a21736a1aeb40546ded96a3b357f463f6cfa166b24af97179",
  }
  let wire = local_preparation_raw_metadata_record(
    "sha256:" + "b".repeat(64),
    "original-use",
    metadata,
  )
  let value = @json.parse(wire)
  let expected = @json.parse(
    "{\"kind\":\"local_preparation_raw_lookup\",\"operationCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"useId\":\"original-use\",\"useCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"originalUseOutcome\":\"unknown\",\"originalUseStatus\":null,\"rawResponse\":{\"status\":401,\"bodyBytes\":15,\"bodyDigest\":\"sha256:d510903212234c6a21736a1aeb40546ded96a3b357f463f6cfa166b24af97179\"}}",
  )
  assert_eq(value, expected)
}

///|
test "Local raw metadata refuses another use before producing a reply" {
  let metadata : LocalPreparationRawMetadata = {
    use_cid: "sha256:" + "a".repeat(64),
    outcome: "unknown",
    use_status: None,
    raw_use_cid: "sha256:" + "c".repeat(64),
    raw_status: 200,
    body_bytes: 15,
    body_digest: "sha256:d510903212234c6a21736a1aeb40546ded96a3b357f463f6cfa166b24af97179",
  }
  let refusal = try {
    local_preparation_raw_metadata_record(
      "sha256:" + "b".repeat(64),
      "original-use",
      metadata,
    )
    |> ignore
    None
  } catch {
    ClientStop(reason) => Some(reason)
  }
  assert_eq(refusal, Some("LocalPreparationRawUseMismatch"))
}
