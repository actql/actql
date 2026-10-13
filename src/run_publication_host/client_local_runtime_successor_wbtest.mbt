///|
// Authored metadata sizing vector with a synthetic current package. These
// bytes do not claim physical/adoption/HMAC/Account/compatibility acceptance.
let runtime_successor_metadata_fixture = "{\"account_configuration_cid\":\"sha256:fd6d54cc5bcc0a7af2a7919981b4e06604a3380897bcf9ceb51cf764ecdfb396\",\"adoption_cid\":\"sha256:78e003c0887555b1dd839eae9f4949b023cd5d8f3549ed1154155a9eed49df01\",\"authority_scope_cid\":\"sha256:a62e64584505a511f3186d8fbaa4edd56bf27c0f7fa7ae68ce4eb25298cadc4c\",\"current_package_identity_wire\":\"{\\\"launcher_inventory_sha256\\\":\\\"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\\\",\\\"native_binary_sha256\\\":\\\"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\\\",\\\"platform\\\":\\\"darwin-arm64\\\",\\\"platform_inventory_sha256\\\":\\\"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\\\",\\\"runtime_manifest_sha256\\\":\\\"deaca430de7bccaf15d90a7cc23ae3dc9caa8cd8b8ec36f498b674b812bb021d\\\",\\\"source_sha\\\":\\\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\\\"}\",\"operation_id\":\"explicit-runtime-successor-vector\",\"original_upgrade_cid\":\"sha256:8210e07a447b79db5057fcf92a7d39fa583519a1e52fc631360cf3f8e7a542f9\",\"original_upgrade_packet_sha256\":\"2077970d7a158326528463f9418e578a96e024358d5d17dccc2527d80698a2fe\",\"prior_pair_sha256\":\"2b06a81d8266f98c954a76556c3312e3abba0acb8615f19c501ce3df920d367b\",\"prior_runtime_wire\":\"{\\n  \\\"sourceSha\\\": \\\"a3b1643fbedc5180db38b6e08459a188f05b1135\\\",\\n  \\\"platform\\\": \\\"darwin-arm64\\\",\\n  \\\"libraries\\\": [\\n    {\\n      \\\"role\\\": \\\"sqlite\\\",\\n      \\\"path\\\": \\\"lib/libsqlite3.dylib\\\",\\n      \\\"bytes\\\": 1268496,\\n      \\\"sha256\\\": \\\"c7406a3ef688914647c2bf05b6ac86282981c3484e18745b97e92e3c08939f1d\\\",\\n      \\\"license\\\": \\\"licenses/sqlite3.h\\\",\\n      \\\"dependencies\\\": [\\n        \\\"/usr/lib/libz.1.dylib\\\",\\n        \\\"/usr/lib/libSystem.B.dylib\\\"\\n      ],\\n      \\\"abi\\\": {\\n        \\\"minimumMacOS\\\": \\\"26.0\\\"\\n      }\\n    },\\n    {\\n      \\\"role\\\": \\\"crypto\\\",\\n      \\\"path\\\": \\\"lib/libcrypto.3.dylib\\\",\\n      \\\"bytes\\\": 4843248,\\n      \\\"sha256\\\": \\\"125a8de6bf7ab462a0f2f8f53358a9560555e94cd3331d4a6d41a95f1536b0a1\\\",\\n      \\\"license\\\": \\\"licenses/openssl-LICENSE.txt\\\",\\n      \\\"dependencies\\\": [\\n        \\\"/usr/lib/libSystem.B.dylib\\\"\\n      ],\\n      \\\"abi\\\": {\\n        \\\"minimumMacOS\\\": \\\"26.0\\\"\\n      }\\n    }\\n  ],\\n  \\\"assets\\\": [\\n    {\\n      \\\"role\\\": \\\"environment\\\",\\n      \\\"path\\\": \\\"data/environment.json\\\",\\n      \\\"bytes\\\": 919,\\n      \\\"sha256\\\": \\\"e79109d982ad96e84d19d3d91b71cbec6f38511f94e80e62b5ad4573b5d7173c\\\"\\n    },\\n    {\\n      \\\"role\\\": \\\"registry\\\",\\n      \\\"path\\\": \\\"data/registry.json\\\",\\n      \\\"bytes\\\": 5585,\\n      \\\"sha256\\\": \\\"6ae574874934fcda0f8b0d7bf5f26b085a6c25fad25f5be319f4430ba9e66633\\\"\\n    },\\n    {\\n      \\\"role\\\": \\\"values\\\",\\n      \\\"path\\\": \\\"data/values.json\\\",\\n      \\\"bytes\\\": 9241,\\n      \\\"sha256\\\": \\\"8ff4a4f20578297eff9f7c40df8d32f4dd1e6d5ccbc9a24156b6ab533c292b53\\\"\\n    },\\n    {\\n      \\\"role\\\": \\\"fragment\\\",\\n      \\\"path\\\": \\\"data/fragment.json\\\",\\n      \\\"bytes\\\": 1621,\\n      \\\"sha256\\\": \\\"3da36b6da829dce7db05c15bbe00baa8abe3884a8b33e348c31d6ff55a1abacd\\\"\\n    },\\n    {\\n      \\\"role\\\": \\\"ordered\\\",\\n      \\\"path\\\": \\\"data/ordered.json\\\",\\n      \\\"bytes\\\": 21853,\\n      \\\"sha256\\\": \\\"dd5c69871006b36152fa87ffc5cbb21fb045d4ad29ef85e3a28e2b6508944343\\\"\\n    },\\n    {\\n      \\\"role\\\": \\\"result-policy\\\",\\n      \\\"path\\\": \\\"data/result-policy.json\\\",\\n      \\\"bytes\\\": 160,\\n      \\\"sha256\\\": \\\"470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563\\\"\\n    }\\n  ],\\n  \\\"licenses\\\": [\\n    {\\n      \\\"path\\\": \\\"licenses/sqlite3.h\\\",\\n      \\\"bytes\\\": 671786,\\n      \\\"sha256\\\": \\\"6c8b9f648f36c84b0eeb3239b1e6f32b459d2c859d905ba5d59153c3569e6562\\\"\\n    },\\n    {\\n      \\\"path\\\": \\\"licenses/openssl-LICENSE.txt\\\",\\n      \\\"bytes\\\": 10175,\\n      \\\"sha256\\\": \\\"7d5450cb2d142651b8afa315b5f238efc805dad827d91ba367d8516bc9d49e7a\\\"\\n    }\\n  ]\\n}\\n\",\"successor_runtime_pair_wire\":\"{\\\"current_manifest_sha256\\\":\\\"deaca430de7bccaf15d90a7cc23ae3dc9caa8cd8b8ec36f498b674b812bb021d\\\",\\\"current_source_sha\\\":\\\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\\\",\\\"evidence_cid\\\":\\\"sha256:8bdf483589d04809f0e2e198708adc8335b38179f332e58d25a8a09497633a22\\\",\\\"original_manifest_sha256\\\":\\\"80731853b15f4d600ef391b3778c734bc40bfb6caed246c0c145916b419e49bd\\\",\\\"original_source_sha\\\":\\\"109564ef9a4f8241096292843b875d4c81fbb6f3\\\",\\\"platform\\\":\\\"darwin-arm64\\\",\\\"profile\\\":\\\"primitive-scalar-values\\\",\\\"version\\\":\\\"actql-native-local-scalar-runtime-pair/0.1\\\"}\",\"version\":\"actql-local-runtime-successor/0.1\"}"

///|
fn successor_metadata_fixture_create(
  fields : Array[String],
) -> Result[
  ClientLocalRuntimeSuccessorMetadata,
  ClientLocalRuntimeSuccessorIssue,
] {
  client_local_runtime_successor_metadata(
    fields[0],
    fields[1],
    fields[2],
    fields[3],
    fields[4],
    fields[5],
    fields[6],
    fields[7],
    fields[8],
    fields[9],
  )
}

///|
fn successor_metadata_fixture_fields() -> Array[String] {
  client_local_original_record_fields(
    @utf8.encode(runtime_successor_metadata_fixture),
    local_runtime_successor_keys(),
  ).unwrap()
}

///|
test "runtime successor metadata exact independent bytes and content identity" {
  let fields = successor_metadata_fixture_fields()
  let value = successor_metadata_fixture_create(fields).unwrap()
  assert_eq(@utf8.decode(value.body), runtime_successor_metadata_fixture)
  assert_eq(value.body.length(), 4344)
  assert_eq(
    client_local_runtime_successor_metadata_cid(value),
    "sha256:e4a1b2d89f094acc5680f3f88fd04224022d8682b9b2dffbe7b4eda3d0e2616b",
  )
  let saved = read_client_local_runtime_successor_metadata(value.body).unwrap()
  assert_eq(client_local_runtime_successor_metadata_body(saved), value.body)
  for index, key in local_runtime_successor_keys() {
    assert_eq(
      client_local_runtime_successor_metadata_field(saved, key),
      Some(fields[index]),
    )
  }
  assert_eq(client_local_runtime_successor_metadata_field(saved, "grant"), None)
}

///|
test "runtime successor metadata closed keys canonical bytes null duplicates" {
  let fields = successor_metadata_fixture_fields()
  let keys = local_runtime_successor_keys()
  for omitted in 0..<keys.length() {
    let pairs = keys.mapi((index, key) => (key, fields[index]))
    ignore(pairs.remove(omitted))
    assert_true(
      read_client_local_runtime_successor_metadata(
        client_local_original_record_body(pairs).unwrap(),
      )
      is Err(InvalidOriginal),
    )
  }
  for
    wire in [
      runtime_successor_metadata_fixture + " ",
      runtime_successor_metadata_fixture.replace(
        old="\"operation_id\":\"explicit-runtime-successor-vector\"",
        new="\"operation_id\":null",
      ),
      runtime_successor_metadata_fixture.replace(
        old="\"operation_id\":\"explicit-runtime-successor-vector\"",
        new="\"operation_id\":\"a\",\"operation_id\":\"b\"",
      ),
      runtime_successor_metadata_fixture.replace(
        old="\"version\":\"actql-local-runtime-successor/0.1\"",
        new="\"version\":\"actql-local-runtime-policy-upgrade/0.1\"",
      ),
      runtime_successor_metadata_fixture.replace(
        old="\"version\":",
        new="\"unknown\":\"copied\",\"version\":",
      ),
    ] {
    assert_true(
      read_client_local_runtime_successor_metadata(@utf8.encode(wire))
      is Err(InvalidOriginal),
    )
  }
}

///|
test "runtime successor metadata rejects changed syntax without normalizing identifiers" {
  let original = successor_metadata_fixture_fields()
  for index in [0, 1, 2, 5, 6, 7] {
    let fields = original.copy()
    fields[index] = "copied"
    assert_true(
      successor_metadata_fixture_create(fields) is Err(InvalidOriginal),
    )
  }
  for invalid in ["", String::make(129, 'x'), "a\u{0000}b"] {
    let fields = original.copy()
    fields[4] = invalid
    assert_true(
      successor_metadata_fixture_create(fields) is Err(InvalidOriginal),
    )
  }
  for index in [3, 8, 9] {
    let fields = original.copy()
    fields[index] = ""
    assert_true(
      successor_metadata_fixture_create(fields) is Err(InvalidOriginal),
    )
    fields[index] = String::make(4097, 'x')
    assert_true(
      successor_metadata_fixture_create(fields) is Err(InvalidOriginal),
    )
  }
  // Another well-formed CID is metadata, not a proof of matching original
  // custody. Native must reject it against independently authenticated rows.
  let changed = original.copy()
  changed[0] = "sha256:" + String::make(64, 'a')
  assert_true(successor_metadata_fixture_create(changed) is Ok(_))
  assert_true(changed[0] != original[0])
}

///|
test "runtime successor metadata bounded escape and invalid utf16" {
  let fields = successor_metadata_fixture_fields()
  fields[4] = String::make(128, (1).unsafe_to_char())
  let escaped = successor_metadata_fixture_create(fields).unwrap()
  assert_eq(escaped.body.length(), 5079)
  assert_true(
    read_client_local_runtime_successor_metadata(escaped.body) is Ok(_),
  )
  fields[4] = String::from_array([(0xd800).unsafe_to_char()])
  assert_true(successor_metadata_fixture_create(fields) is Err(Encoding))
  fields[4] = "bounded"
  fields[3] = String::make(2000, 'x')
  fields[8] = String::make(2000, 'x')
  fields[9] = String::make(2000, 'x')
  assert_true(
    successor_metadata_fixture_create(fields) is Err(CapacityExceeded),
  )
  assert_true(
    read_client_local_runtime_successor_metadata(
      @utf8.encode(String::make(5633, 'x')),
    )
    is Err(CapacityExceeded),
  )
}
