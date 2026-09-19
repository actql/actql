///|
fn cid(unit : String) -> String {
  "sha256:" + unit.repeat(64)
}

///|
test "physical schema and view identities are portable" {
  let admitted = admit_contracts(
    (
      #|[["id","DOUBLE",null,null],["名前","VARCHAR",null,null]]
    ),
    [1, 0],
    4096,
  ).unwrap()
  assert_eq(
    admitted.schema_contract,
    (
      #|{"fields":[["名前","VARCHAR",null,null],["id","DOUBLE",null,null]],"version":"actql-managed-physical-schema/0.1"}
    ),
  )
  assert_eq(
    admitted.schema_contract_cid,
    "sha256:ac51c20f5f452e5963e3f60642c23b73302ec5d3b59d05dceb7d3d13f1a11af3",
  )
  assert_eq(
    admitted.view_contract_cid,
    "sha256:ea76b21bf9e99331b43f5aff2a67ab6b42a3e684df388e2d7dbcae4635aa2869",
  )
}

///|
test "physical contract admission rejects malformed fields and storage order" {
  for
    fields in [
      (
        #|{"id":"DOUBLE"}
      ),
      (
        #|[["id","DOUBLE",null]]
      ),
      (
        #|[["id","DOUBLE",0,null]]
      ),
    ] {
    assert_true(admit_contracts(fields, [0], 4096) is Err(InvalidManifest))
  }
  let fields =
    #|[["id","DOUBLE",null,null],["n","DOUBLE",null,null]]
  assert_true(admit_contracts(fields, [0], 4096) is Err(InvalidManifest))
  assert_true(admit_contracts(fields, [0, 0], 4096) is Err(InvalidManifest))
  assert_true(admit_contracts(fields, [0, 2], 4096) is Err(InvalidManifest))
  assert_true(admit_contracts(fields, [0, 1], 16) is Err(InvalidManifest))
}

///|
test "ordered physical manifest has one portable identity" {
  let admitted = admit(
    "actql-managed-physical-manifest/0.1",
    cid("1"),
    cid("2"),
    cid("3"),
    3,
    [cid("a"), cid("b"), cid("a")],
    [5L, 7L, 5L],
    [1, 1, 1],
    3,
    1024,
    17L,
  ).unwrap()
  assert_eq(admitted.referenced_bytes, 17L)
  assert_eq(admitted.row_count, 3)
  assert_eq(admitted.chunks.length(), 3)
  assert_eq(admitted.chunks[0].cid, admitted.chunks[2].cid)
  assert_eq(
    admitted.manifest_cid,
    "sha256:ec4c075b32341d24cf45aa8b19394c547cb9e3d55a4fb56f5aa8798b12a25e73",
  )
  let reordered = admit(
    "actql-managed-physical-manifest/0.1",
    cid("1"),
    cid("2"),
    cid("3"),
    3,
    [cid("b"), cid("a"), cid("a")],
    [7L, 5L, 5L],
    [1, 1, 1],
    3,
    1024,
    17L,
  ).unwrap()
  assert_not_eq(admitted.manifest_cid, reordered.manifest_cid)
}

///|
test "canonical manifest wire is re-admitted without losing occurrences" {
  let admitted = admit(
    "actql-managed-physical-manifest/0.1",
    cid("1"),
    cid("2"),
    cid("3"),
    3,
    [cid("a"), cid("b"), cid("a")],
    [5L, 7L, 5L],
    [1, 1, 1],
    3,
    1024,
    17L,
  ).unwrap()
  let body = manifest_json(admitted).unwrap()
  let expected = "{\"chunks\":[{\"byte_length\":5,\"cid\":\"" +
    cid("a") +
    "\",\"row_count\":1},{\"byte_length\":7,\"cid\":\"" +
    cid("b") +
    "\",\"row_count\":1},{\"byte_length\":5,\"cid\":\"" +
    cid("a") +
    "\",\"row_count\":1}],\"codec_contract_cid\":\"" +
    cid("3") +
    "\",\"row_count\":3,\"schema_contract_cid\":\"" +
    cid("1") +
    "\",\"version\":\"actql-managed-physical-manifest/0.1\"," +
    "\"view_contract_cid\":\"" +
    cid("2") +
    "\"}"
  assert_eq(body, expected)
  let restored = admit_json(body, admitted.manifest_cid, 3, 1024, 17L).unwrap()
  assert_eq(restored.manifest_cid, admitted.manifest_cid)
  assert_eq(restored.chunks.length(), 3)
  assert_eq(restored.chunks[0].cid, restored.chunks[2].cid)
  assert_true(
    admit_json(body + " ", admitted.manifest_cid, 3, 1024, 17L)
    is Err(InvalidManifest),
  )
  assert_true(admit_json(body, cid("f"), 3, 1024, 17L) is Err(InvalidManifest))
  assert_true(
    admit_json(body, admitted.manifest_cid, 2, 1024, 17L) is Err(ManifestLimit),
  )
}

///|
test "physical manifest rejects limits counts and malformed identities" {
  let base_cids = [cid("a")]
  let base_bytes = [5L]
  let base_rows = [1]
  assert_true(
    admit(
      "actql-managed-physical-manifest/0.2",
      cid("1"),
      cid("2"),
      cid("3"),
      1,
      base_cids,
      base_bytes,
      base_rows,
      1,
      1024,
      5L,
    )
    is Err(InvalidManifest),
  )
  assert_true(
    admit(
      "actql-managed-physical-manifest/0.1",
      cid("1"),
      cid("2"),
      cid("3"),
      1,
      base_cids,
      base_bytes,
      base_rows,
      0,
      1024,
      5L,
    )
    is Err(ManifestLimit),
  )
  assert_true(
    admit(
      "actql-managed-physical-manifest/0.1",
      cid("1"),
      cid("2"),
      cid("3"),
      1,
      base_cids,
      base_bytes,
      base_rows,
      1,
      1024,
      4L,
    )
    is Err(ManifestLimit),
  )
  assert_true(
    admit(
      "actql-managed-physical-manifest/0.1",
      cid("1"),
      cid("2"),
      cid("3"),
      2,
      base_cids,
      base_bytes,
      base_rows,
      1,
      1024,
      5L,
    )
    is Err(RowCountMismatch),
  )
  assert_true(
    admit(
      "actql-managed-physical-manifest/0.1",
      "not-a-cid",
      cid("2"),
      cid("3"),
      1,
      base_cids,
      base_bytes,
      base_rows,
      1,
      1024,
      5L,
    )
    is Err(InvalidManifest),
  )
  assert_true(
    admit(
      "actql-managed-physical-manifest/0.1",
      cid("1"),
      cid("2"),
      cid("3"),
      2,
      [cid("a"), cid("b")],
      [9007199254740991L, 1L],
      [1, 1],
      2,
      1024,
      9007199254740991L,
    )
    is Err(CountOverflow),
  )
}
