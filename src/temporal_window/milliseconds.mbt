///|
struct CheckedMilliseconds {
  value : Milliseconds
  usage : Usage
}

///|
/// Bounded scalar option admission shared by temporal operations. The source
/// and declaration names are charged here; defaults are never bound or read.
pub fn read_milliseconds(
  source : @decode.Cursor,
  domain : Domain,
  parameters : @parameter.Declarations?,
  limits : Limits,
) -> Result[CheckedMilliseconds, Issue] {
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
    let params : Map[String, @contract.ParameterType] = Map([])
    if parameters is Some(ds) {
      let n = @parameter.declaration_count(ds)
      spend(b, source, n)
      for i in 0..<n {
        let d = @parameter.declaration_at(ds, i).unwrap()
        charge(b, source, d.name)
        params[d.name] = d.parameter_type
      }
    }
    let value = read_ms(source, domain, params)
    Ok({
      value,
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

///|
pub fn milliseconds_value(v : CheckedMilliseconds) -> Milliseconds {
  v.value
}

///|
pub fn milliseconds_usage(v : CheckedMilliseconds) -> Usage {
  v.usage
}
