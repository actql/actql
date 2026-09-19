///|
test "native HTTPS client is explicit on unsupported targets" {
  guard load_library("libcurl") is Err(UnsupportedTarget) else {
    fail("unsupported HTTPS client was accepted")
  }
}
