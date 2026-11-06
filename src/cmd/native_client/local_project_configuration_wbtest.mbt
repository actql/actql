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
test "project command flags override metadata while legacy installation selection stays explicit" {
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
  assert_true(local_project_discovery_selected(legacy))
  let explicit_legacy = command().parse(argv=[
    "--mode", "local", "--config-file", "legacy.json", "connect",
  ])
  assert_false(local_project_discovery_selected(explicit_legacy))
  assert_true(local_project_read(explicit_legacy) is Ok(None))
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
        ["--mode", "remote", "--config", "never-open.json", "connect"],
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
        [
          "--mode", "local", "--config-root", "/legacy", "--profile", "mock", "connect",
        ],
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
      "\"lock\":\"lock.json\"", "\"mock\":{\"catalog\":\"catalog.json\"}", "\"mock\":{\"data\":\"data.json\"}",
      "\"mock\":{\"answers\":{\"task\":\"answers.yaml\"}}",
    ] {
    let project = local_project_select_loaded(
      matches,
      "/project",
      "{\"version\":\"actql-config/0.1\"," + field + "}",
    )
    for
      operation in ["check", "explain", "run", "aql", "start", "new-submission"] {
      let rejected = try {
        local_project_require_execution_bindings(project, operation)
        false
      } catch {
        ClientStop(reason) => reason == "LocalProjectBindingsUnavailable"
      }
      assert_true(rejected)
    }
    // Adoption/connection do not execute project declarations. Saved operations
    // still restore the original Run/Policy under current
    // authorization; project metadata does not re-prepare or extend it.
    for
      operation in [
        "adopt", "connect", "status", "read", "cancel", "lookup-submission",
      ] {
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

///|
test "project discovery selects the nearest file and resolves paths beside that file" {
  let root = @env.get_env_var("ACTQL_TEST_NATIVE_PROJECT_CONFIGURATION_ROOT").unwrap_or_else(() => {
      fail("mandatory fresh project configuration fixture missing")
    },
  )
  let matches = command().parse(argv=["--mode", "local", "connect"])
  let parent = local_project_read_from(matches, root + "/parent/child")
    .unwrap()
    .unwrap()
  assert_eq(parent.state_directory, root + "/parent/.parent-state")
  let nearest = local_project_read_from(matches, root + "/nearer/child")
    .unwrap()
    .unwrap()
  assert_eq(nearest.state_directory, root + "/nearer/.nearer-state")
  let overridden = command().parse(argv=[
    "--mode",
    "local",
    "--state-dir",
    root + "/.explicit-state",
    "--profile",
    "mock",
    "connect",
  ])
  let selected = local_project_read_from(overridden, root + "/nearer/child")
    .unwrap()
    .unwrap()
  assert_eq(selected.state_directory, root + "/.explicit-state")
  assert_eq(selected.profile, Some("mock"))
}

///|
test "project discovery cannot rescue malformed nearer metadata with a valid parent" {
  let root = @env.get_env_var("ACTQL_TEST_NATIVE_PROJECT_CONFIGURATION_ROOT").unwrap_or_else(() => {
      fail("mandatory fresh project configuration fixture missing")
    },
  )
  let matches = command().parse(argv=["--mode", "local", "connect"])
  let rejected = try {
    ignore(local_project_read_from(matches, root + "/malformed/child"))
    false
  } catch {
    ClientStop(reason) => reason == "InvalidProjectConfiguration"
  }
  assert_true(rejected)
}

///|
test "project discovery preserves physical refusal instead of trying another ancestor" {
  let root = @env.get_env_var("ACTQL_TEST_NATIVE_PROJECT_CONFIGURATION_ROOT").unwrap_or_else(() => {
      fail("mandatory fresh project configuration fixture missing")
    },
  )
  let matches = command().parse(argv=["--mode", "local", "connect"])
  for name in ["symlink", "oversize", "invalid-utf8", "directory"] {
    let original = match
      local_project_read_from(matches, root + "/" + name + "/child") {
      Err(original) => original
      Ok(_) => {
        fail("invalid nearest project input fell back")
        return
      }
    }
    match name {
      "oversize" => assert_true(original.issue() is @files.CapacityExceeded)
      "invalid-utf8" => assert_true(original.issue() is @files.InvalidUtf8)
      _ => assert_true(original.issue() is @files.Filesystem(_))
    }
    original.retry_cleanup().unwrap()
  }
}

///|
test "project ancestor traversal terminates at root and Remote never discovers a Local project" {
  assert_eq(local_project_parent_directory("/"), None)
  assert_eq(local_project_parent_directory("/project"), Some("/"))
  assert_eq(local_project_parent_directory("/project/child"), Some("/project"))
  let remote = command().parse(argv=["--mode", "remote", "connect"])
  assert_false(local_project_discovery_selected(remote))
  assert_true(local_project_read_from(remote, "/never-opened") is Ok(None))
  let legacy_root = command().parse(argv=[
    "--mode", "local", "--config-root", "/legacy", "connect",
  ])
  assert_false(local_project_discovery_selected(legacy_root))
  assert_true(local_project_read_from(legacy_root, "/never-opened") is Ok(None))
}

///|
test "default mode selects Local only after the existing nearest project reader completes" {
  let root = @env.get_env_var("ACTQL_TEST_NATIVE_PROJECT_CONFIGURATION_ROOT").unwrap()
  let matches = command().parse(argv=["connect"])
  assert_true(local_project_default_local_candidate(matches))
  assert_true(matches.sources.get("mode") is Some(@argparse.Default))
  let selected = local_project_read_from(matches, root + "/nearer/child").unwrap()
  assert_eq(required(matches, "mode"), "remote")
  assert_eq(optional(matches, "state-dir"), None)
  local_project_apply_selection(matches, selected)
  assert_eq(required(matches, "mode"), "local")
  assert_eq(
    optional(matches, "state-dir"),
    Some(root + "/nearer/.nearer-state"),
  )
  local_project_apply_selection(matches, selected)
  assert_eq(required(matches, "mode"), "local")
}

///|
test "explicit project metadata uses the same default route without repairing an absent selected file" {
  let root = @env.get_env_var("ACTQL_TEST_NATIVE_PROJECT_CONFIGURATION_ROOT").unwrap()
  let matches = command().parse(argv=[
    "--config",
    root + "/actql.config.json",
    "connect",
  ])
  let selected = local_project_read(matches).unwrap()
  assert_eq(required(matches, "mode"), "remote")
  local_project_apply_selection(matches, selected)
  assert_eq(required(matches, "mode"), "local")
  let missing = command().parse(argv=[
    "--config",
    root + "/missing.json",
    "connect",
  ])
  guard local_project_read(missing) is Err(original) else {
    fail("missing explicit metadata unexpectedly selected a Host")
  }
  assert_true(original.issue() is @files.Missing)
  original.retry_cleanup().unwrap()
  assert_eq(required(missing, "mode"), "remote")
  assert_eq(optional(missing, "state-dir"), None)
}

///|
test "missing metadata is not an implicit Local adoption or installation selection" {
  let matches = command().parse(argv=["connect"])
  local_project_apply_selection(matches, None)
  assert_eq(required(matches, "mode"), "remote")
  assert_eq(optional(matches, "state-dir"), None)
}

///|
test "an explicit Remote route never discovers an existing Local project" {
  let root = @env.get_env_var("ACTQL_TEST_NATIVE_PROJECT_CONFIGURATION_ROOT").unwrap()
  let matches = command().parse(argv=["--mode", "remote", "connect"])
  assert_false(local_project_default_local_candidate(matches))
  assert_true(
    local_project_read_from(matches, root + "/nearer/child") is Ok(None),
  )
  assert_eq(required(matches, "mode"), "remote")
  assert_eq(optional(matches, "state-dir"), None)
}

///|
test "Remote connection and legacy configuration selectors do not become Local through a project file" {
  let root = @env.get_env_var("ACTQL_TEST_NATIVE_PROJECT_CONFIGURATION_ROOT").unwrap()
  for
    name in [
      "endpoint", "connection-root", "connection-file", "token-root", "token-file",
      "http-library", "ca", "cert", "key", "config-root", "config-file",
    ] {
    let matches = command().parse(argv=[
      "--" + name,
      "original-selection",
      "connect",
    ])
    assert_false(local_project_default_local_candidate(matches))
    assert_true(
      local_project_read_from(matches, root + "/nearer/child") is Ok(None),
    )
    assert_eq(required(matches, "mode"), "remote")
    assert_eq(optional(matches, "state-dir"), None)
  }
}

///|
test "malformed or physically refused default project reads cannot switch mode or fall back" {
  let root = @env.get_env_var("ACTQL_TEST_NATIVE_PROJECT_CONFIGURATION_ROOT").unwrap()
  let malformed = command().parse(argv=["connect"])
  let rejected = try {
    ignore(local_project_read_from(malformed, root + "/malformed/child"))
    false
  } catch {
    ClientStop(reason) => reason == "InvalidProjectConfiguration"
  }
  assert_true(rejected)
  assert_eq(required(malformed, "mode"), "remote")
  for name in ["symlink", "oversize", "invalid-utf8", "directory"] {
    let matches = command().parse(argv=["connect"])
    guard local_project_read_from(matches, root + "/" + name + "/child")
      is Err(original) else {
      fail("invalid nearest metadata fell back")
    }
    original.retry_cleanup().unwrap()
    assert_eq(required(matches, "mode"), "remote")
    assert_eq(optional(matches, "state-dir"), None)
  }
}

///|
test "a project profile selects no mock execution or runtime permission in default mode" {
  let matches = command().parse(argv=["check", "never-read.aql"])
  let project = local_project_select_loaded(
    matches, "/project", "{\"version\":\"actql-config/0.1\",\"profile\":\"mock\"}",
  )
  let rejected = try {
    local_project_apply_selection(matches, Some(project))
    false
  } catch {
    ClientStop(reason) => reason == "LocalProjectBindingsUnavailable"
  }
  assert_true(rejected)
  assert_eq(required(matches, "mode"), "remote")
  assert_eq(optional(matches, "state-dir"), None)
}

///|
test "a conflicting Remote connection never interprets an explicit project as permission to change Hosts" {
  let matches = command().parse(argv=[
    "--endpoint", "https://remote.example.invalid", "--config", "/never-opened/config.json",
    "connect",
  ])
  let rejected = try {
    ignore(local_project_read(matches))
    false
  } catch {
    ClientStop(reason) =>
      reason == "Local project configuration is unavailable in Remote mode"
  }
  assert_true(rejected)
  assert_eq(required(matches, "mode"), "remote")
}

///|
fn project_bindings_fixture(
  directory : String,
  configuration : String,
) -> LocalProjectConfiguration raise {
  local_project_select_loaded(
    command().parse(argv=["check", "never-read.aql"]),
    @env.get_env_var("ACTQL_TEST_NATIVE_PROJECT_CONFIGURATION_ROOT").unwrap() +
    "/" +
    directory,
    configuration,
  )
}

///|
test "plain project execution reads both selected empty declarations before changing the route" {
  let project = project_bindings_fixture(
    "plain", "{\"version\":\"actql-config/0.1\",\"connectors\":\"connectors.json\",\"model_tasks\":\"model-tasks.json\"}",
  )
  assert_true(project.source_free_bindings is None)
  let selected = local_project_read_execution_bindings(Some(project), "check")
    .unwrap()
    .unwrap()
  let facts = selected.source_free_bindings.unwrap()
  assert_true(facts.has_connectors_file())
  assert_true(facts.has_model_tasks_file())
  assert_eq(selected.state_directory, project.state_directory)
  let matches = command().parse(argv=["check", "never-read.aql"])
  assert_eq(required(matches, "mode"), "remote")
  local_project_apply_selection(matches, Some(selected))
  assert_eq(required(matches, "mode"), "local")
  assert_eq(optional(matches, "config-file"), None)
  assert_eq(optional(matches, "config-root"), Some("."))
}

///|
test "project declaration paths use the selected project directory rather than process cwd" {
  let project = project_bindings_fixture(
    "plain", "{\"version\":\"actql-config/0.1\",\"connectors\":\"./nested/../connectors.json\"}",
  )
  let selected = local_project_read_execution_bindings(Some(project), "explain")
    .unwrap()
    .unwrap()
  let facts = selected.source_free_bindings.unwrap()
  assert_true(facts.has_connectors_file())
  assert_false(facts.has_model_tasks_file())
  local_project_require_execution_bindings(selected, "explain")
}

///|
test "nonempty selected declarations cannot fall back to the packaged empty environment" {
  for directory in ["connector", "model", "provider", "default-provider"] {
    let project = project_bindings_fixture(
      directory, "{\"version\":\"actql-config/0.1\",\"connectors\":\"connectors.json\",\"model_tasks\":\"model-tasks.json\"}",
    )
    let matches = command().parse(argv=["check", "never-read.aql"])
    assert_true(
      try {
        ignore(local_project_read_execution_bindings(Some(project), "check"))
        false
      } catch {
        ClientStop(reason) => reason == "LocalProjectBindingsUnavailable"
      },
    )
    assert_eq(required(matches, "mode"), "remote")
    assert_eq(optional(matches, "state-dir"), None)
  }
}

///|
test "malformed and duplicate selected project declarations remain refusals" {
  for directory in ["bad-connectors", "bad-model", "duplicate-connectors"] {
    let project = project_bindings_fixture(
      directory, "{\"version\":\"actql-config/0.1\",\"connectors\":\"connectors.json\",\"model_tasks\":\"model-tasks.json\"}",
    )
    assert_true(
      try {
        ignore(local_project_read_execution_bindings(Some(project), "check"))
        false
      } catch {
        ClientStop(reason) => reason == "InvalidProjectBindings"
      },
    )
  }
}

///|
test "a refused declaration Reader retains original cleanup and never substitutes an empty file" {
  for
    directory in [
      "missing-bindings", "symlink-bindings", "oversize-bindings", "invalid-utf8-bindings",
      "directory-bindings",
    ] {
    let project = project_bindings_fixture(
      directory, "{\"version\":\"actql-config/0.1\",\"connectors\":\"connectors.json\"}",
    )
    guard local_project_read_execution_bindings(Some(project), "check")
      is Err(original) else {
      fail("declaration physical refusal became source-free facts")
    }
    match directory {
      "missing-bindings" => assert_true(original.issue() is @files.Missing)
      "oversize-bindings" =>
        assert_true(original.issue() is @files.CapacityExceeded)
      "invalid-utf8-bindings" =>
        assert_true(original.issue() is @files.InvalidUtf8)
      _ => assert_true(original.issue() is @files.Filesystem(_))
    }
    original.retry_cleanup().unwrap()
    assert_true(project.source_free_bindings is None)
  }
}

///|
test "saved operations do not read current declarations to repair original Run materials" {
  let project = project_bindings_fixture(
    "never-created", "{\"version\":\"actql-config/0.1\",\"connectors\":\"absent.json\",\"model_tasks\":\"absent.json\"}",
  )
  for
    operation in [
      "connect", "adopt", "status", "read", "cancel", "lookup-submission",
    ] {
    let selected = local_project_read_execution_bindings(
        Some(project),
        operation,
      )
      .unwrap()
      .unwrap()
    assert_true(selected.source_free_bindings is None)
    local_project_require_execution_bindings(selected, operation)
  }
}

///|
test "unsupported mock profile refuses before any declaration IO and retains default route" {
  let matches = command().parse(argv=["check", "never-read.aql"])
  let project = local_project_select_loaded(
    matches, "/never-created", "{\"version\":\"actql-config/0.1\",\"profile\":\"mock\",\"connectors\":\"absent.json\",\"model_tasks\":\"absent.json\"}",
  )
  assert_true(
    try {
      ignore(local_project_read_execution_bindings(Some(project), "check"))
      false
    } catch {
      ClientStop(reason) => reason == "LocalProjectBindingsUnavailable"
    },
  )
  assert_eq(required(matches, "mode"), "remote")
  assert_eq(optional(matches, "state-dir"), None)
}

///|
test "declaration facts cannot be transplanted across selected file roles" {
  let project = project_bindings_fixture(
    "plain", "{\"version\":\"actql-config/0.1\",\"connectors\":\"connectors.json\"}",
  )
  let wrong = @run_host.admit_client_source_free_project_bindings(
    None,
    Some(
      "{\"version\":\"actql-model-tasks/0.1\",\"tasks\":{},\"providers\":{}}",
    ),
  ).unwrap()
  let selected = { ..project, source_free_bindings: Some(wrong), }
  assert_true(
    try {
      local_project_require_execution_bindings(selected, "check")
      false
    } catch {
      ClientStop(reason) => reason == "LocalProjectBindingsUnavailable"
    },
  )
}

///|
test "saved public Run operands choose the existing default Local route without a project" {
  for
    arguments in [
      ["result", "original-run"],
      ["status", "original-run"],
      ["status", "--run-id", "original-run"],
    ] {
    let matches = command().parse(argv=arguments[:], env=Map([]))
    normalize_native_status_arguments(matches)
    assert_true(local_project_default_local_candidate(matches))
    assert_true(local_project_saved_run_requested(matches))
    let original_config = optional(matches, "config-file")
    local_project_apply_selection(matches, None)
    assert_eq(required(matches, "mode"), "local")
    assert_eq(optional(matches, "state-dir"), None)
    assert_eq(optional(matches, "config-file"), original_config)
    assert_true(command_preparation_invocation.val is None)
    assert_true(initial_crypto_invocation.val is None)
  }
}

///|
test "saved default selection never replaces explicit Remote or reference-file routing" {
  for
    arguments in [
      ["--mode", "remote", "result", "original-run"],
      ["--endpoint", "https://example.invalid", "status", "original-run"],
      ["status", "--ref-file", "original.json"],
      ["status", "--submission-ref-file", "original.json"],
    ] {
    let matches = command().parse(argv=arguments[:], env=Map([]))
    normalize_native_status_arguments(matches)
    local_project_apply_selection(matches, None)
    assert_eq(required(matches, "mode"), "remote")
    assert_eq(optional(matches, "state-dir"), None)
    assert_true(command_preparation_invocation.val is None)
  }
}

///|
test "catalog-only mock metadata cannot silently select the source-free installation" {
  let matches = command().parse(argv=["check", "never-read.aql"])
  let project = local_project_select_loaded(
    matches, "/never-created", "{\"version\":\"actql-config/0.1\",\"mock\":{\"catalog\":\"never-opened.json\"},\"connectors\":\"absent.json\"}",
  )
  assert_true(
    try {
      ignore(local_project_read_execution_bindings(Some(project), "check"))
      false
    } catch {
      ClientStop(reason) => reason == "LocalProjectBindingsUnavailable"
    },
  )
  assert_eq(required(matches, "mode"), "remote")
  assert_eq(optional(matches, "state-dir"), None)
  // Saved operations do not replace original bindings from current metadata.
  assert_true(
    local_project_read_execution_bindings(Some(project), "status") is Ok(_),
  )
}
