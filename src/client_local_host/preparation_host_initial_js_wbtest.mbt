///|
test "Host initial carrier keeps one zero-byte identity until its selected Source successor retires" {
  let input = [1]
  let initial = request_parent_fixture(input)
  let owner = begin_host_initialization_preparation(
    initial,
    input,
    client_local_resource_policy(),
  ).unwrap()
  let (original, capacity) = take_host_initialization_preparation_capacity(
    owner,
  ).unwrap()
  assert_true(physical_equal(original, input))
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input).unwrap(),
    (0L, 0L),
  )
  assert_false(@resources.preparation_capacity_reservation_retired(capacity))
  assert_true(close_host_initialization_preparation(owner) is Err(WrongPhase))
  let next : @resources.PreparationCapacity[Array[Int], Array[String]] = @resources.continue_preparation_capacity(
    capacity, input,
  ).unwrap()
  @resources.reserve_working_preparation_phase(next, input, 100L, 20L).unwrap()
  let body = ["source"]
  @resources.complete_preparation_capacity(next, input, body, 80L, 0L).unwrap()
  // Two Requests borrow this same installation material, without reload or Run.
  let first = @resources.borrow_preparation_capacity(next).unwrap()
  let second = @resources.borrow_preparation_capacity(next).unwrap()
  assert_true(
    physical_equal(
      @resources.preparation_capacity_borrow_value(first).unwrap(),
      body,
    ),
  )
  assert_true(
    physical_equal(
      @resources.preparation_capacity_borrow_value(second).unwrap(),
      body,
    ),
  )
  assert_false(@resources.retire_preparation_capacity(next).unwrap())
  assert_true(close_host_initialization_preparation(owner) is Err(WrongPhase))
  assert_false(@resources.return_preparation_capacity_borrow(first).unwrap())
  assert_true(close_host_initialization_preparation(owner) is Err(WrongPhase))
  assert_true(@resources.return_preparation_capacity_borrow(second).unwrap())
  assert_true(@resources.preparation_capacity_reservation_retired(capacity))
  close_host_initialization_preparation(owner).unwrap()
  close_host_initialization_preparation(owner).unwrap()
  assert_true(owner.input is None && owner.phase == Closed)
}

///|
test "Host initial carrier refuses foreign and repeated selection without losing its original cleanup" {
  let input = [2]
  let initial = request_parent_fixture(input)
  assert_true(
    begin_host_initialization_preparation(
      initial,
      [2],
      client_local_resource_policy(),
    )
    is Err(Initial(_)),
  )
  let owner = begin_host_initialization_preparation(
    initial,
    input,
    client_local_resource_policy(),
  ).unwrap()
  let (original, capacity) = take_host_initialization_preparation_capacity(
    owner,
  ).unwrap()
  assert_true(physical_equal(original, input))
  assert_true(
    take_host_initialization_preparation_capacity(owner) is Err(WrongPhase),
  )
  assert_true(
    @resources.abort_preparation_capacity_after_cleanup(capacity, input).unwrap(),
  )
  close_host_initialization_preparation(owner).unwrap()
  assert_true(
    take_host_initialization_preparation_capacity(owner) is Err(WrongPhase),
  )
}

///|
test "Host initial carrier closes an unselected entrance and retains a cancelled selected constructor" {
  let input = [3]
  let current = Ref(true)
  let initial = request_parent_fixture(input, current=() => current.val)
  let owner = begin_host_initialization_preparation(
    initial,
    input,
    client_local_resource_policy(),
  ).unwrap()
  let (original, capacity) = take_host_initialization_preparation_capacity(
    owner,
  ).unwrap()
  assert_true(physical_equal(original, input))
  current.val = false
  assert_true(
    @resources.reserve_working_preparation_phase(capacity, input, 1L, 0L)
    is Err(Resource(_)),
  )
  assert_false(@resources.preparation_capacity_reservation_retired(capacity))
  assert_true(close_host_initialization_preparation(owner) is Err(WrongPhase))
  assert_true(
    @resources.abort_preparation_capacity_after_cleanup(capacity, input).unwrap(),
  )
  close_host_initialization_preparation(owner).unwrap()
  let another = [4]
  let empty = begin_host_initialization_preparation(
    request_parent_fixture(another),
    another,
    client_local_resource_policy(),
  ).unwrap()
  close_host_initialization_preparation(empty).unwrap()
  assert_true(empty.phase == Closed)
}
