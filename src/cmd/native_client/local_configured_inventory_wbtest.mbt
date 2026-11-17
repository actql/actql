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
