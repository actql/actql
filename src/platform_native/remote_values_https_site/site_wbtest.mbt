///|
test "native Values Site URL segment preserves exact route identity" {
  assert_eq(
    encoded_site_key("namespace_id/site #1"),
    Some("namespace_id%2Fsite%20%231"),
  )
  assert_eq(encoded_site_key("site-._~!'()*"), Some("site-._~!'()*"))
  assert_true(encoded_site_key("") is None)
}
