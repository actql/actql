///|
fn cid(unit : String) -> String {
  "sha256:" + unit.repeat(64)
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
