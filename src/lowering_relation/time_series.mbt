///|
/// Bound, typed execution parameters for one finite time-series occurrence.
/// This is lowering material, not an execution permit or published result.
struct PreparedTimeSeries {
  node : PreparedNode
  start : String
  end : String
  step : Int64
  row_count : Int
}

///|
pub(all) enum TimeSeriesIssue {
  InvalidTimeSeriesLimits
  InvalidTimeSeriesWiring
  TimeSeriesPreparationLimit
  MissingTimeSeriesParameter(String)
  InvalidTimeSeriesParameter(String)
  InvalidTimeSeriesRange
} derive(Eq, Debug)

///|
fn resolve_time_series_endpoint(
  owner : BoundPrepared,
  endpoint : @series.Endpoint,
) -> Result[(String, @value.CheckedValue?, Int, Int), TimeSeriesIssue] {
  match endpoint {
    @series.Literal(text) => Ok((text, None, 0, 0))
    @series.Parameter(name) => {
      guard parameter_value(owner, name) is Some(bound) else {
        return Err(MissingTimeSeriesParameter(name))
      }
      guard bound.value is @value.Timestamp(text) else {
        return Err(InvalidTimeSeriesParameter(name))
      }
      Ok((text, Some(bound), 1, @utf8.encode(name).length()))
    }
  }
}

///|
fn resolve_time_series_step(
  owner : BoundPrepared,
  value : @window.Milliseconds,
) -> Result[(Int64, Int64?, Int, Int), TimeSeriesIssue] {
  match value {
    @window.Literal(step) => Ok((step, None, 0, 0))
    @window.Parameter(name, duration~, domain~) => {
      guard parameter_value(owner, name) is Some(bound) else {
        return Err(MissingTimeSeriesParameter(name))
      }
      let step = if duration {
        match bound.value {
          @value.Text(text) => @scalar.read_duration_ms(text)
          _ => None
        }
      } else {
        match bound.value {
          @value.Number(number) => @scalar.read_safe_integer(number)
          _ => None
        }
      }
      guard step is Some(step) &&
        domain == @window.PositiveMilliseconds &&
        step > 0L else {
        return Err(InvalidTimeSeriesParameter(name))
      }
      Ok((step, Some(step), 1, @utf8.encode(name).length()))
    }
  }
}

///|
fn prepare_time_series_node(
  owner : BoundPrepared,
  node : PreparedNode,
  max_rows~ : Int,
  max_cells~ : Int,
  max_bindings~ : Int,
  max_name_bytes~ : Int,
  max_work~ : Int,
) -> Result[(PreparedTimeSeries, Int, Int, Int), TimeSeriesIssue] {
  if max_rows < 0 ||
    max_cells < 0 ||
    max_bindings < 0 ||
    max_name_bytes < 0 ||
    max_work < 0 {
    return Err(InvalidTimeSeriesLimits)
  }
  guard node.payload is TimeSeriesValue(checked) && node.inputs.is_empty() else {
    return Err(InvalidTimeSeriesWiring)
  }
  let (start, start_value, start_bindings, start_names) = match
    resolve_time_series_endpoint(owner, @series.start(checked)) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let (end, end_value, end_bindings, end_names) = match
    resolve_time_series_endpoint(owner, @series.end(checked)) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let (step, step_value, step_bindings, step_names) = match
    resolve_time_series_step(owner, @series.step(checked)) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let bindings = start_bindings + end_bindings + step_bindings
  let names = start_names + end_names + step_names
  let work = 4
  if bindings > max_bindings || names > max_name_bytes || work > max_work {
    return Err(TimeSeriesPreparationLimit)
  }
  let row_count = match
    @series.resolve_row_count(checked, start_value~, end_value~, step_value~) {
    Ok(value) => value
    Err(_) => return Err(InvalidTimeSeriesRange)
  }
  if row_count < 0L ||
    row_count > max_rows.to_int64() ||
    row_count > max_cells.to_int64() {
    return Err(TimeSeriesPreparationLimit)
  }
  Ok(
    (
      { node, start, end, step, row_count: row_count.to_int(), },
      bindings,
      names,
      work,
    ),
  )
}

///|
pub fn time_series_start(value : PreparedTimeSeries) -> String {
  value.start
}

///|
pub fn time_series_end(value : PreparedTimeSeries) -> String {
  value.end
}

///|
pub fn time_series_step(value : PreparedTimeSeries) -> Int64 {
  value.step
}

///|
pub fn time_series_row_count(value : PreparedTimeSeries) -> Int {
  value.row_count
}

///|
fn emit_time_series_node(
  prepared : PreparedTimeSeries,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(out)
  @encode.key(out, "id")
  @encode.string_value(out, prepared.node.id)
  @encode.key(out, "in")
  @encode.begin_array(out)
  @encode.end_array(out)
  @encode.key(out, "op")
  @encode.string_value(out, "TEA.time_series")
  @encode.key(out, "params")
  @encode.begin_object(out)
  @encode.key(out, "end")
  @encode.string_value(out, prepared.end)
  @encode.key(out, "start")
  @encode.string_value(out, prepared.start)
  @encode.key(out, "step")
  @encode.number_value(out, prepared.step.to_double())
  @encode.end_object(out)
  @encode.end_object(out)
}
