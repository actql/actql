///|
fn resident_compute_event_name(
  event : @resident.ResidentSourceComputeEvent,
) -> String {
  match event {
    AcquisitionEntered => "acquisition-entered"
    ProducerCaptured => "producer-captured"
    ConsumerEntered(task) => "consumer-entered-\{task}"
    ConsumerCompleted(task) => "consumer-completed-\{task}"
    CleanupPending => "cleanup-pending"
    CleanupCompleted => "cleanup-completed"
  }
}

///|
test "resident producer capture evidence failure returns the original retryable cleanup owner" {
  guard resident_compute_prerequisites() is Some((library_path, root_path)) else {
    return
  }
  let library = @duckdb.load_library(library_path).unwrap()
  let name = "source-capture-evidence-" + @env.now().to_string() + ".duckdb"
  let path = root_path + "/" + name
  let root = @filesystem.open_root(root_path).unwrap()
  resident_compute_database(library, path)
  let events : Array[String] = []
  let (_, cleanup) = @resident.open_resident_source_compute(
    resident_compute_prepared(),
    resident_compute_configuration(library, path),
    name,
    observe=event => {
      events.push(resident_compute_event_name(event))
      !(event is ProducerCaptured)
    },
  ).unwrap_err()
  assert_eq(events, ["acquisition-entered", "producer-captured"])
  assert_true(
    @output.native_remote_standard_input_failure_cleanup_pending(cleanup),
  )
  assert_true(
    @output.retry_native_remote_standard_input_failure_cleanup(cleanup),
  )
  assert_false(
    @output.native_remote_standard_input_failure_cleanup_pending(cleanup),
  )
  let count = events.length()
  assert_true(
    @output.retry_native_remote_standard_input_failure_cleanup(cleanup),
  )
  assert_eq(events.length(), count)
  assert_eq(events[count - 1], "cleanup-completed")
  resident_compute_reclaim(root, name)
}

///|
test "resident Source Compute observations count actual owner entries without reacquisition" {
  guard resident_compute_prerequisites() is Some((library_path, root_path)) else {
    return
  }
  let library = @duckdb.load_library(library_path).unwrap()
  let name = "source-observed-" + @env.now().to_string() + ".duckdb"
  let path = root_path + "/" + name
  let root = @filesystem.open_root(root_path).unwrap()
  resident_compute_database(library, path)
  let events : Array[String] = []
  let owner = @resident.open_resident_source_compute(
    resident_compute_prepared(),
    resident_compute_configuration(library, path),
    name,
    observe=event => {
      events.push(resident_compute_event_name(event))
      true
    },
  ).unwrap()
  assert_eq(events, ["acquisition-entered", "producer-captured"])
  assert_true(owner.execute_task(0) is Err(Unavailable))
  resident_compute_reclaim(root, name)
  resident_compute_execute(owner) |> ignore
  assert_true(owner.execute_task(1) is Err(Unavailable))
  assert_eq(events, [
    "acquisition-entered", "producer-captured", "consumer-entered-1", "consumer-completed-1",
  ])
  let output = owner.prepare_result_export(resident_compute_limits()).unwrap()
  assert_false(owner.close())
  assert_true(owner.usage().held_bytes > 0L)
  assert_eq(events[events.length() - 1], "cleanup-pending")
  output.cancel()
  assert_true(owner.close())
  let count = events.length()
  assert_true(owner.close())
  assert_eq(events.length(), count)
  assert_eq(events[count - 1], "cleanup-completed")
  assert_eq(owner.usage().held_bytes, 0L)
  assert_eq(owner.usage().attempts, 2)
}

///|
test "resident consumer entry evidence failure retains Source cleanup without consumer work" {
  guard resident_compute_prerequisites() is Some((library_path, root_path)) else {
    return
  }
  let library = @duckdb.load_library(library_path).unwrap()
  let name = "source-entry-refused-" + @env.now().to_string() + ".duckdb"
  let path = root_path + "/" + name
  let root = @filesystem.open_root(root_path).unwrap()
  resident_compute_database(library, path)
  let events : Array[String] = []
  let owner = @resident.open_resident_source_compute(
    resident_compute_prepared(),
    resident_compute_configuration(library, path),
    name,
    observe=event => {
      events.push(resident_compute_event_name(event))
      !(event is ConsumerEntered(_))
    },
  ).unwrap()
  assert_true(
    owner.execute_task(1) is Err(ObservationUnrecorded(ConsumerEntered(1))),
  )
  assert_true(owner.execute_task(1) is Err(Unavailable))
  assert_eq(events, [
    "acquisition-entered", "producer-captured", "consumer-entered-1",
  ])
  assert_eq(owner.usage().attempts, 1)
  assert_true(owner.usage().held_bytes > 0L)
  assert_true(owner.usage().reserved_execution_bytes > 0L)
  assert_true(owner.close())
  assert_true(owner.close())
  assert_eq(owner.usage().attempts, 1)
  assert_eq(owner.usage().held_bytes, 0L)
  assert_eq(owner.usage().reserved_execution_bytes, 0L)
  resident_compute_reclaim(root, name)
}

///|
test "resident consumer completion evidence failure never repeats confirmed Compute" {
  guard resident_compute_prerequisites() is Some((library_path, root_path)) else {
    return
  }
  let library = @duckdb.load_library(library_path).unwrap()
  let name = "source-completion-lost-" + @env.now().to_string() + ".duckdb"
  let path = root_path + "/" + name
  let root = @filesystem.open_root(root_path).unwrap()
  resident_compute_database(library, path)
  let events : Array[String] = []
  let owner = @resident.open_resident_source_compute(
    resident_compute_prepared(),
    resident_compute_configuration(library, path),
    name,
    observe=event => {
      events.push(resident_compute_event_name(event))
      !(event is ConsumerCompleted(_))
    },
  ).unwrap()
  assert_true(
    owner.execute_task(1) is Err(ObservationUnrecorded(ConsumerCompleted(1))),
  )
  let attempts = owner.usage().attempts
  assert_eq(attempts, 2)
  assert_true(owner.execute_task(1) is Err(Unavailable))
  assert_eq(owner.usage().attempts, attempts)
  assert_true(owner.usage().held_bytes > 0L)
  assert_true(owner.close())
  assert_true(owner.close())
  assert_eq(owner.usage().attempts, attempts)
  assert_eq(events, [
    "acquisition-entered", "producer-captured", "consumer-entered-1", "consumer-completed-1",
    "cleanup-completed",
  ])
  resident_compute_reclaim(root, name)
}

///|
test "resident cleanup evidence retry preserves the same owner after physical release" {
  guard resident_compute_prerequisites() is Some((library_path, root_path)) else {
    return
  }
  let library = @duckdb.load_library(library_path).unwrap()
  let name = "source-cleanup-evidence-" + @env.now().to_string() + ".duckdb"
  let path = root_path + "/" + name
  let root = @filesystem.open_root(root_path).unwrap()
  resident_compute_database(library, path)
  let accepted : Array[String] = []
  let completion_calls = Ref(0)
  let owner = @resident.open_resident_source_compute(
    resident_compute_prepared(),
    resident_compute_configuration(library, path),
    name,
    observe=event => {
      if event is CleanupCompleted {
        completion_calls.val += 1
        if completion_calls.val == 1 {
          return false
        }
      }
      accepted.push(resident_compute_event_name(event))
      true
    },
  ).unwrap()
  resident_compute_execute(owner) |> ignore
  let attempts = owner.usage().attempts
  assert_false(owner.close())
  assert_eq(owner.usage().held_bytes, 0L)
  assert_eq(owner.usage().reserved_execution_bytes, 0L)
  assert_true(owner.execute_task(1) is Err(Unavailable))
  assert_true(owner.close())
  assert_true(owner.close())
  assert_eq(completion_calls.val, 2)
  assert_eq(owner.usage().attempts, attempts)
  assert_eq(accepted, [
    "acquisition-entered", "producer-captured", "consumer-entered-1", "consumer-completed-1",
    "cleanup-completed",
  ])
  resident_compute_reclaim(root, name)
}
