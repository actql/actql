///|
test "Catalog headers are closed and required even without consumers" {
  let original = catalog_fixture("example", [])
  for
    body in [
      original.replace(old="\"commands\":[],", new=""),
      original.replace(old="\"commands\":[]", new="\"commands\":null"),
      original.replace(old="\"contracts\":[]", new="\"contracts\":{}"),
      original.replace(old="\"source_views\":[]", new="\"source_views\":null"),
      original.replace(old="\"schema\":", new="\"extra\":null,\"schema\":"),
      original.replace(old="\"example\"", new="\"\""),
      original.replace(old="\"external-7\"", new="null"),
      original.replace(old="actql.connector_catalog/0.1", new="unknown"),
    ] {
    assert_true(
      check_catalog_contents(catalog_environment([body], []), caps()) is Err(_),
    )
  }
}

///|
test "Catalog integrity defers SourceView selector uniqueness to resource resolution" {
  let a = view_fixture("example", "main")
  let b = view_fixture("example", "main", version="external-2")
  // Prefixes are identical through contract_cid, so lexical order here is
  // self-CID order. No repair is performed by the product reader.
  let views = [a, b]
  views.sort_by((a, b) => a.compare(b))
  let registry = catalog_environment(
    [catalog_fixture("example", [], views~)],
    [],
    views~,
  )
  assert_true(check_catalog_contents(registry, caps()) is Ok(_))
}
