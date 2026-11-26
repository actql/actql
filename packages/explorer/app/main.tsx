import type {CheckpointPageModel,ReviewObservation,ReviewReference} from '@actql/explorer-ui/checkpoint-review';
import {useCallback, useEffect, useId, useMemo, useRef, useState, type ChangeEvent, type FormEvent, type ReactNode} from 'react';
import {createRoot} from 'react-dom/client';
import {PlanExplorer, OriginalPlanMetadata, RunInspector, CheckpointPanel} from '@actql/explorer-ui/plan-explorer';
import type {OriginalCancellation, CancellationObservation} from '@actql/explorer-ui/plan-explorer';
import {resumeControlOperationRef, validCancellationRef, validOperationAttemptRef, validRunRef} from '@actql/client-wire';
import type {RunReference} from '@actql/sdk';
import type {WireCancellationLookup, WireControlOperationLookup, WireControlOperationRef, WireRunSample, WireSubmissionRef} from '@actql/client-wire';
import {observedPlanStep, runObservationModel, storyNextPause, type RunObservationModel, type StoryNextPause} from '@actql/explorer-ui/run-observation';
import type {PlanReadModel, StaticExplanationReadModel, OriginalRunPlanReadModel, OriginalRunPresentationReadModel, SavedExplanationReadModel, ExplanationStoryModel, SamplePortSelection} from '@actql/explorer-ui/read-model';
import {expectedStoryPortColumns, storySamplePorts, sampleCaptureCaption, sampleCellPreview} from '@actql/explorer-ui/read-model';
import {createExplorerBrowserSource, type ExplorerStartObservation} from '@actql/explorer/browser-source';
import '@actql/explorer-ui/styles.css';
import './styles.css';
import {explorerCopy, type ExplorerCopy} from '../../explorer-ui/i18n.mjs';
import {storyCardGroups, type StoryGroup} from './story-card-groups.mts';

type StoryContext = StaticExplanationReadModel['context'];
type Step = ExplanationStoryModel['occurrences'][number];

function sameRun(original: RunReference, other: RunReference | undefined) {
  return other?.namespaceId === original.namespaceId && other.authorityScopeCid === original.authorityScopeCid &&
    other.runDefinitionCid === original.runDefinitionCid;
}

function parseLocalJson(text: string): unknown {
  try {return JSON.parse(text);}
  catch {return undefined;}
}

function StoryText({text}: {text: string}) {
  return <>{text.split(/("[^"\n]+")/u).map((part, index) => index % 2
    ? <code key={index}>{part.slice(1, -1)}</code> : part)}</>;
}

function StoryHeading({story, context}: {story: ExplanationStoryModel; context: StoryContext}) {
  const sources = context.filter(({origin}) => origin.kind === 'source').length;
  const models = context.filter(({origin}) => origin.kind === 'model_task').length;
  const effects = context.flatMap(({origin}) => origin.kind === 'effect_set' ? origin.members : []);
  const requiresApproval = effects.some(({declaration}) => declaration.minimum_approval.kind === 'contract_minimum' &&
    declaration.minimum_approval.value === 'required');
  const ja = story.locale === 'ja';
  const words = explorerCopy(ja);
  return <>
    <h1><StoryText text={story.narrative.summary}/></h1>
    <div className="story-chips">
      {effects.length > 0 && <span className="workspace-chip" data-tone="amber">{requiresApproval
        ? words.writeDeclaredApprovalRequiredForAtLeastOneOperation
        : words.writeDeclaredApprovalRequirementUnknown}</span>}
      {sources > 0 && <span className="workspace-chip" data-tone="teal">{words.declaredSources(sources)}</span>}
      {models > 0 && <span className="workspace-chip" data-tone="lilac">{words.modelTasks(models)}</span>}
    </div>
  </>;
}

type StepState = 'Planned' | 'Unknown' | 'Observed' | 'Next';
function stepStateLabel(state: StepState | undefined, ja: boolean) {
  return state && explorerCopy(ja).stepState[state];
}

function graphStepLabels(story: ExplanationStoryModel | undefined, context: StoryContext,
  stageResultLinks: PlanReadModel['stageResultLinks']) {
  const importedInputs = stageResultLinks && new Set(stageResultLinks.map(link=>link.consumer.port_id));
  const sources = new Map<string, {resource: string; connector: string}[]>();
  const tasks = new Map<string, string[]>();
  const results = new Map<string, string[]>();
  const add = <T,>(index: Map<string, T[]>, stepId: string, value: T) => {
    const entries = index.get(stepId);
    if (entries) entries.push(value);
    else index.set(stepId, [value]);
  };
  for (const {origin} of context) {
    if (origin.kind === 'source' && importedInputs) {
      const consumers = origin.consuming_ports.filter(port=>!importedInputs.has(port.port_id));
      for (const id of new Set(consumers.map(port=>port.step_id))) add(sources, id, origin.source_view);
    } else if (origin.kind === 'model_task' && origin.producer.state === 'projected') {
      add(tasks, origin.producer.step_id, origin.task_id.replace(/^model-task:/u, ''));
    } else if (origin.kind === 'result' && origin.producer.state === 'projected') {
      add(results, origin.producer.step_id, origin.name);
    }
  }
  const labels = new Map<string, {kind?: string; title: string; inputs?: string; sourceInput?: boolean}>();
  const ja = story?.locale === 'ja';
  const words = explorerCopy(ja);
  for (const step of story?.occurrences ?? []) {
    const inputs = sources.get(step.stepId), models = tasks.get(step.stepId), outputs = results.get(step.stepId);
    const {meaning} = step.explanation;
    const inputNames = inputs?.map(input=>input.resource).join(', ');
    const inputDetail = inputNames ? `${words.input} · ${inputNames}` : undefined;
    if (meaning.kind === 'join') {
      const key = meaning.keys.find(({left, right})=>!left.startsWith('aql_') && !right.startsWith('aql_'));
      const name = words.join;
      labels.set(step.stepId, {kind: words.combine, title: key ?
        `${name} · ${key.left} = ${key.right}` :
        meaning.keys.length ? words.joinOnCheckedKeys : name, inputs: inputDetail});
    } else if (models?.length) {
      labels.set(step.stepId, {kind: words.model, title: words.ask(models.join(', ')),
        inputs: inputDetail});
    } else if (inputs?.length && inputDetail) {
      // A linked declaration names the input port; it does not make this
      // logical occurrence an actual Source attempt or another Graph node.
      const systems = new Set(inputs.map(input=>input.connector));
      labels.set(step.stepId, {kind: systems.size === 1 ? inputs[0].connector : words.inputs,
        title: inputDetail, sourceInput: true});
    } else if (outputs?.length) {
      labels.set(step.stepId, {kind: words.result, title: `${words.return} ${outputs.join(', ')}`});
    } else if (meaning.kind === 'projection' && meaning.operation === 'select') {
      labels.set(step.stepId, {title: words.selectFields});
    } else if (step.operator === 'assert_rows') {
      labels.set(step.stepId, {title: words.checkRowConstraints});
    } else if (step.operator === 'filter') {
      labels.set(step.stepId, {title: words.filterRows});
    }
  }
  if (story) {
    const reads = context.filter(({origin}) => origin.kind === 'source');
    const source = storyProjections(story, reads, stageResultLinks);
    for (const [index, {step}] of source) {
      const {origin} = reads[index];
      if (origin.kind !== 'source') continue;
      const {resource, connector} = origin.source_view;
      labels.set(step.stepId, {kind: connector, title: words.readResource(resource), sourceInput: true});
    }
  }
  return labels;
}

function stepTitle(step: Step, label: string | undefined, words: ExplorerCopy) {
  if (label) return label;
  const names = step.names.filter(name=>!name.startsWith('aql_'));
  if (names.length) return names.join(', ');
  return words.operation(step.operator);
}

function stepState(stepId: string, saved: boolean, boundary?: {stepId: string; state: StepState}): StepState | undefined {
  return stepId === boundary?.stepId ? boundary.state : saved ? undefined : 'Planned';
}

function StoryCard({ordinal, label, title, detail, system, state, ja, open, selected, onToggle, children}: {
  ordinal: number; label: string; title: string; detail?: string; system?: string; state?: StepState;
  ja: boolean; open: boolean; selected?: boolean; onToggle(): void; children: ReactNode;
}) {
  return <li className="story-row" data-state={state}>
    <span className="step-marker" aria-hidden="true">{ordinal}</span>
    <details className="story-card panel" open={open} data-selected={selected}>
      <summary onClick={event=>{event.preventDefault(); onToggle();}}>
        <span className="step-label">{label}
          {system && <span className="workspace-chip step-system">{system}</span>}
          {state && <span className="workspace-chip step-state" data-state={state}>{stepStateLabel(state, ja)}</span>}</span>
        <strong><StoryText text={title}/></strong>
        {detail && title !== detail && <span className="step-summary"><StoryText text={detail}/></span>}
      </summary>
      <div className="step-details">{children}</div>
    </details>
  </li>;
}

function PlanAdvanced({model, ja}: {model: PlanReadModel; ja: boolean}) {
  const words = explorerCopy(ja);
  return <details className="original-plan-advanced">
    <summary>{words.advancedOriginalPlan}</summary>
    <OriginalPlanMetadata model={model} workspace locale={ja ? 'ja' : 'en'}/>
  </details>;
}

type PlanNode = PlanReadModel['nodes'][number];

function planNodeTitle(node: PlanNode, locale: 'en' | 'ja') {
  return explorerCopy(locale).operation(node.operator);
}

function PlanSteps({map, boundary, selection, select, graph, locale, pause, readSample, saved}: {
  map: PlanReadModel; boundary?: {stepId: string; state: StepState}; selection?: string;
  select(id: string): void; graph: boolean; locale: 'en' | 'ja'; pause?: StoryNextPause; readSample?: SampleRead; saved: boolean;
}) {
  const [collapsed, setCollapsed] = useState<string>();
  const steps = useMemo(() => new Map(map.nodes.map(node => [node.id,
    {stepId: node.id, ports: node.ports, title: planNodeTitle(node, locale)}])), [map, locale]);
  const ja = locale === 'ja';
  const words = explorerCopy(ja);
  return <section aria-label={graph ? words.selectedStep : words.originalSteps}>
    <ol className="story-steps">
      {map.nodes.map((node, index) => {
        const selected = selection === node.id;
        if (graph && !selected) return null;
        const open = graph || selected && collapsed !== node.id;
        const step = steps.get(node.id)!;
        return <StoryCard key={node.id} ordinal={index + 1} ja={ja} label={words.logicalStep}
          title={planNodeTitle(node, locale)} selected={selected}
          state={node.id === boundary?.stepId ? boundary.state : undefined}
          open={open} onToggle={() => {
            select(node.id);
            setCollapsed(open && !graph ? node.id : undefined);
          }}>
          {open && <StepData locale={locale} step={step} plan={map} saved={saved} readSample={readSample}/>}
          {open && pause?.stepId === node.id && <NextInputs locale={locale} key={pause.revision}
            step={step} plan={map} steps={steps} pause={pause} readSample={readSample}/>}
          <details><summary>{words.originalStepAndPorts}</summary>
            {node.names.length > 0 && <p>{node.names.map(name => <code key={name}>{name}</code>)}</p>}
            <code>{node.id}</code>
            <ul>{node.ports.map(port => <li key={port.port_id}>
              {words.portRole[port.role]} · {port.carrier} · <code>{port.port_id}</code>
            </li>)}</ul>
          </details>
          {selected && <PlanAdvanced model={map} ja={ja}/>}
        </StoryCard>;
      })}
    </ol>
  </section>;
}

function StepOrigin({step, label, select, folded = false, state, ja}: {
  step: Step; label?: string; select?(): void; folded?: boolean; state?: StepState; ja: boolean;
}) {
  const meaning = step.explanation.meaning;
  const words = explorerCopy(ja);
  return <div className="occurrence-origin">
    {!folded && <><strong>{stepTitle(step, label, words)}</strong><p><StoryText text={step.explanation.text}/></p></>}
    <details><summary>{words.originalStepAndPorts}{state && <span className="workspace-chip step-state">{stepStateLabel(state, ja)}</span>}</summary>
      {folded && <p><StoryText text={step.explanation.text}/></p>}
      {meaning.kind === 'join' && <ul aria-label={words.checkedJoinKeys}>
        {meaning.keys.map(({left,right},index)=><li key={index}><code>{left}</code> = <code>{right}</code></li>)}
      </ul>}
      {step.names.length > 0 && <p>{step.names.map(name=><code key={name}>{name}</code>)}</p>}
      {select && <button type="button" className="small" onClick={select}>{words.selectOriginalStep}</button>}
      <code>{step.stepId}</code>
      <ul>{step.ports.map(port=><li key={port.port_id}>{words.portRole[port.role]} · <code>{port.port_id}</code></li>)}</ul>
    </details>
  </div>;
}

type SampleStep = Readonly<{stepId: string; ports: Step['ports']; title: string}>;
type SamplePlan = Pick<PlanReadModel, 'compiledPlanCid' | 'logicalMapCid'>;
type SampleRead = (port: SamplePortSelection) => Promise<WireRunSample | undefined>;
type SampleDisplay = WireRunSample | {state: 'reading'} | {state: 'read_failed'};

function sampleMessage(sample: Exclude<SampleDisplay, {state: 'available'}>, words: ExplorerCopy) {
  switch (sample.state) {
    case 'reading': return words.readingSample;
    case 'read_failed': return words.sampleReadFailed;
    case 'forbidden': return words.sampleAccessDenied;
    case 'expired': return words.sampleExpired;
    case 'unknown': return words.sampleOutcomeUnknown;
    case 'unavailable':
      switch (sample.reason) {
        case 'not_retained': return words.sampleNotRetained;
        case 'selection_required': return words.sampleSelectionRequired;
        case 'not_supported': return words.sampleNotSupported;
        case 'not_sealed': return words.sampleNotSealed;
        case 'evicted': return words.sampleEvicted;
        case 'capacity': return words.sampleCapacity;
      }
  }
}

function ColumnTable({label, names, caption, children, words}: {
  words: ExplorerCopy;
  label: string; names: readonly (string | null)[]; caption?: string; children?: ReactNode;
}) {
  return <div className="step-data-scroll" tabIndex={0} role="region" aria-label={label}>
    <table className="step-data-table">
      {caption !== undefined && <caption>{caption}</caption>}
      <thead><tr>{names.map((name, index)=>
      <th key={index} scope="col">{name ?? words.column(index + 1)}</th>)}</tr></thead>
      {children}
    </table>
  </div>;
}

function ExpandableSampleCell({text, preview, row, column, words}: {
  words: ExplorerCopy;
  text: string; preview: string; row: number; column: number;
}) {
  const [expanded, setExpanded] = useState(false);
  const content = useId();
  return <>
    <span id={content}>{expanded ? text : preview}{!expanded && <span aria-hidden="true">…</span>}</span>
    <button type="button" className="sample-cell-toggle" aria-expanded={expanded} aria-controls={content}
      aria-label={words.toggleCell(expanded, row + 1, column + 1)}
      onClick={()=>setExpanded(!expanded)}>{expanded ? words.collapse : words.expandCell}</button>
  </>;
}

function SampleCellText({text, row, column, words}: {text: string; row: number; column: number; words: ExplorerCopy}) {
  const preview = sampleCellPreview(text);
  return preview === text ? text : <ExpandableSampleCell words={words} text={text} preview={preview} row={row} column={column}/>;
}

function RetainedRelationTable({sample, label, words, locale}: {sample: Extract<WireRunSample, {state: 'available'}>;
  label: string; words: ExplorerCopy; locale: 'en' | 'ja';
}) {
  const relation = sample.data;
  if (relation.kind !== 'relation') return null;
  return <ColumnTable words={words} label={label} caption={sampleCaptureCaption(sample.capture, locale)}
    names={relation.columns.map(column=>column.name)}>
    <tbody>{relation.rows.map((row, index)=><tr key={index}>{row.map((cell, column)=>
      <td key={column}>{cell.presence === 'absent' ? <em>{words.absent}</em> : cell.value === null ? <code>NULL</code> :
        <SampleCellText words={words} text={typeof cell.value === 'string' ? cell.value : JSON.stringify(cell.value)}
          row={index} column={column}/>}</td>)}</tr>)}</tbody>
  </ColumnTable>;
}

function nextSampleProducer(steps: ReadonlyMap<string, SampleStep>, input: Step['ports'][number],
  sample: Extract<WireRunSample, {state: 'available'}>) {
  const producer = sample.source.producer;
  if (sample.data.kind !== 'relation' || producer.kind !== 'logical_output') return undefined;
  const source = input.source;
  if (source.kind === 'logical_output' && (source.step_id !== producer.step_id ||
      source.output_port_id !== producer.output_port_id)) return undefined;
  const step = steps.get(producer.step_id);
  return step?.ports.some(output=>output.role === 'output' && output.port_id === producer.output_port_id &&
    output.carrier === input.carrier && output.carrier_contract_cid === input.carrier_contract_cid) ? step : undefined;
}

function NextInputs({step, plan, steps, pause, readSample, locale}: {
  locale: 'en' | 'ja';
  step: SampleStep; plan: SamplePlan; steps: ReadonlyMap<string, SampleStep>;
  pause: StoryNextPause; readSample?: SampleRead;
}) {
  const words = explorerCopy(locale);
  const inputs = useMemo(()=>step.ports.filter(port=>port.role === 'input')
    .filter(port=>port.carrier === 'relation'), [step]);
  const [samples, showSamples] = useState<Record<string, SampleDisplay>>({});
  const {revision, expires} = pause;
  const {compiledPlanCid, logicalMapCid} = plan;
  useEffect(()=>{
    if (!readSample) return;
    let mounted = true;
    const current = () => mounted && Date.now() < expires;
    const read = async () => {
      for (const port of inputs) {
        if (!current()) return;
        let sample: SampleDisplay | undefined;
        try {
          sample = await readSample({stepId: step.stepId, portId: port.port_id, role: 'input',
            carrierContractCid: port.carrier_contract_cid, compiledPlanCid, logicalMapCid, nextRevision: revision});
          if (sample?.state === 'available' && !nextSampleProducer(steps, port, sample)) sample = {state: 'read_failed'};
        } catch {
          sample = {state: 'read_failed'};
        }
        if (!current() || !sample) return;
        const nextSample = sample;
        showSamples(values=>({...values, [port.port_id]: nextSample}));
      }
    };
    void read();
    return ()=>{mounted = false;};
  }, [compiledPlanCid, expires, inputs, logicalMapCid, readSample, revision, step.stepId, steps]);
  return <section className="step-data" aria-label={words.nextStepInputs}>
    <strong>{words.inputsAtPause}</strong>
    {inputs.length === 0 && <p>{words.noRelationInputs}</p>}
    {inputs.map(port=>{
      const sample = samples[port.port_id];
      const upstream = sample?.state === 'available' ? nextSampleProducer(steps, port, sample) :
        port.source.kind === 'logical_output' ? steps.get(port.source.step_id) : undefined;
      const label = words.inputPort(port.port_ordinal + 1, upstream?.title);
      return <section className="next-input" key={port.port_id} aria-label={label}>
        <strong>{label}</strong>
        {!readSample ? <p>{words.sampleReadUnavailable}</p> :
          sample?.state === 'available' ? <RetainedRelationTable words={words} locale={locale} sample={sample} label={words.capturedRows + ' · ' + label}/> :
          <p role="status">{sampleMessage(sample ?? {state: 'reading'}, words)}</p>}
      </section>;
    })}
  </section>;
}

function StepData({step, plan, expectedColumns, saved, readSample, locale}: {
  locale: 'en' | 'ja';
  step: SampleStep; plan: SamplePlan; expectedColumns?(port: Step['ports'][number]): readonly string[] | undefined;
  saved: boolean; readSample?: SampleRead;
}) {
  const words = explorerCopy(locale);
  const ports = storySamplePorts(step);
  const ambiguousOutput = step.ports.filter(port=>port.role === 'output').length > 1;
  const [selectedPort, selectPort] = useState<string>();
  const [sample, showSample] = useState<SampleDisplay>();
  const request = useRef(0);
  useEffect(() => () => {request.current++;}, []);
  const port = ports.find(item=>item.port_id === selectedPort) ?? ports.find(item=>item.role === 'output') ?? ports[0];
  const expected = !saved && port ? expectedColumns?.(port) : undefined;
  const load = async () => {
    if (!port || !readSample) return;
    const issued = ++request.current;
    showSample({state: 'reading'});
    try {
      const value = await readSample({stepId: step.stepId, portId: port.port_id, role: port.role,
        carrierContractCid: port.carrier_contract_cid, compiledPlanCid: plan.compiledPlanCid,
        logicalMapCid: plan.logicalMapCid});
      if (request.current === issued && value) showSample(value);
    } catch {
      if (request.current === issued) showSample({state: 'read_failed'});
    }
  };
  const retained = sample?.state === 'available' && sample.data.kind === 'relation' ? sample : undefined;
  return <section className="step-data" data-step-id={step.stepId} aria-label={saved ? words.stepSample : words.expectedColumns}>
    <strong>{saved ? words.sampleData : words.expectedColumns}</strong>
    {ports.length > 1 && <label className="step-data-port">{words.relationPort} <select value={port?.port_id}
      onChange={event=>{request.current++; selectPort(event.target.value); showSample(undefined);}}>
      {ports.map(item=><option key={item.port_id} value={item.port_id}>
        {words.portRole[item.role]} {item.port_ordinal + 1}
      </option>)}</select></label>}
    {!saved && (expected?.length ? <ColumnTable words={words} label={words.expectedColumns} names={expected}/> :
      expected ? <p>{words.noOutputColumns}</p> :
        <p>{words.noExpectedColumns}</p>)}
    {saved && <>{ambiguousOutput && <p>{words.multiOutputSampleUnavailable}</p>}
      {port && readSample ? <button type="button" className="small"
      onClick={()=>void load()} disabled={sample?.state === 'reading'}>{sample ? words.readSampleAgain : words.readRetainedSample}</button> :
      <p>{words.noReadableSamplePort}</p>}
      {sample && sample.state !== 'available' && <p role="status">{sampleMessage(sample, words)}</p>}
      {retained && <RetainedRelationTable words={words} locale={locale} sample={retained} label="Captured rows"/>}
    </>}
  </section>;
}

type KeptColumns = {step: Step; columns: readonly string[]};

// A same-name field selection can be described in its caller's card when
// the original Plan links that exact port. The field list is still shown
// because selection can drop columns even though it keeps their values.
function storyProjections(story: ExplanationStoryModel, sources: StoryContext,
  stageResultLinks: PlanReadModel['stageResultLinks']) {
  const source = new Map<number, KeptColumns>();
  const imported = stageResultLinks && new Set(stageResultLinks.map(link=>link.consumer.port_id));
  const claimed = new Set<string>();
  const steps = new Map(story.occurrences.map(step => [step.stepId, step]));
  const kept = (step: Step | undefined) => {
    if (!step || claimed.has(step.stepId)) return;
    const {meaning} = step.explanation;
    if (meaning.kind !== 'projection' || meaning.operation !== 'select' ||
        !meaning.fields.length || !meaning.fields.every(({input, output}) => input === output)) return;
    const inputs = step.ports.filter(port => port.role === 'input');
    const outputs = step.ports.filter(port => port.role === 'output');
    if (inputs.length === 1 && outputs.length === 1 && inputs[0].carrier === 'relation' &&
        outputs[0].carrier === 'relation') return {step, columns: meaning.fields.map(field => field.output),
      input: inputs[0], output: outputs[0]};
    return undefined;
  };
  for (const [index, {origin}] of sources.entries()) {
    if (!imported || origin.kind !== 'source' || origin.link_state !== 'linked' ||
        origin.consuming_ports.length !== 1) continue;
    const link = origin.consuming_ports[0], selection = kept(steps.get(link.step_id));
    const locator = selection?.input.source;
    if (!imported.has(link.port_id) && selection?.input.port_id === link.port_id && locator?.kind === 'stage_input' &&
        locator.stage_ordinal === origin.stage_input.stage_ordinal &&
        locator.input_port_ordinal === origin.stage_input.input_port_ordinal) {
      source.set(index, selection);
      claimed.add(selection.step.stepId);
    }
  }
  return source;
}

function ModelFields({origin, locale}: {
  origin: Extract<StoryContext[number]['origin'], {kind: 'model_task'}>; locale: 'en' | 'ja';
}) {
  const words = explorerCopy(locale);
  return <>
    <dl className="model-fields">
      <dt>{words.inputs}</dt>
      <dd>{origin.input_bindings.length ? <ul>{origin.input_bindings.map(({role, binding, type}) =>
        <li key={role}><code>{role}</code>
          {binding.state === 'field' && binding.name !== role && <> ← <code>{binding.name}</code></>}
          {' · '}{type.kind}{type.nullable ? words.nullable : ''}</li>)}</ul>
        : words.unprojected}</dd>
      <dt>{words.outputs}</dt>
      <dd>{origin.output_fields.length ? <ul>{origin.output_fields.map(({name, type}) =>
        <li key={name}><code>{name}</code>{' · '}{type.kind}
          {type.nullable ? words.nullable : ''}</li>)}</ul>
        : words.unprojected}</dd>
    </dl>
    <details><summary>{words.originalModelContract}</summary><code>{origin.contract_cid}</code></details>
  </>;
}

type EffectOrigin = Extract<StoryContext[number]['origin'], {kind: 'effect_set'}>;

function declaredWrite(origin: EffectOrigin) {
  const member = origin.members.length === 1 ? origin.members[0] : undefined;
  const contract = member?.declaration.contract;
  const target = contract?.kind === 'mapping'
    ? /^connector:\/\/[\w.-]{1,48}\/([\w.-]{1,48})$/u.exec(contract.declared_target)?.[1]
    : undefined;
  return {target, fields: member?.write_fields.state === 'declared' ? member.write_fields.fields : undefined,
    update: member?.declaration.effect_kind === 'update'};
}

function writeCardTitle(origin: EffectOrigin, ja: boolean) {
  const words = explorerCopy(ja);
  const {target, fields, update} = declaredWrite(origin);
  if (!target) return words.declaredChanges;
  const names = fields?.map(field => '"' + field + '"').join(words.fieldsJoin);
  if (update && names) {
    return words.updateFields(target, names);
  }
  return words.writeTarget(target);
}

function storyGroupTitle(group: StoryGroup, labels: ReturnType<typeof graphStepLabels>, ja: boolean) {
  const words = explorerCopy(ja);
  const origin = group.item?.origin;
  switch (origin?.kind) {
    case 'source':
      return words.readResource('"' + origin.source_view.resource + '"');
    case 'model_task': {
      const model = origin.task_id.replace(/^model-task:/u, '');
      return words.askModel(model);
    }
    case 'result':
      return words.returnResult('"' + origin.name + '"');
    case 'effect_set':
      return writeCardTitle(origin, ja);
    default:
      if (group.kind === 'join' && group.members.length > 1) return words.joinInputs;
      return group.primary ? stepTitle(group.primary, labels.get(group.primary.stepId)?.title, words) : '';
  }
}

function storyGroupLabel(group: StoryGroup, ja: boolean): string {
  const words = explorerCopy(ja);
  return ({
    source: words.read, model: words.askModelKind, join: words.combineInputs,
    filter: words.filter, result: words.result,
    effect: words.write, operation: words.compute,
  })[group.kind];
}

function StorySteps({story, groups, sourceColumns, model, saved, boundary, selectedStep, selectStep, graph, labels, pause, readSample}: {
  story: ExplanationStoryModel; groups: readonly StoryGroup[]; sourceColumns: ReadonlyMap<number, KeptColumns>;
  model?: PlanReadModel;
  saved: boolean; boundary?: {stepId: string; state: StepState}; selectedStep?: string;
  selectStep(id: string): void; graph: boolean; labels: ReturnType<typeof graphStepLabels>;
  pause?: StoryNextPause; readSample?: SampleRead;
}) {
  const [opened, setOpened] = useState<Record<string, boolean>>({});
  const originalSteps = useMemo(() => new Map(story.occurrences.map(step => [step.stepId, step])), [story]);
  const steps = useMemo(() => new Map(story.occurrences.map(step => [step.stepId,
    {stepId: step.stepId, ports: step.ports, title: stepTitle(step, labels.get(step.stepId)?.title, explorerCopy(story.locale))}])), [story, labels]);
  const ja = story.locale === 'ja';
  const words = explorerCopy(ja);
  let sourceIndex = 0;
  return <section aria-label={graph ? words.selectedStep : words.originalStory}>
    <ol className="story-steps">
      {groups.map((group, index) => {
        const origin = group.item?.origin;
        const selected = group.members.find(step => step.stepId === selectedStep);
        const selectedGroup = group.id === selectedStep || selected !== undefined;
        const observed = group.members.find(step => step.stepId === boundary?.stepId);
        const active = selected ?? observed ?? group.primary;
        const dataStep = active && steps.get(active.stepId);
        const columns = group.kind === 'source' ? sourceColumns.get(sourceIndex++)?.columns : undefined;
        const state = active ? stepState(active.stepId, saved, boundary) : saved ? undefined : 'Planned';
        const defaultOpen = !saved && index === 0 || selectedGroup;
        const open = graph || observed !== undefined || (opened[group.id] ?? defaultOpen);
        if (graph && !selectedGroup) return null;
        const title = storyGroupTitle(group, labels, ja);
        const label = storyGroupLabel(group, ja);
        const detail = group.item?.text ?? (group.primary?.explanation.meaning.kind === 'not_projected'
          ? undefined : group.primary?.explanation.text);
        return <StoryCard key={group.id} ordinal={index + 1} selected={selectedGroup} ja={ja}
          label={label} title={title} detail={detail} state={state} open={open}
          system={origin?.kind === 'source' ? origin.source_view.connector : undefined}
          onToggle={() => {
            if (!selectedGroup) selectStep(active?.stepId ?? group.id);
            if (!graph) setOpened(values => ({...values, [group.id]: !(values[group.id] ?? defaultOpen)}));
          }}>
          {origin?.kind === 'source' && <>
            {!saved && (columns ? <div className="expected-columns"><table>
              <caption>{words.expectedColumns}</caption>
              <thead><tr>{columns.map(name => <th key={name} scope="col"><code>{name}</code></th>)}</tr></thead>
            </table></div> : <p>{words.columnsNotProjected}</p>)}
            <details><summary>{words.originalSourceAndLinks}</summary>
              <p>{words.stageInput(origin.stage_input.stage_ordinal + 1, origin.stage_input.input_port_ordinal + 1)}</p>
              <dl><dt>{words.contract}</dt><dd><code>{origin.source_view.contract_cid}</code></dd>
                <dt>{words.catalog}</dt><dd><code>{origin.source_view.catalog_cid}</code></dd></dl>
              {origin.consuming_ports.length > 0 && <ul aria-label={words.originalConsumers}>
                {origin.consuming_ports.map(port => <li key={port.port_id}><code>{port.step_id}</code><br/><code>{port.port_id}</code></li>)}
              </ul>}
            </details>
          </>}
          {origin?.kind === 'model_task' && <ModelFields origin={origin} locale={story.locale}/>}
          {origin?.kind === 'result' && <p>{words.namedResult} <code>{origin.name}</code></p>}
          {origin?.kind === 'effect_set' && <>
            <p>{words.writePreviewIsUnavailable}</p>
            <details><summary>{words.originalEffectDeclarations}</summary><p>{words.effectSet} <code>{origin.unit_id}</code></p>
              <ul>{origin.members.map(({declaration, write_fields}, position) => <li key={position}>
                <strong>{declaration.effect_kind}</strong> · <code>{declaration.contract.kind === 'mapping'
                  ? declaration.contract.declared_target : declaration.contract.resource_kind}</code>
                {write_fields.state === 'declared' && <p>{words.fields} {write_fields.fields.join(', ')}</p>}
              </li>)}</ul></details>
          </>}
          {open && dataStep && active && (group.kind !== 'source' || saved) && <>
            <StepData locale={story.locale} key={active.stepId} step={dataStep} plan={story} saved={saved} readSample={readSample}
              expectedColumns={port => expectedStoryPortColumns(originalSteps, active, port) ??
                (origin?.kind === 'model_task' && origin.producer.state === 'projected' &&
                  origin.producer.step_id === active.stepId && origin.producer.port_id === port.port_id
                  ? origin.output_fields.map(field => field.name) : undefined)}/>
            {pause?.stepId === active.stepId && <NextInputs locale={story.locale} key={pause.revision} step={dataStep}
              plan={story} steps={steps} pause={pause} readSample={readSample}/>}
          </>}
          {group.kind === 'join' && group.members.length > 1 && <div className="step-data-choice" aria-label={words.originalStepData}>
            {group.members.map((member, index) => <button type="button" className="small" key={member.stepId}
              aria-pressed={active?.stepId === member.stepId} onClick={() => selectStep(member.stepId)}>
              {words.join} {index + 1}{member.stepId === pause?.stepId && <> · {words.stepState.Next}</>}
            </button>)}
          </div>}
          {group.members.map(member => {
            const folded = member !== group.primary && group.kind !== 'join' || group.kind === 'source' ||
              group.kind === 'model' && member.explanation.meaning.kind === 'not_projected';
            const originalLabel = labels.get(member.stepId)?.title;
            return <StepOrigin key={member.stepId} step={member} label={originalLabel} folded={folded} ja={ja}
              state={member.stepId === boundary?.stepId ? boundary.state : undefined}
              select={group.members.length > 1 ? () => selectStep(member.stepId) : undefined}/>;
          })}
          {selectedGroup && model && <PlanAdvanced model={model} ja={ja}/>}
        </StoryCard>;
      })}
    </ol>
  </section>;
}

function WorkspaceDialog({title, close, children, words}: {title: string; close(): void; children: ReactNode; words: ExplorerCopy}) {
  const dialog = useRef<HTMLDialogElement>(null);
  useEffect(()=>{dialog.current?.showModal();}, []);
  return <dialog ref={dialog} className="workspace-dialog" aria-label={title}
    onCancel={event=>{event.preventDefault(); close();}} onClick={event=>{if (event.target === event.currentTarget) close();}}>
    <div className="dialog-content">
      <header><h2>{title}</h2><button type="button" className="small" aria-label={words.closeDialog} onClick={close}>×</button></header>
      {children}
    </div>
  </dialog>;
}

type StopAttempt = Readonly<{
  original: OriginalCancellation;
  observation?: CancellationObservation; history?: WireCancellationLookup;
}>;

function awaitsPhysicalStop(run: RunObservationModel) {
  const stop = run.run.cancellation;
  return stop.state === 'observed' && stop.requested && stop.physicalStop !== 'confirmed';
}

function saveJson(value: unknown, filename: string) {
  const url = URL.createObjectURL(new Blob([JSON.stringify(value, null, 2) + '\n'], {type: 'application/json'}));
  const link = document.createElement('a');
  link.href = url; link.download = filename; link.click();
  setTimeout(() => URL.revokeObjectURL(url), 0);
}

type ResumeAttempt = Readonly<{operation: WireControlOperationRef; receipt?: WireControlOperationLookup}>;
const runKey = (ref: RunReference) => JSON.stringify([ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid]);

function App() {
  const source = useMemo(() => createExplorerBrowserSource({origin: window.location.origin}), []);
  const [connected, connect] = useState(false), [plan, showPlan] = useState<PlanReadModel>();
  const [staticExplanation, showStaticExplanation] = useState<StaticExplanationReadModel>();
  const [run, showRun] = useState<RunObservationModel>(), [result, showResult] = useState<unknown>();
  const [follow, setFollow] = useState(false);
  const [observationAt, markObserved] = useState<number>();
  const [queryShown, showQuery] = useState(true), [editing, setEditing] = useState(false);
  const [graph, showGraph] = useState(false);
  const [drawer, showDrawer] = useState<'connect' | 'open-run' | 'stop'>();
  const [selectedStep, selectStep] = useState<{scope: string; id: string}>();
  const [locale, setLocale] = useState<'en' | 'ja'>('en');
  const ja = locale === 'ja';
  const words = explorerCopy(locale);
  useEffect(() => {document.documentElement.lang = locale;}, [locale]);
  const [analyzedDraft, keepAnalyzedDraft] = useState<{text: string; format: typeof programFormat; debugDefinitionCid?: string}>();
  const [selectedRef, selectRef] = useState<RunReference>();
  const [originalPlan, showOriginalPlan] = useState<OriginalRunPlanReadModel>();
  const [originalPresentation, showOriginalPresentation] = useState<OriginalRunPresentationReadModel | SavedExplanationReadModel>();
  const [programText, setProgramText] = useState('SELECT 1 AS answer');
  const [draftName, setDraftName] = useState<string>();
  const draftVersion = useRef(0);
  const [programFormat, setProgramFormat] = useState<'sql' | 'aql' | 'aql-text' | 'program'>('sql');
  const [runReference, setRunReference] = useState('');
  const [launcherProgram, showLauncherProgram] = useState(false);
  const [error, showError] = useState(''), [pending, busy] = useState(false);
  const [startEnabled, enableStart] = useState(false);
  const [sampleEnabled, enableSamples] = useState(false);
  const [debugResumeEnabled, enableDebugResume] = useState(false);
  const [resumes, saveResumes] = useState<ReadonlyMap<string, ResumeAttempt>>(new Map());
  const preparingResume = useRef(false);
  const [start, showStart] = useState<{ref: WireSubmissionRef;
    state: keyof ExplorerCopy['startStatus']; executionProfile?: 'debug'}>();
  const starting = useRef(false);
  const [cancellationEnabled, enableCancellation] = useState(false);
  const [stops, showStops] = useState<ReadonlyMap<string, StopAttempt>>(new Map());
  const sentStops = useRef(new Set<string>());
  const [stopDraft, stageStop] = useState<OriginalCancellation>();
  const [checkpointPage,showCheckpointPage]=useState<CheckpointPageModel|null>(null);
  const [review,showReview]=useState<ReviewObservation|null>(null);
  const [checkpointCapabilities,setCheckpointCapabilities]=useState({list:false,read:false});
  const reviewSelection=useRef(0);
  const epoch = useRef(0);
  const runSelection = useRef(0);
  const invalidate = useCallback(() => {epoch.current++; runSelection.current++; setFollow(false); source.close(); connect(false); enableCancellation(false); enableStart(false); enableSamples(false); enableDebugResume(false); busy(false);
    selectRef(undefined); selectStep(undefined); showDrawer(undefined); keepAnalyzedDraft(undefined);
    showPlan(undefined); showStaticExplanation(undefined); showRun(undefined); showResult(undefined); showOriginalPlan(undefined); showOriginalPresentation(undefined); showLauncherProgram(false);
    reviewSelection.current++;showCheckpointPage(null);showReview(null);setCheckpointCapabilities({list:false,read:false});
    markObserved(undefined); stageStop(undefined);
    showStops(current => new Map([...current].map(([key, {original}]) => [key, {original}])));
    showError('');}, [source]);
  const perform = async (action: () => Promise<void>) => {
    const original = epoch.current; busy(true); showError('');
    try {await action();}
    catch (error) {
      if (original !== epoch.current) return;
      if (typeof error === 'object' && error !== null && 'code' in error && error.code === 'ExplorerReadUnavailable') {
        showError(words.hostReadFailed);
      } else {
        invalidate();
        showError(words.localLost);
      }
    }
    finally {if (original === epoch.current) busy(false);}
  };
  useEffect(() => {
    if (!follow || !run || pending || !connected || !selectedRef || !sameRun(selectedRef, run.runRef)) return;
    const selection = runSelection.current, scope = epoch.current;
    let active = true;
    const current = () => active && runSelection.current === selection && epoch.current === scope;
    const timer = setTimeout(async () => {
      try {
        const next = await source.observe(run.runRef);
        if (current()) {showRun(next); markObserved(Date.now());}
      } catch (error) {
        if (!current()) return;
        const code = (error as {code?: string} | null)?.code;
        if (code === 'ExplorerSessionExpired' || code === 'ExplorerStaleScope') {
          invalidate();
          showError(words.localLost);
        } else {
          setFollow(false); showRun(undefined); markObserved(undefined);
          showError(words.currentStatusReadFailed);
        }
      }
    }, 1000);
    return () => {active = false; clearTimeout(timer);};
  }, [follow, run, pending, connected, selectedRef, source, invalidate, words]);
  useEffect(() => {
    const toggle = (event: KeyboardEvent) => {
      if (event.altKey || event.metaKey || event.ctrlKey || event.shiftKey ||
          !(event.target instanceof HTMLElement) ||
          event.target.closest('input, textarea, select, button, summary, a, [contenteditable]')) return;
      if (event.key.toLowerCase() === 'q') showQuery(value => !value);
      if (event.key.toLowerCase() === 'g') showGraph(value => !value);
    };
    window.addEventListener('keydown', toggle);
    return () => window.removeEventListener('keydown', toggle);
  }, []);
  const followOriginal = async (ref: RunReference, current: () => boolean) => {
    try {
      const observation = await source.observe(ref);
      if (current()) {
        showRun(observation); markObserved(Date.now());
        setFollow(!observation.run.terminal || awaitsPhysicalStop(observation));
      }
    } catch (error) {
      if (current() && (error as {code?: string} | null)?.code !== 'ExplorerReadUnavailable') throw error;
    }
  };
  const session = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault(); const form = event.currentTarget;
    const token = String(new FormData(form).get('bootstrap')); form.reset(); invalidate();
    void perform(async () => {
      const selected = epoch.current, launchSelection = runSelection.current;
      const capabilities = await source.connect(token);
      if (epoch.current !== selected) return;
      setCheckpointCapabilities({list:capabilities.checkpointList,read:capabilities.checkpointReview});
      enableCancellation(capabilities.cancellation); enableStart(capabilities.runStart === true);
      enableSamples(capabilities.sample); enableDebugResume(capabilities.debugResume === true); connect(true);
      const view = await source.launchView();
      if (epoch.current !== selected) return;
      if (view?.kind === 'program') {
        showLauncherProgram(true); showPlan(view.plan);
      } else if (view?.kind === 'run') {
        const original = view.originalPlan.runRef;
        setRunReference(JSON.stringify(original, null, 2));
        selectRef(original);
        showOriginalPlan(view.originalPlan);
        await followOriginal(original, () => epoch.current === selected && runSelection.current === launchSelection);
      }
    });
  };
  const openDraft = async (event: ChangeEvent<HTMLInputElement>) => {
    const file = event.currentTarget.files?.[0];
    event.currentTarget.value = '';
    if (!file) return;
    const version = ++draftVersion.current;
    const extension = file.name.split('.').at(-1)?.toLowerCase();
    if (file.size > 60000 || !['sql', 'aql', 'json'].some(value=>value === extension)) {
      showError(words.chooseProgramFile);
      return;
    }
    try {
      const text = new TextDecoder('utf-8', {fatal: true}).decode(await file.arrayBuffer());
      if (version !== draftVersion.current) return;
      setProgramText(text); setDraftName(file.name);
      setProgramFormat(extension === 'json' ? 'program' : extension === 'aql' ? 'aql' : 'sql');
      showError('');
    } catch {
      if (version === draftVersion.current) showError(words.invalidFileUtf8);
    }
  };
  const readPlan = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const text = programText, format = programFormat;
    let input: string | Record<string, unknown> = text;
    if (format === 'program') {
      const parsed = parseLocalJson(text);
      if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
        showError(words.invalidProgramJson);
        return;
      }
      input = parsed as Record<string, unknown>;
    }
    const explain = (event.nativeEvent as SubmitEvent).submitter?.getAttribute('value') === 'static-explanation';
    const queryMenu = event.currentTarget.querySelector<HTMLDetailsElement>('.query-menu');
    const scope = epoch.current, selected = ++runSelection.current;
    setFollow(false);
    void perform(async () => {
      const options = format === 'program' ? {} : {format};
      const explanation = explain ? await source.staticExplanation(input, options, locale) : undefined;
      const map = explanation?.plan ?? await source.plan(input, options);
      if (scope !== epoch.current || selected !== runSelection.current) return;
      selectRef(undefined); showRun(undefined); showResult(undefined);
      showOriginalPlan(undefined); showOriginalPresentation(undefined); showLauncherProgram(false);
      showPlan(map); showStaticExplanation(explanation);
      keepAnalyzedDraft({text, format, ...(map.debugEntry === true ? {debugDefinitionCid: map.programDefinitionCid} : {})});
      showGraph(!explain); setEditing(false);
      if (queryMenu) queryMenu.open = false;
    });
  };
  const displayStart = async (answer: ExplorerStartObservation, ref: WireSubmissionRef, selected: number,
    executionProfile?: 'debug') => {
    if (answer.state !== 'ready') {
      showStart({ref, state: answer.state, executionProfile});
      return;
    }
    if (selected !== runSelection.current) {
      showStart({ref, state: 'ready', executionProfile});
      return;
    }
    showStart(undefined);
    setRunReference(JSON.stringify(answer.ref, null, 2));
    selectRef(answer.ref); selectStep(undefined);
    showPlan(undefined); showStaticExplanation(undefined);
    showOriginalPlan(undefined); showOriginalPresentation(undefined);
    showRun(undefined); showResult(undefined);
    const scope = epoch.current;
    const current = () => epoch.current === scope && runSelection.current === selected;
    await followOriginal(answer.ref, current);
    if (executionProfile === 'debug' && current()) {
      // An adopted Run has its own compiler Map. Use that original for the
      // step label and controls once the Host has admitted the Run.
      const original = await source.runPlan(answer.ref);
      if (current()) showOriginalPlan(original);
    }
  };
  const startDraft = (executionProfile?: 'debug') => {
    if (!startEnabled || !connected || starting.current || pending || !analyzedDraft || selectedRef ||
        start && !['not_accepted', 'preparation_failed'].includes(start.state) ||
        analyzedDraft.text !== programText || analyzedDraft.format !== programFormat) return;
    const {text, format, debugDefinitionCid} = analyzedDraft;
    if (executionProfile === 'debug' && debugDefinitionCid === undefined) return;
    const scope = epoch.current, version = draftVersion.current;
    const selected = runSelection.current;
    starting.current = true;
    void perform(async () => {
      try {
        const ref = await source.prepareStart();
        if (epoch.current !== scope || selected !== runSelection.current || version !== draftVersion.current) return;
        showStart({ref, state: 'reply_unknown', executionProfile});
        const answer = await source.startRun(executionProfile === 'debug' && debugDefinitionCid !== undefined
          ? {ref, text, format, executionProfile, programDefinitionCid: debugDefinitionCid}
          : {ref, text, format});
        if (epoch.current === scope) await displayStart(answer, ref, selected, executionProfile);
      } finally {starting.current = false;}
    });
  };
  const lookupStart = () => {
    if (!start || !startEnabled || !connected || pending || starting.current) return;
    const {ref, executionProfile} = start, scope = epoch.current, selected = runSelection.current;
    void perform(async () => {
      const answer = await source.lookupStart(ref);
      if (epoch.current === scope) await displayStart(answer, ref, selected, executionProfile);
    });
  };
  const readOriginal = (original: RunReference, action: string, name = '') => {
    const selected = ++runSelection.current, scope = epoch.current;
    setFollow(false);
    const current = () => runSelection.current === selected && epoch.current === scope;
    const adopt = () => {
      if (!sameRun(original, selectedRef)) {
        showRun(undefined); showResult(undefined); showOriginalPlan(undefined); showOriginalPresentation(undefined);
      }
      selectRef(original); showPlan(undefined); showStaticExplanation(undefined); showLauncherProgram(false);
    };
    void perform(async () => {
      if (action === 'run-explanation-context' || action === 'run-presentation') {
        const view = await (action === 'run-explanation-context'
          ? source.runContext(original, locale) : source.runPresentation(original, {locale}));
        if (!current()) return;
        adopt();
        showOriginalPresentation(view); showRun(undefined); showGraph(false); showDrawer(undefined);
        if (view.plan !== null && view.explanation.state === 'projected' && 'context' in view.explanation &&
          Array.isArray(view.explanation.context) &&
          (view.explanation.context as StoryContext).some(({origin}) => origin.kind === 'result')) {
          // Status uses a separate authorized, bounded read. A Saved Story
          // already admitted on this selection remains visible on refusal.
          try {
            const response = await source.inspect(original);
            if (!current()) return;
            const observation = runObservationModel(response, null, original);
            const binding = observation.planBinding;
            if (observation.run.status === 'succeeded' &&
                (binding.compiledPlanCid === null || binding.compiledPlanCid === view.plan.compiledPlanCid) &&
                (binding.logicalMapCid === null || binding.logicalMapCid === view.plan.logicalMapCid)) {
              showRun(observation); markObserved(Date.now());
            }
          } catch (error) {
            if (!current()) return;
            if (!(typeof error === 'object' && error !== null && 'code' in error &&
              error.code === 'ExplorerReadUnavailable')) throw error;
          }
        }
      } else if (action === 'run-plan') {
        const view = await source.runPlan(original);
        if (!current()) return;
        adopt();
        showOriginalPlan(view);
      } else {
        const observation = await source.observe(original);
        if (!current()) return;
        adopt();
        showRun(observation); markObserved(Date.now()); setFollow(!observation.run.terminal || awaitsPhysicalStop(observation));
        if (name && action === 'inspect') {
          const metadata = await source.describe(original, name);
          if (!current()) return;
          showResult(metadata);
        }
      }
      showDrawer(undefined);
    });
  };
  const readRun = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const original = parseLocalJson(runReference);
    if (!validRunRef(original)) {
      showError(words.invalidRunRef);
      return;
    }
    const action = (event.nativeEvent as SubmitEvent).submitter?.getAttribute('value') ?? 'run-explanation-context';
    const name = String(new FormData(event.currentTarget).get('name') ?? '');
    readOriginal(original, action, name);
  };
  const updateStop = (key: string, attempt: StopAttempt) => {
    showStops(current => new Map(current).set(key, attempt));
  };
  const prepareCancellation = () => {
    if (!run || !connected || !cancellationEnabled || !selectedRef || !sameRun(selectedRef, run.runRef) ||
        run.run.terminal || sentStops.current.has(runKey(selectedRef))) return;
    const original = Object.freeze({cancelRef: Object.freeze({...run.runRef,
      cancelId: crypto.randomUUID(), expectedRevision: run.run.controlRevision}),
      attemptRef: Object.freeze({operation: 'cancel' as const, attemptId: crypto.randomUUID()})});
    stageStop(original); showError(''); showDrawer('stop');
  };
  const requestCancellation = () => {
    if (!stopDraft || !run || !connected || pending || !cancellationEnabled || !selectedRef ||
        !sameRun(selectedRef, stopDraft.cancelRef) || !sameRun(selectedRef, run.runRef)) return;
    if (run.run.terminal || run.run.controlRevision !== stopDraft.cancelRef.expectedRevision) {
      stageStop(undefined); showDrawer(undefined);
      showError(words.theRunChangedCheckItsCurrentStatusBeforeStoppingIt);
      return;
    }
    const original = stopDraft, key = runKey(selectedRef), scope = epoch.current, selection = runSelection.current;
    if (sentStops.current.has(key)) return;
    // Install the original before transport. Reconnection and uncertain
    // delivery leave only the existing lookup route for this invocation.
    sentStops.current.add(key);
    updateStop(key, {original});
    stageStop(undefined); showDrawer(undefined);
    setFollow(true);
    void perform(async () => {
      const observation = await source.cancel(original);
      if (epoch.current === scope && runSelection.current === selection) updateStop(key, {original, observation});
    });
  };
  const lookupCancellation = (stop: StopAttempt) => {
    if (!selectedRef || !connected || !cancellationEnabled || !sameRun(selectedRef, stop.original.cancelRef)) return;
    const key = runKey(selectedRef), scope = epoch.current, selection = runSelection.current;
    void perform(async () => {
      const history = await source.lookupCancellation(stop.original.cancelRef);
      if (epoch.current === scope && runSelection.current === selection) updateStop(key, {...stop, history});
    });
  };
  const importCancellation = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!selectedRef || sentStops.current.has(runKey(selectedRef))) return;
    const input = parseLocalJson(String(new FormData(event.currentTarget).get('original')));
    const record = input as {cancelRef?: unknown; attemptRef?: unknown} | undefined;
    if (!record || Object.keys(record).length !== 2 || !validCancellationRef(record.cancelRef) ||
        !validOperationAttemptRef(record.attemptRef) || record.attemptRef.operation !== 'cancel' ||
        !sameRun(selectedRef, record.cancelRef)) {
      showError(words.enterTheOriginalCancellationReferenceForThisRun);
      return;
    }
    const key = runKey(selectedRef);
    const original = Object.freeze({cancelRef: Object.freeze({...record.cancelRef}),
      attemptRef: Object.freeze({...record.attemptRef, operation: 'cancel' as const})});
    sentStops.current.add(key);
    const stop = {original};
    updateStop(key, stop); lookupCancellation(stop);
  };
  const listCheckpoints=()=>{const selected=++reviewSelection.current,scope=epoch.current;setFollow(false);
    void perform(async()=>{showCheckpointPage(null);showReview(null);const value=await source.checkpoints();
      if(epoch.current===scope&&selected===reviewSelection.current)showCheckpointPage(value);});};
  const readReview=(checkpoint:ReviewReference)=>{const selected=++reviewSelection.current,scope=epoch.current;setFollow(false);
    void perform(async()=>{showReview(null);const value=await source.reviewCheckpoint(checkpoint);
      if(epoch.current===scope&&selected===reviewSelection.current)showReview(value);});};
  const explanation = originalPresentation?.explanation;
  const story = selectedRef
    ? explanation?.state === 'projected' ? explanation.story : undefined
    : staticExplanation?.story;
  const context = selectedRef
    ? explanation?.state === 'projected' && 'context' in explanation ? explanation.context : []
    : staticExplanation?.context ?? [];
  const map = selectedRef ? originalPresentation?.plan ?? originalPlan?.plan : plan;
  const graphLabels = useMemo(()=>graphStepLabels(story, context, map?.stageResultLinks), [story, context, map]);
  const presentation = useMemo(() => {
    if (!story) return undefined;
    const sources = context.filter(item => item.origin.kind === 'source');
    const source = storyProjections(story, sources, map?.stageResultLinks);
    const groups = storyCardGroups(story, context, source, map?.stageResultLinks);
    const graphGroups = groups.map(card => {
      const origin = card.item?.origin;
      return {id: card.primary?.stepId ?? card.id, members: card.members.map(step => step.stepId),
        representative: card.primary?.stepId,
        ...(origin?.kind === 'source' && origin.link_state === 'linked' ? {source: {
          stageOrdinal: origin.stage_input.stage_ordinal, inputOrdinal: origin.stage_input.input_port_ordinal,
          inputs: origin.consuming_ports.map(({step_id, port_id}) => ({stepId: step_id, portId: port_id})),
        }} : {})};
    });
    return {source, groups, graphGroups};
  }, [story, context, map?.stageResultLinks]);
  const planOnly = !story ? map : undefined;
  const originalStep = observedPlanStep(run, selectedRef, map);
  const pause = storyNextPause(run, selectedRef, map, Date.now());
  const exactRun = selectedRef && run && sameRun(run.runRef, selectedRef) &&
    run.planBinding.compiledPlanCid === map?.compiledPlanCid && run.planBinding.logicalMapCid === map?.logicalMapCid
    ? run : undefined;
  const {run: state} = exactRun ?? {};
  const entryPause = state?.status === 'paused' && !state.expiryPending && state.boundary?.kind === 'entry' &&
    state.boundary.position === 'before' ? Date.parse(state.expiresAt ?? '') : NaN;
  const expiration = pause?.expires ?? (entryPause > Date.now() ? entryPause : undefined);
  const [, refreshPause] = useState(0);
  useEffect(() => {
    if (expiration === undefined) return;
    const recheck = () => {
      const remaining = expiration - Date.now();
      if (remaining <= 0) refreshPause(n => n + 1);
      else timer = window.setTimeout(recheck, Math.min(2147483647, remaining));
    };
    let timer: number | undefined;
    recheck();
    return () => window.clearTimeout(timer);
  }, [expiration]);
  const key = selectedRef && runKey(selectedRef);
  const resumeAttempt = key ? resumes.get(key) : undefined;
  const stop = key ? stops.get(key) : undefined;
  const stopOutcome = stop?.observation?.state === 'observed' ? stop.observation.outcome : undefined;
  const cancellation = stop?.history?.kind === 'found' ? stop.history.cancellation :
    stopOutcome?.kind === 'accepted' || stopOutcome?.kind === 'already_satisfied' ? stopOutcome.cancellation : undefined;
  const confirmedStop = run?.run.cancellation.state === 'observed' && run.run.cancellation.physicalStop === 'confirmed' &&
    (!cancellation || run.run.controlRevision >= cancellation.revision);
  const stopping = (cancellation !== undefined && cancellation.kind !== 'already_terminal' ||
    run !== undefined && awaitsPhysicalStop(run)) && !confirmedStop;
  const unresolvedStop = stop !== undefined && cancellation === undefined &&
    stopOutcome?.kind !== 'conflict' && stopOutcome?.kind !== 'refused';
  useEffect(() => {
    if (run?.run.terminal && !stopping) setFollow(false);
  }, [run?.run.terminal, stopping]);
  const previousAccepted = resumeAttempt?.receipt?.state === 'found' && resumeAttempt.receipt.receipt.outcome === 'accepted';
  const sameParkUnresolved = resumeAttempt !== undefined &&
    (!previousAccepted || !state || state.controlRevision <= resumeAttempt.operation.accepted_from_revision);
  const nextPause = !sameParkUnresolved && !stopping && !unresolvedStop ? pause : undefined;
  const boundary = originalStep ? {stepId: originalStep.stepId,
    state: nextPause || entryPause > Date.now() && !sameParkUnresolved ? 'Next' as const : 'Observed' as const} : undefined;
  const resumePause = !stopping && !unresolvedStop && connected && debugResumeEnabled && exactRun?.resumeAvailable && state && expiration &&
    state.controlRevision > 0 && !sameParkUnresolved ? {
      ref: exactRun.runRef, revision: state.controlRevision, expires: expiration,
      step: entryPause > Date.now() || originalStep?.position === 'before',
    } : undefined;
  const keepResume = (run: string, attempt: ResumeAttempt | undefined) => {
    saveResumes(original => {
      const next = new Map(original);
      if (attempt) next.set(run, attempt);
      else next.delete(run);
      return next;
    });
  };
  const requestResume = (until: 'step' | 'terminal') => {
    if (!resumePause || pending || preparingResume.current || resumePause.expires <= Date.now() ||
        until === 'step' && !resumePause.step) return;
    const {ref, revision, expires} = resumePause;
    const scope = epoch.current, selected = runSelection.current, run = runKey(ref);
    const current = () => epoch.current === scope && runSelection.current === selected;
    preparingResume.current = true;
    setFollow(false);
    void perform(async () => {
      try {
        const command = await source.prepareResume(ref, {operationId: crypto.randomUUID(), expectedRevision: revision, until});
        if (!current() || expires <= Date.now()) return;
        const operation = resumeControlOperationRef(command);
        keepResume(run, {operation});
        showRun(undefined);
        const answer = await source.resume(command);
        if (answer.state !== 'reply_unknown') keepResume(run, {operation, receipt: answer});
        if (!current() || answer.state !== 'found' || answer.receipt.outcome !== 'accepted') return;
        const observed = await source.observe(ref);
        if (current()) {showRun(observed); markObserved(Date.now()); setFollow(!observed.run.terminal || awaitsPhysicalStop(observed));}
      } catch (error) {
        const code = (error as {code?: string} | null)?.code;
        if (code === 'ExplorerControlRevisionConflict' || code === 'ExplorerResumeUnsupported') {
          keepResume(run, resumeAttempt);
          if (current()) showError(code === 'ExplorerControlRevisionConflict'
            ? 'The Run changed. Inspect the current status before choosing another action.'
            : words.pauseActionUnavailable);
        } else if (current()) throw error;
      } finally {preparingResume.current = false;}
    });
  };
  const lookupResume = () => {
    if (!connected || !debugResumeEnabled || pending || !key || !resumeAttempt) return;
    const {operation} = resumeAttempt;
    void perform(async () => {
      const receipt = await source.lookupControlOperation(operation);
      keepResume(key, {operation, receipt});
    });
  };
  const readSample = useCallback<SampleRead>(async port => {
    if (!connected || !sampleEnabled || !selectedRef) return;
    const scope = epoch.current, selection = runSelection.current;
    const current = () => epoch.current === scope && runSelection.current === selection;
    try {
      const sample = await source.runSample(selectedRef, port);
      if (current()) return sample;
    } catch (error) {
      if (!current()) return;
      const code = (error as {code?: string} | null)?.code;
      if (code === 'ExplorerSessionExpired' || code === 'ExplorerStaleScope') {
        invalidate();
        showError(words.localLost);
        return;
      }
      throw error;
    }
    return undefined;
  }, [connected, sampleEnabled, selectedRef, source, invalidate]);
  const sample = sampleEnabled && selectedRef ? readSample : undefined;
  const scopeKey = JSON.stringify([epoch.current, selectedRef, map?.compiledPlanCid, map?.logicalMapCid, story?.factsCid]);
  const stepScope = JSON.stringify([scopeKey, originalStep?.stepId, originalStep?.position, nextPause?.revision, nextPause?.boundaryCid]);
  const edited = analyzedDraft !== undefined &&
    (analyzedDraft.text !== programText || analyzedDraft.format !== programFormat);
  const draftStartPending = !connected || pending || !analyzedDraft || edited ||
    !!start && !['not_accepted', 'preparation_failed'].includes(start.state);
  const selection = selectedStep?.scope === stepScope ? selectedStep.id :
    boundary?.stepId ?? (graph || planOnly ? presentation?.graphGroups[0]?.id ?? map?.nodes[0]?.id : undefined);
  const setSelection = (id: string) => selectStep({scope: stepScope, id});
  const savedRun = words.savedRun;
  const liveRun = run !== undefined && !run.run.terminal && follow;
  const runMode = run?.run.status === 'paused' && exactRun ? words.debugRun :
    liveRun ? words.liveRun : savedRun;
  const status = stopping ? words.stopping :
    run?.run.status === 'paused' ? originalStep ? words.pausedAtStep(originalStep.position, originalStep.number) :
      state?.boundary?.kind === 'entry' ? words.pausedAtEntry : words.paused :
    run?.run.status === 'succeeded' ? words.finishedWritesUnknown :
    run?.run.status === 'failed' ? originalStep ? words.failedAtStep(originalStep.number) : words.failed :
    run?.run.status === 'cancelled' ? confirmedStop ?
      originalStep ? words.stoppedAtStep(originalStep.position, originalStep.number) : words.stopped :
      words.cancelledPhysicalStopUnconfirmed :
    run ? words.runStatus(run.run.status) :
    selectedRef ? words.currentStatusUnavailable :
    map ? words.planCheckedNotRun : words.noRunSelected;
  const stopStatus = unresolvedStop ? words.originalStopOutcomeIsUnconfirmed :
    stopOutcome?.kind === 'conflict' ? words.stopConflictTheRunChanged :
    stopOutcome?.kind === 'refused' ? words.stopRefused : undefined;
  const stopEnabled = connected && cancellationEnabled && !!run && !run.run.terminal && selectedRef !== undefined &&
    sameRun(selectedRef, run.runRef) && !stop && !stopping;
  const observedTime = observationAt === undefined ? undefined :
    new Date(observationAt).toLocaleTimeString(words.enGb, {hour12: false});
  const launcherCommand = 'npx actql-explorer --local --state-dir .actql --run run.json';
  const cliRunId = run && /^[A-Za-z0-9][A-Za-z0-9._:-]*$/u.test(run.run.id) ? run.run.id : '"$RUN_ID"';
  const cliCommand = 'actql status ' + cliRunId;
  const copyCommand = (command: string) => {
    void navigator.clipboard.writeText(command).catch(() => showError(words.couldNotCopyTheCommand));
  };
  const supportedCheckpoint = connected && (checkpointCapabilities.list || checkpointCapabilities.read);
  const fileLabel = selectedRef ? words.originalQuery : draftName ?? words.queryDraft;
  const independentDraft = !!selectedRef || launcherProgram;
  const draftStatus = independentDraft ? (editing ? words.editingIndependentDraft : words.independentDraft) :
    editing ? words.editingDraft : draftName ? words.loadedFile(draftName) : words.localQueryDraft;
  const openDrawer = (next: 'connect' | 'open-run') => {showError(''); showDrawer(next);};
  const closeDrawer = () => {showDrawer(undefined); stageStop(undefined); showError('');};
  return <div className="explorer-workspace">
    <header className="workspace-header">
      <div className="workspace-brand"><strong><span aria-hidden="true">&gt;</span> ActQL<span aria-hidden="true">_</span></strong>
        <span>Explorer</span><span className="breadcrumb-divider" aria-hidden="true">/</span>
      <span className="workspace-label" aria-label={launcherProgram && !selectedRef ? words.localDraftFile : undefined}>{fileLabel}</span>
      </div>
      <div className="workspace-actions">
        <button type="button" className="small" onClick={()=>showQuery(value=>!value)}
          aria-controls="query-pane" aria-expanded={queryShown}>{queryShown ? words.hideQuery : words.showQuery} <kbd>Q</kbd></button>
        <div className="view-switch" role="group" aria-label={words.planView}>
          <button type="button" className="small" aria-pressed={!graph} onClick={()=>showGraph(false)}>{words.steps}</button>
          <button type="button" className="small" aria-pressed={graph} onClick={()=>showGraph(true)}>{words.graph} <kbd>G</kbd></button>
        </div>
        {connected ? <details className="toolbar-menu connection-menu">
          <summary><span className="connection-dot"/>{words.local} <span className="sr-only">{words.connection}</span></summary>
          <div className="panel terminal-card"><p>{words.gatewayConnected}</p>
            <button type="button" className="small" onClick={invalidate}>{words.disconnect}</button></div>
        </details> : <button type="button" className="small connect-button" onClick={()=>openDrawer('connect')}>
          <span className="connection-dot" data-connected={false}/>{error ? words.reconnect : words.connectLocal}</button>}
        <details className="shortcut-help"><summary aria-label={words.keyboardShortcuts}>?</summary>
          <div className="panel shortcut-card"><p><kbd>Q</kbd> {words.toggleQueryPane}</p><p><kbd>G</kbd> {words.switchViews}</p></div>
        </details>
      </div>
    </header>
    <div className={'workspace-grid' + (queryShown ? '' : ' query-hidden')}>
      {queryShown && <aside id="query-pane" className="query-panel panel" aria-label={words.query}>
        <header><div><span className="connection-dot" data-connected={!independentDraft && !!analyzedDraft && !edited}/>
          <span>{selectedRef ? fileLabel : draftStatus}</span></div>
          {!selectedRef && <button className="small" type="button" onClick={()=>setEditing(value=>!value)}>
            {editing ? words.done : words.edit}
          </button>}</header>
        {selectedRef ? <p className="query-scope-note">{words.originalQueryNotRetainedInThisRead}</p> : <>
        {independentDraft && <p className="query-scope-note">{words.launcherDraft}</p>}
        {editing ? <label className="query-editor"><span className="sr-only">{words.program}</span>
          <textarea value={programText} onChange={event=>{draftVersion.current++; setProgramText(event.target.value);}}
            maxLength={60000} rows={8} spellCheck={false}/>
        </label> : <ol className="query-lines" aria-label={words.queryText}>
          {programText.split('\n').map((line,index)=><li key={index}><code>{line || ' '}</code></li>)}</ol>}
        <form className="query-controls" onSubmit={readPlan}>
          <span className="query-format">{words.programFormat[programFormat]}</span>
          <button className="small primary" value="static-explanation" disabled={!connected || pending || !programText}>{words.explain}</button>
          <details className="toolbar-menu query-menu"><summary aria-label={words.queryOptions}>⋯</summary>
            <div className="panel query-options">
              <label className="query-file">{words.openQueryFile} <input type="file" accept=".sql,.aql,.json" onChange={event=>void openDraft(event)}/></label>
              <label>{words.format} <select name="format" value={programFormat} onChange={event=>{draftVersion.current++; setProgramFormat(event.target.value as typeof programFormat);}}>
                <option value="sql">SQL</option><option value="aql">AQL</option><option value="aql-text">{words.programFormat['aql-text']}</option><option value="program">{words.programFormat.program}</option></select></label>
              <label>{words.language} <select value={locale} onChange={event=>setLocale(event.target.value === 'ja' ? 'ja' : 'en')}>
                <option value="en">English</option><option value="ja">日本語</option></select></label>
              <button className="small" disabled={!connected || pending || !programText}>{words.readPlan}</button>
            </div>
          </details>
        </form>
        </>}
      </aside>}
      <main className="story-workspace">
        <div className="story-heading">
          <p className="eyebrow">{selectedRef ? <>{runMode} <code>{run?.run.id ?? selectedRef.runDefinitionCid.slice(7, 19)}</code></> :
            map ? words.beforeRunCheckedPlan : words.beforeRun}</p>
          {run && <p className="observation-line">{words.observedAt(run.run.updatedAt)}{run.run.cleanupPending ? words.cleanupPendingSuffix : ''}</p>}
          {story ? <StoryHeading story={story} context={context}/> : <h1>{selectedRef ?
            explanation?.state === 'not_projected' ? words.savedExplanationUnavailable : words.originalRun :
            map ? words.inspectCheckedPlan : words.explainQuery}</h1>}
          {explanation?.state === 'not_projected' && <p className="workspace-note">{explanation.reason === 'not_retained'
            ? words.explanationNotRetained : words.explanationUnsupported}</p>}
          {!selectedRef && !map && <p className="workspace-note">{words.openQueryPrompt}</p>}
        </div>
        <div className="run-toolbar" aria-label={words.runControls}>
          <span className="workspace-chip">{selectedRef ? runMode : words.noRunYet}</span>
          {!selectedRef && startEnabled && <>
            <button className={analyzedDraft?.debugDefinitionCid && !edited ? "small" : "small primary"}
              type="button" onClick={()=>startDraft()} disabled={draftStartPending}>{words.run}</button>
            {analyzedDraft?.debugDefinitionCid && !edited && <button className="small primary" type="button"
              onClick={()=>startDraft('debug')} disabled={draftStartPending}>{words.debug}</button>}
          </>}
          <button className="small" type="button" disabled={!connected || pending} onClick={()=>openDrawer('open-run')}>{words.openRun}</button>
          {selectedRef && !originalPresentation && <button className="small" type="button" disabled={pending}
            onClick={()=>readOriginal(selectedRef, 'run-explanation-context')}>{words.readStory}</button>}
          {selectedRef && !map && <button className="small" type="button" disabled={pending}
            onClick={()=>readOriginal(selectedRef, 'run-plan')}>{words.readSavedPlan}</button>}
          {selectedRef && <button className="small" type="button" disabled={pending}
            onClick={()=>readOriginal(selectedRef, 'inspect')}>{words.inspectStatus}</button>}
          {resumePause && <div className="step-data-choice" aria-label={words.pausedRunActions}>
            {resumePause.step && <button type="button" className="small" disabled={pending}
              onClick={() => requestResume('step')}>{words.step}</button>}
            <button type="button" className="small" disabled={pending}
              onClick={() => requestResume('terminal')}>{words.continue}</button>
          </div>}
          {stopEnabled && <button type="button" className="small" disabled={pending}
            onClick={prepareCancellation}>{words.stop}</button>}
          <span className="run-status" role="status" data-known={!!run || !selectedRef}><span className="status-dot"/>
            {!connected ? words.localDisconnected :
              pending && !run ? words.reading : status}</span>
          {follow && observedTime && run && (!run.run.terminal || stopping || unresolvedStop) &&
            <span className="live-observation">{words.live} · {observedTime}</span>}
          {stopStatus && <span className="stop-observation" role="status">{stopStatus}</span>}
          {selectedRef && <details className="toolbar-menu terminal-menu">
            <summary>{words.terminal}</summary>
            <div className="panel terminal-card">
              <pre>{launcherCommand}</pre>
              <button className="small" type="button" onClick={()=>copyCommand(launcherCommand)}>{words.copy}</button>
              <pre>{cliCommand}</pre>
              <button className="small" type="button" onClick={()=>copyCommand(cliCommand)}>{words.copy}</button>
              <button className="small" type="button" onClick={()=>saveJson(selectedRef, 'run.json')}>
                {words.saveAsRunJson}</button>
              {cancellationEnabled && <details><summary>{words.lookUpOriginalStop}</summary>
                {stop ? <>
                  <button type="button" className="small" disabled={pending}
                    onClick={()=>lookupCancellation(stop)}>{words.lookUp}</button>
                  <button type="button" className="small" onClick={()=>saveJson(stop.original, 'actql-original-cancellation.json')}>
                    {words.saveCancellationReference}</button>
                  {cancellation && <p>{cancellation.kind} · {words.controlRevision} {cancellation.revision}</p>}
                  {stop.history?.kind === 'unknown' && <p>{words.originalCancellationHistoryIsUnknown}</p>}
                </> : <form onSubmit={importCancellation}>
                  <label>{words.originalCancellationReferenceJson}
                    <textarea name="original" maxLength={8192} required/></label>
                  <button type="submit" disabled={pending}>{words.lookUp}</button>
                </form>}
              </details>}
            </div>
          </details>}
        </div>
        {start && <details className="workspace-tools panel"><summary>{words.startStatus[start.state]}</summary>
          <p>{words.startLookupHint}</p>
          <button className="small" type="button" onClick={lookupStart}
            disabled={!connected || !startEnabled || pending}>{words.lookupStart}</button>
          <pre aria-label={words.originalSubmission}>{JSON.stringify(start.ref, null, 2)}</pre>
        </details>}
        {error && !drawer && <p className="workspace-notice" role="alert">{error}</p>}
        {edited && !selectedRef && map && <p className="workspace-notice">{words.changedDraft}</p>}
        {map && <div className="inspection-strip">
          {resumeAttempt && <button type="button" className="small" disabled={!connected || pending || !debugResumeEnabled}
            onClick={lookupResume}>{words.lookUpOriginalControl}</button>}
          {resumeAttempt && <p role="status">{previousAccepted ? words.resumeAccepted :
            words.originalControlOutcomeIsUnconfirmed}</p>}
          {run?.run.status === 'paused' && !resumePause && <details className="toolbar-menu capability-menu"><summary>{words.stepControlsUnavailable}</summary>
            <div className="panel terminal-card">
              <p>{words.durableControlsUnavailable}</p>
              {!sampleEnabled && <p>{words.relationSampleUnavailable}</p>}
              <p>{words.sealedReviewUnavailable}</p>
              <p>{words.checkpointSeparate}</p>
            </div>
          </details>}
        </div>}
        {graph && map && <PlanExplorer model={map} initialView="flow" scopeKey={scopeKey}
          workspace={{stepId: selection, select: setSelection, groups: presentation?.graphGroups, locale,
            label: id => {
              const group = presentation?.groups.find(card => (card.primary?.stepId ?? card.id) === id);
              const effect = group?.item?.origin.kind === 'effect_set' ? declaredWrite(group.item.origin) : undefined;
              if (effect) return {
                kind: words.declaredWrite,
                title: effect.target && effect.update ? words.updateTarget(effect.target)
                  : effect.target ?? words.declaredChanges,
                effectDeclaration: {fields: effect.fields?.join(words.listJoin),
                  missingProducer: words.producerLinkNotProjected},
              };
              return group && story ? {
                state: stepStateLabel(group.members.some(member => member.stepId === boundary?.stepId)
                  ? boundary?.state : selectedRef ? undefined : 'Planned', ja),
                kind: storyGroupLabel(group, ja), title: storyGroupTitle(group, graphLabels, ja),
                sourceInput: group.kind === 'source',
              } : {state: stepStateLabel(stepState(id, !!selectedRef, boundary), ja), ...graphLabels.get(id)};
            }}}/>}
        {planOnly && <PlanSteps key={stepScope} map={planOnly} boundary={boundary} selection={selection}
          select={setSelection} graph={graph} locale={locale} pause={nextPause} readSample={sample} saved={!!selectedRef}/>}
        {story && presentation && <StorySteps key={scopeKey} story={story} groups={presentation.groups}
          sourceColumns={presentation.source} model={map} boundary={boundary} saved={!!selectedRef} selectedStep={selection}
          selectStep={setSelection} graph={graph} labels={graphLabels} pause={nextPause} readSample={sample}/>}
        {graph && !map && <p className="workspace-note">{words.readPlanToSeeGraph}</p>}
        {!graph && !story && !planOnly && map && <p className="workspace-note">{words.chooseGraph}</p>}
        {run && <details className="workspace-tools panel"><summary>{words.currentRunObservations}</summary><RunInspector model={run} locale={locale}/></details>}
        {result !== undefined && <details className="workspace-tools panel"><summary>{words.namedResultMetadata}</summary><pre>{JSON.stringify(result, null, 2)}</pre></details>}
        {(supportedCheckpoint || run?.run.status === 'waiting_checkpoint') &&
          <details className="workspace-tools panel"><summary>{words.checkpointReview}</summary>
            <CheckpointPanel locale={locale} page={checkpointPage} review={review} pending={pending}
              canList={connected&&checkpointCapabilities.list} canRead={connected&&checkpointCapabilities.read}
              onList={listCheckpoints} onRead={readReview}/>
          </details>}
      </main>
    </div>
    {drawer === 'stop' && stopDraft && <WorkspaceDialog title={words.stopThisRun} close={closeDrawer} words={words}>
      <p>{words.requestAStopForThisRunAtTheObservedRevision}</p>
      <button className="small" type="button" onClick={closeDrawer}>{words.back}</button>{' '}
      <button className="small primary" type="button" disabled={pending} onClick={requestCancellation}>
        {words.requestStop}</button>
    </WorkspaceDialog>}
    {drawer === 'connect' && <WorkspaceDialog title={words.connectLocal} close={closeDrawer} words={words}>
      <p className="workspace-note">{words.newBootstrap}</p>
      <form onSubmit={session}>
        <label>{words.bootstrap} <input name="bootstrap" type="password" autoComplete="off" maxLength={43} required disabled={pending}/></label>
        <button className="primary" disabled={pending}>{words.connect}</button>
      </form>
      {error && <p role="alert">{error}</p>}
    </WorkspaceDialog>}
    {drawer === 'open-run' && <WorkspaceDialog title={words.openRun} close={closeDrawer} words={words}>
      <form className="run-reference-form" onSubmit={readRun}>
        <label>{words.runReference}<textarea name="ref" value={runReference} onChange={event=>setRunReference(event.target.value)}
          maxLength={4096} rows={4} required spellCheck={false}/></label>
        {error && <p role="alert">{error}</p>}
        <button className="primary" value="run-explanation-context" disabled={pending}>{words.openSavedExplanation}</button>
        <details className="run-options"><summary>{words.otherOriginalReads}</summary>
          <label>{words.namedResult} <input name="name" maxLength={1024}/></label>
          <label>{words.language} <select value={locale} onChange={event=>setLocale(event.target.value === 'ja' ? 'ja' : 'en')}>
            <option value="en">English</option><option value="ja">日本語</option></select></label>
          <div className="toolbar-form-actions">
            <button value="inspect" disabled={pending}>{words.inspectStatus}</button>
            <button value="run-plan" disabled={pending}>{words.readSavedPlan}</button>
            <button value="run-presentation" disabled={pending}>{words.readOriginalFacts}</button>
          </div>
        </details>
      </form>
    </WorkspaceDialog>}
  </div>;
}
createRoot(document.getElementById('root')!).render(<App/>);
