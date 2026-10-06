///|
fn ranking_name_length(name : @schema.FieldName) -> Int64 {
  match name {
    @schema.Unqualified(text) => text.length().to_int64()
    @schema.Qualified(@schema.Left, text) => text.length().to_int64() + 5L
    @schema.Qualified(@schema.Right, text) => text.length().to_int64() + 6L
  }
}

///|
fn ranking_name_equal_budget(
  state : RankingState,
  left : @schema.FieldName,
  right : @schema.FieldName,
  allowance : Int,
) -> (Bool?, Int) {
  if ranking_name_length(left) != ranking_name_length(right) {
    state.name_offset.val = 0
    return (Some(false), 0)
  }
  let (order, offset, spent) = @schema.compare_reference_fragment(
    left,
    right,
    state.name_offset.val,
    allowance,
  )
  state.name_offset.val = offset
  (order.map(order => order == 0), spent)
}

///|
fn match_ranking_field(state : RankingState) -> Result[Unit, RankingIssue] {
  guard state.pending_field is Some((name, value)) else {
    return Err(InvalidRankingKernel)
  }
  let candidate = state.by.length()
  let tie_start = candidate + 1
  let score = tie_start + state.tie.length()
  let rank = score + 1
  let mut remaining = 64
  // Preserve multiple roles for a field without materializing a role array.
  // Both wide role lists and long spellings yield within the charged poll.
  for _ in 0..<8 {
    if state.name_probe > rank {
      state.pending_field = None
      state.field += 1
      state.phase = ReadField
      return Ok(())
    }
    let expected = if state.name_probe < candidate {
      Some(state.by[state.name_probe])
    } else if state.name_probe == candidate {
      Some(state.candidate_name)
    } else if state.name_probe < score {
      Some(state.tie[state.name_probe - tie_start])
    } else if state.name_probe == score {
      state.score_name
    } else {
      state.rank_name
    }
    if expected is Some(expected) {
      let (equal, spent) = ranking_name_equal_budget(
        state,
        name,
        @schema.Unqualified(expected),
        remaining,
      )
      remaining -= spent
      guard equal is Some(equal) else { return Ok(()) }
      if equal {
        if state.name_probe < candidate {
          state.group_values[state.name_probe] = Some(value)
        } else if state.name_probe == candidate {
          state.candidate_value = Some(value)
        } else if state.name_probe < score {
          state.tie_values[state.name_probe - tie_start] = Some(value)
        } else {
          guard value.value is @value.Number(number) else {
            return Err(InvalidRankingRecord(state.input, state.row))
          }
          if state.name_probe == score {
            state.score_value = Some(number)
          } else {
            state.rank_value = Some(number)
          }
        }
      }
    }
    state.name_probe += 1
    if remaining == 0 {
      return Ok(())
    }
  }
  Ok(())
}
