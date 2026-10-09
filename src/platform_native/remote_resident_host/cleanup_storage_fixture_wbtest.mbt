// Resolve the Native cleanup fixture's required configuration without opening
// storage. The caller owns directory creation and reads the clock afterward.

///|
fn cleanup_storage_configuration(
  name : String,
  read_env? : (String) -> String? = @env.get_env_var,
) -> Result[(String, String, String), String] {
  guard read_env("ACTQL_TEST_NATIVE_SQLITE_LIBRARY") is Some(sqlite_path) else {
    return Err("SQLite required")
  }
  guard read_env("ACTQL_TEST_NATIVE_SQLITE_ROOT") is Some(parent) else {
    return Err("private SQLite root required")
  }
  Ok((sqlite_path, parent, parent + "/" + name))
}

///|
test "cleanup storage configuration requires SQLite before reading the root" {
  let reads : Array[String] = []
  let configuration = cleanup_storage_configuration("missing-library", read_env=key => {
    reads.push(key)
    if key == "ACTQL_TEST_NATIVE_SQLITE_ROOT" {
      Some("/owned/sqlite")
    } else {
      None
    }
  })
  assert_eq(configuration, Err("SQLite required"))
  assert_eq(reads, ["ACTQL_TEST_NATIVE_SQLITE_LIBRARY"])
}

///|
test "cleanup storage configuration requires the invocation's private root" {
  let reads : Array[String] = []
  let configuration = cleanup_storage_configuration("missing-root", read_env=key => {
    reads.push(key)
    if key == "ACTQL_TEST_NATIVE_SQLITE_LIBRARY" {
      Some("libsqlite3.so.0")
    } else {
      None
    }
  })
  assert_eq(configuration, Err("private SQLite root required"))
  assert_eq(reads, [
    "ACTQL_TEST_NATIVE_SQLITE_LIBRARY", "ACTQL_TEST_NATIVE_SQLITE_ROOT",
  ])
}

///|
test "cleanup storage configuration keeps each case under the supplied root" {
  let read_env = key => {
    match key {
      "ACTQL_TEST_NATIVE_SQLITE_LIBRARY" => Some("libsqlite3.so.0")
      "ACTQL_TEST_NATIVE_SQLITE_ROOT" => Some("/owned/sqlite")
      _ => None
    }
  }
  let first = cleanup_storage_configuration("first-case", read_env~).unwrap()
  let second = cleanup_storage_configuration("second-case", read_env~).unwrap()
  assert_eq(
    first,
    ("libsqlite3.so.0", "/owned/sqlite", "/owned/sqlite/first-case"),
  )
  assert_eq(
    second,
    ("libsqlite3.so.0", "/owned/sqlite", "/owned/sqlite/second-case"),
  )
  assert_eq(
    cleanup_storage_configuration("first-case", read_env~).unwrap(),
    first,
  )
}

///|
test "cleanup storage configuration preserves present empty values" {
  assert_eq(
    cleanup_storage_configuration("empty-values", read_env=_ => Some("")),
    Ok(("", "", "/empty-values")),
  )
}
