///|
test "native remote environment is absent on unsupported targets" {
  ignore(@env.get_env_var("ACTQL_TEST_NATIVE_HTTP_LIBRARY"))
  ignore(@sqlite.load_library(""))
  ignore(@site.create_site("", 0, "", 0, 0, 0L, 0L))
}
