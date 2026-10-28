///|
/// Original check_with_evidence boundaries. These are compiler DATA states,
/// never Resource grants or permission observations.
pub(all) enum PipelineEvidenceReadPhase {
  Carriers
  Keys
  Rankings
  Core
  Complete
  Failed
  Taken
  Cleared
} derive(Eq, Debug)

///|
priv enum PipelineEvidenceStep {
  Carriers
  Keys(Array[(String, @carrier.Carrier)])
  Rankings(Array[(String, @carrier.Carrier)], Array[@evidence.KeySet?])
  Core(
    Array[(String, @carrier.Carrier)],
    Array[@evidence.KeySet?],
    Array[@vector.RankingInput?]
  )
}

///|
priv struct PipelineEvidenceBody {
  source : @decode.Cursor
  inputs : Array[(String, InputContract)]
  parameters : @parameter.Declarations?
  from : @decode.Cursor?
  limits : Limits
  calendar_profile : @calendar_profile.Profile?
  text_rank_profile : @text_rank_profile.Profile?
  delta_contracts : Array[
    (String, @schema.FieldName, @graph_contract.CheckedContract),
  ]
  model_tasks : @model_environment.ModelTasks?
  mut key_work : Int
  mut key_text : Int
  mut score_nodes : Int
  mut carrier_wrappers : Int
  mut step : PipelineEvidenceStep
}

///|
priv enum PipelineEvidenceState {
  Reading(PipelineEvidenceBody)
  Completed(CheckedPipeline)
  Rejected(PipelineEvidenceBody, Issue)
  Taken
  Cleared
}

///|
/// Retains the actual original evidence arrays, budgets and nested result.
/// No Source parsing, schema admission or core checker is duplicated here.
struct PipelineEvidenceRead {
  mut state : PipelineEvidenceState
}

///|
pub fn begin_pipeline_evidence_read(
  source : @decode.Cursor,
  inputs : Array[(String, InputContract)],
  parameters : @parameter.Declarations?,
  from : @decode.Cursor?,
  limits : Limits,
  calendar_profile? : @calendar_profile.Profile? = None,
  text_rank_profile? : @text_rank_profile.Profile? = None,
  delta_contracts? : Array[
    (String, @schema.FieldName, @graph_contract.CheckedContract),
  ] = [],
  model_tasks? : @model_environment.ModelTasks? = None,
) -> Result[PipelineEvidenceRead, Issue] {
  if limits.max_steps < 0 ||
    limits.max_work < 0 ||
    limits.max_text_bytes < 0 ||
    limits.max_nodes < 0 ||
    limits.max_tokens < 0 ||
    limits.max_depth < 0 {
    return Err({
      kind: InvalidLimits,
      source,
      path: @decode.cursor_path(source),
      span: @decode.cursor_span(source),
      range: None,
    })
  }
  Ok({
    state: Reading({
      source,
      inputs,
      parameters,
      from,
      limits,
      calendar_profile,
      text_rank_profile,
      delta_contracts,
      model_tasks,
      key_work: limits.max_work,
      key_text: limits.max_text_bytes,
      score_nodes: limits.max_nodes,
      carrier_wrappers: 0,
      step: Carriers,
    }),
  })
}

///|
pub fn pipeline_evidence_read_phase(
  original : PipelineEvidenceRead,
) -> PipelineEvidenceReadPhase {
  match original.state {
    Reading(body) =>
      match body.step {
        Carriers => Carriers
        Keys(_) => Keys
        Rankings(_, _) => Rankings
        Core(_, _, _) => Core
      }
    Completed(_) => Complete
    Rejected(_, _) => Failed
    Taken => Taken
    Cleared => Cleared
  }
}

///|
/// Successful original prefix only. A failed nested read has no complete
/// Usage; it is never represented as zero work or a fresh allowance.
pub fn pipeline_evidence_read_owned_work(
  original : PipelineEvidenceRead,
) -> Int? {
  match original.state {
    Reading(body) => Some(body.limits.max_work - body.key_work)
    Completed(checked) => Some(checked.usage.work)
    _ => None
  }
}

///|
pub fn advance_pipeline_evidence_read(
  original : PipelineEvidenceRead,
) -> PipelineEvidenceReadPhase {
  guard original.state is Reading(body) else {
    return pipeline_evidence_read_phase(original)
  }
  match advance_pipeline_evidence_read_owned(body) {
    Err(issue) => original.state = Rejected(body, issue)
    Ok(Some(checked)) => original.state = Completed(checked)
    Ok(None) => ()
  }
  pipeline_evidence_read_phase(original)
}

///|
pub fn take_pipeline_evidence_read(
  original : PipelineEvidenceRead,
) -> Result[CheckedPipeline, Issue]? {
  match original.state {
    Completed(checked) => {
      original.state = Taken
      Some(Ok(checked))
    }
    Rejected(_, issue) => {
      original.state = Taken
      Some(Err(issue))
    }
    _ => None
  }
}

///|
pub fn clear_pipeline_evidence_read(original : PipelineEvidenceRead) -> Unit {
  if !(original.state is Taken) {
    match original.state {
      Reading(body) | Rejected(body, _) => body.step = Carriers
      _ => ()
    }
    original.state = Cleared
  }
}

///|
fn advance_pipeline_evidence_read_owned(
  original : PipelineEvidenceBody,
) -> Result[CheckedPipeline?, Issue] {
  let source = original.source
  let inputs = original.inputs
  let parameters = original.parameters
  let from = original.from
  let limits = original.limits
  let calendar_profile = original.calendar_profile
  let text_rank_profile = original.text_rank_profile
  let delta_contracts = original.delta_contracts
  let model_tasks = original.model_tasks
  match original.step {
    Carriers => {
      let carriers = inputs.map(pair => {
        if pair.1 is (KeyedInput(_) | CandidateKeysInput(_)) {
          original.carrier_wrappers += 1
        }
        (
          pair.0,
          match pair.1 {
            ProducedInput(p) => p.carrier
            SourceViewInput(_, _, _, owner) =>
              @model_environment.carrier_schema_value(
                @model_environment.source_view_carrier_schema(owner),
              )
            CarrierInput(c) => c
            KeyedInput(k) => @carrier.relation(@evidence.keyed_records(k))
            CandidateKeysInput(k) =>
              @carrier.relation(@evidence.key_set_records(k))
            RankingInput(r) => @vector.ranking_input_carrier(r)
            RelationEvidenceInput(e) => @vector.ranking_input_carrier(e.ranking)
          },
        )
      })
      original.step = Keys(carriers)
    }
    Keys(carriers) => {
      let mut key_work = original.key_work
      let mut key_text = original.key_text
      let keys = []
      for (_, input) in inputs {
        let key = match input {
          SourceViewInput(_, _, _, owner) =>
            match
              @evidence.source_view_keys(owner, {
                max_work: key_work,
                max_name_bytes: key_text,
              }) {
              Ok(None) => None
              Ok(Some(value)) => {
                key_work -= value.work
                key_text -= value.name_bytes
                Some(value.keys)
              }
              Err(issue) =>
                return Err({
                  kind: KeyEvidence(issue.kind),
                  source,
                  path: issue.path.copy(),
                  span: issue.span,
                  range: None,
                })
            }
          ProducedInput(p) => p.keys
          CarrierInput(_) | RankingInput(_) => None
          KeyedInput(k) => Some(@evidence.singleton_key(k))
          CandidateKeysInput(k) => Some(k)
          RelationEvidenceInput(e) => Some(e.keys)
        }
        keys.push(key)
      }
      original.key_work = key_work
      original.key_text = key_text
      original.step = Rankings(carriers, keys)
    }
    Rankings(carriers, keys) => {
      let mut key_work = original.key_work
      let mut key_text = original.key_text
      let mut score_nodes = original.score_nodes
      let rankings = []
      for (_, input) in inputs {
        let ranking = match input {
          SourceViewInput(_, _, _, owner) =>
            match
              @vector.source_view_scores(owner, {
                max_work: key_work,
                max_nodes: score_nodes,
                max_depth: limits.max_depth,
                max_text_bytes: key_text,
              }) {
              Ok(None) => None
              Ok(Some(value)) => {
                key_work -= value.usage.work
                key_text -= value.usage.text_bytes
                score_nodes -= value.usage.nodes
                Some(value.input)
              }
              Err(issue) =>
                return Err({
                  kind: Vector(issue.kind),
                  source,
                  path: issue.path.copy(),
                  span: issue.span,
                  range: None,
                })
            }
          ProducedInput(p) => p.ranking
          RankingInput(r) => Some(r)
          RelationEvidenceInput(e) => Some(e.ranking)
          _ => None
        }
        rankings.push(ranking)
      }
      original.key_work = key_work
      original.key_text = key_text
      original.score_nodes = score_nodes
      original.step = Core(carriers, keys, rankings)
    }
    Core(carriers, keys, rankings) => {
      let key_work = original.key_work
      let key_text = original.key_text
      let score_nodes = original.score_nodes
      let checked = check_impl(
        source,
        carriers,
        parameters,
        from,
        {
          ..limits,
          max_work: key_work,
          max_nodes: score_nodes,
          max_text_bytes: key_text,
        },
        calendar_profile,
        text_rank_profile,
        delta_contracts,
        keys,
        rankings,
        inputs.map(pair => {
          match pair.1 {
            ProducedInput(p) => Some(p)
            _ => None
          }
        }),
        inputs.map(pair => pair.1),
        model_tasks,
      ) catch {
        Stop(issue) => return Err(issue)
      }
      return Ok(
        Some({
          ..checked,
          usage: {
            ..checked.usage,
            work: limits.max_work - key_work + checked.usage.work,
            text_bytes: limits.max_text_bytes -
            key_text +
            checked.usage.text_bytes,
          },
        }),
      )
    }
  }
  Ok(None)
}
