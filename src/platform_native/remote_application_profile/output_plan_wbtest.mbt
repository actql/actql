///|
fn output_plan_cid(unit : String) -> String {
  "sha256:" + unit.repeat(64)
}

///|
test "observed output fixes publication and Transfer physical binding" {
  let bytes = b"[{\"id\":3}]"
  let schema = output_plan_cid("1")
  let view = output_plan_cid("2")
  let codec = output_plan_cid("3")
  let manifest = @manifest.admit(
    "actql-managed-physical-manifest/0.1",
    schema,
    view,
    codec,
    1,
    ["sha256:" + @sha.hex(bytes)],
    [bytes.length().to_int64()],
    [1],
    8,
    4096,
    bytes.length().to_int64(),
  ).unwrap()
  let measurement = @remote.prepare_remote_managed_output_measurement(
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
  ).unwrap()
  let facts : @runtime.NativeRemoteOutputFacts = {
    material_generation: output_plan_cid("4"),
    managed_profile_cid: output_plan_cid("5"),
    result_schema_cid: schema,
    logical_view_cid: view,
    representation_codec_cid: codec,
    physical_manifest: manifest,
    row_count: 1,
    retained_bytes: bytes.length().to_int64(),
    measurement,
  }
  let site = @site.create_site(
    "source-site",
    7,
    output_plan_cid("6"),
    1,
    1,
    1024L,
    1024L,
  ).unwrap()
  let intent : NativeRemoteApplicationOutputIntent = {
    store_authority_cid: output_plan_cid("7"),
    publication_attempt_cid: output_plan_cid("8"),
    result_definition_cid: output_plan_cid("9"),
    ordering_evidence_cid: output_plan_cid("a"),
    coordinator_authority: "coordinator",
    transfer_attempt: "transfer-1",
    transfer_route: @transfer.TransferStore,
    destination_site_key: "destination-site",
    destination_site_generation: 3,
    transfer_max_bytes: 1024L,
    transfer_expires_unix_ms: 4102444800000L,
    source_grant_cid: output_plan_cid("b"),
    destination_grant_cid: output_plan_cid("c"),
    route_capability_cid: output_plan_cid("d"),
  }
  let plan = prepare_native_remote_application_output_plan(site, facts, intent).unwrap()
  assert_eq(
    @payload.publication_payload_material_identity(plan.payload),
    facts.material_generation,
  )
  assert_eq(
    @payload.publication_payload_request_logical_relation(plan.payload),
    view,
  )
  assert_eq(@payload.publication_payload_request_schema(plan.payload), schema)
  assert_eq(@payload.publication_payload_request_codec(plan.payload), codec)
  let projection = @transfer.request_projection(plan.transfer)
  assert_eq(projection[2], "source-site")
  assert_eq(projection[3], "7")
  assert_eq(projection[4], "destination-site")
  assert_eq(projection[5], "3")
  assert_eq(projection[6], facts.material_generation)
  assert_eq(projection[7], @manifest.manifest_cid(manifest))
}

///|
test "observed output rejects inconsistent retained facts" {
  let bytes = b"x"
  let manifest = @manifest.admit(
    "actql-managed-physical-manifest/0.1",
    output_plan_cid("1"),
    output_plan_cid("2"),
    output_plan_cid("3"),
    1,
    ["sha256:" + @sha.hex(bytes)],
    [1L],
    [1],
    8,
    4096,
    1L,
  ).unwrap()
  let facts : @runtime.NativeRemoteOutputFacts = {
    material_generation: output_plan_cid("4"),
    managed_profile_cid: output_plan_cid("5"),
    result_schema_cid: output_plan_cid("f"),
    logical_view_cid: manifest.view_contract_cid,
    representation_codec_cid: manifest.codec_contract_cid,
    physical_manifest: manifest,
    row_count: 1,
    retained_bytes: 1L,
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
  let site = @site.create_site(
    "source-site",
    7,
    output_plan_cid("6"),
    1,
    1,
    1024L,
    1024L,
  ).unwrap()
  let intent : NativeRemoteApplicationOutputIntent = {
    store_authority_cid: output_plan_cid("7"),
    publication_attempt_cid: output_plan_cid("8"),
    result_definition_cid: output_plan_cid("9"),
    ordering_evidence_cid: output_plan_cid("a"),
    coordinator_authority: "coordinator",
    transfer_attempt: "transfer-1",
    transfer_route: @transfer.DirectStream,
    destination_site_key: "destination-site",
    destination_site_generation: 3,
    transfer_max_bytes: 1024L,
    transfer_expires_unix_ms: 4102444800000L,
    source_grant_cid: output_plan_cid("b"),
    destination_grant_cid: output_plan_cid("c"),
    route_capability_cid: output_plan_cid("d"),
  }
  assert_true(
    prepare_native_remote_application_output_plan(site, facts, intent)
    is Err(InvalidOutputFacts),
  )
}
