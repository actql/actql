///|
// Authored field coverage only. A template still needs its actual JoinRight
// consumers; neither form grants completeness, capacity or execution authority.
pub(all) enum RequestForm {
  DirectForm
  KeyedTemplate
} derive(Eq, Debug)

///|
pub(all) enum RequestFormIssue {
  InvalidLimits
  ForeignRequests
  WorkLimit
  PartialCorrelation
} derive(Eq, Debug)

///|
struct RequestFormCheck {
  context : RequestContext
  input : ResolvedInput
  form : RequestForm
  work : Int
}

///|
fn classify_authored_request_form(
  context : RequestContext,
  input : ResolvedInput,
  b : Budget,
  index : Int,
) -> RequestForm raise AcquisitionStop {
  let correlation = @environment.source_request_correlation(
    input.selected.contract,
  )
  if correlation is Some(c) {
    let reserved : Map[String, Bool] = Map([])
    let count = @environment.source_correlation_pair_count(c)
    for j in 0..<count {
      let name = @environment.source_correlation_pair_at(c, j).unwrap().request.name
      acquisition_charge(b, 1)
      acquisition_charge(b, name.length())
      reserved[name] = true
    }
    acquisition_charge(b, input.declaration.input_name.length())
    let fields = context.fields
      .get((input.declaration.stage_index, input.declaration.input_name))
      .unwrap_or([])
    let mut present = 0
    for field in fields {
      acquisition_charge(b, 1)
      acquisition_charge(b, field.field_name.length())
      if reserved.contains(field.field_name) {
        present += 1
      }
    }
    if present != 0 && present != count {
      raise AcquisitionStop(PartialCorrelation(index))
    }
    if present == 0 {
      return KeyedTemplate
    }
  }
  DirectForm
}

///|
// Reuse the acquisition Owner's exact field-coverage classification. The
// original RequestContext/selected input stay nominally bound. Final request
// value admission, mode selection and actual consumer checks are separate.
pub fn check_request_form(
  context : RequestContext,
  input : ResolvedInput,
  max_work : Int,
) -> Result[RequestFormCheck, RequestFormIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  if !physical_equal(context.resolved.owner, input.owner) {
    return Err(ForeignRequests)
  }
  let b = { work: max_work, }
  try {
    let form = classify_authored_request_form(context, input, b, 0)
    Ok({ context, input, form, work: max_work - b.work, })
  } catch {
    AcquisitionStop(WorkLimit) => Err(WorkLimit)
    AcquisitionStop(PartialCorrelation(_)) => Err(PartialCorrelation)
    AcquisitionStop(_) => abort("unexpected authored request form error")
  }
}

///|
pub fn request_form(v : RequestFormCheck) -> RequestForm {
  v.form
}

///|
pub fn request_form_context(v : RequestFormCheck) -> RequestContext {
  v.context
}

///|
pub fn request_form_input(v : RequestFormCheck) -> ResolvedInput {
  v.input
}

///|
pub fn request_form_work(v : RequestFormCheck) -> Int {
  v.work
}
