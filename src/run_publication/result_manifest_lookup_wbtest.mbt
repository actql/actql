///|
// This is only the nested-identity input, not an issued whole Manifest.
fn nested_artifact_lookup_value(
  values : Array[@json.CanonicalValue],
) -> @json.CanonicalValue {
  let fields = values.mapi((index, value) => ("k\{1000 + index}", value))
  let skeleton = "{\"results\":{" +
    fields.map(entry => "\"" + entry.0 + "\":null").join(",") +
    "}}"
  let root = parse_contract_wire(skeleton, 262144, 16384, 32).unwrap()
  let results = @json.object_field(root, "results").unwrap()
  let results = @json.object_with_replaced_fields(results, fields).unwrap()
  @json.object_with_replaced_fields(root, [("results", results)]).unwrap()
}

///|
test "nested Artifact lookup retains canonical originals and reordered fallback" {
  let artifacts = inventory_fixture(32).artifacts
  let value = nested_artifact_lookup_value(
    artifacts.map(original => original.value),
  )
  let spec = contract_spec("result_manifest").unwrap()
  assert_eq(
    validate_nested_identities(
      spec,
      value,
      262144,
      16384,
      32,
      known_artifacts=artifacts,
    ),
    Ok(()),
  )
  let reversed = Array::makei(artifacts.length(), index => {
    artifacts[artifacts.length() - index - 1]
  })
  assert_eq(
    validate_nested_identities(
      spec,
      value,
      262144,
      16384,
      32,
      known_artifacts=reversed,
    ),
    Ok(()),
  )
  assert_eq(validate_nested_identities(spec, value, 262144, 16384, 32), Ok(()))
}

///|
test "nested Artifact lookup admits copied values and refuses a foreign nested CID" {
  let original = inventory_fixture(1).artifacts[0]
  let copied = parse_contract_wire(original.wire, 65536, 4096, 32).unwrap()
  assert_false(physical_equal(copied, original.value))
  let spec = contract_spec("result_manifest").unwrap()
  assert_eq(
    validate_nested_identities(
      spec,
      nested_artifact_lookup_value([copied]),
      65536,
      4096,
      32,
      known_artifacts=[original],
    ),
    Ok(()),
  )
  let foreign = parse_contract_wire(
    original.wire.replace(old=original.identity, new=inventory_fixture_cid("f")),
    65536,
    4096,
    32,
  ).unwrap()
  assert_eq(
    validate_nested_identities(
      spec,
      nested_artifact_lookup_value([foreign]),
      65536,
      4096,
      32,
      known_artifacts=[original],
    ),
    Err(InvalidField("results")),
  )
}

///|
test "nested Artifact positional match retains each supplied admission bound" {
  let original = inventory_fixture(1).artifacts[0]
  let value = nested_artifact_lookup_value([original.value])
  let spec = contract_spec("result_manifest").unwrap()
  for (bytes, nodes, depth) in [(1, 4096, 32), (65536, 1, 32), (65536, 4096, 1)] {
    assert_eq(
      validate_nested_identities(spec, value, bytes, nodes, depth, known_artifacts=[
        original,
      ]),
      Err(InvalidField("results")),
    )
  }
}
