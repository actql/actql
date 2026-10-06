///|
priv enum RankingComparison {
  GroupComparison(Array[@value.CheckedValue], Array[@value.CheckedValue])
  TieComparison(Array[@value.CheckedValue], Array[@value.CheckedValue])
  CandidateComparison(RankingRecord, RankingRecord)
  RecordComparison(RankingRecord, RankingRecord, RankingRecordOrder)
  OutputComparison(FusedRanking, FusedRanking)
  ScalarComparison(@value.CheckedValue, @value.CheckedValue, Int)
}

///|
priv struct RankingComparisonCursor {
  goal : RankingComparison
  mut stage : Int
  mut component : Int
  mut scalar : @value.BoundedKeyComparison?
}

///|
fn start_ranking_comparison(
  goal : RankingComparison,
) -> RankingComparisonCursor {
  { goal, stage: 0, component: 0, scalar: None, }
}

///|
fn ranking_compare_scalar(
  cursor : RankingComparisonCursor,
  left : @value.CheckedValue,
  right : @value.CheckedValue,
  mode : Int,
) -> Result[Int?, RankingIssue] {
  let active = match cursor.scalar {
    Some(value) => value
    None => {
      let started = if mode == 0 {
        @value.start_bounded_group_key_comparison(left, right)
      } else if mode == 1 {
        @value.start_bounded_author_order_comparison(left, right)
      } else {
        @value.start_bounded_key_comparison(left, right)
      }
      let value = match started {
        Ok(value) => value
        Err(issue) => return Err(RankingKeyOrder(issue))
      }
      cursor.scalar = Some(value)
      value
    }
  }
  match @value.advance_bounded_key_comparison(active, 1) {
    Ok(@value.KeyComparisonContinue(_)) => Ok(None)
    Ok(@value.KeyComparisonComplete(order~, ..)) => {
      cursor.scalar = None
      Ok(Some(order))
    }
    Err(issue) => Err(RankingKeyOrder(issue))
  }
}

///|
/// One call scans at most one scalar code unit/digit. Constant transitions
/// preserve the existing lexicographic laws; components are borrowed, not
/// flattened into a second key representation.
fn advance_ranking_comparison(
  cursor : RankingComparisonCursor,
) -> Result[Int?, RankingIssue] {
  let mut scanned = false
  while true {
    match cursor.stage {
      0 => {
        match cursor.goal {
          RecordComparison(left, right, InputCandidateOrder)
          | RecordComparison(left, right, InputRankOrder) =>
            if left.input != right.input {
              return Ok(Some(if left.input < right.input { -1 } else { 1 }))
            }
          ScalarComparison(left, right, mode) =>
            return ranking_compare_scalar(cursor, left, right, mode)
          _ => ()
        }
        cursor.stage = 1
      }
      1 | 3 => {
        let pair = match (cursor.stage, cursor.goal) {
          (1, GroupComparison(left, right)) | (3, TieComparison(left, right)) =>
            Some((left, right))
          (1, CandidateComparison(left, right))
          | (1, RecordComparison(left, right, _)) =>
            Some((left.group, right.group))
          (1, OutputComparison(left, right)) => Some((left.group, right.group))
          (3, OutputComparison(left, right)) => Some((left.tie, right.tie))
          _ => None
        }
        if pair is Some((left, right)) {
          if left.length() != right.length() {
            return Err(InvalidRankingKernel)
          }
          if cursor.component < left.length() {
            if scanned {
              return Ok(None)
            }
            let comparison = match
              ranking_compare_scalar(
                cursor,
                left[cursor.component],
                right[cursor.component],
                if cursor.stage == 1 {
                  0
                } else {
                  1
                },
              ) {
              Ok(value) => value
              Err(issue) => return Err(issue)
            }
            guard comparison is Some(order) else { return Ok(None) }
            if order != 0 {
              return Ok(Some(order))
            }
            cursor.component += 1
            scanned = true
            continue
          }
        }
        cursor.component = 0
        cursor.stage += 1
      }
      2 => {
        match cursor.goal {
          GroupComparison(_, _) => return Ok(Some(0))
          RecordComparison(left, right, InputRankOrder) => {
            guard left.rank is Some(a) && right.rank is Some(b) else {
              return Err(InvalidRankingKernel)
            }
            if a != b {
              return Ok(Some(if a < b { -1 } else { 1 }))
            }
          }
          OutputComparison(left, right) =>
            if left.score != right.score {
              return Ok(Some(if left.score > right.score { -1 } else { 1 }))
            }
          _ => ()
        }
        cursor.stage = 3
      }
      4 => {
        let pair = match cursor.goal {
          TieComparison(_, _) => return Ok(Some(0))
          CandidateComparison(left, right) | RecordComparison(left, right, _) =>
            Some((left.candidate, right.candidate))
          OutputComparison(left, right) =>
            Some((left.candidate, right.candidate))
          _ => None
        }
        if pair is Some((left, right)) {
          if scanned {
            return Ok(None)
          }
          let comparison = match
            ranking_compare_scalar(cursor, left, right, 2) {
            Ok(value) => value
            Err(issue) => return Err(issue)
          }
          guard comparison is Some(order) else { return Ok(None) }
          if order != 0 {
            return Ok(Some(order))
          }
          scanned = true
        }
        cursor.stage = 5
      }
      5 => {
        match cursor.goal {
          RecordComparison(left, right, CandidateInputOrder) =>
            if left.input != right.input {
              return Ok(Some(if left.input < right.input { -1 } else { 1 }))
            }
          _ => ()
        }
        return Ok(Some(0))
      }
      _ => return Err(InvalidRankingKernel)
    }
  } nobreak {
    Err(InvalidRankingKernel)
  }
}

///|
fn ranking_compare(
  state : RankingState,
  goal : RankingComparison,
) -> Result[Int?, RankingIssue] {
  let cursor = match state.comparison {
    Some(value) => value
    None => {
      let value = start_ranking_comparison(goal)
      state.comparison = Some(value)
      value
    }
  }
  state.comparison_units.val += 1
  match advance_ranking_comparison(cursor) {
    Ok(Some(order)) => {
      state.comparison = None
      Ok(Some(order))
    }
    result => result
  }
}
