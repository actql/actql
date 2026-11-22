///|
// Lower the longest prefix first so every original grouping key is checked
// and first appears in the result in its normal position. Other branches use
// the same aggregate bodies and the exact same input snapshot.
fn append_rollup_groups(
  construction : Construction,
  steps : Array[Array[(String, @builder.Node)]],
  entries : Array[(String, @builder.Node)],
  input_from : String,
  names : Array[String],
  reserved : Array[String],
  ends : Array[Int],
  introductions : Array[Int],
  key_names : Array[String],
  by : Array[@builder.Node],
  aggregates : Array[(String, @builder.Node)],
  work : Int,
) -> Unit raise Abort {
  // Each prefix visits the retained keys and aggregate entries once. Use
  // division to refuse oversized expansion before constructing its arrays.
  let width = by.length() + aggregates.length() + 1
  if ends.length() >= work / width {
    raise Abort(
      Expression({
        issue: @expression.WorkLimit,
        origin: Some(construction.generated),
      }),
    )
  }
  let taken : Map[String, Bool] = Map([])
  for candidate in names {
    taken[ascii_upper(candidate)] = true
  }
  let mut serial = names.length()
  let name = fn() {
    let mut value = "aql_rollup_" + serial.to_string()
    while taken.contains(ascii_upper(value)) {
      serial += 1
      value = "aql_rollup_" + serial.to_string()
    }
    serial += 1
    reserved.push(value)
    value
  }
  let input = if !entries.is_empty() {
    // The ordinary Group would take the original explicit FROM here.
    entries.clear()
    input_from
  } else {
    let captured = name()
    if steps.last() is Some(previous) && !previous.any(entry => entry.0 == "as") {
      previous.push(("as", construction.text(captured)))
    } else {
      // Keep an already named step and its existing consumer intact.
      steps.push([
        (
          "filter",
          construction.object([("literal", construction.add(Bool(true)))]),
        ),
        ("as", construction.text(captured)),
      ])
    }
    captured
  }
  // A filtered-out original field is never demanded. The ordinary AnyValue
  // result still carries its original shape, made nullable, even on empty input.
  let never = construction.object([("literal", construction.add(Bool(false)))])
  let missing = Array::makei(key_names.length(), index => {
    let key = key_names[index]
    (
      key,
      construction.object([
        ("fn", construction.text("any_value")),
        ("field", by[index]),
        ("filter", never),
      ]),
    )
  })
  let mut previous = ""
  for level = ends.length(); level >= 0; level = level - 1 {
    let end = if level == 0 { 0 } else { ends[level - 1] }
    let keys : Array[@builder.Node] = []
    let outputs = aggregates.copy()
    for index in 0..<introductions.length() {
      if introductions[index] < end {
        keys.push(by[index])
      } else {
        outputs.push(missing[index])
      }
    }
    let branch = name()
    steps.push([
      ("from", construction.text(input)),
      (
        "group",
        construction.object([
          ("by", construction.array(keys)),
          ("aggregates", construction.object(outputs)),
        ]),
      ),
      ("as", construction.text(branch)),
    ])
    if previous == "" {
      previous = branch
    } else {
      let append = [
        ("from", construction.text(previous)),
        ("append", construction.object([("with", construction.text(branch))])),
      ]
      if level == 0 {
        entries.append(append)
      } else {
        previous = name()
        append.push(("as", construction.text(previous)))
        steps.push(append)
      }
    }
  }
}
