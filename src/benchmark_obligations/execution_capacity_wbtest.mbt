///|
test "independent DB capacity counts each Compute task without multiplying bytes" {
  let owner = obligation_execution(100L, 80L, 20L, 3)
  assert_eq(obligation_execution_usage(owner).attempts, 1)
  assert_eq(obligation_execution_usage(owner).reserved_execution_bytes, 100L)
  obligation_execution_task_begin(owner)
  assert_true(
    try {
      obligation_execution_task_begin(owner)
      false
    } catch {
      ExecutionCapacityFailure::State => true
      _ => false
    },
  )
  obligation_execution_task_finish(owner)
  assert_eq(obligation_execution_usage(owner).attempts, 1)
  obligation_execution_task_begin(owner)
  assert_eq(obligation_execution_usage(owner).attempts, 2)
  assert_eq(obligation_execution_usage(owner).reserved_execution_bytes, 100L)
  obligation_execution_task_finish(owner)
  obligation_execution_task_begin(owner)
  obligation_execution_task_finish(owner)
  assert_eq(obligation_execution_usage(owner).attempts, 3)
  assert_true(
    try {
      obligation_execution_task_begin(owner)
      false
    } catch {
      ExecutionCapacityFailure::State => true
      _ => false
    },
  )
  obligation_execution_released(owner)
  assert_eq(obligation_execution_usage(owner).reserved_execution_bytes, 0L)
  assert_eq(obligation_execution_usage(owner).attempts, 3)
  assert_true(
    try {
      obligation_execution_released(owner)
      false
    } catch {
      ExecutionCapacityFailure::State => true
      _ => false
    },
  )
}

///|
test "failed Compute task keeps shared capacity until confirmed DB stop" {
  let owner = obligation_execution(100L, 80L, 20L, 3)
  obligation_execution_task_begin(owner)
  obligation_execution_task_finish(owner)
  obligation_execution_task_begin(owner)
  assert_eq(obligation_execution_usage(owner).attempts, 2)
  assert_eq(obligation_execution_usage(owner).reserved_execution_bytes, 100L)
  // The caller closes the native DB before acknowledging this cleanup.
  obligation_execution_released(owner)
  assert_eq(obligation_execution_usage(owner).reserved_execution_bytes, 0L)
  assert_eq(obligation_execution_usage(owner).attempts, 2)
  assert_true(
    try {
      obligation_execution_task_finish(owner)
      false
    } catch {
      ExecutionCapacityFailure::State => true
      _ => false
    },
  )
}

///|
test "independent Compute attempt and capacity limits reject one-short" {
  assert_true(
    try {
      ignore(obligation_execution(99L, 80L, 20L, 3))
      false
    } catch {
      ExecutionCapacityFailure::State => true
      _ => false
    },
  )
  assert_true(
    try {
      ignore(obligation_execution(100L, 80L, 20L, 0))
      false
    } catch {
      ExecutionCapacityFailure::State => true
      _ => false
    },
  )
  let owner = obligation_execution(100L, 80L, 20L, 1)
  obligation_execution_task_begin(owner)
  obligation_execution_task_finish(owner)
  assert_true(
    try {
      obligation_execution_task_begin(owner)
      false
    } catch {
      ExecutionCapacityFailure::State => true
      _ => false
    },
  )
  obligation_execution_released(owner)
}
