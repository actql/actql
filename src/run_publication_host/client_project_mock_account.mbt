///|
/// Project concrete Source, Model and target subjects from the installing
/// Host's bound originals. The caller supplies only admitted declarations
/// and Model tasks, and funds the resulting inventory before allocation.
pub fn[T] client_project_mock_account_subjects(
  selected : Array[T],
  connection : (T) -> String,
  declaration : (T) -> @row_host.RowDeclaration,
  writes : (T) -> Array[@row_host.ProjectMockWriteDeclaration],
  task_slots : Int,
  task_at : (Int) -> String?,
  prepare : (@authorization.AccountConfigurationConstruction) -> Bool,
) -> Result[
  (@authorization.LocalMockAccountSubjects, Array[(String, String)]),
  Unit,
]? {
  guard task_slots >= 0 else { return Some(Err(())) }
  let mut source_slots = 0L
  let mut target_slots = 0L
  for source in selected {
    source_slots += declaration(source).views.length().to_int64()
    target_slots += writes(source).length().to_int64()
  }
  let total_slots = source_slots + target_slots + task_slots.to_int64()
  guard total_slots <= 2147483647L &&
    @shape.reference_array_retained_extent(3L, total_slots) is Some(arrays) else {
    return None
  }
  // Exact backing slots are reserved before the three non-growing Arrays.
  // The Source/target tuples borrow declaration text. The returned subjects,
  // pair and tagged options occupy fixed carriers. Model material projection
  // may also have one transient three-field tuple.
  let retained : @authorization.AccountConfigurationConstructionUnits = {
    record_headers: arrays.record_headers + source_slots + target_slots + 5L,
    reference_slots: arrays.reference_slots +
    2L * (source_slots + target_slots) +
    13L,
    scalar_words: arrays.scalar_words + 3L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  guard prepare({
    retained,
    execution: {
      ..retained,
      record_headers: retained.record_headers + 1L,
      reference_slots: retained.reference_slots + 3L,
    },
  }) else {
    return None
  }
  let sources : Array[(String, String)] = Array(capacity=source_slots.to_int())
  let tasks : Array[String] = Array(capacity=task_slots)
  let targets : Array[(String, String)] = Array(capacity=target_slots.to_int())
  for source in selected {
    for view in declaration(source).views {
      let subject = (connection(source), view.resource)
      if !sources.contains(subject) {
        sources.push(subject)
      }
    }
    let previous_sources = targets.length()
    for write in writes(source) {
      let subject = (connection(source), write.mapping.resource)
      let mut duplicate = false
      for index, existing in targets {
        if existing == subject {
          if index < previous_sources {
            return Some(Err(()))
          }
          duplicate = true
          break
        }
      }
      if !duplicate {
        targets.push(subject)
      }
    }
  }
  for index in 0..<task_slots {
    guard task_at(index) is Some(task) else { return Some(Err(())) }
    if !tasks.contains(task) {
      tasks.push(task)
    }
  }
  let subjects : @authorization.LocalMockAccountSubjects = {
    account_id: "local-cli",
    principal: "local-cli",
    control_connection: "local",
    sources,
    model_tasks: tasks,
    request_target: None,
    update_target: if targets.length() == 1 {
      Some(targets[0])
    } else {
      None
    },
    signing_key_resource: None,
  }
  Some(Ok((subjects, targets)))
}
