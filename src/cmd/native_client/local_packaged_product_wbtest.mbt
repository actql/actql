///|
// Pure metadata/caller cases. These definitions are compiler-only until the
// fixed formal Native artifact is executed; no synthetic library is loaded.
test "packaged Local context rejects unknown fields and unbounded roots" {
  let good = "{\"root\":\"/product\",\"sourceSha\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"platform\":\"darwin-arm64\",\"manifestSha256\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"}"
  assert_eq(local_product_context(good).0, "/product")
  for
    wire in [
      good.replace(old="/product", new="relative"),
      good.replace(old="/product", new="/product/../outside"),
      good.replace(old="{", new="{\"authority\":true,"),
    ] {
    let rejected = try {
      ignore(local_product_context(wire))
      false
    } catch {
      ClientStop(_) => true
    }
    assert_true(rejected)
  }
}

///|
test "packaged selection keeps unsupported Local controls unavailable" {
  for command in ["adopt", "check", "aql", "read", "lookup-submission"] {
    assert_true(local_product_operation(command))
  }
  for command in ["approve", "run", "step", "pause", "reconcile"] {
    assert_false(local_product_operation(command))
  }
  let parsed = command().parse(argv=["--mode", "local", "adopt"])
  assert_true(parsed.sources.get("config-root") is Some(@argparse.Default))
  assert_true(optional(parsed, "config-file") is None)
  let explicit = command().parse(argv=[
    "--mode", "local", "--config-root", "/private", "adopt",
  ])
  assert_true(explicit.sources.get("config-root") is Some(@argparse.Argv))
}

///|
test "packaged check preserves distinct document and configuration roots" {
  let selected = command().parse(argv=[
    "--mode", "local", "--input-root", "/documents", "check", "--format", "sql",
    "--program-file", "query.sql",
  ])
  assert_eq(
    local_document_root(selected, "/private/.actql-local"),
    "/documents",
  )
  assert_eq(
    required(selected.subcommand.unwrap().1, "program-file"),
    "query.sql",
  )
  let legacy = command().parse(argv=[
    "--mode", "local", "--config-root", "/private", "--config-file", "config.json",
    "check", "--format", "sql", "--program-file", "query.sql",
  ])
  assert_eq(local_document_root(legacy, "/private"), "/private")
}
