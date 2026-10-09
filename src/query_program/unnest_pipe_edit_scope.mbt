///|
// A value table owns one column; its implicitly exposed object members are
// expression/star names, not SET/DROP/RENAME column targets.
fn unnest_edit_columns(
  visible : Array[(String, String)],
  ranges : Array[(@query.NamePart, Array[(String, String)])],
  receivers : Array[(@query.NamePart, String)],
) -> Array[(String, String)] {
  let result = visible.filter(entry => {
    !receivers.any(receiver => {
      ranges.any(range => {
        same_name(range.0, receiver.0) &&
        range.1.any(field => field.1 == entry.1)
      })
    })
  })
  result.append(receivers.map(receiver => (receiver.0.value, receiver.1)))
  result
}

///|
// Apply edits to the public star layout, without changing original values.
// Replacing a whole value table makes one ordinary column at its old position.
// Dropping it removes every implicitly exposed member. Edits to other columns
// exclude same-named implicit members, while surviving ranges retain them.
fn unnest_edit_visible(
  visible : Array[(String, String)],
  ranges : Array[(@query.NamePart, Array[(String, String)])],
  receivers : Array[(@query.NamePart, String)],
  physical : Array[String],
  edits : Array[(String, String?)],
) -> Array[(String, String)] {
  let result : Array[(String, String)] = []
  let emitted : Array[String] = []
  for current in visible {
    let owners = receivers.filter(receiver => {
      ranges.any(range => {
        same_name(range.0, receiver.0) &&
        range.1.any(field => field.1 == current.1)
      })
    })
    let whole = edits.filter(edit => {
      owners.any(owner => same_name(owner.0, { value: edit.0, quoted: false, }))
    })
    if !whole.is_empty() {
      for edit in whole {
        if !emitted.contains(edit.0) {
          if edit.1 is Some(slot) {
            result.push((owners[0].0.value, slot))
          }
          emitted.push(edit.0)
        }
      }
      continue
    }
    let matching = edits.filter(edit => {
      same_name({ value: current.0, quoted: false, }, {
        value: edit.0,
        quoted: false,
      })
    })
    if matching.is_empty() {
      result.push(current)
    } else if owners.is_empty() {
      if matching[0].1 is Some(slot) {
        result.push((current.0, slot))
      }
    }
  }
  // An empty object has no star members. Locate its value slot among the
  // original physical slots so that an OFFSET/parent column stays in order.
  for receiver in receivers {
    let matching = edits.filter(edit => {
      same_name(receiver.0, { value: edit.0, quoted: false, })
    })
    if matching.is_empty() || emitted.contains(matching[0].0) {
      continue
    }
    if matching[0].1 is Some(slot) {
      let mut receiver_at = physical.length()
      for index in 0..<physical.length() {
        if physical[index] == receiver.1 {
          receiver_at = index
        }
      }
      let mut insertion = result.length()
      for index in 0..<result.length() {
        let mut column_at = physical.length()
        for physical_index in 0..<physical.length() {
          if physical[physical_index] == result[index].1 {
            column_at = physical_index
          }
        }
        if column_at > receiver_at {
          insertion = index
          break
        }
      }
      result.insert(insertion, (receiver.0.value, slot))
    }
  }
  result
}
