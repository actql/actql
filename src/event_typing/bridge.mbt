///|
pub fn check_bridge(
  source : @decode.Cursor,
  input : @carrier.Carrier,
  limits : Limits,
) -> Result[CheckedEvent, Issue] {
  try {
    if limits.max_work < 0 ||
      limits.max_nodes < 0 ||
      limits.max_depth < 0 ||
      limits.max_text_bytes < 0 {
      fail(source, InvalidLimits)
    }
    let b : Budget = {
      limits,
      work: limits.max_work,
      nodes: limits.max_nodes,
      text: limits.max_text_bytes,
    }
    scan(b, source)
    guard @carrier.relation_rows(input) is Some(records) else {
      fail(source, WrongCarrier(@carrier.kind(input)))
    }
    let object = decoded(@decode.closed_object(source, ["id", "time"]))
    let id_source = decoded(@decode.required(object, "id"))
    let time_source = decoded(@decode.required(object, "time"))
    let id = role_name(id_source)
    let time = role_name(time_source)
    spend(b, source, 2)
    let output = match @carrier.events(records, id~, time~) {
      Ok(c) => c
      Err(e) => {
        let at = match e {
          UnknownRole(name) | InvalidRole(name) | DuplicateRole(name) =>
            if name == time {
              time_source
            } else {
              id_source
            }
          _ => source
        }
        fail(at, InvalidRole(e))
      }
    }
    Ok({
      source,
      input,
      output,
      options: ToEvents,
      usage: {
        work: limits.max_work - b.work,
        nodes: limits.max_nodes - b.nodes,
        text_bytes: limits.max_text_bytes - b.text,
      },
    })
  } catch {
    Stop(e) => Err(e)
  }
}
