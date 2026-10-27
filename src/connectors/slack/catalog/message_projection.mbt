///|
pub(all) struct SlackMessageProjectionLimits {
  max_rows : Int
  max_occurrences : Int
  max_work : Int
  comparison : @admitted.Limits
}

///|
// Original completed acquisition DATA. This retains every selected protocol
// prefix and the first checked row for each key. It is not a complete workspace
// inventory, current Source authority, reservation or physical cleanup ACK.
// Keep original acquisition dependencies alive with this projection, even
// though getters only read the checked rows; this is not a cleanup ACK.
#warnings("-unused_field")
pub struct SlackMessageProjection {
  priv _history : SlackMessageHistory
  priv _replies : Array[SlackMessageReplies]
  priv rows : Array[Array[@admitted.CheckedValue]]
}

///|
priv struct SlackMessageProjectionWork {
  limits : SlackMessageProjectionLimits
  mut remaining : Int
}

///|
priv struct SlackMessageOccurrence {
  page : SlackMessagePage
  index : Int
}

///|
fn projection_spend(work : SlackMessageProjectionWork, amount : Int) -> Bool {
  if amount < 0 || amount > work.remaining {
    return false
  }
  work.remaining -= amount
  true
}

///|
fn projection_equal(
  work : SlackMessageProjectionWork,
  left : @admitted.CheckedValue,
  right : @admitted.CheckedValue,
) -> Result[Bool, SlackMessagePageIssue] {
  if !projection_spend(work, 1) {
    return Err(BudgetExceeded)
  }
  let equality = match
    @admitted.start_complete_equality(left, right, work.limits.comparison) {
    Ok(value) => value
    Err(_) => return Err(BudgetExceeded)
  }
  while true {
    if work.remaining <= 0 {
      @admitted.cancel_complete_equality(equality)
      return Err(BudgetExceeded)
    }
    match @admitted.advance_complete_equality(equality, 1) {
      EqualityContinue(work=used) =>
        if !projection_spend(work, used) {
          @admitted.cancel_complete_equality(equality)
          return Err(BudgetExceeded)
        }
      EqualityComplete(equal~, work=used) => {
        if !projection_spend(work, used) {
          return Err(BudgetExceeded)
        }
        return Ok(equal)
      }
      EqualityFailed(_, work=_) => return Err(BudgetExceeded)
    }
  }
  Err(BudgetExceeded)
}

///|
fn projection_reaction_field(
  work : SlackMessageProjectionWork,
  value : @admitted.Value,
  name : String,
) -> Result[@admitted.CheckedValue, SlackMessagePageIssue] {
  guard value is @admitted.Object(fields) else {
    return Err(InconsistentThread)
  }
  for index in 0..<@admitted.element_count(fields) {
    if !projection_spend(work, 1) {
      return Err(BudgetExceeded)
    }
    let (key, original) = @admitted.element_at(fields, index).unwrap()
    if key == name {
      let contract = match name {
        "name" => @contract.primitive(@contract.StringType, nullable=false)
        "count" => @contract.primitive(@contract.Signed64Type, nullable=false)
        _ =>
          @contract.array_contract(
            @contract.primitive(@contract.StringType, nullable=false),
            nullable=true,
          ).unwrap()
      }
      // Recheck a subvalue of the original checked reaction. No row or JSON
      // replacement is emitted, and the bounded traversal is charged as work.
      guard @admitted.recheck_runtime_value_usage(
          original,
          contract,
          work.limits.comparison,
        )
        is Some((checked, nodes, text)) else {
        return Err(BudgetExceeded)
      }
      if !projection_spend(work, nodes) || !projection_spend(work, text) {
        return Err(BudgetExceeded)
      }
      return Ok(checked)
    }
  }
  Err(InconsistentThread)
}

///|
fn projection_reactions_equal(
  work : SlackMessageProjectionWork,
  left : @admitted.CheckedValue,
  right : @admitted.CheckedValue,
  left_presence : Array[Bool],
  right_presence : Array[Bool],
) -> Result[Bool, SlackMessagePageIssue] {
  match (left.value, right.value) {
    (@admitted.Array(a), @admitted.Array(b)) => {
      let count = @admitted.element_count(a)
      if count != @admitted.element_count(b) {
        return Ok(false)
      }
      for index in 0..<count {
        if !projection_spend(work, 1) {
          return Err(BudgetExceeded)
        }
        let x = @admitted.element_at(a, index).unwrap()
        let y = @admitted.element_at(b, index).unwrap()
        for name in ["name", "count", "users"] {
          if name == "users" && !(left_presence[index] && right_presence[index]) {
            continue
          }
          let first = match projection_reaction_field(work, x, name) {
            Ok(value) => value
            Err(issue) => return Err(issue)
          }
          let second = match projection_reaction_field(work, y, name) {
            Ok(value) => value
            Err(issue) => return Err(issue)
          }
          match projection_equal(work, first, second) {
            Ok(true) => ()
            result => return result
          }
        }
      }
      Ok(true)
    }
    _ => projection_equal(work, left, right)
  }
}

///|
fn projection_occurrences_equal(
  work : SlackMessageProjectionWork,
  left : SlackMessageOccurrence,
  right : SlackMessageOccurrence,
) -> Result[Bool, SlackMessagePageIssue] {
  let a = left.page.rows[left.index]
  let b = right.page.rows[right.index]
  let af = left.page.facts[left.index]
  let bf = right.page.facts[right.index]
  for index in 0..<a.length() {
    if !projection_spend(work, 1) {
      return Err(BudgetExceeded)
    }
    if !(af.established[index] && bf.established[index]) {
      continue
    }
    let result = if index == 7 {
      projection_reactions_equal(
        work,
        a[index],
        b[index],
        af.reaction_users,
        bf.reaction_users,
      )
    } else {
      projection_equal(work, a[index], b[index])
    }
    match result {
      Ok(true) => ()
      _ => return result
    }
  }
  Ok(true)
}

///|
pub fn coalesce_slack_message_originals(
  history : SlackMessageHistory,
  replies : Array[SlackMessageReplies],
  limits : SlackMessageProjectionLimits,
) -> Result[SlackMessageProjection, SlackMessagePageIssue] {
  if limits.max_rows <= 0 ||
    limits.max_occurrences <= 0 ||
    limits.max_work <= 0 ||
    limits.comparison.max_nodes <= 0 ||
    limits.comparison.max_depth <= 0 ||
    limits.comparison.max_text_bytes <= 0 {
    return Err(InvalidLimits)
  }
  if !history.completed {
    return Err(HistoryUnavailable)
  }
  let work = { limits, remaining: limits.max_work, }
  let pages = []
  for page in history.pages {
    if !projection_spend(work, 1) || pages.length() >= limits.max_occurrences {
      return Err(BudgetExceeded)
    }
    pages.push(page)
  }
  for protocol in replies {
    if !projection_spend(work, 1) {
      return Err(BudgetExceeded)
    }
    // Pointer membership is the original page/row selection, not matching wire.
    guard protocol.completed &&
      protocol.source_page.history_request is Some(request) &&
      physical_equal(request.history, history) else {
      return Err(ForeignRepliesRequest)
    }
    let mut original = false
    for page in history.pages {
      if !projection_spend(work, 1) {
        return Err(BudgetExceeded)
      }
      if physical_equal(page, protocol.source_page) {
        original = true
        break
      }
    }
    if !original {
      return Err(ForeignRepliesRequest)
    }
    for page in protocol.pages {
      if !projection_spend(work, 1) || pages.length() >= limits.max_occurrences {
        return Err(BudgetExceeded)
      }
      pages.push(page.original)
    }
  }
  let rows = []
  let occurrences : Map[String, Array[SlackMessageOccurrence]] = Map([])
  let children : Map[String, Map[String, Bool]] = Map([])
  let mut total = 0
  for page in pages {
    for index in 0..<page.rows.length() {
      if !projection_spend(work, 1) || total >= limits.max_occurrences {
        return Err(BudgetExceeded)
      }
      total += 1
      let row = page.rows[index]
      guard row[0].value is @admitted.Text(id) &&
        row[2].value is @admitted.Text(ts) else {
        return Err(InvalidCell("id"))
      }
      if !projection_spend(work, id.length()) ||
        !projection_spend(work, ts.length()) {
        return Err(BudgetExceeded)
      }
      let occurrence = { page, index, }
      match occurrences.get(id) {
        Some(previous) => {
          // Compare all established observations, including later facts absent
          // from the first row. Omission never erases a previous observation.
          for before in previous {
            match projection_occurrences_equal(work, before, occurrence) {
              Ok(true) => ()
              Ok(false) => return Err(InconsistentThread)
              Err(issue) => return Err(issue)
            }
          }
          previous.push(occurrence)
        }
        None => {
          if rows.length() >= limits.max_rows {
            return Err(BudgetExceeded)
          }
          occurrences[id] = [occurrence]
          rows.push(row)
        }
      }
      if row[5].value is @admitted.Text(root) && root != ts {
        if !projection_spend(work, root.length()) {
          return Err(BudgetExceeded)
        }
        let members = match children.get(root) {
          Some(value) => value
          None => {
            let value = Map([])
            children[root] = value
            value
          }
        }
        members[id] = true
      }
    }
  }
  // A retained established zero cannot coexist with actual distinct children.
  // More generally, an observed count cannot be less than the selected known
  // children. This is consistency, not an atomic/latest snapshot assertion.
  for page in pages {
    for index in 0..<page.rows.length() {
      if !projection_spend(work, 1) {
        return Err(BudgetExceeded)
      }
      let row = page.rows[index]
      if row[2].value is @admitted.Text(ts) &&
        children.get(ts) is Some(members) &&
        page.facts[index].established[6] &&
        row[6].value is @admitted.Signed64(count) &&
        count < members.length().to_int64() {
        return Err(InconsistentThread)
      }
    }
  }
  Ok({ _history: history, _replies: replies.copy(), rows, })
}

///|
pub fn slack_message_projection_row_count(
  projection : SlackMessageProjection,
) -> Int {
  projection.rows.length()
}

///|
pub fn slack_message_projection_rows_wire(
  projection : SlackMessageProjection,
  names : Array[String],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, SlackMessagePageIssue] {
  message_rows_wire(projection.rows, names, max_bytes, max_nodes, max_depth)
}
