///|
test "Program dependency topology is nonrecursive and retains repeated edges" {
  // Synthetic topology, not a claim to construct cyclic SHA-256 preimages.
  let n = 10000
  let successors : Array[Array[Int]] = Array::makei(n, i => {
    if i + 1 < n {
      [i + 1, i + 1]
    } else {
      []
    }
  })
  let indegrees = Array::makei(n, i => if i == 0 { 0 } else { 2 })
  assert_true(program_inputs_acyclic(successors, indegrees.copy()))
  successors[n - 1].push(0)
  indegrees[0] = 1
  assert_false(program_inputs_acyclic(successors, indegrees))
  assert_false(program_inputs_acyclic([[0]], [1]))
  assert_false(program_inputs_acyclic([[], [2], [1]], [0, 1, 1]))
  assert_true(program_inputs_acyclic([], []))
}
