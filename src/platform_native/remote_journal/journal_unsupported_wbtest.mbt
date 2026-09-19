///|
test "non-native targets reject the native remote journal" {
  ignore(@env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY"))
  let site = @site.create_site(
    "unsupported-site", 0, "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    1, 1, 1L, 1L,
  ).unwrap()
  ignore(site)
  guard @sqlite.load_library("unavailable") is Err(_) else {
    fail("non-native target loaded SQLite")
  }
}
