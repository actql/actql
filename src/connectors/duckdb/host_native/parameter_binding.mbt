///|
/// Native physical binding errors retain the owning Connector's projection
/// failure separately from the environment adapter's observed failure.
pub(all) enum NativeParameterBindingIssue {
  Parameter(@duckdb.ValueIssue)
  Runtime(@native_duckdb.NativeDuckDBIssue)
} derive(Eq, Debug)

///|
/// Bind one Connector-admitted parameter through the native DuckDB adapter.
/// The bridge performs no parsing, coercion, or logical value admission.
pub fn bind_native_parameter(
  query : @native_duckdb.Query,
  index : Int,
  parameter : @duckdb.PhysicalParameter,
) -> Result[Unit, NativeParameterBindingIssue] {
  let binding = match @duckdb.physical_parameter_binding(parameter) {
    Ok(value) => value
    Err(issue) => return Err(Parameter(issue))
  }
  let native = match binding {
    BindNull => @native_duckdb.NullValue
    BindBoolean(value) => @native_duckdb.BooleanValue(value)
    BindDouble(value) => @native_duckdb.DoubleValue(value)
    BindText(value) => @native_duckdb.TextValue(value)
    BindDecimal(coefficient, precision, scale) =>
      @native_duckdb.DecimalValue(coefficient, precision, scale)
    BindDate(days) => @native_duckdb.DateValue(days)
    BindTimestamp(micros) => @native_duckdb.TimestampValue(micros)
  }
  query.bind_parameter(index, native).map_err(issue => Runtime(issue))
}
