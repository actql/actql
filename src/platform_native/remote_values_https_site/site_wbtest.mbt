///|
test "native Values Site URL segment preserves exact route identity" {
  assert_eq(encoded_site_key("tenant/site #1"), Some("tenant%2Fsite%20%231"))
  assert_eq(encoded_site_key("site-._~!'()*"), Some("site-._~!'()*"))
  assert_true(encoded_site_key("") is None)
}
