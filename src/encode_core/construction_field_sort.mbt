///|
pub fn construction_work_active(writer : Writer) -> Bool {
  writer.output is WorkGeometryOutput(_, _, _) ||
  writer.output is WorkTextOutput(_, _) ||
  writer.output is WorkHashOutput(_, _) ||
  writer.output is WorkCompareOutput(_, _)
}

///|
fn construction_field_order(
  writer : Writer,
  left : String,
  right : String,
) -> Int raise EncodeFailure {
  construction_work_step(writer, left.length())
  construction_work_step(writer, right.length())
  let count = Int::min(left.length(), right.length())
  for index in 0..<count {
    if left[index] < right[index] {
      return -1
    }
    if left[index] > right[index] {
      return 1
    }
  }
  if left.length() < right.length() {
    -1
  } else if left.length() > right.length() {
    1
  } else {
    0
  }
}

///|
fn[T] sift_construction_fields(
  values : Array[(String, T)],
  start : Int,
  end : Int,
  writer : Writer,
) -> Unit raise EncodeFailure {
  let mut root = start
  while root < end / 2 {
    construction_work_step(writer, 1)
    let mut child = 2 * root + 1
    if child + 1 < end &&
      construction_field_order(writer, values[child].0, values[child + 1].0) < 0 {
      child += 1
    }
    if construction_field_order(writer, values[root].0, values[child].0) >= 0 {
      break
    }
    let saved = values[root]
    values[root] = values[child]
    values[child] = saved
    root = child
  }
}

///|
// Only the private funded dependency emission uses this in-place heap sort.
// Its array was funded from actual census fields before creation. No sort
// scratch, owned keys, comparator callbacks or external current calls occur.
// Legacy emitters keep their original sort. Every compared span/heap step is
// debited on the SAME original Work before it is read, including refusal.
pub fn[T] sort_construction_fields(
  values : Array[(String, T)],
  writer : Writer,
) -> Unit raise EncodeFailure {
  if !construction_work_active(writer) {
    raise OutputLimit
  }
  let count = values.length()
  for start = count / 2 - 1; start >= 0; start = start - 1 {
    sift_construction_fields(values, start, count, writer)
  }
  for end = count - 1; end > 0; end = end - 1 {
    construction_work_step(writer, 1)
    let saved = values[0]
    values[0] = values[end]
    values[end] = saved
    sift_construction_fields(values, 0, end, writer)
  }
}
