///|
fn material_choice_wire() -> String {
  local_read_original_wire.replace_all(
    old="\"sink\":\"stdout\"",
    new="\"sink\":\"material\"",
  )
}

///|
fn[T, E] material_choice_ok(value : Result[T, E], phase : String) -> T raise {
  match value {
    Ok(value) => value
    Err(_) => fail("material choice fixture: " + phase)
  }
}

///|
test "Native material is an explicit original destination rather than a stdout alias" {
  let stdout = material_choice_ok(
    admit_native_local_read_selection(local_read_original_wire),
    "stdout.selection",
  )
  let material = material_choice_ok(
    admit_native_local_read_selection(material_choice_wire()),
    "material.selection",
  )
  assert_eq(stdout.sink(), Stdout)
  assert_eq(material.sink(), Material)
  assert_eq(material.principal, stdout.principal)
  assert_eq(material.connection, stdout.connection)
  assert_eq(material.formats, stdout.formats)
  assert_eq(material.purpose, stdout.purpose)
  assert_eq(material.max_bytes, stdout.max_bytes)
  assert_eq(material.max_uses, stdout.max_uses)
}

///|
test "Native material destination admission keeps closed spelling and missing null refusals" {
  let file = admit_native_local_read_selection(
    local_read_original_wire.replace_all(old="stdout", new="file"),
  ).unwrap()
  assert_true(file.sink is File)
  for
    spelling in [
      "Material", "table", "File", "client-material", "stdout material",
    ] {
    assert_true(
      admit_native_local_read_selection(
        local_read_original_wire.replace_all(old="stdout", new=spelling),
      )
      is Err(UnsupportedSink),
    )
  }
  for replacement in ["", "\"sink\":null,"] {
    assert_true(
      admit_native_local_read_selection(
        local_read_original_wire.replace_all(
          old="\"sink\":\"stdout\",",
          new=replacement,
        ),
      )
      is Err(InvalidOriginal),
    )
  }
}

///|
test "Native stdout binding cannot allocate material admission from destination DATA" {
  let name = "material-choice-no-receiver"
  let root = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let parent = material_choice_ok(@filesystem.open_private_root(root), "root")
  defer parent.close() |> ignore
  let file = name + ".read.json"
  let writer = material_choice_ok(
    parent.create_writer(name + ".read.stage", 65536L),
    "writer",
  )
  material_choice_ok(
    writer.append(@utf8.encode(material_choice_wire())),
    "append",
  )
  material_choice_ok(writer.seal(file), "seal") |> ignore
  let host = policy_host_fixture(name, files=[file])
  defer host.close() |> ignore
  assert_true(
    host.bind_result_read_policy(epoch_test_crypto(), file, "operator", "cli")
    is Err(MaterialUnavailable),
  )
  let usage = material_choice_ok(
    host.database.capacity_usage("client_local_read_evidence"),
    "evidence.capacity",
  )
  assert_eq(usage.reserved_bytes, 0L)
  assert_eq(usage.reserved_objects, 0L)
  assert_true(
    host.database.scan_after("client_local_read_evidence", "")
    is Err(@sqlite.NotFound),
  )
  assert_eq(
    material_choice_ok(
      host.database.read("client_local_read_custody", "issued"),
      "evidence.issued",
    ).body,
    b"0",
  )
  material_choice_ok(host.close(), "host.close")
  material_choice_ok(parent.close(), "root.close")
}

///|
test "Native material metadata cannot reuse the original stdout admission or preimage" {
  let (host, stdout, original, facts, _) = read_evidence_fixture(
    "material-choice-no-stdout-proof",
  )
  defer host.close() |> ignore
  // Deliberately bypass the public constructor inside this white-box counter.
  // This copied DATA is not a receiver, original workspace or typed loan.
  let material = {
    ..stdout,
    selection: { ..stdout.selection, sink: Material, },
  }
  let policy = "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563"
  assert_true(
    material.require_request(original, facts) is Err(MaterialUnavailable),
  )
  assert_true(
    material.read_admission_preimages(original, facts, policy)
    is Err(MaterialUnavailable),
  )
  assert_true(
    material.retain_read_admission(original, facts, policy)
    is Err(MaterialUnavailable),
  )
  assert_eq(
    material_choice_ok(
      host.database.capacity_usage("client_local_read_evidence"),
      "forged.evidence.capacity",
    ).reserved_bytes,
    0L,
  )
  material_choice_ok(host.close(), "forged.host.close")
}
