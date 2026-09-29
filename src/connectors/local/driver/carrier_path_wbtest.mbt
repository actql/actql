///|
test "Carrier path table scans a long task chain once" {
  let own_carrier = Array::make(1025, false)
  own_carrier[1] = true
  let edges : Array[(Int, Int)] = []
  for task in 1..<1024 {
    edges.push((task, task + 1))
  }
  let edge_scans = Ref(0)
  let predecessor_scans = Ref(0)
  let paths = carrier_path_table_from_edges(
    1,
    own_carrier,
    edges.length(),
    index => edges[index],
    Some((edge_scans, predecessor_scans)),
  )
  assert_eq(paths[0], false)
  for task in 1..<1025 {
    assert_eq(paths[task], true)
  }
  assert_eq(edge_scans.val, 1023)
  assert_eq(predecessor_scans.val, 1023)
  for _ in 0..<1024 {
    assert_eq(paths[1024], true)
  }
  assert_eq(edge_scans.val, 1023)
  assert_eq(predecessor_scans.val, 1023)
}

///|
test "Carrier path table preserves branch and merge decisions" {
  let own_carrier = Array::make(8, false)
  own_carrier[0] = true
  own_carrier[1] = true
  let edges : Array[(Int, Int)] = [
    (0, 5),
    (1, 2),
    (1, 3),
    (2, 4),
    (5, 4),
    (5, 6),
    (4, 7),
    (6, 7),
  ]
  let edge_scans = Ref(0)
  let predecessor_scans = Ref(0)
  let paths = carrier_path_table_from_edges(
    1,
    own_carrier,
    edges.length(),
    index => edges[index],
    Some((edge_scans, predecessor_scans)),
  )
  assert_eq(paths, [false, true, true, true, true, false, false, true])
  assert_eq(edge_scans.val, 8)
  assert_eq(predecessor_scans.val, 5)
}
