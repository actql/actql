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
  for
    command in [
      "adopt", "check", "aql", "run", "read", "lookup-submission", "approve", "reject",
    ] {
    assert_true(local_product_operation(command))
  }
  for command in ["step", "pause", "reconcile"] {
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

///|
test "packaged Local project location is explicit and leaves the HOME default unchanged" {
  let selected = local_product_selected_location(
    Some("/projects/churn-risk/.actql"),
    None,
  )
  assert_eq(selected.parent_path, "/projects/churn-risk")
  assert_eq(selected.directory_name, ".actql")
  let original = local_product_selected_location(None, Some("/home/alice"))
  assert_eq(original.parent_path, "/home/alice")
  assert_eq(original.directory_name, ".actql-local")
  let direct = local_product_selected_location(Some("/.actql"), None)
  assert_eq(direct.parent_path, "/")
  assert_eq(direct.directory_name, ".actql")
}

///|
test "packaged Local project location refuses ambiguous paths without HOME fallback" {
  for
    path in [
      "",
      ".actql",
      "./.actql",
      "/",
      "/project/../.actql",
      "/project/./.actql",
      "/project//.actql",
      "/project/.actql/",
      "/project/\\.actql",
      "/project/\u{0000}",
      "/project/" + "x".repeat(129),
    ] {
    let refused = try {
      ignore(local_product_selected_location(Some(path), Some("/home/alice")))
      false
    } catch {
      ClientStop(message) => message == "InvalidLocalStateDirectory"
    }
    assert_true(refused)
  }
}

///|
test "state selection never substitutes an explicit legacy configuration or Remote connection" {
  let configured = command().parse(argv=[
    "--mode", "local", "--config-file", "config.json", "--state-dir", "/projects/example/.actql",
    "connect",
  ])
  let refused = try {
    ignore(execute_native_local(configured))
    false
  } catch {
    ClientStop(message) => message == "ConflictingLocalInstallationSelection"
  }
  assert_true(refused)
  let remote = command().parse(argv=[
    "--state-dir", "/projects/example/.actql", "connect",
  ])
  let refused = try {
    ignore(execute(remote))
    false
  } catch {
    ClientStop(message) =>
      message == "Local installation directory is unavailable in Remote mode"
  }
  assert_true(refused)
}

///|
test "packaged fresh runtime refuses the retained historical descriptor without a fresh fallback" {
  // Exact retained independent predecessor bytes; no original installation is opened.
  let historical = "{\n  \"sourceSha\": \"109564ef9a4f8241096292843b875d4c81fbb6f3\",\n  \"platform\": \"darwin-arm64\",\n  \"libraries\": [\n    {\n      \"role\": \"sqlite\",\n      \"path\": \"lib/libsqlite3.dylib\",\n      \"bytes\": 1268496,\n      \"sha256\": \"c7406a3ef688914647c2bf05b6ac86282981c3484e18745b97e92e3c08939f1d\",\n      \"license\": \"licenses/sqlite3.h\",\n      \"dependencies\": [\n        \"/usr/lib/libz.1.dylib\",\n        \"/usr/lib/libSystem.B.dylib\"\n      ],\n      \"abi\": {\n        \"minimumMacOS\": \"26.0\"\n      }\n    },\n    {\n      \"role\": \"crypto\",\n      \"path\": \"lib/libcrypto.3.dylib\",\n      \"bytes\": 4843248,\n      \"sha256\": \"125a8de6bf7ab462a0f2f8f53358a9560555e94cd3331d4a6d41a95f1536b0a1\",\n      \"license\": \"licenses/openssl-LICENSE.txt\",\n      \"dependencies\": [\n        \"/usr/lib/libSystem.B.dylib\"\n      ],\n      \"abi\": {\n        \"minimumMacOS\": \"26.0\"\n      }\n    }\n  ],\n  \"assets\": [\n    {\n      \"role\": \"environment\",\n      \"path\": \"data/environment.json\",\n      \"bytes\": 919,\n      \"sha256\": \"e79109d982ad96e84d19d3d91b71cbec6f38511f94e80e62b5ad4573b5d7173c\"\n    },\n    {\n      \"role\": \"registry\",\n      \"path\": \"data/registry.json\",\n      \"bytes\": 5585,\n      \"sha256\": \"a212a9ee1aa4d927591ffc15f25df3218548e9da2f9aa688c6b5733f7348a8aa\"\n    },\n    {\n      \"role\": \"values\",\n      \"path\": \"data/values.json\",\n      \"bytes\": 9241,\n      \"sha256\": \"7f667a6f89689763a2cb8bf8db81318408bd6eb0b3ad399ed5fd218d79ffa529\"\n    },\n    {\n      \"role\": \"fragment\",\n      \"path\": \"data/fragment.json\",\n      \"bytes\": 1621,\n      \"sha256\": \"9d361dde54e27332a350f3f1d2ebfaef8c991b69a935538b45a049a739f775ca\"\n    },\n    {\n      \"role\": \"ordered\",\n      \"path\": \"data/ordered.json\",\n      \"bytes\": 21855,\n      \"sha256\": \"96f0783f537b1856116d818cc5f73c67c27977b48ec6f2f6e2d1eac5b0a04748\"\n    },\n    {\n      \"role\": \"result-policy\",\n      \"path\": \"data/result-policy.json\",\n      \"bytes\": 160,\n      \"sha256\": \"470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563\"\n    }\n  ],\n  \"licenses\": [\n    {\n      \"path\": \"licenses/sqlite3.h\",\n      \"bytes\": 671786,\n      \"sha256\": \"6c8b9f648f36c84b0eeb3239b1e6f32b459d2c859d905ba5d59153c3569e6562\"\n    },\n    {\n      \"path\": \"licenses/openssl-LICENSE.txt\",\n      \"bytes\": 10175,\n      \"sha256\": \"7d5450cb2d142651b8afa315b5f238efc805dad827d91ba367d8516bc9d49e7a\"\n    }\n  ]\n}\n"
  let current = historical.replace(
    old="109564ef9a4f8241096292843b875d4c81fbb6f3",
    new="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  )
  local_product_require_same_runtime_wire(current, current)
  for original in [historical, "{}", ""] {
    let rejected = try {
      local_product_require_same_runtime_wire(original, current)
      false
    } catch {
      ClientStop(issue) => issue == "HistoricalLocalRuntimeUnavailable"
    }
    assert_true(rejected)
  }
}
