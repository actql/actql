///|
test "project configuration defaults are metadata without Host authority" {
  let config = admit_client_project_configuration(
    "{\"version\":\"actql-config/0.1\"}",
  ).unwrap()
  assert_eq(config.state_directory(), "./.actql")
  assert_eq(config.connectors_file(), None)
  assert_eq(config.model_tasks_file(), None)
  assert_eq(config.lock_file(), None)
  assert_eq(config.selected_profile(), None)
  assert_eq(config.mock_catalog_file(), None)
  assert_eq(config.mock_data_file(), None)
  assert_eq(config.mock_answer_count(), 0)
  assert_eq(config.mock_answer_at(-1), None)
  assert_eq(config.mock_answer_at(0), None)
}

///|
test "project configuration retains independently written Quickstart locators" {
  let config = admit_client_project_configuration(
    (
      #|{"version":"actql-config/0.1","connectors":"./connectors.json","model_tasks":"./model-tasks.json","lock":"./actql.lock.json","state_dir":"./.actql","profile":"mock","mock":{"data":"./mock/data.json","answers":{"model-task:churn-risk.v1":"./mock/churn-risk.v1.answers.yaml","model-task:other.v1":"../other.yaml"}}}
    ),
  ).unwrap()
  assert_eq(config.connectors_file(), Some("./connectors.json"))
  assert_eq(config.model_tasks_file(), Some("./model-tasks.json"))
  assert_eq(config.lock_file(), Some("./actql.lock.json"))
  assert_eq(config.state_directory(), "./.actql")
  assert_eq(config.selected_profile(), Some("mock"))
  assert_eq(config.mock_data_file(), Some("./mock/data.json"))
  assert_eq(config.mock_answer_count(), 2)
  assert_eq(
    config.mock_answer_at(0),
    Some(("model-task:churn-risk.v1", "./mock/churn-risk.v1.answers.yaml")),
  )
  assert_eq(
    config.mock_answer_at(1),
    Some(("model-task:other.v1", "../other.yaml")),
  )
  assert_eq(config.mock_answer_at(2), None)
}

///|
test "project configuration leaves path resolution and profile decisions to consumers" {
  for profile in ["mock", "production", "unknown-profile"] {
    let config = admit_client_project_configuration(
      "{\"version\":\"actql-config/0.1\",\"state_dir\":\"../shared\",\"profile\":\"" +
      profile +
      "\",\"mock\":{}}",
    ).unwrap()
    assert_eq(config.selected_profile(), Some(profile))
    assert_eq(config.state_directory(), "../shared")
    assert_eq(config.mock_answer_count(), 0)
    assert_eq(config.mock_catalog_file(), None)
    assert_eq(config.mock_data_file(), None)
  }
}

///|
test "project configuration rejects Host and legacy Native fields without fallback" {
  for
    field in [
      "account_config", "signers", "run_policy", "effect_policy", "native", "host",
      "permission", "runnable", "unknown",
    ] {
    assert_true(
      admit_client_project_configuration(
        "{\"version\":\"actql-config/0.1\",\"" + field + "\":{}}",
      )
      is Err(InvalidConfiguration),
    )
  }
  for
    wire in [
      "{\"version\":\"actql-config/0.1\",\"mock\":{\"signers\":{}}}", "{\"version\":\"actql-config/0.1\",\"mock\":{\"data\":\"a\",\"extra\":false}}",
    ] {
    assert_true(
      admit_client_project_configuration(wire) is Err(InvalidConfiguration),
    )
  }
}

///|
test "project configuration rejects null empty and wrong typed locators" {
  for field in ["connectors", "model_tasks", "lock", "state_dir", "profile"] {
    for value in ["null", "false", "42", "[]", "{}", "\"\"", "\"a\\u0000b\""] {
      assert_true(
        admit_client_project_configuration(
          "{\"version\":\"actql-config/0.1\",\"" + field + "\":" + value + "}",
        )
        is Err(InvalidConfiguration),
      )
    }
  }
  for
    mock in [
      "null", "[]", "false", "{\"data\":null}", "{\"data\":\"\"}", "{\"answers\":null}",
      "{\"answers\":[]}", "{\"answers\":{\"task\":null}}", "{\"answers\":{\"\":\"x\"}}",
      "{\"answers\":{\"task\":\"\"}}",
    ] {
    assert_true(
      admit_client_project_configuration(
        "{\"version\":\"actql-config/0.1\",\"mock\":" + mock + "}",
      )
      is Err(InvalidConfiguration),
    )
  }
}

///|
test "project configuration preserves strict duplicate Unicode and JSON admission" {
  for
    wire in [
      "{}", "[]", "null", "{\"version\":\"actql-config/0.2\"}", "{\"version\":\"actql-config/0.1\",\"version\":\"actql-config/0.1\"}",
      "{\"version\":\"actql-config/0.1\",\"profile\":\"mock\",\"profi\\u006ce\":\"mock\"}",
      "{\"version\":\"actql-config/0.1\",\"mock\":{\"answers\":{\"task\":\"a\",\"task\":\"b\"}}}",
      "{\"version\":\"actql-config/0.1\",\"state_dir\":\"\\ud800\"}", "{\"version\":\"actql-config/0.1\"}{}",
    ] {
    assert_true(
      admit_client_project_configuration(wire) is Err(InvalidConfiguration),
    )
  }
  let config = admit_client_project_configuration(
    "{\"version\":\"actql-config/0.1\",\"state_dir\":\"./日本語😀\"}",
  ).unwrap()
  assert_eq(config.state_directory(), "./日本語😀")
}

///|
test "project configuration derives intake geometry from the original wire" {
  let original = "{\"version\":\"actql-config/0.1\"}"
  let exact = original + " ".repeat(65536 - original.length())
  assert_true(admit_client_project_configuration(exact) is Ok(_))
  assert_true(admit_client_project_configuration(exact + " ") is Ok(_))
}

///|
test "project configuration retains explicit catalog text without discovering a default" {
  let config = admit_client_project_configuration(
    (
      #|{"version":"actql-config/0.1","mock":{"catalog":"../catalog-é😀.json","data":"./rows.json","answers":{}}}
    ),
  ).unwrap()
  assert_eq(config.mock_catalog_file(), Some("../catalog-é😀.json"))
  assert_eq(config.mock_data_file(), Some("./rows.json"))
  assert_eq(config.mock_answer_count(), 0)
}

///|
test "project configuration rejects invalid and duplicate catalog locators" {
  for
    value in [
      "null", "false", "42", "[]", "{}", "\"\"", "\"a\\u0000b\"", "\"\\ud800\"",
    ] {
    assert_true(
      admit_client_project_configuration(
        "{\"version\":\"actql-config/0.1\",\"mock\":{\"catalog\":" +
        value +
        "}}",
      )
      is Err(InvalidConfiguration),
    )
  }
  for
    wire in [
      (
        #|{"version":"actql-config/0.1","mock":{"catalog":"a","catalog":"b"}}
      ),
      (
        #|{"version":"actql-config/0.1","mock":{"catalog":"a","cata\u006cog":"b"}}
      ),
      (
        #|{"version":"actql-config/0.1","mock":{"catalog":"a","unknown":false}}
      ),
    ] {
    assert_true(
      admit_client_project_configuration(wire) is Err(InvalidConfiguration),
    )
  }
}
