///|
priv enum MeanPropertyPhase {
  AwaitMeanSample
  CompareMeanValue
  AddMeanValue
  FinishMeanValue
  AdmitMeanValue
  MeanPropertyTerminal
} derive(Eq)

///|
priv enum MeanPropertyIssue {
  InvalidMeanProperty
  MeanPropertyConflict
  MeanPropertyNull
  MeanPropertyWorkLimit
  MeanPropertyValueLimit
  MeanPropertyArithmetic(@exact.Issue)
  MeanPropertyEquality(@value.CompleteEqualityIssue)
} derive(Eq, Debug)

///|
/// One field of one retained identity. The enclosing Graph owner supplies
/// every ordered occurrence, including zero weights and absent entities.
/// This cursor neither owns its borrowed values nor publishes a Graph.
priv struct MeanProperty {
  strategy : @graph_type.MeanStrategy
  output : @contract.Contract
  limits : @value.Limits
  samples : Int
  mut received : Int
  mut remaining : Int
  mut phase : MeanPropertyPhase
  mut chosen : @value.CheckedValue?
  mut candidate : @value.CheckedValue?
  mut equality : @value.CompleteEquality?
  mut admission : @value.RecheckCursor?
  mut arithmetic : @exact.Mean?
  mut weight : Double
}

///|
priv enum MeanPropertyPoll {
  MeanPropertyNeedsSample(Int)
  MeanPropertyContinue(Int)
  MeanPropertyComplete(@value.CheckedValue, Int)
  MeanPropertyFailed(MeanPropertyIssue, Int)
}

///|
fn start_mean_property(
  strategy : @graph_type.MeanStrategy,
  output : @contract.Contract,
  limits : @value.Limits,
  samples : Int,
  remaining : Int,
  max_bits : Int,
) -> MeanProperty? {
  if samples < 1 ||
    remaining < 0 ||
    limits.max_nodes < 0 ||
    limits.max_depth < 0 ||
    limits.max_text_bytes < 0 {
    return None
  }
  let arithmetic = match strategy {
    @graph_type.EqualValues => None
    @graph_type.WeightedMean(_, _) => {
      if !(output.shape is @contract.Number) || !output.nullable {
        return None
      }
      match @exact.prepare_weighted_mean(max_bits) {
        Ok(mean) => Some(mean)
        Err(_) => return None
      }
    }
  }
  Some({
    strategy,
    output,
    limits,
    samples,
    received: 0,
    remaining,
    phase: AwaitMeanSample,
    chosen: None,
    candidate: None,
    equality: None,
    admission: None,
    arithmetic,
    weight: 0.0,
  })
}

///|
/// None is absence of the entire entity, never a missing declared property.
/// The Graph owner admits each sample before extracting this field.
fn supply_mean_property_sample(
  value : MeanProperty,
  weight : Double,
  property : @value.CheckedValue?,
) -> Result[Unit, MeanPropertyIssue] {
  if value.phase != AwaitMeanSample ||
    value.received >= value.samples ||
    weight < 0.0 ||
    weight.is_nan() ||
    weight.is_inf() {
    return Err(InvalidMeanProperty)
  }
  if value.remaining < 1 {
    return Err(MeanPropertyWorkLimit)
  }
  // Sample admission has its own single control tick, reported by advance.
  // Supplying a sample cannot silently consume the enclosing work meter.
  value.candidate = property
  value.weight = weight
  value.phase = AddMeanValue
  Ok(())
}

///|
fn cleanup_mean_property(value : MeanProperty) -> Unit {
  if value.arithmetic is Some(mean) {
    @exact.cancel_weighted_mean(mean) |> ignore
  }
  if value.admission is Some(cursor) {
    @value.cancel_recheck_runtime_value(cursor)
  }
  value.arithmetic = None
  value.admission = None
  value.equality = None
  value.chosen = None
  value.candidate = None
  value.phase = MeanPropertyTerminal
}

///|
fn mean_property_failed(
  value : MeanProperty,
  issue : MeanPropertyIssue,
  work : Int,
) -> MeanPropertyPoll {
  cleanup_mean_property(value)
  MeanPropertyFailed(issue, work)
}

///|
fn mean_property_next(value : MeanProperty) -> Unit {
  value.candidate = None
  value.received += 1
  value.phase = if value.received == value.samples {
    FinishMeanValue
  } else {
    AwaitMeanSample
  }
}

///|
fn advance_mean_property(
  value : MeanProperty,
  quantum : Int,
) -> MeanPropertyPoll {
  if quantum < 1 || value.phase == MeanPropertyTerminal {
    return MeanPropertyFailed(InvalidMeanProperty, 0)
  }
  let mut work = 0
  while work < quantum {
    if value.phase == AwaitMeanSample {
      return MeanPropertyNeedsSample(work)
    }
    if value.remaining < 1 {
      return mean_property_failed(value, MeanPropertyWorkLimit, work)
    }
    value.remaining -= 1
    work += 1
    match value.phase {
      AddMeanValue => {
        // Zero-weight samples have already been admitted by the Graph owner;
        // their observed NULLs make no property contribution, even for fail.
        if value.weight == 0.0 {
          mean_property_next(value)
          continue
        }
        match value.strategy {
          @graph_type.EqualValues => {
            guard value.candidate is Some(candidate) else {
              mean_property_next(value)
              continue
            }
            if value.chosen is Some(chosen) {
              value.equality = match
                @value.start_complete_equality(chosen, candidate, value.limits) {
                Ok(cursor) => Some(cursor)
                Err(issue) =>
                  return mean_property_failed(
                    value,
                    MeanPropertyEquality(issue),
                    work,
                  )
              }
              value.phase = CompareMeanValue
            } else {
              value.chosen = Some(candidate)
              mean_property_next(value)
            }
          }
          @graph_type.WeightedMean(missing, nulls) => {
            let number = match value.candidate {
              None =>
                match missing {
                  @graph_type.ExcludeMissing => {
                    mean_property_next(value)
                    continue
                  }
                  @graph_type.ZeroMissing => 0.0
                }
              Some({ value: @value.Null, .. }) =>
                match nulls {
                  @graph_type.ExcludeNull => {
                    mean_property_next(value)
                    continue
                  }
                  @graph_type.ZeroNull => 0.0
                  @graph_type.FailNull =>
                    return mean_property_failed(value, MeanPropertyNull, work)
                }
              Some({ value: @value.Number(number), .. }) => number
              _ => return mean_property_failed(value, InvalidMeanProperty, work)
            }
            match
              @exact.add_weighted_value(
                value.arithmetic.unwrap(),
                number,
                value.weight,
              ) {
              Ok(_) => mean_property_next(value)
              Err(issue) =>
                return mean_property_failed(
                  value,
                  MeanPropertyArithmetic(issue),
                  work,
                )
            }
          }
        }
      }
      CompareMeanValue =>
        match @value.advance_complete_equality(value.equality.unwrap(), 1) {
          @value.EqualityContinue(..) => ()
          @value.EqualityComplete(equal~, ..) => {
            value.equality = None
            if !equal {
              return mean_property_failed(value, MeanPropertyConflict, work)
            }
            mean_property_next(value)
          }
          @value.EqualityFailed(issue, ..) =>
            return mean_property_failed(
              value,
              MeanPropertyEquality(issue),
              work,
            )
        }
      FinishMeanValue => {
        let result = match value.strategy {
          @graph_type.EqualValues =>
            match value.chosen {
              Some(chosen) => chosen.value
              None =>
                return mean_property_failed(value, InvalidMeanProperty, work)
            }
          @graph_type.WeightedMean(_, _) => {
            let result = @exact.finish_weighted_mean(value.arithmetic.unwrap())
            value.arithmetic = None
            match result {
              Ok(number) =>
                match @value.number_value(number) {
                  Some(number) => number
                  None =>
                    return mean_property_failed(
                      value,
                      InvalidMeanProperty,
                      work,
                    )
                }
              Err(@exact.ZeroDenominator) => @value.null_value()
              Err(issue) =>
                return mean_property_failed(
                  value,
                  MeanPropertyArithmetic(issue),
                  work,
                )
            }
          }
        }
        value.admission = @value.start_recheck_runtime_value(
          result,
          value.output,
          value.limits,
        )
        if value.admission is None {
          return mean_property_failed(value, MeanPropertyValueLimit, work)
        }
        value.phase = AdmitMeanValue
      }
      AdmitMeanValue =>
        match @value.advance_recheck_runtime_value(value.admission.unwrap()) {
          @value.RecheckContinue => ()
          @value.RecheckComplete(result, _, _) => {
            cleanup_mean_property(value)
            return MeanPropertyComplete(result, work)
          }
          @value.RecheckFailed =>
            return mean_property_failed(value, MeanPropertyValueLimit, work)
        }
      AwaitMeanSample | MeanPropertyTerminal =>
        return mean_property_failed(value, InvalidMeanProperty, work)
    }
  }
  MeanPropertyContinue(work)
}
