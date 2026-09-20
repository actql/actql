///|
test "Site journal binding changes with generation and runtime authority" {
  let revision_a = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  let revision_b = "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  let first = @site.create_site("site-a", 1, revision_a, 1, 1, 1024L, 1024L).unwrap()
  let journal = create_site_dispatch_journal(first, "actql-remote-site/0.1").unwrap()
  assert_eq(
    site_dispatch_binding_json(journal).unwrap(),
    "{\"protocol_version\":\"actql-remote-site/0.1\"," +
    "\"runtime_revision\":\"" +
    revision_a +
    "\",\"site_generation\":1,\"site_key\":\"site-a\"," +
    "\"version\":\"actql-remote-site-binding/0.1\"}",
  )
  let replacement = @site.create_site(
    "site-a", 2, revision_b, 1, 1, 1024L, 1024L,
  ).unwrap()
  let restart = prepare_site_generation_restart(journal, replacement).unwrap()
  assert_eq(
    site_restart_next_binding_json(restart).unwrap(),
    "{\"protocol_version\":\"actql-remote-site/0.1\"," +
    "\"runtime_revision\":\"" +
    revision_b +
    "\",\"site_generation\":2,\"site_key\":\"site-a\"," +
    "\"version\":\"actql-remote-site-binding/0.1\"}",
  )
}
