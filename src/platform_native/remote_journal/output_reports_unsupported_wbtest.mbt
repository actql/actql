///|
test "output report fixtures keep the physical manifest admission available" {
  let cid = fn(fill : String) { "sha256:" + fill.repeat(64) }
  ignore(
    @manifest.admit(
      "actql-managed-physical-manifest/0.1",
      cid("1"),
      cid("2"),
      cid("3"),
      2,
      [cid("d")],
      [12L],
      [2],
      4,
      4096,
      12L,
    ),
  )
}
