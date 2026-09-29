///|
fn dependency_test_id(index : Int) -> String {
  let hash = @sha.text_hex(index.to_string()).unwrap()
  "sha256:" + hash
}

///|
fn dependency_test_ref(index : Int) -> CapturedEffectDependencyReference {
  { kind: "fixture", identity: dependency_test_id(index), }
}

///|
fn dependency_test_node(
  index : Int,
  children : Array[Int],
) -> CapturedEffectDependencyNode {
  {
    kind: "fixture",
    identity: dependency_test_id(index),
    canonical_bytes: 10,
    references: children.map(dependency_test_ref),
  }
}

///|
test "dependency closure rejects missing duplicated foreign and unused nodes" {
  let limits : CapturedEffectDependencyLimits = {
    max_entries: 4,
    max_total_bytes: 100,
    max_depth: 4,
    max_references: 4,
  }
  let roots = [dependency_test_ref(1)]
  let valid = [dependency_test_node(1, [2]), dependency_test_node(2, [])]
  assert_eq(
    validate_captured_effect_dependency_graph(valid, roots, 5, limits),
    Ok(()),
  )
  assert_eq(
    validate_captured_effect_dependency_graph([valid[0]], roots, 5, limits),
    Err(MissingDependency),
  )
  assert_eq(
    validate_captured_effect_dependency_graph(
      [valid[0], valid[1], valid[1]],
      roots,
      5,
      limits,
    ),
    Err(DuplicateIdentity),
  )
  let foreign = { ..valid[1], kind: "foreign", }
  assert_eq(
    validate_captured_effect_dependency_graph(
      [valid[0], foreign],
      roots,
      5,
      limits,
    ),
    Err(WrongDependencyKind),
  )
  assert_eq(
    validate_captured_effect_dependency_graph(
      [..valid, dependency_test_node(3, [])],
      roots,
      5,
      limits,
    ),
    Err(UnusedDependency),
  )
}

///|
test "dependency closure accounts shared depth bytes and edges independently" {
  let nodes = [
    dependency_test_node(1, [4, 2]),
    dependency_test_node(2, [3]),
    dependency_test_node(3, [4]),
    dependency_test_node(4, [5]),
    dependency_test_node(5, []),
  ]
  let limits : CapturedEffectDependencyLimits = {
    max_entries: 5,
    max_total_bytes: 55,
    max_depth: 4,
    max_references: 6,
  }
  let roots = [dependency_test_ref(1)]
  assert_eq(
    validate_captured_effect_dependency_graph(nodes, roots, 5, limits),
    Ok(()),
  )
  assert_eq(
    validate_captured_effect_dependency_graph(nodes, roots, 6, limits),
    Err(ByteLimit),
  )
  assert_eq(
    validate_captured_effect_dependency_graph(nodes, roots, 5, {
      ..limits,
      max_entries: 4,
    }),
    Err(EntryLimit),
  )
  assert_eq(
    validate_captured_effect_dependency_graph(nodes, roots, 5, {
      ..limits,
      max_references: 5,
    }),
    Err(ReferenceLimit),
  )
  // Node 4 was visited through a short path first. Memoization must not hide
  // the longer 1 -> 2 -> 3 -> 4 -> 5 path.
  assert_eq(
    validate_captured_effect_dependency_graph(nodes, roots, 5, {
      ..limits,
      max_depth: 3,
    }),
    Err(DepthLimit),
  )
  assert_eq(
    validate_captured_effect_dependency_graph(
      [dependency_test_node(1, [2]), dependency_test_node(2, [1])],
      roots,
      5,
      limits,
    ),
    Err(DependencyCycle),
  )
}

///|
test "dependency roots also consume the reference budget" {
  let limits : CapturedEffectDependencyLimits = {
    max_entries: 1,
    max_total_bytes: 10,
    max_depth: 1,
    max_references: 0,
  }
  assert_eq(
    validate_captured_effect_dependency_graph(
      [dependency_test_node(1, [])],
      [dependency_test_ref(1)],
      0,
      limits,
    ),
    Err(ReferenceLimit),
  )
  assert_eq(
    validate_captured_effect_dependency_graph(
      [dependency_test_node(1, [])],
      [dependency_test_ref(1)],
      0,
      { ..limits, max_references: 1, },
    ),
    Ok(()),
  )
}
