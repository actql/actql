///|
test "Native configured inventory retains all seventeen unique output selections" {
  let argv = ["result", "original-run"]
  for index in 0..<17 {
    argv.push("--deliver")
    argv.push(
      "result-" +
      index.to_string() +
      "=json:file-" +
      index.to_string() +
      ".json",
    )
  }
  let selected = local_result_delivery_selection(
    result_command_child(argv),
    "/project",
  )
  assert_eq(selected.files.length(), 17)
  for index, file in selected.files {
    assert_eq(file.result_name, Some("result-" + index.to_string()))
    assert_eq(file.path, "/project/file-" + index.to_string() + ".json")
  }
  argv.push("--deliver")
  argv.push("foreign=json:./file-16.json")
  let duplicate = result_command_child(argv)
  let refused = try {
    ignore(local_result_delivery_selection(duplicate, "/project"))
    "unexpected acceptance"
  } catch {
    ClientStop(issue) => issue
  }
  assert_eq(refused, "ConflictingLocalResultDestination")
}

///|
test "Native configured inventory retains seventeen rates with original slot and coefficient rules" {
  let profile = "{\"work_slots\":[0],\"fixed_ms\":1}"
  let wire = "[" + Array::make(17, profile).join(",") + "]"
  let rates = source_rates(local_input_cursor(wire))
  assert_eq(rates.length(), 17)
  for rate in rates {
    assert_eq(rate.work_slots, [0])
    assert_eq(rate.fixed_ms, Some(1L))
    assert_eq(rate.per_row_ms, None)
  }
  for slots in ["[8]", "[0,0]"] {
    let refused = try {
      ignore(
        source_rates(local_input_cursor("[{\"work_slots\":" + slots + "}]")),
      )
      "unexpected acceptance"
    } catch {
      ClientStop(issue) => issue
    }
    assert_eq(refused, "InvalidLocalSourceInstallation")
  }
}

///|
test "Native configured inventory admits thirty-three selected Source estimates without opening a provider" {
  // This tracked fixture is declaration DATA. No DuckDB library/database is
  // opened and its returned physical configuration closure is not invoked.
  let fixture = text_file(
    @env.current_dir().unwrap() + "/scripts/fixtures/native-local-cli",
    "source-installation.json",
    65536L,
  )
  let value = @json.parse(fixture) catch { _ => fail("fixture JSON required") }
  guard value is Object(root) &&
    root.get("native") is Some(Object(native)) &&
    native.get("source") is Some(Object(source)) else {
    fail("original Source fixture required")
  }
  let profile = @json.parse(
    "{\"local_rates\":[],\"native_rates\":[],\"native_capacity\":{\"transfer_bytes\":0,\"retained_bytes\":0,\"execution_bytes\":0}}",
  ) catch {
    _ => fail("independent profile fixture required")
  }
  source["estimates"] = Json::array(Array::make(33, profile))
  let wire = value.stringify()
  assert_true(wire.length() < 65536)
  let selected = local_source_installation(wire)
  assert_eq(selected.source_ref, "connector://crm/main/r#v")
  assert_eq(selected.database_file, "records.duckdb")
}

///|
fn declared_file_source_fixture(source : Map[String, Json]) -> String {
  Json::object({
    "version": Json::string("actql-config/0.1"),
    "native": Json::object({ "source": Json::object(source) }),
  }).stringify()
}

///|
test "Native adopts protected File declarations without opening the payload" {
  let connections = "{\"version\":\"actql-connectors/0.1\",\"connections\":{\"shared\":{\"connector\":\"file\"}}}"
  let catalog = "{\"connections\":{\"shared\":{\"files\":{}}}}"
  let path = "/operator-selected/data/original.json"
  let source : Map[String, Json] = {
    "kind": Json::string("declared_file"),
    "connections": Json::string(connections),
    "catalog": Json::string(catalog),
    "data_file": Json::string(path),
  }
  let wire = declared_file_source_fixture(source)
  let body = @utf8.encode(wire)
  let original : LocalCommandDeclaredFileSourceOriginal = {
    name: "source.json",
    body,
    material: local_prepare_source_installation(wire).unwrap(),
  }
  let (admitted_connections, admitted_catalog, admitted_path) = original
    .select("source.json", @utf8.encode(wire))
    .unwrap()
  assert_eq(admitted_connections.original_wire(), connections)
  assert_eq(admitted_catalog.original_wire(), catalog)
  assert_eq(admitted_path, path)
  assert_true(original.select("foreign-source.json", body) is None)
  assert_true(original.select("source.json", @utf8.encode(wire + " ")) is None)
  let resident_refusal = try {
    ignore(local_source_installation(wire))
    "unexpected acceptance"
  } catch {
    ClientStop(issue) => issue
  }
  assert_eq(resident_refusal, "LocalDeclaredFileSourceBindingRequired")
  for
    (field, changed, expected) in [
      (
        "kind",
        Json::string("mock"),
        "InvalidLocalDeclaredFileSourceInstallation",
      ),
      ("kind", Json::null(), "InvalidLocalDeclaredFileSourceInstallation"),
      (
        "catalog",
        Json::string("{\"unsupported\":true}"),
        "InvalidLocalDeclaredFileSourceInstallation",
      ),
      (
        "data_file",
        Json::string("/other/../data"),
        "InvalidLocalSourceLocation",
      ),
      ("data_file", Json::string("data.json"), "InvalidLocalSourceLocation"),
      ("data_file", Json::string("/other/"), "InvalidLocalSourceLocation"),
      ("data_file", Json::string("/other//data"), "InvalidLocalSourceLocation"),
      (
        "data_file",
        Json::string("/other\u{0000}/data"),
        "InvalidLocalSourceLocation",
      ),
      (
        "extra",
        Json::boolean(true),
        "InvalidLocalDeclaredFileSourceInstallation",
      ),
    ] {
    let foreign = source.copy()
    foreign[field] = changed
    let refused = try {
      ignore(
        local_prepare_source_installation(declared_file_source_fixture(foreign)),
      )
      "unexpected acceptance"
    } catch {
      ClientStop(issue) => issue
    }
    assert_eq(refused, expected)
  }
}

///|
test "Native configured inventory preserves nine explicit installation originals and supplied policy" {
  let names = Array::makei(9, index => {
    "\"original-" + index.to_string() + ".json\""
  })
  let wire = local_reviewer_cli_configuration.replace_all(
    old="[\"reviewer.json\"]",
    new="[" + names.join(",") + "]",
  )
  let selected = local_host_settings(wire)
  assert_eq(selected.installation_files.length(), 9)
  assert_eq(selected.installation_files[8], "original-8.json")
  assert_eq(selected.record_limit, 8)
  assert_eq(selected.snapshot_bytes, 8388608L)
  assert_eq(selected.principal, "original-client")
  assert_eq(selected.connection, "original-cli")
  let refused = try {
    ignore(
      local_host_settings(
        wire.replace_all(old="\"original-8.json\"", new="\"original-0.json\""),
      ),
    )
    "unexpected acceptance"
  } catch {
    ClientStop(issue) => issue
  }
  assert_eq(refused, "InvalidLocalInstallationSelection")
}

///|
test "Native Model installation inventory accepts distinct providers with distinct Task and credential originals" {
  let first =
    #|{"task_id":"model-task:producer.v1","provider_id":"models/producer","credential_installation":"a-credential.json","installation_revision":"a-revision.json","configuration_contract":"a-contract.json","response_profile":"a-profile.json","response_profile_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}
  let second =
    #|{"task_id":"model-task:receiver.v1","provider_id":"models/receiver","credential_installation":"b-credential.json","installation_revision":"b-revision.json","configuration_contract":"b-contract.json","response_profile":"b-profile.json","response_profile_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}
  let files =
    #|["a-credential.json","a-revision.json","a-contract.json","a-profile.json","b-credential.json","b-revision.json","b-contract.json","b-profile.json"]
  let selected = fn(second : String) {
    local_reviewer_cli_configuration.replace_all(
      old="[\"reviewer.json\"]",
      new=files + ",\"model_http_installations\":[" + first + "," + second + "]",
    )
  }
  for provider in ["models/receiver", "models/producer"] {
    let settings = local_host_settings(
      selected(second.replace_all(old="models/receiver", new=provider)),
    )
    let models = settings.model_http_installations.unwrap()
    assert_eq(models.length(), 2)
    assert_eq(
      (models[0].task_id, models[0].provider_id, models[0].files.setting),
      ("model-task:producer.v1", "models/producer", "a-credential.json"),
    )
    assert_eq(
      (models[1].task_id, models[1].provider_id, models[1].files.setting),
      ("model-task:receiver.v1", provider, "b-credential.json"),
    )
  }
  for
    (original, duplicate) in [
      ("model-task:receiver.v1", "model-task:producer.v1"),
      ("b-credential.json", "a-credential.json"),
    ] {
    let refused = try {
      ignore(
        local_host_settings(
          selected(second.replace_all(old=original, new=duplicate)),
        ),
      )
      "unexpected acceptance"
    } catch {
      ClientStop(issue) => issue
    }
    assert_eq(refused, "InvalidLocalModelHttpInstallation")
  }
}
