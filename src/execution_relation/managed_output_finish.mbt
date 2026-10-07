///|
priv enum ManagedOutputFinishPhase {
  References
  FixedInputs
  ManagedInputs
  Columns
  Issue
}

///|
/// Partial receipt copies belong to admission until the common issuer succeeds.
/// They never grant execution, retention or reference authority themselves.
priv struct ManagedOutputFinishCursor {
  mut phase : ManagedOutputFinishPhase
  mut row : Int
  mut column : Int
  mut reference : Int
  mut input : Int
  references : Array[Array[Array[@admitted.ReferenceValue]]]
  column_usage : Array[(Int, Int)]
  column_maxima : Array[Int]
  column_nulls : Array[Int]
  mut fixed_measurement : (Ref[Bool], (Int, Int, Int))?
  mut managed_measurement : (Ref[Bool], (Int, Int, Int))?
}

///|
pub(all) struct ManagedOutputFinishAdvance {
  receipt : ManagedOutputValueReceipt?
  steps : Int
}

///|
/// Revalidate and copy at most quantum traversal steps: one reference,
/// container boundary, or fixed-size column fact per step. The retained driver
/// resumes this same stream without restarting admission or resetting budgets.
pub fn advance_managed_output_values_finish(
  stream : ManagedOutputValues,
  quantum : Int,
) -> Result[ManagedOutputFinishAdvance, ManagedOutputValueIssue] {
  if quantum <= 0 || stream.active_uses != 0 || !stream.open || stream.reading {
    return Err(Closed)
  }
  with_managed_output_scratch_use(stream, fn() {
    stream.reading = true
    let result = advance_managed_output_finish_active(stream, quantum)
    stream.reading = false
    if result is Err(_) {
      stream.open = false
      stream.buffer.open = false
    }
    result
  })
}

///|
fn advance_managed_output_finish_active(
  stream : ManagedOutputValues,
  quantum : Int,
) -> Result[ManagedOutputFinishAdvance, ManagedOutputValueIssue] {
  if stream.finish_cursor is None {
    stream.finish_started = true
    stream.finish_cursor = Some({
      phase: References,
      row: 0,
      column: 0,
      reference: 0,
      input: -1,
      references: [],
      column_usage: [],
      column_maxima: [],
      column_nulls: [],
      fixed_measurement: None,
      managed_measurement: None,
    })
  }
  let cursor = stream.finish_cursor.unwrap()
  for step in 0..<quantum {
    if !stream.open {
      return Err(Closed)
    }
    match cursor.phase {
      References =>
        if cursor.row == stream.reference_rows.length() {
          cursor.phase = FixedInputs
        } else if cursor.references.length() == cursor.row {
          cursor.references.push([])
        } else {
          let row = stream.reference_rows[cursor.row]
          let copied = cursor.references[cursor.row]
          if cursor.column == row.length() {
            cursor.row += 1
            cursor.column = 0
          } else if copied.length() == cursor.column {
            copied.push([])
          } else if cursor.reference == row[cursor.column].length() {
            cursor.column += 1
            cursor.reference = 0
          } else {
            guard row[cursor.column][cursor.reference] is Some(reference) else {
              return Err(Closed)
            }
            if !@admitted.reference_available(reference) {
              cancel_managed_output_values(stream) |> ignore
              return Err(ReferenceUnavailable(cursor.row, cursor.column))
            }
            if !stream.open {
              return Err(Closed)
            }
            copied[cursor.column].push(reference)
            cursor.reference += 1
          }
        }
      FixedInputs =>
        match stream.producer {
          None => cursor.phase = ManagedInputs
          Some(producer) =>
            if cursor.input < 0 {
              if producer.identity.val {
                return Err(Guard(ForeignInput))
              }
              // Preserve one-shot consumption and failure precedence.
              producer.identity.val = true
              cursor.input = 0
            } else if cursor.input < producer.inputs.length() {
              if !producer_read_available(producer.inputs[cursor.input]) {
                return Err(Guard(ForeignInput))
              }
              cursor.input += 1
            } else {
              cursor.fixed_measurement = Some(
                (
                  producer.identity,
                  (
                    producer.initial.max_work - producer.budget.work,
                    producer.initial.max_bytes - producer.budget.bytes,
                    producer.initial.max_nodes - producer.budget.nodes,
                  ),
                ),
              )
              cursor.input = -1
              cursor.phase = ManagedInputs
            }
        }
      ManagedInputs =>
        match stream.managed_producer {
          None => {
            cursor.phase = Columns
            cursor.column = 0
          }
          Some(producer) =>
            if cursor.input < 0 {
              if producer.identity.val {
                return Err(Guard(ForeignInput))
              }
              cursor.input = 0
            } else if cursor.input < producer.live.length() {
              if !producer.live[cursor.input]() {
                return Err(Guard(ForeignInput))
              }
              cursor.input += 1
            } else {
              producer.identity.val = true
              cursor.managed_measurement = Some(
                (
                  producer.identity,
                  (
                    producer.initial.max_work - producer.budget.work,
                    producer.initial.max_bytes - producer.budget.bytes,
                    producer.initial.max_nodes - producer.budget.nodes,
                  ),
                ),
              )
              cursor.phase = Columns
              cursor.column = 0
            }
        }
      Columns =>
        if cursor.column == stream.column_usage.length() {
          cursor.phase = Issue
        } else {
          cursor.column_usage.push(stream.column_usage[cursor.column])
          cursor.column_maxima.push(stream.column_maxima[cursor.column])
          cursor.column_nulls.push(stream.column_nulls[cursor.column])
          cursor.column += 1
        }
      Issue => {
        let receipt = match issue_managed_output_value_receipt(stream, cursor) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        return Ok({ receipt: Some(receipt), steps: step + 1, })
      }
    }
  }
  if !stream.open {
    return Err(Closed)
  }
  Ok({ receipt: None, steps: quantum, })
}
