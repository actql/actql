///|
priv struct SequencePartial {
  positions : Array[Int]
}

///|
fn sequence_ordering_issue(issue : OrderingIssue) -> RowIssue {
  match issue {
    InvalidInput => InvalidRows
    Limit => RowLimit
    Scalar(issue) => Comparison(issue)
  }
}

///|
fn[T : RelationRows] evaluate_sequence_match_rows(
  kernel : @lower.PreparedSequenceMatch,
  input : T,
  max_rows : Int,
  control : ControlBudget,
  output : ValueBudget,
  workspace : RowWorkspace,
) -> Result[Table, RowIssue] {
  let owner = @lower.sequence_match_owner(kernel)
  if !physical_equal(input.checked_owner(), owner) {
    return Err(OwnerMismatch)
  }
  if input.relation_id() != @lower.sequence_match_input(kernel) {
    return Err(InputMismatch)
  }
  if max_rows < 0 ||
    workspace.live != 0 ||
    workspace.peak != 0 ||
    workspace.limit < 0 {
    return Err(InvalidRowLimits)
  }
  let count = IndexedRows::row_count(input)
  if count > max_rows {
    return Err(RowLimit)
  }
  let mut retained = 0
  let run = fn() -> Result[Table, RowIssue] {
    let input_names = input.field_names()
    let resolve = fn(field : @schema.FieldName) -> Result[Int, RowIssue] {
      let reference = @schema.reference_name(field)
      for index, name in input_names {
        if !spend_control(control, 1) ||
          !spend_control_text(control, reference) ||
          !spend_control_text(control, name) {
          return Err(RowLimit)
        }
        if name == reference {
          return Ok(index)
        }
      }
      Err(InvalidRows)
    }
    let key_columns : Array[Int] = []
    let key_fields : Array[@schema.FieldName] = []
    let order : Array[ColumnOrder] = []
    for index in 0..<@lower.sequence_match_key_count(kernel) {
      let field = @lower.sequence_match_key_at(kernel, index).unwrap()
      let column = match resolve(field) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      if !reserve_slots(workspace, 3) {
        return Err(RowLimit)
      }
      key_columns.push(column)
      key_fields.push(field)
      order.push({ column, descending: false, nulls_first: true, })
    }
    let identity_field = @lower.sequence_match_identity(kernel)
    let identity_column = match resolve(identity_field) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let time_column = match resolve(@lower.sequence_match_time(kernel)) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if !reserve_slots(workspace, 2) {
      return Err(RowLimit)
    }
    order.push({ column: time_column, descending: false, nulls_first: false, })
    order.push({
      column: identity_column,
      descending: false,
      nulls_first: false,
    })
    let ordinals : Map[String, Int] = Map([])
    for index, name in input_names {
      ordinals[name] = index
    }
    match
      validate_unique_rows(
        input,
        [identity_field],
        ordinals,
        control,
        workspace,
      ) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    let clocks : Array[Int64] = []
    if !reserve_slots(workspace, count) {
      return Err(RowLimit)
    }
    for row in 0..<count {
      match
        interval_clock(
          IndexedRows::read_cell(input, row, time_column),
          @lower.sequence_match_uses_timestamp(kernel),
          control,
        ) {
        Ok(value) => clocks.push(value)
        Err(issue) => return Err(issue)
      }
    }
    let ordered = match stable_order_indices(input, order, control, workspace) {
      Ok(value) => value
      Err(issue) => return Err(sequence_ordering_issue(issue))
    }
    let pattern_count = @lower.sequence_match_pattern_count(kernel)
    if pattern_count < 2 ||
      (pattern_count != 0 && count > workspace.limit / pattern_count) ||
      !reserve_slots(workspace, pattern_count) ||
      !reserve_slots(workspace, count * pattern_count) {
      return Err(RowLimit)
    }
    let predicates = Array::makei(pattern_count, _ => Array::make(count, -1))
    let matches_pattern = fn(
      position : Int,
      pattern : Int,
    ) -> Result[Bool, RowIssue] {
      let row = ordered[position]
      if predicates[pattern][row] >= 0 {
        return Ok(predicates[pattern][row] == 1)
      }
      let snapshot : Map[String, Value] = Map([])
      if !reserve_slots(workspace, input_names.length()) {
        return Err(RowLimit)
      }
      for column, name in input_names {
        if !spend_control(control, 1) || !spend_control_text(control, name) {
          return Err(RowLimit)
        }
        snapshot[name] = IndexedRows::read_cell(input, row, column)
      }
      let expression = @lower.sequence_match_predicate(kernel, pattern).unwrap()
      let value = match
        evaluate_expression_with_workspace(
          expression,
          snapshot,
          [],
          control,
          workspace,
        ) {
        Ok(value) => value
        Err(issue) => {
          release_slots(workspace, snapshot.length())
          return Err(Evaluation(row, pattern, issue))
        }
      }
      release_slots(workspace, snapshot.length())
      let matched = match value {
        Boolean(value) => value
        Null => false
        Number(_) | Text(_) | Captured(_) => return Err(InvalidRows)
      }
      predicates[pattern][row] = if matched { 1 } else { 0 }
      Ok(matched)
    }
    let same_key = fn(
      left_position : Int,
      right_position : Int,
    ) -> Result[Bool, RowIssue] {
      let left = ordered[left_position]
      let right = ordered[right_position]
      for column in key_columns {
        match
          compare_complete_value(
            IndexedRows::read_cell(input, left, column),
            IndexedRows::read_cell(input, right, column),
            control,
          ) {
          Ok(0) => ()
          Ok(_) => return Ok(false)
          Err(issue) => return Err(sequence_ordering_issue(issue))
        }
      }
      Ok(true)
    }
    let matches : Array[SequencePartial] = []
    let mut group_start = 0
    while group_start < ordered.length() {
      let mut group_end = group_start + 1
      while group_end < ordered.length() {
        match same_key(group_start, group_end) {
          Ok(true) => group_end += 1
          Ok(false) => break
          Err(issue) => return Err(issue)
        }
      }
      let per_key_limit = match @lower.sequence_match_per_key_limit(kernel) {
        Some(value) => Int64::min(value, max_rows.to_int64()).to_int()
        None => max_rows
      }
      let before = matches.length()
      if @lower.sequence_match_overlap(kernel) ==
        @relation.SequenceOverlap::Disallow {
        let mut cursor = group_start
        while cursor < group_end {
          let mut first = cursor
          while first < group_end {
            if !spend_control(control, 1) {
              return Err(RowLimit)
            }
            let matched = match matches_pattern(first, 0) {
              Ok(value) => value
              Err(issue) => return Err(issue)
            }
            if matched {
              break
            }
            first += 1
          }
          if first == group_end {
            break
          }
          let selected : Array[Int] = [first]
          if !reserve_slots(workspace, 1) {
            return Err(RowLimit)
          }
          let mut prior = first
          let mut complete = true
          for pattern in 1..<pattern_count {
            let mut next = prior + 1
            if @lower.sequence_match_contiguity(kernel) ==
              @relation.SequenceContiguity::Adjacent {
              if next >= group_end {
                complete = false
                break
              }
              let matched = match matches_pattern(next, pattern) {
                Ok(value) => value
                Err(issue) => return Err(issue)
              }
              if !matched {
                complete = false
                break
              }
            } else {
              while next < group_end {
                if !spend_control(control, 1) {
                  return Err(RowLimit)
                }
                let matched = match matches_pattern(next, pattern) {
                  Ok(value) => value
                  Err(issue) => return Err(issue)
                }
                if matched {
                  break
                }
                next += 1
              }
              if next == group_end {
                complete = false
                break
              }
            }
            if clocks[ordered[next]] - clocks[ordered[first]] >
              @lower.sequence_match_within(kernel) {
              complete = false
              break
            }
            if !reserve_slots(workspace, 1) {
              return Err(RowLimit)
            }
            selected.push(next)
            prior = next
          }
          if complete {
            if matches.length() - before == per_key_limit ||
              matches.length() == max_rows ||
              !reserve_slots(workspace, 1) {
              return Err(RowLimit)
            }
            matches.push({ positions: selected, })
            cursor = selected[selected.length() - 1] + 1
          } else {
            release_slots(workspace, selected.length())
            cursor = first + 1
          }
        }
      } else {
        let partials : Array[Array[SequencePartial]] = Array::makei(
          pattern_count,
          _ => [],
        )
        if !reserve_slots(workspace, pattern_count) {
          return Err(RowLimit)
        }
        for position in group_start..<group_end {
          let row = ordered[position]
          let row_matches = Array::make(pattern_count, false)
          if !reserve_slots(workspace, pattern_count) {
            return Err(RowLimit)
          }
          for pattern in 0..<pattern_count {
            let demanded = if pattern == 0 {
              true
            } else if partials[pattern - 1].is_empty() {
              false
            } else if @lower.sequence_match_contiguity(kernel) ==
              @relation.SequenceContiguity::Subsequence {
              true
            } else {
              partials[pattern - 1].any(partial => {
                partial.positions[partial.positions.length() - 1] ==
                position - 1
              })
            }
            if demanded {
              row_matches[pattern] = match matches_pattern(position, pattern) {
                Ok(value) => value
                Err(issue) => return Err(issue)
              }
            }
          }
          for pattern = pattern_count - 1; pattern >= 1; pattern = pattern - 1 {
            if !row_matches[pattern] {
              continue
            }
            let prior_count = partials[pattern - 1].length()
            for index in 0..<prior_count {
              let prior = partials[pattern - 1][index]
              let first = prior.positions[0]
              let last = prior.positions[prior.positions.length() - 1]
              let adjacent = @lower.sequence_match_contiguity(kernel) ==
                @relation.SequenceContiguity::Adjacent &&
                position == last + 1
              let subsequence = @lower.sequence_match_contiguity(kernel) ==
                @relation.SequenceContiguity::Subsequence
              if (adjacent || subsequence) &&
                clocks[row] - clocks[ordered[first]] <=
                @lower.sequence_match_within(kernel) {
                if !spend_control(control, 1) ||
                  !reserve_slots(workspace, prior.positions.length() + 1) {
                  return Err(RowLimit)
                }
                let extended = prior.positions.copy()
                extended.push(position)
                let match_ : SequencePartial = { positions: extended, }
                partials[pattern].push(match_)
                if pattern == pattern_count - 1 {
                  if matches.length() - before == per_key_limit ||
                    matches.length() == max_rows ||
                    !reserve_slots(workspace, 1) {
                    return Err(RowLimit)
                  }
                  matches.push(match_)
                }
              }
            }
          }
          if row_matches[0] {
            if !reserve_slots(workspace, 2) {
              return Err(RowLimit)
            }
            partials[0].push({ positions: [position], })
          }
          release_slots(workspace, row_matches.length())
        }
      }
      group_start = group_end
    }
    let output_limit = match @lower.sequence_match_output_limit(kernel) {
      Some(value) => Int64::min(value, max_rows.to_int64()).to_int()
      None => max_rows
    }
    if matches.length() > output_limit {
      return Err(RowLimit)
    }
    let schema = @lower.sequence_match_output_schema(kernel)
    let names : Array[String] = []
    for index in 0..<@schema.field_count(schema) {
      let name = @schema.reference_name(
        @schema.field_at(schema, index).unwrap().name,
      )
      if !reserve_slots(workspace, 1) || !spend_control_text(control, name) {
        return Err(RowLimit)
      }
      retained += 1
      names.push(name)
    }
    let rows : Array[Array[Value]] = []
    for match_ in matches {
      let first_row = ordered[match_.positions[0]]
      let last_row = ordered[match_.positions[match_.positions.length() - 1]]
      let row : Array[Value] = []
      for name in names {
        let mut value : Value? = None
        for index in 0..<key_fields.length() {
          if name == @schema.reference_name(key_fields[index]) {
            value = Some(
              IndexedRows::read_cell(input, first_row, key_columns[index]),
            )
          }
        }
        if name == "match_start_ms" {
          value = Some(Number(clocks[first_row].to_double()))
        } else if name == "match_end_ms" {
          value = Some(Number(clocks[last_row].to_double()))
        }
        for pattern in 0..<pattern_count {
          let label = @lower.sequence_match_pattern_label(kernel, pattern).unwrap()
          let source = ordered[match_.positions[pattern]]
          if name == label + "_id" {
            value = Some(IndexedRows::read_cell(input, source, identity_column))
          } else if name == label + "_time_ms" {
            value = Some(Number(clocks[source].to_double()))
          }
        }
        guard value is Some(value) else { return Err(InvalidRows) }
        row.push(value)
      }
      if row.length() != names.length() ||
        !reserve_slots(workspace, 1 + row.length()) ||
        !retain_row(row, names, output) {
        return Err(RowLimit)
      }
      retained += 1 + row.length()
      rows.push(row)
    }
    Ok({
      owner,
      id: @lower.node_id(
        @lower.node_at(
          @lower.bound_preparation(owner),
          @lower.sequence_match_step(kernel),
        ).unwrap(),
      ),
      names,
      rows,
    })
  }
  let result = run()
  let keep = match result {
    Ok(_) => retained
    Err(_) => 0
  }
  release_slots(workspace, workspace.live - keep)
  result
}
