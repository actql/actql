///|
priv enum ActionKeyPhase {
  AdmitActionKey
  EmitActionKey
  FinishActionKey
  ActionKeyFinished
}

///|
priv struct ActionKeyAdmission {
  limits : Limits
  mut phase : ActionKeyPhase
  mut admission : @value.JsonAdmission?
  mut writer : @encode.Writer?
  mut emitter : @value.WireEmitCursor?
}

///|
priv enum ActionKeyPoll {
  ActionKeyContinue
  ActionKeyComplete(String)
  ActionKeyFailed
}

///|
fn start_action_key(
  record : @decode.Cursor,
  edge : Bool,
  limits : Limits,
) -> ActionKeyAdmission? {
  let names = if edge {
    ["dst", "id", "key", "props", "src"]
  } else {
    ["id", "key", "props"]
  }
  guard delta_object(record, names) is Some(object) &&
    @decode.lookup(object, "id") is Some(identity) &&
    @value.start_json_admission(identity, limits.value_limits) is Ok(admission) else {
    return None
  }
  Some({
    limits,
    phase: AdmitActionKey,
    admission: Some(admission),
    writer: None,
    emitter: None,
  })
}

///|
/// One existing JSON-admission or wire-emission step, never a synchronous
/// identity-tree walk hidden behind a single reported work unit.
fn advance_action_key(key : ActionKeyAdmission) -> ActionKeyPoll {
  match key.phase {
    AdmitActionKey => {
      guard key.admission is Some(admission) else { return ActionKeyFailed }
      match @value.advance_json_admission(admission) {
        @value.JsonAdmissionContinue => ActionKeyContinue
        @value.JsonAdmissionComplete(checked, _, _) => {
          key.admission = None
          try {
            let writer = @encode.writer(
              key.limits.max_identity_bytes,
              key.limits.max_identity_nodes,
              key.limits.max_identity_depth,
            )
            @encode.begin_array(writer)
            key.writer = Some(writer)
            key.emitter = Some(@value.start_wire_emit(checked.value, writer))
            key.phase = EmitActionKey
            ActionKeyContinue
          } catch {
            _ => ActionKeyFailed
          }
        }
        @value.JsonAdmissionFailed(_) | @value.JsonAdmissionTerminal =>
          ActionKeyFailed
      }
    }
    EmitActionKey => {
      guard key.emitter is Some(emitter) else { return ActionKeyFailed }
      try {
        if @value.advance_wire_emit(emitter) {
          key.emitter = None
          key.phase = FinishActionKey
        }
        ActionKeyContinue
      } catch {
        _ => ActionKeyFailed
      }
    }
    FinishActionKey => {
      guard key.writer is Some(writer) else { return ActionKeyFailed }
      try {
        @encode.end_array(writer)
        let text = @encode.finish(writer)
        key.writer = None
        key.phase = ActionKeyFinished
        ActionKeyComplete(text)
      } catch {
        _ => ActionKeyFailed
      }
    }
    ActionKeyFinished => ActionKeyFailed
  }
}

///|
fn cleanup_action_key(key : ActionKeyAdmission) -> Unit {
  if key.admission is Some(admission) {
    @value.cancel_json_admission(admission)
  }
  if key.emitter is Some(emitter) {
    @value.cancel_wire_emit(emitter)
  }
  key.admission = None
  key.emitter = None
  key.writer = None
  key.phase = ActionKeyFinished
}

///|
priv enum ActionsPhase {
  SelectActions
  SelectAction
  ReadActionKey
  CommitAction
  ActionsFinished
}

///|
priv struct ActionAdmission {
  object : @decode.ObjectView
  edge : Bool
  limits : Limits
  result : ActionSet
  seen : Map[String, Bool]
  mut remaining_text : Int
  mut phase : ActionsPhase
  mut kind : Int
  mut array : @decode.Cursor?
  mut count : Int
  mut index : Int
  mut previous : String?
  mut before : @decode.Cursor?
  mut after : @decode.Cursor?
  mut key : ActionKeyAdmission?
  mut before_key : String?
  mut accepted_key : String?
}

///|
priv enum ActionsPoll {
  ActionsContinue(work~ : Int)
  ActionsComplete(work~ : Int)
  ActionsFailed(work~ : Int)
}

///|
fn action_workspace_slots(limits : Limits) -> Int? {
  // The identity's admitted value, object-name/sort indexes and wire frames
  // coexist with the action arrays. Text has its separate byte ceiling. This
  // is conservative preparation admission, not a total-Graph memory theorem.
  guard checked_add(
      limits.value_limits.max_nodes,
      limits.value_limits.max_nodes,
    )
    is Some(n2) &&
    checked_add(n2, n2) is Some(n4) &&
    checked_add(n4, n4) is Some(n8) &&
    checked_add(limits.value_limits.max_depth, limits.value_limits.max_depth)
    is Some(d2) &&
    checked_add(d2, d2) is Some(d4) &&
    checked_add(n8, d4) is Some(slots) else {
    return None
  }
  checked_add(slots, 64)
}

///|
fn start_actions(
  cursor : @decode.Cursor,
  edge : Bool,
  limits : Limits,
) -> ActionAdmission? {
  guard delta_object(cursor, ["add", "remove", "update"]) is Some(object) else {
    return None
  }
  Some({
    object,
    edge,
    limits,
    result: { add: [], remove: [], update: [], },
    seen: Map([]),
    remaining_text: limits.max_identity_bytes,
    phase: SelectActions,
    kind: 0,
    array: None,
    count: 0,
    index: 0,
    previous: None,
    before: None,
    after: None,
    key: None,
    before_key: None,
    accepted_key: None,
  })
}

///|
fn advance_actions(value : ActionAdmission, quantum : Int) -> ActionsPoll {
  let mut used = 0
  while used < quantum {
    used += 1
    match value.phase {
      SelectActions => {
        if value.kind == 3 {
          value.phase = ActionsFinished
          return ActionsComplete(work=used)
        }
        let name = ["add", "remove", "update"][value.kind]
        guard @decode.lookup(value.object, name) is Some(array) &&
          @decode.array_length(array) is Some(count) else {
          return ActionsFailed(work=used)
        }
        value.array = Some(array)
        value.count = count
        value.index = 0
        value.previous = None
        value.phase = SelectAction
      }
      SelectAction => {
        if value.index == value.count {
          value.array = None
          value.kind += 1
          value.phase = SelectActions
          continue
        }
        guard value.array is Some(array) &&
          @decode.element_at(array, value.index) is Some(item) else {
          return ActionsFailed(work=used)
        }
        value.before_key = None
        value.accepted_key = None
        if value.kind == 2 {
          guard delta_object(item, ["before", "after"]) is Some(update) &&
            @decode.lookup(update, "before") is Some(before) &&
            @decode.lookup(update, "after") is Some(after) else {
            return ActionsFailed(work=used)
          }
          value.before = Some(before)
          value.after = Some(after)
        } else {
          value.before = if value.kind == 1 { Some(item) } else { None }
          value.after = if value.kind == 0 { Some(item) } else { None }
        }
        let first = match value.before {
          Some(before) => before
          None => value.after.unwrap()
        }
        guard start_action_key(first, value.edge, value.limits) is Some(key) else {
          return ActionsFailed(work=used)
        }
        value.key = Some(key)
        value.phase = ReadActionKey
      }
      ReadActionKey => {
        guard value.key is Some(key) else { return ActionsFailed(work=used) }
        match advance_action_key(key) {
          ActionKeyContinue => ()
          ActionKeyFailed => return ActionsFailed(work=used)
          ActionKeyComplete(text) => {
            value.key = None
            if value.kind == 2 && value.before_key is None {
              value.before_key = Some(text)
              guard value.after is Some(after) &&
                start_action_key(after, value.edge, value.limits) is Some(next) else {
                return ActionsFailed(work=used)
              }
              value.key = Some(next)
            } else {
              if value.kind == 2 && value.before_key != Some(text) {
                return ActionsFailed(work=used)
              }
              value.accepted_key = Some(text)
              value.phase = CommitAction
            }
          }
        }
      }
      CommitAction => {
        guard value.accepted_key is Some(key) else {
          return ActionsFailed(work=used)
        }
        if value.seen.contains(key) ||
          (
            value.previous is Some(old) &&
            @canonical.compare_utf16(old, key) >= 0
          ) {
          return ActionsFailed(work=used)
        }
        guard @scalar.admit_utf8_length(key, value.remaining_text) is Ok(bytes) else {
          return ActionsFailed(work=used)
        }
        value.remaining_text -= bytes
        value.seen[key] = true
        value.previous = Some(key)
        let actions = match value.kind {
          0 => value.result.add
          1 => value.result.remove
          _ => value.result.update
        }
        actions.push({ key, before: value.before, after: value.after, })
        value.before = None
        value.after = None
        value.before_key = None
        value.accepted_key = None
        value.index += 1
        value.phase = SelectAction
      }
      ActionsFinished => return ActionsFailed(work=used)
    }
  }
  ActionsContinue(work=used)
}

///|
fn cleanup_actions(value : ActionAdmission) -> Unit {
  if value.key is Some(key) {
    cleanup_action_key(key)
  }
  value.key = None
  value.array = None
  value.before = None
  value.after = None
  value.before_key = None
  value.accepted_key = None
  value.previous = None
  value.seen.clear()
  // Retire transient admission without clearing the same arrays subsequently
  // consumed by Apply. The Apply cleanup owner clears those retained actions.
  value.phase = ActionsFinished
}
