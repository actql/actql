///|
pub(all) enum AggregateFunction {
  Count
  CountIf
  Sum
  Avg
  Min
  Max
  ArrayAgg
  StringAgg
  First
  Last
  PercentileDisc
  PercentileCont
  VarPop
  VarSamp
  StddevPop
  StddevSamp
} derive(Eq, Debug)

///|
pub enum AggregateArgument {
  Field(KeyField)
  // Index in the containing operation's bindings, not a shared evaluation slot.
  Expression(Int)
  Rows
}

///|
pub(all) enum FractionValue {
  Fraction(Double)
  ParameterFraction(String)
} derive(Eq, Debug)

///|
struct CheckedAggregate {
  name : String
  source : @decode.Cursor
  function : AggregateFunction
  argument : AggregateArgument
  filter : Int?
  result : @contract.Contract
  distinct : Bool?
  order : Array[OrderTerm]
  item_limit : CountValue?
  byte_limit : CountValue?
  delimiter : String?
  fraction : FractionValue?
}

///|
struct CheckedGroup {
  keys : Array[KeyField]
  aggregates : Array[CheckedAggregate]
  validation_aggregates : Map[Int, Int]
}

///|
/// Owned aggregate for an operation-local pending-validation index.
/// Group-wide requirements and out-of-range indices have no aggregate owner.
pub fn aggregate_for_validation(
  value : CheckedGroup,
  index : Int,
) -> CheckedAggregate? {
  match value.validation_aggregates.get(index) {
    Some(i) => value.aggregates.get(i)
    None => None
  }
}

///|
pub fn group(value : CheckedOperation) -> CheckedGroup? {
  value.group
}

///|
pub fn group_keys(value : CheckedGroup) -> Array[KeyField] {
  value.keys.copy()
}

///|
pub fn aggregate_count(value : CheckedGroup) -> Int {
  value.aggregates.length()
}

///|
pub fn aggregate_at(value : CheckedGroup, index : Int) -> CheckedAggregate? {
  if index < 0 || index >= value.aggregates.length() {
    None
  } else {
    Some(value.aggregates[index])
  }
}

///|
pub fn aggregate_name(value : CheckedAggregate) -> String {
  value.name
}

///|
pub fn aggregate_source(value : CheckedAggregate) -> @decode.Cursor {
  value.source
}

///|
pub fn aggregate_function(value : CheckedAggregate) -> AggregateFunction {
  value.function
}

///|
pub fn aggregate_argument(value : CheckedAggregate) -> AggregateArgument {
  value.argument
}

///|
pub fn aggregate_filter(value : CheckedAggregate) -> Int? {
  value.filter
}

///|
pub fn aggregate_result(value : CheckedAggregate) -> @contract.Contract {
  value.result
}

///|
pub fn aggregate_distinct(value : CheckedAggregate) -> Bool? {
  value.distinct
}

///|
pub fn aggregate_order(value : CheckedAggregate) -> Array[OrderTerm] {
  value.order.copy()
}

///|
pub fn aggregate_order_count(value : CheckedAggregate) -> Int {
  value.order.length()
}

///|
pub fn aggregate_order_at(value : CheckedAggregate, index : Int) -> OrderTerm? {
  value.order.get(index)
}

///|
pub fn aggregate_item_limit(value : CheckedAggregate) -> CountValue? {
  value.item_limit
}

///|
pub fn aggregate_byte_limit(value : CheckedAggregate) -> CountValue? {
  value.byte_limit
}

///|
pub fn aggregate_delimiter(value : CheckedAggregate) -> String? {
  value.delimiter
}

///|
pub fn aggregate_fraction(value : CheckedAggregate) -> FractionValue? {
  value.fraction
}

///|
fn aggregate_function_name(
  source : @decode.Cursor,
) -> AggregateFunction raise Stop {
  let name = decoded(@decode.text(source), source)
  match name {
    "count" => Count
    "count_if" => CountIf
    "sum" => Sum
    "avg" => Avg
    "min" => Min
    "max" => Max
    "array_agg" => ArrayAgg
    "string_agg" => StringAgg
    "first" => First
    "last" => Last
    "percentile_disc" => PercentileDisc
    "percentile_cont" => PercentileCont
    "var_pop" => VarPop
    "var_samp" => VarSamp
    "stddev_pop" => StddevPop
    "stddev_samp" => StddevSamp
    _ => fail(source, InvalidAggregate(name))
  }
}

///|
fn aggregate_domain(function : AggregateFunction) -> @typing.ArgumentDomain? {
  match function {
    CountIf => Some(BooleanArgument)
    Avg | PercentileCont | VarPop | VarSamp | StddevPop | StddevSamp =>
      Some(NumberArgument)
    StringAgg => Some(StringArgument)
    _ => None
  }
}

///|
fn aggregate_constructible(
  b : Budget,
  source : @decode.Cursor,
  root : @contract.Contract,
) -> Unit raise Stop {
  let work = [(root, 0)]
  while work.pop() is Some((c, depth)) {
    spend(b, source)
    if depth > b.limits.max_depth {
      fail(source, BudgetExceeded)
    }
    match c.shape {
      @contract.Json | @contract.ResourceRef(..) | @contract.ArtifactRef(..) =>
        fail(source, ForbiddenAggregateValue)
      @contract.Array(item, ..) => work.push((item, depth + 1))
      @contract.Object(fields) =>
        for i in 0..<@contract.field_count(fields) {
          spend(b, source)
          work.push(
            (@contract.field_at(fields, i).unwrap().contract, depth + 1),
          )
        }
      _ => ()
    }
  }
}

///|
fn aggregate_output(
  b : Budget,
  source : @decode.Cursor,
  function : AggregateFunction,
  input : @contract.Contract?,
) -> @contract.Contract raise Stop {
  if function is Count {
    return @contract.primitive(NumberType, nullable=false)
  }
  let c = input.unwrap()
  let valid = match function {
    CountIf => c.shape is @contract.Boolean
    Sum => c.shape is @contract.Number || c.shape is @contract.Decimal(..)
    Avg | PercentileCont | VarPop | VarSamp | StddevPop | StddevSamp =>
      c.shape is @contract.Number
    Min | Max | PercentileDisc => @order.author_orderable(c)
    StringAgg => c.shape is @contract.Text(_)
    _ => true
  }
  if !valid {
    fail(source, InvalidAggregateArgument("input domain"))
  }
  match function {
    Count | CountIf => @contract.primitive(NumberType, nullable=false)
    Sum =>
      match c.shape {
        @contract.Decimal(scale~, ..) =>
          @contract.decimal_contract(38, scale, nullable=true).unwrap()
        _ => @contract.primitive(NumberType, nullable=true)
      }
    Avg | PercentileCont | VarPop | VarSamp | StddevPop | StddevSamp =>
      @contract.primitive(NumberType, nullable=true)
    ArrayAgg => {
      aggregate_constructible(b, source, c)
      @contract.array_contract(
        @contract.with_nullability(c, false),
        nullable=false,
      ).unwrap()
    }
    StringAgg => @contract.primitive(StringType, nullable=true)
    _ => @contract.with_nullability(c, true)
  }
}

///|
fn aggregate_fraction_value(
  b : Budget,
  source : @decode.Cursor,
  parameters : Map[String, @contract.Contract],
  pending : Array[PendingValidation],
) -> FractionValue raise Stop {
  spend(b, source)
  match @decode.view(source) {
    NumberValue(n) => {
      if n.is_nan() ||
        n.is_inf() ||
        (n == 0.0 && 1.0 / n < 0.0) ||
        n < 0.0 ||
        n > 1.0 {
        fail(source, InvalidAggregateOption("fraction"))
      }
      Fraction(n)
    }
    _ => {
      let obj = decoded(@decode.closed_object(source, ["$param"]), source)
      let s = decoded(@decode.required(obj, "$param"), source)
      let name = decoded(@decode.text(s), s)
      charge(b, s, name)
      let c = match parameters.get(name) {
        Some(c) => c
        None => fail(s, UnknownParameter(name))
      }
      if !(c.shape is @contract.Number) {
        fail(s, InvalidAggregateOption("fraction"))
      }
      pending.push({ kind: BoundFraction(name), source, })
      ParameterFraction(name)
    }
  }
}

///|
// Each call retains its own filter and argument bindings. Inference visits both;
// execution demand still belongs to the filter, not to this static traversal.
fn check_aggregate(
  b : Budget,
  name : String,
  source : @decode.Cursor,
  visible : Map[String, (@contract.Contract, ReferenceTarget)],
  parameters : @parameter.Declarations?,
  parameter_types : Map[String, @contract.Contract],
  bindings : Array[Binding],
  pending : Array[PendingValidation],
  analytic? : Bool = false,
) -> CheckedAggregate raise Stop {
  spend(b, source)
  let obj = decoded(
    @decode.closed_object(source, [
      "fn", "field", "expr", "filter", "distinct", "order_by", "max_items", "max_bytes",
      "delimiter", "fraction",
    ]),
    source,
  )
  let function = aggregate_function_name(
    decoded(@decode.required(obj, "fn"), source),
  )
  let ordered = match function {
    ArrayAgg | StringAgg | First | Last => true
    _ => false
  }
  for option in ["order_by", "max_items", "max_bytes", "delimiter", "fraction"] {
    if @decode.lookup(obj, option) is Some(s) {
      let allowed = match option {
        "order_by" => ordered && !analytic
        "max_items" => function is ArrayAgg
        "max_bytes" | "delimiter" => function is StringAgg
        "fraction" => function is PercentileDisc || function is PercentileCont
        _ => false
      }
      if !allowed {
        fail(s, InvalidAggregateOption(option))
      }
    }
  }
  let filter = match @decode.lookup(obj, "filter") {
    None => None
    Some(s) => {
      let binding = expression(b, s, None, visible, parameters)
      if !(@typing.result_type(binding.expression).shape is @contract.Boolean) {
        fail(s, ExpectedBoolean)
      }
      let index = bindings.length()
      bindings.push(binding)
      Some(index)
    }
  }
  let (argument, input, input_source) = match
    (@decode.lookup(obj, "field"), @decode.lookup(obj, "expr")) {
    (Some(s), None) => {
      let name = decoded(@decode.text(s), s)
      let field = input_reference(b, s, name, visible)
      (
        AggregateArgument::Field({ field, source: s, }),
        Some(visible.get(name).unwrap().0),
        s,
      )
    }
    (None, Some(s)) => {
      let binding = expression(
        b,
        s,
        None,
        visible,
        parameters,
        argument_domain=aggregate_domain(function),
      )
      let index = bindings.length()
      let c = @typing.result_type(binding.expression)
      bindings.push(binding)
      (AggregateArgument::Expression(index), Some(c), s)
    }
    (None, None) => {
      if !(function is Count) {
        fail(source, InvalidAggregateArgument("missing argument"))
      }
      (AggregateArgument::Rows, None, source)
    }
    _ =>
      fail(
        source,
        InvalidAggregateArgument("field and expr are mutually exclusive"),
      )
  }
  let distinct = match @decode.lookup(obj, "distinct") {
    None => None
    Some(s) => {
      let value = match @decode.view(s) {
        BoolValue(v) => v
        _ => fail(s, InvalidAggregateOption("distinct"))
      }
      let allowed = match function {
        Count => !value || !(argument is Rows)
        Sum | Avg | ArrayAgg | StringAgg => true
        Min | Max => !value
        _ => false
      }
      if !allowed {
        fail(s, InvalidAggregateOption("distinct"))
      }
      Some(value)
    }
  }
  let order = if ordered && !analytic {
    let s = decoded(@decode.required(obj, "order_by"), source)
    let terms = row_order(b, s, visible)
    if terms.is_empty() {
      fail(s, InvalidOrder)
    }
    pending.push({ kind: SortOrderCompletion, source: s, })
    terms
  } else {
    []
  }
  let item_limit = @decode.lookup(obj, "max_items").map(s => {
    row_count(b, s, 1L, parameter_types, pending)
  })
  let byte_limit = @decode.lookup(obj, "max_bytes").map(s => {
    row_count(b, s, 1L, parameter_types, pending)
  })
  let delimiter = if function is StringAgg {
    let s = decoded(@decode.required(obj, "delimiter"), source)
    Some(decoded(@decode.text(s), s))
  } else {
    None
  }
  let fraction = if function is PercentileDisc || function is PercentileCont {
    Some(
      aggregate_fraction_value(
        b,
        decoded(@decode.required(obj, "fraction"), source),
        parameter_types,
        pending,
      ),
    )
  } else {
    None
  }
  let result = aggregate_output(b, input_source, function, input)
  pending.push({ kind: AggregateDemand, source, })
  pending.push({ kind: AggregateEnvelope, source, })
  if (function is Sum || function is Avg) &&
    input is Some({ shape: @contract.Number, .. }) {
    pending.push({ kind: NumericAggregateObservation, source, })
  }
  match function {
    PercentileCont | VarPop | VarSamp | StddevPop | StddevSamp =>
      pending.push({ kind: StatisticalAggregateLaw, source, })
    _ => ()
  }
  {
    name,
    source,
    function,
    argument,
    filter,
    result,
    distinct,
    order,
    item_limit,
    byte_limit,
    delimiter,
    fraction,
  }
}

///|
fn check_group(
  b : Budget,
  source : @decode.Cursor,
  visible : Map[String, (@contract.Contract, ReferenceTarget)],
  parameters : @parameter.Declarations?,
  parameter_types : Map[String, @contract.Contract],
  bindings : Array[Binding],
  pending : Array[PendingValidation],
  prefix : Array[@schema.FieldName],
) -> (CheckedGroup, Array[(@schema.FieldName, @contract.Contract)]) raise Stop {
  let obj = decoded(@decode.closed_object(source, ["by", "aggregates"]), source)
  let authored = row_keys(
    b,
    decoded(@decode.required(obj, "by"), source),
    visible,
    unique=false,
  )
  let keys : Array[KeyField] = []
  let prefixed : Map[String, Bool] = Map([])
  spend(b, source, count=prefix.length())
  for field in prefix {
    let name = @schema.reference_name(field)
    let resolved = input_reference(b, source, name, visible)
    if resolved != field {
      fail(source, UnknownField(name))
    }
    let ty = visible.get(name).unwrap().0
    if !@contract.key_comparable(ty, ty) {
      fail(source, NotKeyComparable(name))
    }
    if !prefixed.contains(name) {
      prefixed[name] = true
      keys.push({ field, source, })
    }
  }
  for key in authored {
    spend(b, key.source)
    if !prefixed.contains(@schema.reference_name(key.field)) {
      keys.push(key)
    }
  }
  pending.push({ kind: GroupPartitioning, source, })
  let fields : Array[(@schema.FieldName, @contract.Contract)] = []
  let seen : Map[String, Bool] = Map([])
  for key in keys {
    spend(b, key.source)
    let name = @schema.reference_name(key.field)
    if !seen.contains(name) {
      seen[name] = true
      fields.push((key.field, visible.get(name).unwrap().0))
    }
  }
  let s = decoded(@decode.required(obj, "aggregates"), source)
  let aggs = decoded(@decode.open_object(s), s)
  let names = decoded(@decode.object_field_names(s), s)
  spend(b, s, count=names.length())
  names.sort_by(@canonical.compare_utf16)
  let aggregates : Array[CheckedAggregate] = []
  let validation_aggregates : Map[Int, Int] = Map([])
  for name in names {
    let call = @decode.lookup(aggs, name).unwrap()
    field_name(b, call, name)
    if seen.contains(name) {
      fail(call, DuplicateOutput(name))
    }
    seen[name] = true
    let validation_start = pending.length()
    let checked = check_aggregate(
      b, name, call, visible, parameters, parameter_types, bindings, pending,
    )
    spend(b, call, count=pending.length() - validation_start)
    for index in validation_start..<pending.length() {
      validation_aggregates[index] = aggregates.length()
    }
    fields.push((@schema.Unqualified(name), checked.result))
    aggregates.push(checked)
  }
  ({ keys, aggregates, validation_aggregates, }, fields)
}

///|
/// Check a group with explicit additional leading keys. This validates grouping
/// types only; it does not establish window-role evidence for the caller.
pub fn check_group_with_prefix(
  body : @decode.Cursor,
  input : @schema.Schema,
  prefix : Array[@schema.FieldName],
  parameters : @parameter.Declarations?,
  limits : Limits,
) -> Result[CheckedOperation, Issue] {
  Ok(check_impl(Group, body, input, parameters, limits, group_prefix=prefix)) catch {
    Stop(issue) => Err(issue)
  }
}
