///|
test "prepared attestation wire retains the complete original body and bounds" {
  let (checkpoint, resolution, evidence) = approved_effect()
  let admitted = admit(checkpoint, resolution, Some(evidence)).unwrap()
  let wire = admitted.prepared_wire(limits()).unwrap()
  let value = parse_wire(wire, limits()).unwrap()
  assert_eq(cid_of(value, limits()), Some(admitted.attestation_preimage))
  assert_eq(
    string_field(value, "verified_at"),
    Some("2026-09-25T12:00:01.000Z"),
  )
  // Independent existing complete encoder: stripping only the two transport
  // fields must recover every original field, including the nested evidence.
  let sealed_resolution = seal_verified_resolution(
    admitted,
    "host-key",
    "aG9zdA==",
    limits(),
  ).unwrap()
  let full = parse_wire(sealed_resolution.wire, limits()).unwrap()
  let unsigned = @json.object_without_field(
    @json.object_without_field(full, "verified_resolution_cid").unwrap(),
    "host_attestation",
  ).unwrap()
  assert_eq(wire_of(unsigned, limits()), Some(wire))
  let size = @utf8.encode(wire).length()
  assert_eq(
    admitted.prepared_wire({ ..limits(), max_wire_bytes: size, }),
    Ok(wire),
  )
  assert_eq(
    admitted.prepared_wire({ ..limits(), max_wire_bytes: size - 1, }),
    Err(ResolutionEncoding),
  )
  assert_eq(
    admitted.prepared_wire({ ..limits(), max_nodes: 2, }),
    Err(ResolutionEncoding),
  )
  assert_eq(
    admitted.prepared_wire({ ..limits(), max_depth: 2, }),
    Err(ResolutionEncoding),
  )
  assert_eq(
    admitted.prepared_wire({ ..limits(), max_wire_bytes: 0, }),
    Err(ResolutionInvalidLimits),
  )
}
