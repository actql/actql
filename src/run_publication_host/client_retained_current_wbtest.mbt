///|
test "retained current Site port follows the live Owner without creating a Site" {
  let site = @site.create_site(
    "site-a",
    1,
    retained_input_cid("a"),
    1,
    1,
    1024L,
    1024L,
  ).unwrap()
  let current = install_client_retained_input_current(
    () => site,
    () => "authority-a",
    () => 1L,
    (_, _) => true,
  )
  let delegated = install_client_retained_input_owner_current(
    (key, generation, bundle) => {
      @site.site_key(site) == key &&
      @site.site_generation(site).to_string() == generation &&
      @site.site_binding_current(site, @site.site_generation(site), bundle)
    },
    () => "authority-a",
    () => 1L,
    (_, _) => true,
  )
  for port in [current, delegated] {
    assert_true(
      (port.site_binding_current)("site-a", "1", retained_input_cid("a")),
    )
    assert_false(
      (port.site_binding_current)("site-b", "1", retained_input_cid("a")),
    )
    assert_false(
      (port.site_binding_current)("site-a", "2", retained_input_cid("a")),
    )
    assert_false(
      (port.site_binding_current)("site-a", "1", retained_input_cid("b")),
    )
  }
  let before = @site.site_status(site)
  @site.begin_site_teardown(site)
  for port in [current, delegated] {
    assert_false(
      (port.site_binding_current)("site-a", "1", retained_input_cid("a")),
    )
  }
  // Identity validation reserves neither retention nor execution capacity.
  let after = @site.site_status(site)
  assert_eq(before[7], after[7])
  assert_eq(before[8], after[8])
}
