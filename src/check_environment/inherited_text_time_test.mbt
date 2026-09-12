///|
test "inherited text-time pins resolve a closed graph with explicit leaves" {
  let root = inherited_text_time_contract(
    "sha256:2d41f38bd3bf8217d9bc394b1ca2ed9dfe6695b0088cd6a489328dabdee61dcc",
  ).unwrap()
  assert_eq(root, Base)
  let pending = [root]
  let seen : Array[InheritedTextTimeContract] = []
  let mut edges = 0
  while pending.pop() is Some(body) {
    if seen.contains(body) {
      continue
    }
    seen.push(body)
    assert_eq(
      inherited_text_time_contract(inherited_text_time_cid(body)),
      Some(body),
    )
    let count = inherited_text_time_dependency_count(body)
    for index in 0..<count {
      let edge = inherited_text_time_dependency_at(body, index).unwrap()
      assert_true(edge.pointer.has_prefix("/"))
      pending.push(edge.target)
      edges += 1
    }
    for invalid in [-2147483648, -1, count, 2147483647] {
      assert_true(inherited_text_time_dependency_at(body, invalid) is None)
    }
  }
  assert_eq(seen.length(), 11)
  assert_eq(edges, 12)
  assert_eq(inherited_text_time_dependency_count(UnicodeData), 0)
  assert_eq(inherited_text_time_dependency_count(RegexAst), 0)
}

///|
test "repeated Unicode dependencies retain their distinct source roles" {
  let nfkc = inherited_text_time_dependency_at(Base, 6).unwrap()
  let fold = inherited_text_time_dependency_at(Base, 7).unwrap()
  assert_eq(nfkc.pointer, "/bound_derivation/nfkc/unicode_data_cid")
  assert_eq(fold.pointer, "/bound_derivation/case_fold/unicode_data_cid")
  assert_eq(nfkc.target, fold.target)
  assert_eq(nfkc.target, UnicodeData)
  let descriptor = inherited_text_time_dependency_at(Base, 5).unwrap()
  assert_eq(descriptor.target, UnicodeSemantics)
  assert_true(
    inherited_text_time_cid(descriptor.target) !=
    inherited_text_time_cid(nfkc.target),
  )
  assert_eq(
    inherited_text_time_dependency_at(UnicodeSemantics, 0).unwrap().target,
    UnicodeData,
  )
}

///|
test "unknown contract pins are not interpreted as dependency-free leaves" {
  for
    cid in [
      "", "sha256:4a84a6d133b6282a5d50ba743ef8cab3fc87d4ccc91612663c5fc0d02f705dd5",
      "sha256:2D41f38bd3bf8217d9bc394b1ca2ed9dfe6695b0088cd6a489328dabdee61dcc",
      "sha256:399d4593f8212a2239a0a3e3ca552653ad711010a180207f967cf546012fc1cb",
    ] {
    assert_true(inherited_text_time_contract(cid) is None)
  }
}
