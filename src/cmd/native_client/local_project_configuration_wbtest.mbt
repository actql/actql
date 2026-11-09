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
test "project init support is implementation data and acquires no command original" {
  assert_true(local_project_binding_implementation(None, false))
  assert_true(local_project_binding_implementation(Some("mock"), true))
  assert_false(local_project_binding_implementation(Some("mock"), false))
  assert_false(local_project_binding_implementation(None, true))
  assert_false(local_project_binding_implementation(Some("other"), false))
  let matches = command().parse(argv=[
    "--config", "/never-created/config.json", "--state-dir", "/never-created/state",
    "project-init-support",
  ])
  let reply : Ref[String?] = Ref(None)
  assert_true(command_preparation_invocation.val is None)
  execute_and_write_native_reply(matches, reply)
  assert_eq(
    reply.val,
    Some(
      "{\"version\":\"actql-project-init-support/0.1\",\"sourceFree\":true,\"mock\":true}",
    ),
  )
  assert_true(command_preparation_invocation.val is None)
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

///|
test "Native Project Mock reads exact public declarations and retains same typed selection" {
  let directory = @env.get_env_var(
      "ACTQL_TEST_NATIVE_PROJECT_CONFIGURATION_ROOT",
    ).unwrap() +
    "/deal-review"
  let matches = command().parse(argv=["check", "never-read.aql"])
  let project = local_project_read_from(matches, directory).unwrap().unwrap()
  let selected = local_project_read_execution_bindings(Some(project), "check")
    .unwrap()
    .unwrap()
  let value = selected.mock_declarations.unwrap()
  defer value.retire()
  assert_true(
    physical_equal(value._retained_project.metadata, project.metadata),
  )
  assert_true(
    @run_host.client_project_profile_matches(
      value.profile,
      Some(project.metadata),
      project.profile,
    ),
  )
  assert_eq(value._retained_connections.count(), 2)
  assert_eq(value._retained_connections.at(0).unwrap().0, "salesforce")
  assert_eq(value._retained_connections.at(1).unwrap().0, "drive")
  assert_eq(value._retained_catalog.count(), 2)
  assert_eq(value._retained_registry.unwrap().task_count(), 1)
  assert_eq(value._retained_tasks.length(), 1)
  let (task, selection, answers, _path) = value._retained_tasks[0]
  assert_eq(
    @run_host.client_project_model_task_selection_for(
      selection,
      value._retained_registry.unwrap(),
      task,
    ),
    Some(("openai", None, "./model-tasks/deal-review.v1.yaml")),
  )
  let separately_read = @run_host.admit_client_project_model_registry(
    value._retained_registry.unwrap().original_wire(),
  ).unwrap()
  assert_eq(
    @run_host.client_project_model_task_selection_for(
      selection, separately_read, task,
    ),
    None,
  )
  assert_true(value._retained_data_file.has_suffix("/mock/data.json"))
  assert_true(answers.contains("006Globex"))
  // Implementation availability does not turn standalone declaration intake
  // into the SAME retained Command/Source/Model preparation.
  assert_true(local_project_binding_implementation(Some("mock"), true))
  assert_true(
    try {
      local_project_apply_selection(matches, Some(selected))
      false
    } catch {
      ClientStop(reason) => reason == "LocalProjectBindingsUnavailable"
    },
  )
}

///|
test "Native Project Mock preserves missing Reader and rejects foreign registered Task" {
  let configuration = "{\"version\":\"actql-config/0.1\",\"profile\":\"mock\",\"connectors\":\"./connectors.json\",\"model_tasks\":\"./model-tasks.json\",\"mock\":{\"catalog\":\"./mock/catalog.json\",\"data\":\"./mock/data.json\",\"answers\":{\"model-task:deal-review.v1\":\"./mock/deal-review.v1.answers.yaml\"}}}"
  let missing = project_bindings_fixture(
    "deal-review-missing-task", configuration,
  )
  let original = local_project_read_mock_declarations(
    missing,
    local_project_mock_task_limits(),
  ).unwrap_err()
  assert_true(original.issue() is @files.Missing)
  original.retry_cleanup().unwrap()
  let foreign = project_bindings_fixture(
    "deal-review-wrong-task", configuration,
  )
  assert_true(
    try {
      ignore(
        local_project_read_mock_declarations(
          foreign,
          local_project_mock_task_limits(),
        ),
      )
      false
    } catch {
      ClientStop(reason) => reason == "InvalidProjectBindings"
    },
  )
}

///|
fn native_project_mock_nested_original() -> @run_host.ClientProjectProfileSelection raise {
  let directory = @env.get_env_var(
      "ACTQL_TEST_NATIVE_PROJECT_CONFIGURATION_ROOT",
    ).unwrap() +
    "/deal-review-nested-registry"
  let project = local_project_read_from(
      command().parse(argv=["check", "never-read.aql"]),
      directory,
    )
    .unwrap()
    .unwrap()
  let selected = local_project_read_execution_bindings(Some(project), "check")
    .unwrap()
    .unwrap()
  let original = selected.mock_declarations.unwrap()
  defer original.retire()
  let (task, selection, answers, _path) = original._retained_tasks[0]
  assert_eq(
    @run_host.client_project_model_task_selection_for(
      selection,
      original._retained_registry.unwrap(),
      task,
    ),
    Some(("openai", None, "../model-tasks/deal-review.v1.yaml")),
  )
  // These two original paths remain Project-relative, not registry-relative.
  assert_true(original._retained_data_file.has_suffix("/mock/data.json"))
  assert_true(answers.contains("006Globex"))
  original.profile
}

///|
test "Native Project Mock nested registry keeps original path bases and retires its nominal profile" {
  let original = native_project_mock_nested_original()
  assert_true(
    original.selected_profile()
    is Err(@run_host.ClientProjectProfileIssue::Retired),
  )
}

///|
fn native_project_mock_model_fixture(
  name : String,
  operation? : String = "check",
) -> LocalProjectMockDeclarations raise {
  let directory = @env.get_env_var(
      "ACTQL_TEST_NATIVE_PROJECT_CONFIGURATION_ROOT",
    ).unwrap() +
    "/" +
    name
  let project = local_project_read_from(
      command().parse(argv=["check", "never-read.aql"]),
      directory,
    )
    .unwrap()
    .unwrap()
  local_project_read_execution_bindings(Some(project), operation)
  .unwrap()
  .unwrap().mock_declarations.unwrap()
}

///|
test "Native Project Mock installs original typed answer Model once and retires its cycles" {
  let original = native_project_mock_model_fixture("deal-review")
  defer original.retire()
  let mut clocks = 0
  let now = fn() {
    clocks += 1
    "2026-01-01T00:00:00Z"
  }
  original
  .prepare_models(
    local_project_mock_task_limits(),
    local_project_mock_answer_limits(),
    now,
  )
  .unwrap()
  assert_eq(clocks, 0)
  assert_eq(original.models.length(), 1)
  let entry = original.models[0]
  let answers = entry.answers.unwrap()
  let profile = original.model_profile.unwrap()
  let normalized = entry.normalized.unwrap()
  let installation = entry.installation.unwrap()
  assert_eq(@model.model_mock_answer_count(answers, entry.declaration), Ok(2))
  assert_true(
    @compiler_environment.normalized_public_mock_model_task_original_for(
      normalized,
      entry.declaration,
      profile,
    ),
  )
  let provider = @model.original_model_mock_provider(installation).unwrap()
  assert_true(
    physical_equal(
      provider,
      @model.original_model_mock_provider(installation).unwrap(),
    ),
  )
  assert_true(
    original.prepare_models(
      local_project_mock_task_limits(),
      local_project_mock_answer_limits(),
      now,
    )
    is Err(AlreadyPreparing),
  )
  assert_eq(clocks, 0)
  assert_eq(original.retire_originals().unwrap(), true)
  assert_eq(original.retire_originals().unwrap(), true)
  assert_true(
    @model.original_model_mock_provider(installation)
    is Err(@model.ModelMockInstallationIssue::Retired),
  )
  assert_true(
    @model.model_mock_answer_count(answers, entry.declaration)
    is Err(@model.ModelMockAnswerIssue::Retired),
  )
  assert_false(@compiler_environment.model_mock_profile_current(profile))
}

///|
test "Native Project Mock preserves partial typed answer failure without reinstalling" {
  let original = native_project_mock_model_fixture("deal-review-wrong-answer")
  defer original.retire()
  let mut clocks = 0
  let now = fn() {
    clocks += 1
    "2026-01-01T00:00:00Z"
  }
  assert_true(
    original.prepare_models(
      local_project_mock_task_limits(),
      local_project_mock_answer_limits(),
      now,
    )
    is Err(Answers(@model.ModelMockAnswerIssue::OutputValue)),
  )
  assert_true(original.model_profile is Some(_))
  assert_eq(original.models.length(), 1)
  assert_true(original.models[0].answers is None)
  assert_true(original.models[0].installation is None)
  assert_true(
    original.prepare_models(
      local_project_mock_task_limits(),
      local_project_mock_answer_limits(),
      now,
    )
    is Err(Answers(@model.ModelMockAnswerIssue::OutputValue)),
  )
  assert_eq(original.models.length(), 1)
  assert_eq(clocks, 0)
  assert_eq(original.retire_originals().unwrap(), true)
  assert_true(original.model_profile is None)
}

///|
test "Native Project Mock does not open Source data as a bounded declaration before Request" {
  let original = native_project_mock_model_fixture("deal-review-missing")
  defer original.retire()
  assert_true(
    original._retained_data_file.has_suffix(
      "/deal-review-missing/mock/data.json",
    ),
  )
  assert_eq(original._retained_tasks.length(), 1)
  // A locator is neither an admitted Source snapshot nor missing-file ACK.
  // Its actual source Owner must open it later under the checked Request.
  assert_true(original.model_profile is None)
}

///|
test "Mock initial adoption refuses incomplete declarations before document IO" {
  let matches = command().parse(argv=["adopt"])
  for
    wire in [
      "{\"version\":\"actql-config/0.1\",\"profile\":\"mock\"}", "{\"version\":\"actql-config/0.1\",\"profile\":\"mock\",\"connectors\":\"not-read.json\",\"model_tasks\":\"not-read-tasks.json\"}",
    ] {
    let project = local_project_select_loaded(
      matches, "/never-created-mock", wire,
    )
    let refused = try {
      ignore(local_project_read_execution_bindings(Some(project), "adopt"))
      false
    } catch {
      ClientStop(reason) => reason == "LocalProjectBindingsUnavailable"
    }
    assert_true(refused)
  }
}

///|
// Pure first-adoption DATA correspondence, not Host/Account/runtime admission.
// Explicit policy and retained Intent paths never call the default projector.
test "Native default Model policy retains original assets and explicit lower environments" {
  let assets = @run_host.client_local_product_assets()
  let originals = @run_host.client_local_product_finite_originals(
    "/operator/native-model-policy", "/product/sqlite.dylib", "/product/crypto.dylib",
    "2026-11-09T00:00:00.000Z", assets,
  ).unwrap()
  let text = fn(values : Array[(String, Bytes)], name : String) -> String {
    @utf8.decode(values.iter().find_first(pair => pair.0 == name).unwrap().1) catch {
      _ => abort("invalid original policy bytes")
    }
  }
  let ceiling = fn(value : String) -> Json {
    guard (@json.parse(value) catch { _ => abort("invalid policy JSON") })
      is Object(body) &&
      body.get("host_policy_profile") is Some(Object(host)) &&
      host.get("capacity") is Some(Object(capacity)) else {
      abort("missing original capacity")
    }
    capacity["max_model_request_bytes_per_item"]
  }
  let environment = text(originals, "environment.json")
  let config = text(originals, "config.json")
  assert_eq(ceiling(environment), Json::number(1000))
  let explicit = local_product_model_policy_originals(originals, None)
  assert_true(physical_equal(explicit, originals))
  assert_eq(text(explicit, "environment.json"), environment)
  assert_eq(text(explicit, "config.json"), config)
  let selected = local_product_model_policy_originals(
    originals,
    Some(@local_values.client_local_resource_policy()),
  )
  let selected_environment = text(selected, "environment.json")
  assert_eq(ceiling(selected_environment), Json::number(65536))
  assert_eq(ceiling(assets.environment), Json::number(1000))
  assert_eq(text(originals, "environment.json"), environment)
  assert_eq(text(originals, "config.json"), config)
  for (name, bytes) in originals {
    if name != "environment.json" && name != "config.json" {
      assert_eq(
        selected.iter().find_first(pair => pair.0 == name).unwrap().1,
        bytes,
      )
    }
  }
  let (file, cid) = local_configuration(text(selected, "config.json"))
  assert_eq(file, "environment.json")
  assert_true(
    local_admitted_check_environment(selected_environment, cid) is Some(_),
  )
  // A retained installation restores its exact selected tuple; it does not
  // regenerate a default under the current Resource/Model policy.
  let retained = local_product_model_policy_originals(selected, None)
  assert_true(physical_equal(retained, selected))
  assert_eq(text(retained, "environment.json"), selected_environment)
}

///|
// Constructor DATA only. Physical Store reservations and currentness remain
// with the existing Store; restoring old bytes cannot select a new default.
test "Native finite Store profile retains explicit and legacy object quotas" {
  let assets = @run_host.client_local_product_assets()
  let finite = @run_host.client_local_product_finite_originals(
    "/operator/native-store-policy", "/product/sqlite.dylib", "/product/crypto.dylib",
    "2026-11-09T00:00:00.000Z", assets,
  ).unwrap()
  let legacy = @run_host.client_local_product_originals(
    "/operator/native-store-policy", "/product/sqlite.dylib", "/product/crypto.dylib",
    "2026-11-09T00:00:00.000Z", assets,
  ).unwrap()
  let run_bytes = fn(values : Array[(String, Bytes)]) -> Bytes {
    values.iter().find_first(pair => pair.0 == "run.json").unwrap().1
  }
  let text = fn(bytes : Bytes) -> String {
    @utf8.decode(bytes) catch {
      _ => abort("invalid Store policy bytes")
    }
  }
  let original = local_command_run_installation_original(
    "run.json",
    text(run_bytes(legacy)),
  )
  let selected = local_run_installation(text(run_bytes(finite)))
  assert_eq(selected.store_objects, 100000L)
  // The byte/item/Result ceilings are independent of the object inventory.
  assert_eq(selected.store_capacity_bytes, 1048576L)
  assert_eq(selected.store_record_bytes, 1048576L)
  assert_eq(selected.result_payload_bytes, 65536L)
  assert_eq(original.installation.store_objects, 8L)
  assert_eq(
    original.select("run.json", run_bytes(legacy)).unwrap().store_objects,
    8L,
  )
  assert_true(original.select("run.json", run_bytes(finite)) is None)
  // No default Store selection rewrites the packaged Environment or policy.
  for name in ["environment.json", "store.json"] {
    assert_eq(
      finite.iter().find_first(pair => pair.0 == name).unwrap().1,
      legacy.iter().find_first(pair => pair.0 == name).unwrap().1,
    )
  }
}

///|
// Actual bounded Project declaration readers, with only the three original
// metadata documents present. No Host, Run, Account, payload read or IO grant.
test "Native approval selects write metadata without reopening Model or Source payload" {
  let directory = @env.get_env_var(
      "ACTQL_TEST_NATIVE_PROJECT_CONFIGURATION_ROOT",
    ).unwrap() +
    "/deal-review-approval"
  let project = local_project_read_from(
      command().parse(argv=["check", "never-read.aql"]),
      directory,
    )
    .unwrap()
    .unwrap()
  let selected = local_project_read_execution_bindings(Some(project), "approve")
    .unwrap()
    .unwrap()
  guard selected.mock_declarations is Some(original) else {
    fail("approval must retain its actual write metadata")
  }
  defer original.retire()
  assert_true(
    physical_equal(project.metadata, original._retained_project.metadata),
  )
  assert_eq(original._retained_tasks.length(), 0)
  assert_true(original.model_profile is None)
  assert_false(original.model_started)
  original.prepare_source_declarations().unwrap()
  guard original.sources
    .iter()
    .find_first(source => source._retained_connection == "salesforce")
    is Some(source) else {
    fail("original Salesforce declaration required")
  }
  assert_eq(source._retained_writes.length(), 1)
  assert_true(source._retained_rows.length() > 0)
  assert_true(
    source._retained_writes[0].mapping.write_fields.contains("StageName"),
  )
  assert_true(
    source._retained_writes[0].mapping.write_fields.contains("NextStep"),
  )
  assert_false(
    source._retained_writes[0]._retained_observe_permission.is_empty(),
  )
  let mut clocks = 0
  assert_true(
    original.prepare_models(
      local_project_mock_task_limits(),
      local_project_mock_answer_limits(),
      () => {
        clocks += 1
        "2026-01-01T00:00:00Z"
      },
    )
    is Err(ForeignOriginal),
  )
  assert_eq(clocks, 0)
  assert_false(original.model_started)
  assert_true(original.model_profile is None)
  assert_eq(original.models.length(), 0)
}
