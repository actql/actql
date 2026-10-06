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

///|
test "remote output rejects custody from a different material or manifest" {
  let cid = output_contract_cid("a".repeat(64))
  let request = @remote.prepare_dispatch_request(
    "authority", cid, "task", 1, "dispatch", "site", 1, cid, "local", "local/1",
    "strategy/1", cid, cid, cid, cid, cid,
  ).unwrap()
  let manifest = output_manifest(cid, cid, cid)
  let facts = output_facts(cid, cid, cid, manifest)
  let custody = @journal.prepare_native_output_file_custody(
    request,
    "original-task",
    { device: 1UL, inode: 2UL, size: 3L, },
    cid,
    facts.material_generation,
    manifest,
  ).unwrap()
  let admitted = prepare_native_remote_output(
    facts,
    () => Err("unused"),
    () => Err("unused"),
    () => true,
    file_custody=Some(custody),
  ).unwrap()
  guard admitted is NativeRemoteOutputReady(output) else {
    fail("exact output custody refused")
  }
  assert_true(output.file_custody is Some(_))
  assert_true(
    @journal.native_output_file_custody_matches_request(custody, request),
  )
  let changed_material = @journal.prepare_native_output_file_custody(
    request,
    "original-task",
    { device: 1UL, inode: 2UL, size: 3L, },
    cid,
    "another-generation",
    manifest,
  ).unwrap()
  assert_true(
    prepare_native_remote_output(
      facts,
      () => Err("unused"),
      () => Err("unused"),
      () => true,
      file_custody=Some(changed_material),
    )
    is Err(OutputRejected),
  )
  let foreign = output_contract_cid("b".repeat(64))
  let changed_manifest = @journal.prepare_native_output_file_custody(
    request,
    "original-task",
    { device: 1UL, inode: 2UL, size: 3L, },
    cid,
    facts.material_generation,
    output_manifest(foreign, cid, cid),
  ).unwrap()
  assert_true(
    prepare_native_remote_output(
      facts,
      () => Err("unused"),
      () => Err("unused"),
      () => true,
      file_custody=Some(changed_manifest),
    )
    is Err(OutputRejected),
  )
}
