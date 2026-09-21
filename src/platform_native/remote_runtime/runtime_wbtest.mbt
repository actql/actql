///|
fn output_contract_cid(character : String) -> String {
  "sha256:" + character
}

///|
fn output_manifest(
  schema : String,
  view : String,
  codec : String,
) -> @manifest.PhysicalManifest {
  @manifest.admit(
    "actql-managed-physical-manifest/0.1",
    schema,
    view,
    codec,
    1,
    [
      output_contract_cid(
        "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
      ),
    ],
    [3L],
    [1],
    1,
    1024,
    3L,
  ).unwrap()
}

///|
fn output_facts(
  schema : String,
  view : String,
  codec : String,
  manifest : @manifest.PhysicalManifest,
) -> NativeRemoteOutputFacts {
  {
    material_generation: "generation-a",
    managed_profile_cid: output_contract_cid(
      "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    ),
    result_schema_cid: schema,
    logical_view_cid: view,
    representation_codec_cid: codec,
    physical_manifest: manifest,
    row_count: 1,
    retained_bytes: 3L,
    measurement: @remote.prepare_remote_managed_output_measurement(
      1,
      1,
      1,
      1,
      [1],
      [1],
      [1],
      [1],
      [0],
      [1],
    ).unwrap(),
  }
}

///|
test "remote output admits the exact physical manifest contract" {
  let schema = output_contract_cid(
    "1111111111111111111111111111111111111111111111111111111111111111",
  )
  let view = output_contract_cid(
    "2222222222222222222222222222222222222222222222222222222222222222",
  )
  let codec = output_contract_cid(
    "3333333333333333333333333333333333333333333333333333333333333333",
  )
  let manifest = output_manifest(schema, view, codec)
  let admitted = prepare_native_remote_output(
    output_facts(schema, view, codec, manifest),
    () => Err("unused"),
    () => Err("unused"),
    () => true,
  )
  assert_true(admitted is Ok(NativeRemoteOutputReady(_)))
  let foreign_schema = output_contract_cid(
    "4444444444444444444444444444444444444444444444444444444444444444",
  )
  assert_true(
    prepare_native_remote_output(
      output_facts(foreign_schema, view, codec, manifest),
      () => Err("unused"),
      () => Err("unused"),
      () => true,
    )
    is Err(OutputRejected),
  )
  assert_true(
    prepare_native_remote_output(
      { ..output_facts(schema, view, codec, manifest), retained_bytes: 2L, },
      () => Err("unused"),
      () => Err("unused"),
      () => true,
    )
    is Err(OutputRejected),
  )
}
