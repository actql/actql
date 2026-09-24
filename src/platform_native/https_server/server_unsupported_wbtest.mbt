///|
test "HTTPS server declines unsupported targets before physical I/O" {
  assert_true(
    open("127.0.0.1", 0, "cert", "key", "ca", 1, 1, 1) is Err(UnsupportedTarget),
  )
}
