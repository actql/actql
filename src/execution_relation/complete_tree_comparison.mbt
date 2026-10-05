///|
priv enum CompleteTreeTextOrder {
  Utf16Order
  DecimalOrder(@admitted.DecimalValue, @admitted.DecimalValue)
}

///|
priv enum CompleteTreeComparisonFrame {
  CompareAdmitted(@admitted.Value, @admitted.Value)
  ArrayMembers(
    @admitted.FrozenArray[@admitted.Value],
    @admitted.FrozenArray[@admitted.Value],
    Int
  )
  ObjectMembers(
    @admitted.FrozenArray[(String, @admitted.Value)],
    @admitted.FrozenArray[(String, @admitted.Value)],
    Int
  )
  TextUnits(
    String,
    String,
    BoundedCompleteValueComparison,
    CompleteTreeTextOrder
  )
  VectorMembers(
    @admitted.FrozenArray[Double],
    @admitted.FrozenArray[Double],
    Int,
    Int
  )
}

///|
/// A complete-value comparison continuation, not a serialized copy or a new
/// equality domain. Its input owner retains both admitted roots until stop.
priv struct BoundedCompleteTreeComparison {
  workspace : RowWorkspace
  frames : Array[CompleteTreeComparisonFrame]
  mut outer_charge : Bool
  mut closed : Bool
}

///|
fn start_complete_tree_comparison(
  left : @admitted.Value,
  right : @admitted.Value,
  control : ControlBudget,
  workspace : RowWorkspace,
) -> Result[BoundedCompleteTreeComparison, OrderingIssue] {
  // One cursor handle and one admitted-pair frame, before either allocation.
  if control.max_frames < 1 || !reserve_slots(workspace, 2) {
    return Err(Limit)
  }
  Ok({
    workspace,
    frames: [CompareAdmitted(left, right)],
    outer_charge: true,
    closed: false,
  })
}

///|
fn close_complete_tree_comparison(
  cursor : BoundedCompleteTreeComparison,
) -> Unit {
  if !cursor.closed {
    release_slots(cursor.workspace, cursor.frames.length() + 1)
    cursor.frames.clear()
    cursor.closed = true
  }
}

///|
fn complete_tree_result(
  cursor : BoundedCompleteTreeComparison,
  order : Int,
) -> Int? {
  if order != 0 {
    close_complete_tree_comparison(cursor)
    return Some(order)
  }
  cursor.frames.pop() |> ignore
  release_slots(cursor.workspace, 1)
  if cursor.frames.is_empty() {
    close_complete_tree_comparison(cursor)
    Some(0)
  } else {
    None
  }
}

///|
fn complete_tree_text_frame(
  left : String,
  right : String,
  order? : CompleteTreeTextOrder = Utf16Order,
) -> CompleteTreeComparisonFrame {
  let cursor = bounded_complete_value_comparison()
  // The admitted value's node charge is already paid. Object names have no
  // node charge in the existing complete-value owner.
  cursor.phase = 1
  TextUnits(left, right, cursor, order)
}

///|
fn complete_tree_decimal_step(
  a : @admitted.DecimalValue,
  b : @admitted.DecimalValue,
  index : Int,
) -> (Int?, Int) {
  let ac = a.coefficient
  let bc = b.coefficient
  let an = ac[0] == '-'
  let bn = bc[0] == '-'
  if ac == "0" {
    return (Some(if bc == "0" { 0 } else if bn { 1 } else { -1 }), index)
  }
  if bc == "0" {
    return (Some(if an { -1 } else { 1 }), index)
  }
  if an != bn {
    return (Some(if an { -1 } else { 1 }), index)
  }
  let ai = if an { 1 } else { 0 }
  let bi = if bn { 1 } else { 0 }
  let al = ac.length() - ai
  let bl = bc.length() - bi
  let ae = al - a.scale
  let be = bl - b.scale
  let direction = if an { -1 } else { 1 }
  if ae != be {
    return (Some((if ae < be { -1 } else { 1 }) * direction), index)
  }
  if index == Int::max(al, bl) {
    return (Some(0), index)
  }
  let x = if index < al { ac[ai + index] } else { '0' }
  let y = if index < bl { bc[bi + index] } else { '0' }
  if x != y {
    (Some((if x < y { -1 } else { 1 }) * direction), index + 1)
  } else {
    (None, index + 1)
  }
}

///|
fn advance_complete_tree_comparison(
  cursor : BoundedCompleteTreeComparison,
  control : ControlBudget,
) -> Result[Int?, OrderingIssue] {
  if cursor.closed || cursor.frames.is_empty() {
    return Err(InvalidInput)
  }
  if cursor.outer_charge {
    if !spend_control(control, 1) {
      return Err(Limit)
    }
    cursor.outer_charge = false
    return Ok(None)
  }
  let top = cursor.frames.length() - 1
  match cursor.frames[top] {
    CompareAdmitted(a, b) => {
      if !spend_control(control, 1) {
        return Err(Limit)
      }
      cursor.frames[top] = match (a, b) {
        (@admitted.Array(left), @admitted.Array(right)) =>
          ArrayMembers(left, right, 0)
        (@admitted.Object(left), @admitted.Object(right)) =>
          ObjectMembers(left, right, 0)
        (@admitted.Vector(left), @admitted.Vector(right)) => {
          let count = Int::min(
            @admitted.element_count(left),
            @admitted.element_count(right),
          )
          // Preserve the original all-or-nothing dimension admission, then
          // pay that admitted charge incrementally before reading dimensions.
          if control.remaining < count {
            return Err(Limit)
          }
          VectorMembers(left, right, 0, count)
        }
        (@admitted.Text(left), @admitted.Text(right))
        | (@admitted.Date(left), @admitted.Date(right))
        | (@admitted.Timestamp(left), @admitted.Timestamp(right)) =>
          complete_tree_text_frame(left, right)
        (@admitted.Decimal(left), @admitted.Decimal(right)) =>
          complete_tree_text_frame(
            left.coefficient,
            right.coefficient,
            order=DecimalOrder(left, right),
          )
        (@admitted.Reference(left), @admitted.Reference(right)) => {
          if !@admitted.reference_available(left) ||
            !@admitted.reference_available(right) {
            return Err(Scalar(InvalidOperand))
          }
          if !@admitted.reference_same_domain(left, right) {
            return Err(Scalar(ComparisonDomainNotImplemented))
          }
          complete_tree_text_frame(
            @admitted.reference_identity_cid(left),
            @admitted.reference_identity_cid(right),
          )
        }
        _ => {
          // The node charge above replaces compare_admitted_value's entry
          // charge. Only fixed-size scalar comparison remains here.
          let order = match (a, b) {
            (@admitted.Null, @admitted.Null) => 0
            (@admitted.Number(left), @admitted.Number(right)) =>
              match compare(Number(left), Number(right)) {
                Ok(value) => value
                Err(issue) => return Err(Scalar(issue))
              }
            (@admitted.Boolean(left), @admitted.Boolean(right)) =>
              match compare(Boolean(left), Boolean(right)) {
                Ok(value) => value
                Err(issue) => return Err(Scalar(issue))
              }
            _ => Int::compare(admitted_rank(a), admitted_rank(b))
          }
          return Ok(complete_tree_result(cursor, order))
        }
      }
      Ok(None)
    }
    ArrayMembers(left, right, index) => {
      let lc = @admitted.element_count(left)
      let rc = @admitted.element_count(right)
      if index == Int::min(lc, rc) {
        return Ok(complete_tree_result(cursor, Int::compare(lc, rc)))
      }
      if cursor.frames.length() >= control.max_frames ||
        !reserve_slots(cursor.workspace, 1) {
        return Err(Limit)
      }
      cursor.frames[top] = ArrayMembers(left, right, index + 1)
      cursor.frames.push(
        CompareAdmitted(
          @admitted.element_at(left, index).unwrap(),
          @admitted.element_at(right, index).unwrap(),
        ),
      )
      Ok(None)
    }
    ObjectMembers(left, right, index) => {
      let lc = @admitted.element_count(left)
      let rc = @admitted.element_count(right)
      if index == Int::min(lc, rc) {
        return Ok(complete_tree_result(cursor, Int::compare(lc, rc)))
      }
      if cursor.frames.length() > control.max_frames - 2 ||
        !reserve_slots(cursor.workspace, 2) {
        return Err(Limit)
      }
      let (ln, lv) = @admitted.element_at(left, index).unwrap()
      let (rn, rv) = @admitted.element_at(right, index).unwrap()
      cursor.frames[top] = ObjectMembers(left, right, index + 1)
      cursor.frames.push(CompareAdmitted(lv, rv))
      cursor.frames.push(complete_tree_text_frame(ln, rn))
      Ok(None)
    }
    TextUnits(left, right, text, order) => {
      if text.phase == 3 && order is DecimalOrder(a, b) {
        let (compared, next) = complete_tree_decimal_step(a, b, text.offset)
        text.offset = next
        return match compared {
          None => Ok(None)
          Some(value) => Ok(complete_tree_result(cursor, value))
        }
      }
      // Decimal digit order is handled above; this step only charges both
      // coefficient strings before it reaches phase three.
      match
        bounded_complete_value_comparison_step(
          text,
          Text(left),
          Text(right),
          control,
        ) {
        Err(issue) => Err(issue)
        Ok(None) => Ok(None)
        Ok(Some(value)) => Ok(complete_tree_result(cursor, value))
      }
    }
    VectorMembers(left, right, index, remaining) => {
      if remaining > 0 {
        if !spend_control(control, 1) {
          return Err(Limit)
        }
        cursor.frames[top] = VectorMembers(left, right, index, remaining - 1)
        return Ok(None)
      }
      let lc = @admitted.element_count(left)
      let rc = @admitted.element_count(right)
      if index == Int::min(lc, rc) {
        return Ok(complete_tree_result(cursor, Int::compare(lc, rc)))
      }
      let order = match
        compare(
          Number(@admitted.element_at(left, index).unwrap()),
          Number(@admitted.element_at(right, index).unwrap()),
        ) {
        Ok(value) => value
        Err(issue) => return Err(Scalar(issue))
      }
      if order != 0 {
        return Ok(complete_tree_result(cursor, order))
      }
      cursor.frames[top] = VectorMembers(left, right, index + 1, 0)
      Ok(None)
    }
  }
}
