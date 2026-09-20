///|
test "native bundle adapter is not claimed by portable targets" {
  ignore(@env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY"))
}
