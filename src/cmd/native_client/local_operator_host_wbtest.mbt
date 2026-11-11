///|
test "operator Host selection uses the explicit original path before HOME" {
  let mut homes = 0
  let home = fn() -> String? raise ClientStop {
    homes += 1
    if homes > 1 {
      stop("RepeatedHomeRead")
    }
    Some("/machine-user")
  }
  let explicit = local_operator_host_location(
    Some("./operator/host.json"),
    "/invocation",
    home,
    initialize=true,
  )
  assert_eq(explicit.base_path, "/invocation/operator")
  assert_eq(explicit.name, "host.json")
  assert_eq(explicit.directories.length(), 0)
  assert_false(explicit.create_default)
  assert_eq(homes, 0)
  let standard = local_operator_host_location(
    None,
    "/project",
    home,
    initialize=true,
  )
  assert_eq(standard.base_path, "/machine-user")
  assert_eq(standard.directories, [".config", "actql"])
  assert_eq(standard.name, "host.json")
  assert_true(standard.create_default)
  assert_eq(homes, 1)
}

///|
test "operator Host defaults never ignore configured signers or policy" {
  local_operator_host_require_initial_default(
    "{\"version\":\"actql-host/0.1\"}\n",
  )
  for field in ["signers", "account_config", "run_policy", "effect_policy"] {
    let mut refused = false
    local_operator_host_require_initial_default(
      "{\"version\":\"actql-host/0.1\",\"" + field + "\":{}}",
    ) catch {
      ClientStop(message) => {
        assert_eq(message, "LocalConfiguredHostInstallationUnavailable")
        refused = true
      }
    }
    assert_true(refused)
  }
}
