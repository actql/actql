///|
test "ordinary input paths preserve the selected Root and exact basename" {
  let relative = local_input_file_location("/project", "inputs/parameters.json")
  assert_eq(relative.root, "/project/inputs")
  assert_eq(relative.name, "parameters.json")
  let name = "declarations é " + "x".repeat(130) + ".json"
  let absolute = local_input_file_location("/project", "/other/" + name)
  assert_eq(absolute.root, "/other")
  assert_eq(absolute.name, name)
  let top = local_input_file_location("/project", "/parameters.json")
  assert_eq(top.root, "/")
  assert_eq(top.name, "parameters.json")
  let ordinary = local_input_file_location("/project", "parameters\\copy.json")
  assert_eq(ordinary.root, "/project")
  assert_eq(ordinary.name, "parameters\\copy.json")
  let project_rejected = try {
    ignore(local_project_absolute_path("/project", "parameters\\copy.json"))
    false
  } catch {
    ClientStop(_) => true
  }
  assert_true(project_rejected)
  assert_true(command_preparation_invocation.val is None)
}

///|
test "ordinary input paths preserve an explicitly relative input root" {
  let current = @env.current_dir().unwrap()
  let selected = local_input_file_location(".", "parameters.json")
  assert_eq(selected.root, current)
  assert_eq(selected.name, "parameters.json")
  let nested = local_input_file_location("input directory", "params é.json")
  assert_eq(nested.root, current + "/input directory")
  assert_eq(nested.name, "params é.json")
  assert_true(command_preparation_invocation.val is None)
}

///|
test "ordinary input paths refuse invalid and overbound metadata before IO" {
  for
    value in [
      "",
      "directory/",
      "/",
      "bad\u{0000}file",
      "../../../outside",
      "x".repeat(4097),
      "é".repeat(2050),
    ] {
    let issue = try {
      ignore(local_input_file_location("/project", value))
      "unexpected acceptance"
    } catch {
      ClientStop(issue) => issue
    }
    assert_eq(issue, "InvalidLocalInputPath")
    assert_true(command_preparation_invocation.val is None)
    assert_true(initial_crypto_invocation.val is None)
  }
}
