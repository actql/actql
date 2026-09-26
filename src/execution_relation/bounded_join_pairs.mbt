///|
priv enum BoundedJoinPairPhase {
  ValidateSide
  StartIndex
  BuildIndex
  CheckUnique
  BeginLeft
  SearchRight
  MatchRight
  FinishLeft
  UnmatchedRight
  Terminal
}

///|
/// Coordinates and indices remain private to the owning join session. Every
/// call advances at most one row, key, comparison cursor, or sort step.
priv struct BoundedJoinPairs {
  left : BoundedBindingInput
  right : BoundedBindingInput
  profile : @lower.PreparedInnerJoin
  keys : Array[(Int, Int)]
  orders : Array[ColumnOrder]
  control : ControlBudget
  workspace : RowWorkspace
  engine : @bounded.Control
  comparison : BoundedRowComparison
  mut phase : BoundedJoinPairPhase
  mut on_left : Bool
  mut row : Int
  mut key : Int
  mut row_null : Bool
  left_nulls : Array[Bool]
  right_nulls : Array[Bool]
  right_matches : Array[Bool]
  mut sorter : BoundedIndexSort?
  mut index : Array[Int]
  mut position : Int
  mut representative : Int?
  mut duplicate : (Int, Int)?
  mut left_row : Int
  mut low : Int
  mut high : Int
  mut matched : Bool
}

///|
priv enum BoundedJoinPairPoll {
  JoinPairContinue
  JoinPairReady(JoinPair)
  JoinPairsComplete
}

///|
fn bounded_join_pair_cell(
  state : BoundedJoinPairs,
  row : Int,
  key : Int,
) -> Value? {
  let columns = state.keys[key]
  if row >= 0 {
    bounded_binding_input_cell(state.left, row, columns.0)
  } else {
    bounded_binding_input_cell(state.right, -1 - row, columns.1)
  }
}

///|
fn bounded_join_pair_compare(
  state : BoundedJoinPairs,
  left : Int,
  right : Int,
) -> Result[Int?, RowIssue] {
  bounded_row_comparison_step_with(
    state.comparison,
    state.orders,
    state.control,
    (row, key) => bounded_join_pair_cell(state, row, key),
    left,
    right,
    state.keys.length(),
  ).map_err(ordering_row_issue)
}

///|
fn bounded_join_requires_unique(state : BoundedJoinPairs) -> Bool {
  match @lower.inner_join_assertion(state.profile) {
    Some(OneToOne) => true
    Some(OneToMany) => state.on_left
    Some(ManyToOne) => !state.on_left
    _ => false
  }
}

///|
fn bounded_join_begin_right(state : BoundedJoinPairs) -> Unit {
  release_slots(state.workspace, state.index.length())
  state.index = []
  state.on_left = false
  state.row = 0
  state.key = 0
  state.row_null = false
  state.phase = ValidateSide
}

///|
fn advance_bounded_join_pairs(
  state : BoundedJoinPairs,
) -> Result[BoundedJoinPairPoll, RowIssue] {
  if !bounded_binding_input_available(state.left) ||
    !bounded_binding_input_available(state.right) {
    return Err(InputMismatch)
  }
  if !spend_control(state.control, 1) {
    return Err(RowLimit)
  }
  let count = bounded_binding_input_row_count(
    if state.on_left {
      state.left
    } else {
      state.right
    },
  )
  match state.phase {
    ValidateSide => {
      if state.row == count {
        if state.on_left && !bounded_join_requires_unique(state) {
          bounded_join_begin_right(state)
        } else {
          state.phase = StartIndex
        }
      } else if state.key < state.keys.length() {
        guard bounded_join_pair_cell(
            state,
            if state.on_left {
              state.row
            } else {
              -1 - state.row
            },
            state.key,
          )
          is Some(value) else {
          return Err(InvalidRows)
        }
        if value is Null {
          if @lower.inner_join_fails_null(state.profile) {
            return Err(JoinNullKey(state.on_left, state.row, state.key))
          }
          state.row_null = true
        }
        state.key += 1
      } else {
        let full_right = !state.on_left &&
          @lower.inner_join_kind(state.profile) == @join.Full
        if !reserve_slots(state.workspace, if full_right { 2 } else { 1 }) {
          return Err(RowLimit)
        }
        if state.on_left {
          state.left_nulls.push(state.row_null)
        } else {
          state.right_nulls.push(state.row_null)
          if full_right {
            state.right_matches.push(false)
          }
        }
        state.row += 1
        state.key = 0
        state.row_null = false
      }
      Ok(JoinPairContinue)
    }
    StartIndex => {
      if count > (state.workspace.limit - state.workspace.live) / 2 ||
        !reserve_slots(state.workspace, count * 2) {
        return Err(RowLimit)
      }
      state.sorter = start_bounded_index_sort_stepped(state.engine, count, (
        left,
        right,
      ) => {
        bounded_join_pair_compare(
          state,
          if state.on_left {
            left
          } else {
            -1 - left
          },
          if state.on_left {
            right
          } else {
            -1 - right
          },
        )
      })
      guard state.sorter is Some(_) else { return Err(InvalidRows) }
      state.phase = BuildIndex
      Ok(JoinPairContinue)
    }
    BuildIndex => {
      guard state.sorter is Some(sorter) else { return Err(InvalidRows) }
      match advance_bounded_index_sort(sorter, 1) {
        Err(issue) => return Err(issue)
        Ok(BoundedIndexSortContinue) => ()
        Ok(BoundedIndexSortComplete(indices)) => {
          state.index = indices
          cleanup_bounded_index_sort(sorter) |> ignore
          state.sorter = None
          release_slots(state.workspace, count)
          state.position = 0
          state.representative = None
          state.duplicate = None
          state.phase = if bounded_join_requires_unique(state) {
            CheckUnique
          } else {
            BeginLeft
          }
        }
        Ok(BoundedIndexSortFailed(issue)) => return Err(issue)
        Ok(BoundedIndexSortStopped(_)) => return Err(InvalidRows)
      }
      Ok(JoinPairContinue)
    }
    CheckUnique => {
      if state.position == state.index.length() {
        if state.duplicate is Some((row, previous)) {
          return Err(JoinDuplicateKey(state.on_left, row, previous))
        }
        if state.on_left {
          bounded_join_begin_right(state)
        } else {
          state.phase = BeginLeft
        }
        return Ok(JoinPairContinue)
      }
      let row = state.index[state.position]
      let nulls = if state.on_left {
        state.left_nulls
      } else {
        state.right_nulls
      }
      if nulls[row] {
        state.position += 1
      } else if state.representative is Some(previous) {
        match
          bounded_join_pair_compare(
            state,
            if state.on_left {
              previous
            } else {
              -1 - previous
            },
            if state.on_left {
              row
            } else {
              -1 - row
            },
          ) {
          Err(issue) => return Err(issue)
          Ok(None) => ()
          Ok(Some(comparison)) => {
            if comparison == 0 {
              if state.duplicate is None || row < state.duplicate.unwrap().0 {
                state.duplicate = Some((row, previous))
              }
            } else {
              state.representative = Some(row)
            }
            state.position += 1
          }
        }
      } else {
        state.representative = Some(row)
        state.position += 1
      }
      Ok(JoinPairContinue)
    }
    BeginLeft => {
      if state.left_row == state.left_nulls.length() {
        state.position = 0
        state.phase = UnmatchedRight
      } else {
        state.matched = false
        state.low = 0
        state.high = state.index.length()
        state.phase = if state.left_nulls[state.left_row] {
          FinishLeft
        } else {
          SearchRight
        }
      }
      Ok(JoinPairContinue)
    }
    SearchRight => {
      if state.low == state.high {
        state.position = state.low
        state.phase = MatchRight
      } else {
        let middle = state.low + (state.high - state.low) / 2
        match
          bounded_join_pair_compare(
            state,
            state.left_row,
            -1 - state.index[middle],
          ) {
          Err(issue) => return Err(issue)
          Ok(None) => ()
          Ok(Some(comparison)) =>
            if comparison > 0 {
              state.low = middle + 1
            } else {
              state.high = middle
            }
        }
      }
      Ok(JoinPairContinue)
    }
    MatchRight => {
      if state.position == state.index.length() {
        state.phase = FinishLeft
        return Ok(JoinPairContinue)
      }
      let right = state.index[state.position]
      match bounded_join_pair_compare(state, state.left_row, -1 - right) {
        Err(issue) => Err(issue)
        Ok(None) => Ok(JoinPairContinue)
        Ok(Some(comparison)) => {
          if comparison != 0 {
            state.phase = FinishLeft
            return Ok(JoinPairContinue)
          }
          state.matched = true
          let kind = @lower.inner_join_kind(state.profile)
          if kind == @join.Semi || kind == @join.Anti {
            state.phase = FinishLeft
            return Ok(JoinPairContinue)
          }
          if kind == @join.Full {
            state.right_matches[right] = true
          }
          state.position += 1
          Ok(JoinPairReady({ left: Some(state.left_row), right: Some(right), }))
        }
      }
    }
    FinishLeft => {
      let kind = @lower.inner_join_kind(state.profile)
      let emit = if kind == @join.Semi {
        state.matched
      } else if kind == @join.Anti || kind == @join.Left || kind == @join.Full {
        !state.matched
      } else {
        false
      }
      let row = state.left_row
      state.left_row += 1
      state.phase = BeginLeft
      if emit {
        Ok(JoinPairReady({ left: Some(row), right: None, }))
      } else {
        Ok(JoinPairContinue)
      }
    }
    UnmatchedRight => {
      if @lower.inner_join_kind(state.profile) != @join.Full ||
        state.position == state.right_matches.length() {
        state.phase = Terminal
        return Ok(JoinPairsComplete)
      }
      let row = state.position
      state.position += 1
      if !state.right_matches[row] {
        Ok(JoinPairReady({ left: None, right: Some(row), }))
      } else {
        Ok(JoinPairContinue)
      }
    }
    Terminal => Err(InvalidRows)
  }
}

///|
fn cleanup_bounded_join_pairs(state : BoundedJoinPairs) -> Unit {
  if state.sorter is Some(sorter) {
    // A failed parent may still own a live child. Revoke compute authority
    // before observing its stop, then release its private index storage.
    @bounded.request_cancel(state.engine) |> ignore
    advance_bounded_index_sort(sorter, 1) |> ignore
    cleanup_bounded_index_sort(sorter) |> ignore
    state.sorter = None
  }
  state.index = []
  state.left_nulls.clear()
  state.right_nulls.clear()
  state.right_matches.clear()
  state.keys.clear()
  state.orders.clear()
}
