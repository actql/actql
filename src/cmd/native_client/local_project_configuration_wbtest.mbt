///|
test "project selection consumes the Common metadata relative to its selected file" {
  let matches = command().parse(argv=[
    "--mode", "local", "--config", "actql.config.json", "connect",
  ])
  let selected = local_project_select_loaded(
    matches, "/projects/example", "{\"version\":\"actql-config/0.1\"}",
  )
  assert_eq(selected.state_directory, "/projects/example/.actql")
  assert_eq(selected.profile, None)
  local_project_require_execution_bindings(selected, "connect")
  let selected = local_project_select_loaded(
    matches, "/projects/example", "{\"version\":\"actql-config/0.1\",\"state_dir\":\"../shared/.actql\"}",
  )
  assert_eq(selected.state_directory, "/projects/shared/.actql")
  assert_eq(
    local_project_absolute_path("/", "./project/./actql.config.json"),
    "/project/actql.config.json",
  )
}

///|
test "project command flags override metadata without changing the legacy HOME default" {
  let matches = command().parse(argv=[
    "--mode", "local", "--config", "actql.config.json", "--state-dir", "/other/.actql",
    "--profile", "selected", "connect",
  ])
  let selected = local_project_select_loaded(
    matches, "/projects/example", "{\"version\":\"actql-config/0.1\",\"state_dir\":\"./unused\",\"profile\":\"mock\"}",
  )
  assert_eq(selected.state_directory, "/other/.actql")
  assert_eq(selected.profile, Some("selected"))
  let legacy = command().parse(argv=["--mode", "local", "connect"])
  assert_true(local_project_read(legacy) is Ok(None))
  assert_eq(
    local_product_selected_location(None, Some("/home/user")).directory_name,
    ".actql-local",
  )
}

///|
test "project paths and Host fields cannot fall back into a legacy installation" {
  for
    path in [
      "",
      "../../outside",
      "./nul\u{0000}",
      "bad\\file",
      "/",
      "x".repeat(4097),
    ] {
    let rejected = try {
      ignore(local_project_absolute_path("/project", path))
      false
    } catch {
      ClientStop(reason) => reason == "InvalidProjectConfigurationPath"
    }
    assert_true(rejected)
  }
  let matches = command().parse(argv=["--mode", "local", "connect"])
  for
    wire in [
      "{\"version\":\"actql-config/0.1\",\"native\":{}}", "{\"version\":\"actql-config/0.1\",\"signers\":{}}",
      "{\"version\":\"actql-config/0.1\",\"state_dir\":null}",
    ] {
    let rejected = try {
      ignore(local_project_select_loaded(matches, "/project", wire))
      false
    } catch {
      ClientStop(reason) => reason == "InvalidProjectConfiguration"
    }
    assert_true(rejected)
  }
}

///|
test "project selection refuses Remote or conflicting legacy options before file IO" {
  for
    (argv, expected) in [
      (
        ["--config", "never-open.json", "connect"],
        "Local project configuration is unavailable in Remote mode",
      ),
      (
        [
          "--mode", "local", "--config", "never-open.json", "--config-file", "legacy.json",
          "connect",
        ],
        "ConflictingLocalProjectSelection",
      ),
      (
        [
          "--mode", "local", "--config", "never-open.json", "--config-root", "/legacy",
          "connect",
        ],
        "ConflictingLocalProjectSelection",
      ),
      (
        ["--mode", "local", "--profile", "mock", "connect"],
        "ProjectConfigurationRequired",
      ),
    ] {
    let parsed = command().parse(argv~)
    let rejected = try {
      ignore(local_project_read(parsed))
      false
    } catch {
      ClientStop(reason) => reason == expected
    }
    assert_true(rejected)
  }
}

///|
test "uninstalled project bindings cannot silently run live or fabricate a mock Run" {
  let matches = command().parse(argv=["--mode", "local", "connect"])
  for
    field in [
      "\"profile\":\"mock\"", "\"connectors\":\"connectors.json\"", "\"model_tasks\":\"tasks.json\"",
      "\"lock\":\"lock.json\"", "\"mock\":{\"data\":\"data.json\"}", "\"mock\":{\"answers\":{\"task\":\"answers.yaml\"}}",
    ] {
    let project = local_project_select_loaded(
      matches,
      "/project",
      "{\"version\":\"actql-config/0.1\"," + field + "}",
    )
    for
      operation in [
        "adopt", "connect", "check", "explain", "run", "aql", "start", "new-submission",
      ] {
      let rejected = try {
        local_project_require_execution_bindings(project, operation)
        false
      } catch {
        ClientStop(reason) => reason == "LocalProjectBindingsUnavailable"
      }
      assert_true(rejected)
    }
    // These operations still restore the original Run/Policy under current
    // authorization; project metadata does not re-prepare or extend it.
    for operation in ["status", "read", "cancel", "lookup-submission"] {
      local_project_require_execution_bindings(project, operation)
    }
  }
}

///|
test "project file read retains the existing bounded Reader failure carrier" {
  let root = @env.get_env_var("ACTQL_TEST_NATIVE_PROJECT_CONFIGURATION_ROOT").unwrap_or_else(() => {
      fail("mandatory fresh project configuration fixture missing")
    },
  )
  let matches = command().parse(argv=[
    "--mode",
    "local",
    "--config",
    root + "/actql.config.json",
    "connect",
  ])
  let selected = local_project_read(matches).unwrap().unwrap()
  assert_eq(selected.state_directory, root + "/.actql")
  let missing = command().parse(argv=[
    "--mode",
    "local",
    "--config",
    root + "/missing.json",
    "connect",
  ])
  let failure = match local_project_read(missing) {
    Err(original) => original
    Ok(_) => {
      fail("missing project input admitted")
      return
    }
  }
  assert_true(failure.issue() is @files.Missing)
  failure.retry_cleanup().unwrap()
  assert_true(failure.issue() is @files.Missing)
}
