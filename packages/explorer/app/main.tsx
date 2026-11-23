import type {CheckpointPageModel,ReviewObservation,ReviewReference} from '@actql/explorer-ui/checkpoint-review';
import {useEffect, useMemo, useRef, useState, type ChangeEvent, type FormEvent, type ReactNode} from 'react';
import {createRoot} from 'react-dom/client';
import {PlanExplorer, RunInspector, CancellationPanel, CheckpointPanel} from '@actql/explorer-ui/plan-explorer';
import type {OriginalCancellation, CancellationObservation} from '@actql/explorer-ui/plan-explorer';
import {validCancellationRef, validOperationAttemptRef, validRunRef} from '@actql/client-wire';
import type {RunReference} from '@actql/sdk';
import type {WireCancellationLookup, WireSubmissionRef} from '@actql/client-wire';
import {observedPlanStep, type RunObservationModel} from '@actql/explorer-ui/run-observation';
import type {PlanReadModel, StaticExplanationReadModel, OriginalRunPlanReadModel, OriginalRunPresentationReadModel, SavedExplanationReadModel, ExplanationStoryModel} from '@actql/explorer-ui/read-model';
import {createExplorerBrowserSource, type ExplorerStartObservation} from '@actql/explorer/browser-source';
import '@actql/explorer-ui/styles.css';
import './styles.css';

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
  const effects = context.some(({origin}) => origin.kind === 'effect_set' && origin.members.length > 0);
  const ja = story.locale === 'ja';
  return <>
    <h1><StoryText text={story.narrative.summary}/></h1>
    <div className="story-chips">
      {effects && <span className="workspace-chip" data-tone="amber">{ja ? '書き込みを宣言 · 判断は未確認' : 'Effect declared · decision unknown'}</span>}
      {sources > 0 && <span className="workspace-chip" data-tone="teal">{ja ? `読み取り元 ${sources} 件` :
        `${sources} declared ${sources === 1 ? 'source' : 'sources'}`}</span>}
      {models > 0 && <span className="workspace-chip" data-tone="lilac">{ja ? `モデルタスク ${models} 件 · 入力行ごと` :
        `${models} Model ${models === 1 ? 'task' : 'tasks'} · input rows`}</span>}
    </div>
  </>;
}

type StepState = 'Planned' | 'Unknown' | 'Observed';

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
  for (const step of story?.occurrences ?? []) {
    const inputs = sources.get(step.stepId), models = tasks.get(step.stepId), outputs = results.get(step.stepId);
    const {meaning} = step.explanation;
    const inputNames = inputs?.map(input=>input.resource).join(', ');
    const inputDetail = inputNames ? `${ja ? '入力' : 'Input'} · ${inputNames}` : undefined;
    if (meaning.kind === 'join') {
      const key = meaning.keys.find(({left, right})=>!left.startsWith('aql_') && !right.startsWith('aql_'));
      const name = ja ? '結合' : 'Join';
      labels.set(step.stepId, {kind: ja ? 'データ結合' : 'Combine', title: key ?
        `${name} · ${key.left} = ${key.right}` :
        meaning.keys.length ? (ja ? '確認済みのキーで結合' : 'Join on checked keys') : name, inputs: inputDetail});
    } else if (models?.length) {
      labels.set(step.stepId, {kind: 'Model', title: `${ja ? 'モデル' : 'Ask'} ${models.join(', ')}`,
        inputs: inputDetail});
    } else if (inputs?.length && inputDetail) {
      // A linked declaration names the input port; it does not make this
      // logical occurrence an actual Source attempt or another Graph node.
      const systems = new Set(inputs.map(input=>input.connector));
      labels.set(step.stepId, {kind: systems.size === 1 ? inputs[0].connector : ja ? '入力' : 'Inputs',
        title: inputDetail, sourceInput: true});
    } else if (outputs?.length) {
      labels.set(step.stepId, {kind: 'Result', title: `${ja ? '結果' : 'Return'} ${outputs.join(', ')}`});
    } else if (meaning.kind === 'projection' && meaning.operation === 'select') {
      labels.set(step.stepId, {title: ja ? 'フィールドを選択' : 'Select fields'});
    } else if (step.operator === 'filter') {
      labels.set(step.stepId, {title: ja ? '行を絞り込む' : 'Filter rows'});
    }
  }
  return labels;
}

function stepTitle(step: Step, label?: string) {
  if (label) return label;
  const names = step.names.filter(name=>!name.startsWith('aql_'));
  if (names.length) return names.join(', ');
  return step.operator?.replaceAll('_', ' ').replace(/^./u, char=>char.toUpperCase()) ?? 'Input / output';
}

function stepState(stepId: string, saved: boolean, boundary?: {stepId: string; state: StepState}): StepState | undefined {
  return stepId === boundary?.stepId ? boundary.state : saved ? undefined : 'Planned';
}

function StoryCard({ordinal, label, title, detail, system, state, open, selected, onToggle, children}: {
  ordinal: number; label: string; title: string; detail?: string; system?: string; state?: StepState;
  open: boolean; selected?: boolean; onToggle(): void; children: ReactNode;
}) {
  return <li className="story-row" data-state={state}>
    <span className="step-marker" aria-hidden="true">{ordinal}</span>
    <details className="story-card panel" open={open} data-selected={selected}>
      <summary onClick={event=>{event.preventDefault(); onToggle();}}>
        <span className="step-label">{label}
          {system && <span className="workspace-chip step-system">{system}</span>}
          {state && <span className="workspace-chip step-state" data-state={state}>{state}</span>}</span>
        <strong><StoryText text={title}/></strong>
        {detail && title !== detail && <span className="step-summary"><StoryText text={detail}/></span>}
      </summary>
      <div className="step-details">{children}</div>
    </details>
  </li>;
}

type PlanNode = PlanReadModel['nodes'][number];

function planNodeTitle(node: PlanNode, locale: 'en' | 'ja') {
  return node.operator?.replaceAll('_', ' ').replace(/^./u, char => char.toUpperCase()) ??
    (locale === 'ja' ? '入出力' : 'Input / output');
}

function PlanSteps({map, boundary, selection, select, graph, locale}: {
  map: PlanReadModel; boundary?: {stepId: string; state: StepState}; selection?: string;
  select(id: string): void; graph: boolean; locale: 'en' | 'ja';
}) {
  const [collapsed, setCollapsed] = useState<string>();
  const ja = locale === 'ja';
  return <section aria-label={graph ? 'Selected Step' : 'Original steps'}>
    <ol className="story-steps">
      {map.nodes.map((node, index) => {
        const selected = selection === node.id;
        if (graph && !selected) return null;
        const open = graph || selected && collapsed !== node.id;
        return <StoryCard key={node.id} ordinal={index + 1} label={ja ? '論理工程' : 'Logical step'}
          title={planNodeTitle(node, locale)} selected={selected}
          state={node.id === boundary?.stepId ? boundary.state : undefined}
          open={open} onToggle={() => {
            select(node.id);
            setCollapsed(open && !graph ? node.id : undefined);
          }}>
          <details><summary>{ja ? '元の工程とポート' : 'Original step and ports'}</summary>
            {node.names.length > 0 && <p>{node.names.map(name => <code key={name}>{name}</code>)}</p>}
            <code>{node.id}</code>
            <ul>{node.ports.map(port => <li key={port.port_id}>
              {port.role} · {port.carrier} · <code>{port.port_id}</code>
            </li>)}</ul>
          </details>
        </StoryCard>;
      })}
    </ol>
  </section>;
}

function StepOrigin({step, label, select}: {step: Step; label?: string; select?(): void}) {
  return <div className="occurrence-origin">
    <strong>{stepTitle(step, label)}</strong><p><StoryText text={step.explanation.text}/></p>
    <details><summary>Original step and ports</summary>
      {step.names.length > 0 && <p>{step.names.map(name=><code key={name}>{name}</code>)}</p>}
      {select && <button type="button" className="small" onClick={select}>Select original step</button>}
      <code>{step.stepId}</code>
      <ul>{step.ports.map(port=><li key={port.port_id}>{port.role} · <code>{port.port_id}</code></li>)}</ul>
    </details>
  </div>;
}

type KeptColumns = {step: Step; columns: readonly string[]};

// A same-name field selection can be described in its caller's card when
// the original Plan links that exact port. The field list is still shown
// because selection can drop columns even though it keeps their values.
function storyProjections(story: ExplanationStoryModel, sources: StoryContext,
  context: StoryContext, stageResultLinks: PlanReadModel['stageResultLinks']) {
  const source = new Map<number, KeptColumns>(), model = new Map<string, KeptColumns>();
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
  const edgesByProducer = new Map<string, typeof story.dependencies[number][]>();
  const edgesByConsumer = new Map<string, typeof story.dependencies[number][]>();
  for (const edge of story.dependencies) {
    const bySource = edgesByProducer.get(edge.sourceStepId), byTarget = edgesByConsumer.get(edge.targetStepId);
    if (bySource) bySource.push(edge);
    else edgesByProducer.set(edge.sourceStepId, [edge]);
    if (byTarget) byTarget.push(edge);
    else edgesByConsumer.set(edge.targetStepId, [edge]);
  }
  for (const {origin} of context) {
    if (origin.kind !== 'model_task' || origin.producer.state !== 'projected') continue;
    const {step_id} = origin.producer;
    const consumer = steps.get(step_id);
    if (consumer?.operator !== 'infer') continue;
    const incoming = edgesByConsumer.get(step_id);
    if (incoming?.length !== 1 || model.has(step_id)) continue;
    const edge = incoming[0], selection = kept(steps.get(edge.sourceStepId));
    const port = consumer.ports.find(port => port.port_id === edge.targetPortId);
    const producer = port?.source;
    if (!selection || edgesByProducer.get(edge.sourceStepId)?.length !== 1 ||
        edge.sourcePortId !== selection.output.port_id || origin.input_bindings.length !== selection.columns.length ||
        port?.role !== 'input' || port.carrier !== 'relation' || producer?.kind !== 'logical_output' ||
        producer.step_id !== edge.sourceStepId || producer.output_port_id !== edge.sourcePortId) continue;
    const inputs = new Set(origin.input_bindings.flatMap(({binding}) => binding.state === 'field' ? [binding.name] : []));
    if (inputs.size !== selection.columns.length || !selection.columns.every(column => inputs.has(column))) continue;
    model.set(step_id, selection);
    claimed.add(selection.step.stepId);
  }
  return {source, model, claimed};
}

function StorySteps({story, context, saved, boundary, selectedStep, selectStep, graph, labels, stageResultLinks}: {
  story: ExplanationStoryModel; context: StoryContext; saved: boolean;
  boundary?: {stepId: string; state: StepState}; selectedStep?: string;
  selectStep(id: string): void; graph: boolean; labels: ReturnType<typeof graphStepLabels>;
  stageResultLinks: PlanReadModel['stageResultLinks'];
}) {
  const [opened, setOpened] = useState<Record<string, boolean>>({});
  const sources = context.filter(item=>item.origin.kind === 'source');
  const projections = storyProjections(story, sources, context, stageResultLinks);
  const outputs = context.filter(item=>item.origin.kind === 'result' || item.origin.kind === 'effect_set');
  const models = new Map<string, StoryContext[number][]>();
  const unboundModels: StoryContext[number][] = [];
  for (const item of context) if (item.origin.kind === 'model_task') {
    const producer = item.origin.producer;
    if (producer.state === 'projected') {
      if (!models.has(producer.step_id)) models.set(producer.step_id, []);
      models.get(producer.step_id)!.push(item);
    } else unboundModels.push(item);
  }
  const groups: Step[][] = [];
  for (const step of story.occurrences) {
    if (!graph && projections.claimed.has(step.stepId)) continue;
    const current = groups.at(-1);
    if (step.operator === 'join' && current?.[0]?.operator === 'join') current.push(step);
    else groups.push([step]);
  }
  const unobserved = saved ? undefined : 'Planned';
  let ordinal = 0;
  const card = (id: string, defaultOpen: boolean, selected?: string) => ({
    ordinal: ++ordinal, open: graph || (opened[id] ?? defaultOpen),
    onToggle() {
      if (selected) selectStep(selected);
      if (!graph) setOpened(values=>({...values, [id]: !(values[id] ?? defaultOpen)}));
    },
  });
  return <section aria-label={graph ? 'Selected Step' : 'Original story'}>
    <ol className="story-steps">
      {!graph && sources.map(({origin,text}, index)=>{
        if (origin.kind !== 'source') return null;
        const projection = projections.source.get(index);
        const step = projection?.step;
        const selected = step !== undefined && step.stepId === selectedStep;
        const observed = step !== undefined && step.stepId === boundary?.stepId;
        return <StoryCard
          key={`source-${origin.stage_input.stage_ordinal}-${origin.stage_input.input_port_ordinal}`}
          {...card(`source-${index}`, !saved && index === 0 || selected || observed, step?.stepId)}
          selected={selected}
          label="Read" title={`Read "${origin.source_view.resource}"`} detail={text}
          system={origin.source_view.connector} state={step ? stepState(step.stepId, saved, boundary) : unobserved}>
          <p>Stage {origin.stage_input.stage_ordinal + 1} · input {origin.stage_input.input_port_ordinal + 1}</p>
          {projection && <p>{story.locale === 'ja' ? '保持する列' : 'Selected columns'} · {projection.columns.join(', ')}</p>}
          {step && <StepOrigin step={step} label={labels.get(step.stepId)?.title} select={()=>selectStep(step.stepId)}/>}
          <p>Bounded Source data is not available in this view.</p>
          <details><summary>Original Source and links</summary>
            <dl><dt>Contract</dt><dd><code>{origin.source_view.contract_cid}</code></dd>
              <dt>Catalog</dt><dd><code>{origin.source_view.catalog_cid}</code></dd></dl>
            {origin.consuming_ports.length > 0 && <ul aria-label="Original consumers">
              {origin.consuming_ports.map(port=><li key={port.port_id}><code>{port.step_id}</code><br/><code>{port.port_id}</code></li>)}</ul>}
          </details>
        </StoryCard>;
      })}
      {groups.map(group=>{
        const first = group[0];
        const selected = group.find(item=>item.stepId===selectedStep);
        const observed = group.find(item=>item.stepId===boundary?.stepId);
        const step = graph ? selected ?? first : observed ?? selected ?? first;
        const tasks = models.get(step.stepId) ?? [];
        const title = tasks.length === 1 ? tasks[0].text : tasks.length > 1 ? `Ask ${tasks.length} declared model tasks` :
          group.length > 1 && !graph ? (story.locale === 'ja' ? '入力を結合' : 'Join inputs') :
          stepTitle(step, labels.get(step.stepId)?.title);
        const projection = graph ? undefined : projections.model.get(step.stepId);
        const projectedStep = projection?.step;
        const selectedProjection = projectedStep !== undefined && projectedStep.stepId === selectedStep;
        const observedProjection = projectedStep !== undefined && projectedStep.stepId === boundary?.stepId;
        const focusedStep = (selectedProjection || observedProjection) && projectedStep ? projectedStep : step;
        const controls = card(first.stepId, !saved && ordinal === 0 || observed !== undefined ||
          selectedProjection || observedProjection, focusedStep.stepId);
        if (graph && !selected) return null;
        return <StoryCard key={first.stepId} {...controls} selected={!!selected || selectedProjection}
          label={tasks.length ? 'Ask model' : step.operator === 'join' ? 'Combine' : 'Compute'}
          state={stepState(focusedStep.stepId, saved, boundary)} title={title}
          detail={tasks.length ? undefined : step.explanation.text}>
          {saved && <p>Sample data is unavailable for this step.</p>}
          {projection && <StepOrigin step={projection.step} label={labels.get(projection.step.stepId)?.title}
            select={()=>selectStep(projection.step.stepId)}/>}
          {(graph ? [step] : group).map(item=><StepOrigin key={item.stepId} step={item}
            label={labels.get(item.stepId)?.title}/>)}
          {tasks.map(({origin, text}, index)=>origin.kind === 'model_task' && <div key={index}>
            <p><StoryText text={text}/></p>
            <details><summary>Original ModelTask contract</summary><code>{origin.contract_cid}</code></details>
          </div>)}
        </StoryCard>;
      })}
      {!graph && [...unboundModels,...outputs].map(({origin,text},index)=><StoryCard key={`${origin.kind}-${index}`}
        {...card(`${origin.kind}-${index}`, false)}
        label={origin.kind === 'effect_set' ? 'Write' : origin.kind === 'result' ? 'Result' : 'Ask model'}
        title={origin.kind === 'effect_set' ? 'Declared changes' :
          origin.kind === 'result' ? `Return "${origin.name}"` : text}
        detail={text} state={unobserved}>
        {origin.kind === 'effect_set' ? <><p>Write preview is unavailable. Review an original Checkpoint separately when the Host offers it.</p>
          <details><summary>Original Effect declarations</summary><p>Effect set <code>{origin.unit_id}</code></p>
            <ul>{origin.members.map(({declaration,write_fields},position)=><li key={position}>
              <strong>{declaration.effect_kind}</strong> · <code>{declaration.contract.kind === 'mapping'
                ? declaration.contract.declared_target : declaration.contract.resource_kind}</code>
              {write_fields.state === 'declared' && <p>Fields: {write_fields.fields.join(', ')}</p>}
            </li>)}</ul></details></> :
          origin.kind === 'result' ? <p>Declared output <code>{origin.name}</code> · stage {origin.stage_ordinal + 1}</p> :
          origin.kind === 'model_task' && <details><summary>Original ModelTask contract</summary><code>{origin.contract_cid}</code></details>}
      </StoryCard>)}
    </ol>
  </section>;
}

function WorkspaceDialog({title, close, children}: {title: string; close(): void; children: ReactNode}) {
  const dialog = useRef<HTMLDialogElement>(null);
  useEffect(()=>{dialog.current?.showModal();}, []);
  return <dialog ref={dialog} className="workspace-dialog" aria-label={title}
    onCancel={event=>{event.preventDefault(); close();}} onClick={event=>{if (event.target === event.currentTarget) close();}}>
    <div className="dialog-content">
      <header><h2>{title}</h2><button type="button" className="small" aria-label="Close dialog" onClick={close}>×</button></header>
      {children}
    </div>
  </dialog>;
}

const startStatus = {
  held: 'Waiting on a Checkpoint',
  preparing: 'Preparing the original Run',
  not_accepted: 'Start refused',
  preparation_failed: 'Run preparation failed',
  unresolvable: 'Original start could not be resolved',
  reply_unknown: 'Start outcome unknown',
  ready: 'Original Run accepted',
};

function App() {
  const source = useMemo(() => createExplorerBrowserSource({origin: window.location.origin}), []);
  const [connected, connect] = useState(false), [plan, showPlan] = useState<PlanReadModel>();
  const [staticExplanation, showStaticExplanation] = useState<StaticExplanationReadModel>();
  const [run, showRun] = useState<RunObservationModel>(), [result, showResult] = useState<unknown>();
  const [follow, setFollow] = useState(false);
  const [queryShown, showQuery] = useState(true), [editing, setEditing] = useState(false);
  const [graph, showGraph] = useState(false);
  const [drawer, showDrawer] = useState<'connect' | 'open-run'>();
  const [selectedStep, selectStep] = useState<{scope: string; id: string}>();
  const [locale, setLocale] = useState<'en' | 'ja'>('en');
  const [analyzedDraft, keepAnalyzedDraft] = useState<{text: string; format: typeof programFormat}>();
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
  const [start, showStart] = useState<{ref: WireSubmissionRef;
    state: keyof typeof startStatus}>();
  const starting = useRef(false);
  const [cancellationEnabled, enableCancellation] = useState(false);
  const [originalCancellation, keepCancellation] = useState<OriginalCancellation|null>(null);
  const [cancellationObservation, showCancellation] = useState<CancellationObservation|null>(null);
  const [cancellationHistory, showCancellationHistory] = useState<WireCancellationLookup|null>(null);
  const [savedCancellation, confirmSavedCancellation] = useState(false);
  const [checkpointPage,showCheckpointPage]=useState<CheckpointPageModel|null>(null);
  const [review,showReview]=useState<ReviewObservation|null>(null);
  const [checkpointCapabilities,setCheckpointCapabilities]=useState({list:false,read:false});
  const reviewSelection=useRef(0);
  const cancelSent = useRef(false);
  const epoch = useRef(0);
  const runSelection = useRef(0);
  const invalidate = () => {epoch.current++; runSelection.current++; setFollow(false); source.close(); connect(false); enableCancellation(false); enableStart(false); busy(false);
    selectRef(undefined); selectStep(undefined); showDrawer(undefined); keepAnalyzedDraft(undefined);
    showPlan(undefined); showStaticExplanation(undefined); showRun(undefined); showResult(undefined); showOriginalPlan(undefined); showOriginalPresentation(undefined); showLauncherProgram(false);
    reviewSelection.current++;showCheckpointPage(null);showReview(null);setCheckpointCapabilities({list:false,read:false});
    showCancellationHistory(null);showCancellation(originalCancellation && cancelSent.current
      ? {state:'unknown',original:originalCancellation} : null);showError('');};
  const perform = async (action: () => Promise<void>) => {
    const original = epoch.current; busy(true); showError('');
    try {await action();}
    catch (error) {
      if (original !== epoch.current) return;
      if (typeof error === 'object' && error !== null && 'code' in error && error.code === 'ExplorerReadUnavailable') {
        showError('The Host could not provide this read. Check the selection and its access.');
      } else {
        invalidate();
        showError('The Local connection was lost. Reconnect to open the original again.');
      }
    }
    finally {if (original === epoch.current) busy(false);}
  };
  useEffect(() => {
    if (!follow || !run || run.run.terminal || pending || !connected) return;
    const selected = runSelection.current, scope = epoch.current;
    const timer = setTimeout(() => {void perform(async () => {
      const next = await source.observe(run.runRef);
      if (runSelection.current === selected && epoch.current === scope) showRun(next);
    });}, 1000);
    return () => clearTimeout(timer);
  }, [follow, run, pending, connected, source]);
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
  const session = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault(); const form = event.currentTarget;
    const token = String(new FormData(form).get('bootstrap')); form.reset(); invalidate();
    void perform(async () => {
      const selected = epoch.current;
      const capabilities = await source.connect(token);
      if (epoch.current !== selected) return;
      setCheckpointCapabilities({list:capabilities.checkpointList,read:capabilities.checkpointReview});
      enableCancellation(capabilities.cancellation); enableStart(capabilities.runStart === true); connect(true);
      const view = await source.launchView();
      if (epoch.current !== selected) return;
      if (view?.kind === 'program') {
        showLauncherProgram(true); showPlan(view.plan);
      } else if (view?.kind === 'run') {
        const original = view.originalPlan.runRef;
        setRunReference(JSON.stringify(original, null, 2));
        selectRef(original);
        showOriginalPlan(view.originalPlan);
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
      showError('Choose a SQL, AQL, or Program JSON file up to 60,000 bytes.');
      return;
    }
    try {
      const text = new TextDecoder('utf-8', {fatal: true}).decode(await file.arrayBuffer());
      if (version !== draftVersion.current) return;
      setProgramText(text); setDraftName(file.name);
      setProgramFormat(extension === 'json' ? 'program' : extension === 'aql' ? 'aql' : 'sql');
      showError('');
    } catch {
      if (version === draftVersion.current) showError('The selected file could not be read as UTF-8.');
    }
  };
  const readPlan = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const text = programText, format = programFormat;
    let input: string | Record<string, unknown> = text;
    if (format === 'program') {
      const parsed = parseLocalJson(text);
      if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
        showError('Enter a valid Program JSON object before reading the Plan.');
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
      showPlan(map); showStaticExplanation(explanation); keepAnalyzedDraft({text, format});
      showGraph(!explain); setEditing(false);
      if (queryMenu) queryMenu.open = false;
    });
  };
  const displayStart = (answer: ExplorerStartObservation, ref: WireSubmissionRef, selected: number) => {
    if (answer.state !== 'ready') {
      showStart({ref, state: answer.state});
      return;
    }
    if (selected !== runSelection.current) {
      showStart({ref, state: 'ready'});
      return;
    }
    showStart(undefined);
    setRunReference(JSON.stringify(answer.ref, null, 2));
    selectRef(answer.ref); selectStep(undefined);
    showPlan(undefined); showStaticExplanation(undefined);
    showOriginalPlan(undefined); showOriginalPresentation(undefined);
    showRun(undefined); showResult(undefined);
  };
  const startDraft = () => {
    if (!startEnabled || !connected || starting.current || pending || !analyzedDraft || selectedRef ||
        start && !['not_accepted', 'preparation_failed'].includes(start.state) ||
        analyzedDraft.text !== programText || analyzedDraft.format !== programFormat) return;
    const draft = analyzedDraft, scope = epoch.current, version = draftVersion.current;
    const selected = runSelection.current;
    starting.current = true;
    void perform(async () => {
      try {
        const ref = await source.prepareStart();
        if (epoch.current !== scope || selected !== runSelection.current || version !== draftVersion.current) return;
        showStart({ref, state: 'reply_unknown'});
        const answer = await source.startRun({ref, ...draft});
        if (epoch.current === scope) displayStart(answer, ref, selected);
      } finally {starting.current = false;}
    });
  };
  const lookupStart = () => {
    if (!start || !startEnabled || !connected || pending || starting.current) return;
    const {ref} = start, scope = epoch.current, selected = runSelection.current;
    void perform(async () => {
      const answer = await source.lookupStart(ref);
      if (epoch.current === scope) displayStart(answer, ref, selected);
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
        showOriginalPresentation(view); showGraph(false);
      } else if (action === 'run-plan') {
        const view = await source.runPlan(original);
        if (!current()) return;
        adopt();
        showOriginalPlan(view);
      } else {
        const observation = await source.observe(original);
        if (!current()) return;
        adopt();
        showRun(observation);
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
      showError('Enter the complete original Run reference as JSON.');
      return;
    }
    const action = (event.nativeEvent as SubmitEvent).submitter?.getAttribute('value') ?? 'run-explanation-context';
    const name = String(new FormData(event.currentTarget).get('name') ?? '');
    readOriginal(original, action, name);
  };
  const prepareCancellation = () => {
    if (!run || run.run.terminal || originalCancellation || !connected || !cancellationEnabled) return;
    setFollow(false);
    keepCancellation(Object.freeze({cancelRef:Object.freeze({...run.runRef,
      cancelId:crypto.randomUUID(),expectedRevision:run.run.controlRevision}),
      attemptRef:Object.freeze({operation:'cancel' as const,attemptId:crypto.randomUUID()})}));
  };
  const requestCancellation = () => {
    if (!originalCancellation || !savedCancellation || cancelSent.current || !connected || !cancellationEnabled) return;
    // Keep this exact explicit operation before transport and never dispatch it
    // a second time from this view, including after ACK loss or scope changes.
    cancelSent.current=true;setFollow(false);
    const saved=originalCancellation,scope=epoch.current;
    showCancellation({state:'unknown',original:saved});
    void perform(async () => {const answer=await source.cancel(saved);
      if (epoch.current===scope) showCancellation(answer);});
  };
  const lookupCancellation = () => {
    if (!originalCancellation || !connected || !cancellationEnabled) return;
    const saved=originalCancellation,scope=epoch.current;
    void perform(async () => {const answer=await source.lookupCancellation(saved.cancelRef);
      if (epoch.current===scope) showCancellationHistory(answer);});
  };
  const importCancellation = (event:FormEvent<HTMLFormElement>) => {
    event.preventDefault();if(originalCancellation) return;
    try {
      const input=JSON.parse(String(new FormData(event.currentTarget).get('original')));
      if (!input || Object.keys(input).length!==2 || !validCancellationRef(input.cancelRef) ||
          !validOperationAttemptRef(input.attemptRef) || input.attemptRef.operation!=='cancel') throw new Error();
      const saved=Object.freeze({cancelRef:Object.freeze(structuredClone(input.cancelRef)),
        attemptRef:Object.freeze(structuredClone(input.attemptRef))});
      keepCancellation(saved);cancelSent.current=true;showCancellation({state:'unknown',original:saved});
    } catch {showError('Invalid original cancellation reference. No Host operation was requested.');}
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
  const planOnly = selectedRef && !story ? map : undefined;
  const originalStep = observedPlanStep(run, selectedRef, map);
  const boundary = originalStep ? {stepId: originalStep.stepId, state: 'Observed' as const} : undefined;
  const scopeKey = JSON.stringify([epoch.current, selectedRef, map?.compiledPlanCid, map?.logicalMapCid, story?.factsCid]);
  const stepScope = JSON.stringify([scopeKey, originalStep?.stepId, originalStep?.position]);
  const edited = analyzedDraft !== undefined &&
    (analyzedDraft.text !== programText || analyzedDraft.format !== programFormat);
  const selection = selectedStep?.scope === stepScope ? selectedStep.id :
    boundary?.stepId ?? (graph || planOnly ? map?.nodes[0]?.id : undefined);
  const setSelection = (id: string) => selectStep({scope: stepScope, id});
  const status = run ? run.run.status.replaceAll('_', ' ') : selectedRef ? 'Current status unavailable' :
    map ? 'Plan checked · not run' : 'No Run selected';
  const observedStep = originalStep && (locale === 'ja'
    ? `元工程 ${originalStep.number} の${originalStep.position === 'before' ? '前' : '後'}を観測`
    : `Observed ${originalStep.position} original step ${originalStep.number}`);
  const supportedCheckpoint = connected && (checkpointCapabilities.list || checkpointCapabilities.read);
  const fileLabel = draftName ?? 'Query draft';
  const independentDraft = !!selectedRef || launcherProgram;
  const draftStatus = independentDraft ? (editing ? 'Editing independent draft' : 'Independent draft') :
    editing ? 'Editing draft' : draftName ? `Loaded ${draftName}` : 'Local query draft';
  const openDrawer = (next: 'connect' | 'open-run') => {showError(''); showDrawer(next);};
  const closeDrawer = () => {showDrawer(undefined); showError('');};
  return <div className="explorer-workspace">
    <header className="workspace-header">
      <div className="workspace-brand"><strong><span aria-hidden="true">&gt;</span> ActQL<span aria-hidden="true">_</span></strong>
        <span>Explorer</span><span className="breadcrumb-divider" aria-hidden="true">/</span>
      <span className="workspace-label" aria-label={independentDraft ? 'Local draft file' : undefined}>{fileLabel}</span>
      </div>
      <div className="workspace-actions">
        <button type="button" className="small" onClick={()=>showQuery(value=>!value)}
          aria-controls="query-pane" aria-expanded={queryShown}>{queryShown ? 'Hide query' : 'Show query'} <kbd>Q</kbd></button>
        <div className="view-switch" role="group" aria-label="Plan view">
          <button type="button" className="small" aria-pressed={!graph} onClick={()=>showGraph(false)}>Steps</button>
          <button type="button" className="small" aria-pressed={graph} onClick={()=>showGraph(true)}>Graph <kbd>G</kbd></button>
        </div>
        {connected ? <details className="toolbar-menu connection-menu">
          <summary><span className="connection-dot"/>Local <span className="sr-only">connection</span></summary>
          <div className="panel terminal-card"><p>Gateway connected</p>
            <button type="button" className="small" onClick={invalidate}>Disconnect</button></div>
        </details> : <button type="button" className="small connect-button" onClick={()=>openDrawer('connect')}>
          <span className="connection-dot" data-connected={false}/>{error ? 'Reconnect' : 'Connect to Local'}</button>}
        <details className="shortcut-help"><summary aria-label="Keyboard shortcuts">?</summary>
          <div className="panel shortcut-card"><p><kbd>Q</kbd> Toggle query pane</p><p><kbd>G</kbd> Switch Steps and Graph</p></div>
        </details>
      </div>
    </header>
    <div className={'workspace-grid' + (queryShown ? '' : ' query-hidden')}>
      {queryShown && <aside id="query-pane" className="query-panel panel" aria-label="Query">
        <header><div><span className="connection-dot" data-connected={!independentDraft && !!analyzedDraft && !edited}/>
          <span>{draftStatus}</span></div>
          <button className="small" type="button" onClick={()=>setEditing(value=>!value)}>{editing ? 'Done' : 'Edit'}</button></header>
        {independentDraft && <p className="query-scope-note">{selectedRef
          ? 'This Run keeps its original query. Edits here apply to a future Run.'
          : 'The launcher supplied the Plan. Edits here apply to a future Run.'}</p>}
        {editing ? <label className="query-editor"><span className="sr-only">Program</span>
          <textarea value={programText} onChange={event=>{draftVersion.current++; setProgramText(event.target.value);}}
            maxLength={60000} rows={8} spellCheck={false}/>
        </label> : <ol className="query-lines" aria-label="Query text">
          {programText.split('\n').map((line,index)=><li key={index}><code>{line || ' '}</code></li>)}</ol>}
        <form className="query-controls" onSubmit={readPlan}>
          <span className="query-format">{({sql:'SQL', aql:'AQL', 'aql-text':'AQL text', program:'Program JSON'})[programFormat]}</span>
          <button className="small primary" value="static-explanation" disabled={!connected || pending || !programText}>Explain</button>
          <details className="toolbar-menu query-menu"><summary aria-label="Query options">⋯</summary>
            <div className="panel query-options">
              <label className="query-file">Open query file <input type="file" accept=".sql,.aql,.json" onChange={event=>void openDraft(event)}/></label>
              <label>Format <select name="format" value={programFormat} onChange={event=>{draftVersion.current++; setProgramFormat(event.target.value as typeof programFormat);}}>
                <option value="sql">SQL</option><option value="aql">AQL</option><option value="aql-text">AQL text</option><option value="program">Program JSON</option></select></label>
              <label>Language <select value={locale} onChange={event=>setLocale(event.target.value === 'ja' ? 'ja' : 'en')}>
                <option value="en">English</option><option value="ja">日本語</option></select></label>
              <button className="small" disabled={!connected || pending || !programText}>Read Plan</button>
            </div>
          </details>
        </form>
      </aside>}
      <main className="story-workspace">
        <div className="story-heading">
          <p className="eyebrow">{selectedRef ? <>Saved Run <code>{run?.run.id ?? selectedRef.runDefinitionCid.slice(7, 19)}</code></> :
            map ? 'Before run · checked plan' : 'Before run'}</p>
          {run && <p className="observation-line">Observed {run.run.updatedAt}{run.run.cleanupPending ? ' · cleanup pending' : ''}</p>}
          {story ? <StoryHeading story={story} context={context}/> : <h1>{selectedRef ?
            explanation?.state === 'not_projected' ? 'Saved explanation unavailable' : 'Original Run' :
            map ? 'Inspect the checked Plan' : 'Explain your query'}</h1>}
          {explanation?.state === 'not_projected' && <p className="workspace-note">{explanation.reason === 'not_retained'
            ? 'No explanation was retained for this Run.' : 'The Run profile does not support this explanation.'}</p>}
          {!selectedRef && !map && <p className="workspace-note">Open a local query or edit the draft. The checked Story will appear here.</p>}
        </div>
        <div className="run-toolbar" aria-label="Run controls and status">
          <span className="workspace-chip">{selectedRef ? 'Saved Run' : 'No Run yet'}</span>
          {!selectedRef && startEnabled && <button className="small primary" type="button" onClick={startDraft}
            disabled={pending || !analyzedDraft || edited ||
              !!start && !['not_accepted', 'preparation_failed'].includes(start.state)}>Run</button>}
          <button className="small" type="button" disabled={!connected || pending} onClick={()=>openDrawer('open-run')}>Open Run</button>
          {selectedRef && !originalPresentation && <button className="small" type="button" disabled={pending}
            onClick={()=>readOriginal(selectedRef, 'run-explanation-context')}>Read Story</button>}
          {selectedRef && !map && <button className="small" type="button" disabled={pending}
            onClick={()=>readOriginal(selectedRef, 'run-plan')}>Read Saved Plan</button>}
          {selectedRef && <button className="small" type="button" disabled={pending}
            onClick={()=>readOriginal(selectedRef, 'inspect')}>Inspect status</button>}
          <span className="run-status" role="status" data-known={!!run || !selectedRef}><span className="status-dot"/>
            {pending ? 'Reading…' : !connected ? 'Local disconnected' : status}
            {!pending && connected && observedStep && <> · {observedStep}</>}</span>
          {selectedRef && <details className="toolbar-menu terminal-menu"><summary>Terminal</summary>
            <div className="panel terminal-card"><p>Original reference for an authorized CLI on this Host.</p>
              <pre aria-label="Original Run reference">{JSON.stringify(selectedRef, null, 2)}</pre></div>
          </details>}
        </div>
        {start && <details className="workspace-tools panel"><summary>{startStatus[start.state]}</summary>
          <p>Look up the original submission to check this outcome.</p>
          <button className="small" type="button" onClick={lookupStart}
            disabled={!connected || !startEnabled || pending}>Look up start</button>
          <pre aria-label="Original submission reference">{JSON.stringify(start.ref, null, 2)}</pre>
        </details>}
        {error && !drawer && <p className="workspace-notice" role="alert">{error}</p>}
        {edited && !selectedRef && map && <p className="workspace-notice">Draft changed. Story and Graph still show the last checked version.</p>}
        {map && <div className="inspection-strip">
          {run && <label className="actql-run-follow"><input type="checkbox" checked={follow}
            disabled={pending || run.run.terminal} onChange={event=>setFollow(event.target.checked)}/>Follow this Run</label>}
          <details className="toolbar-menu capability-menu"><summary>Step controls unavailable</summary>
            <div className="panel terminal-card">
              <p>Durable Step, breakpoint and Continue controls are unavailable.</p>
              <p>Relation Samples and sealed write preview are unavailable in Explorer.</p>
              <p>A Checkpoint decision is separate from stepping.</p>
            </div>
          </details>
        </div>}
        {graph && map && <PlanExplorer model={map} initialView="flow" scopeKey={scopeKey}
          workspace={{stepId: selection, select: setSelection,
            label: id=>({state: stepState(id, !!selectedRef, boundary),
              ...graphLabels.get(id)})}}/>}
        {planOnly && <PlanSteps key={stepScope} map={planOnly} boundary={boundary} selection={selection}
          select={setSelection} graph={graph} locale={locale}/>}
        {story && <StorySteps key={scopeKey} story={story} context={context} boundary={boundary}
          saved={!!selectedRef} selectedStep={selection} selectStep={setSelection} graph={graph} labels={graphLabels} stageResultLinks={map?.stageResultLinks}/>}
        {graph && !map && <p className="workspace-note">Read a Plan or open an original Run to see its Graph.</p>}
        {!graph && !story && !planOnly && map && <p className="workspace-note">This read supplies a logical map. Choose Graph to inspect it.</p>}
        {run && <details className="workspace-tools panel"><summary>Current Run observations</summary><RunInspector model={run}/></details>}
        {result !== undefined && <details className="workspace-tools panel"><summary>Named Result metadata</summary><pre>{JSON.stringify(result, null, 2)}</pre></details>}
        {(supportedCheckpoint || run?.run.status === 'waiting_checkpoint') &&
          <details className="workspace-tools panel"><summary>Checkpoint review</summary>
            <CheckpointPanel page={checkpointPage} review={review} pending={pending}
              canList={connected&&checkpointCapabilities.list} canRead={connected&&checkpointCapabilities.read}
              onList={listCheckpoints} onRead={readReview}/>
          </details>}
    {(cancellationEnabled || originalCancellation) && <details className="workspace-tools panel"><summary>Cancellation</summary>
      {!originalCancellation && <form onSubmit={importCancellation}>
        <label>Saved original cancellation JSON (lookup only)<textarea name="original" maxLength={8192} required/></label>
        <button disabled={pending}>Load saved reference for lookup</button></form>}
      {originalCancellation && !cancelSent.current && <label className="actql-run-follow">
        <input type="checkbox" checked={savedCancellation} onChange={event=>confirmSavedCancellation(event.target.checked)} disabled={pending}/>
        I saved this original cancellation reference.</label>}
      <CancellationPanel original={originalCancellation} observation={cancellationObservation}
        history={cancellationHistory} pending={pending}
        canPrepare={connected && cancellationEnabled && !!run && !run.run.terminal && !originalCancellation}
        canRequest={connected && cancellationEnabled && savedCancellation && !cancelSent.current}
        canLookup={connected && cancellationEnabled && !!originalCancellation}
        onPrepare={prepareCancellation} onRequest={requestCancellation} onLookup={lookupCancellation}/>
    </details>}
      </main>
    </div>
    {drawer === 'connect' && <WorkspaceDialog title="Connect to Local" close={closeDrawer}>
      <p className="workspace-note">Use a fresh one-use bootstrap from the Local Host.</p>
      <form onSubmit={session}>
        <label>One-use bootstrap <input name="bootstrap" type="password" autoComplete="off" maxLength={43} required disabled={pending}/></label>
        <button className="primary" disabled={pending}>Connect</button>
      </form>
      {error && <p role="alert">{error}</p>}
    </WorkspaceDialog>}
    {drawer === 'open-run' && <WorkspaceDialog title="Open Run" close={closeDrawer}>
      <form className="run-reference-form" onSubmit={readRun}>
        <label>Original Run reference<textarea name="ref" value={runReference} onChange={event=>setRunReference(event.target.value)}
          maxLength={4096} rows={4} required spellCheck={false}/></label>
        {error && <p role="alert">{error}</p>}
        <button className="primary" value="run-explanation-context" disabled={pending}>Open Saved explanation</button>
        <details className="run-options"><summary>Other original reads</summary>
          <label>Named Result <input name="name" maxLength={1024}/></label>
          <label>Language <select value={locale} onChange={event=>setLocale(event.target.value === 'ja' ? 'ja' : 'en')}>
            <option value="en">English</option><option value="ja">日本語</option></select></label>
          <div className="toolbar-form-actions">
            <button value="inspect" disabled={pending}>Inspect status</button>
            <button value="run-plan" disabled={pending}>Read Saved Plan</button>
            <button value="run-presentation" disabled={pending}>Read original Facts</button>
          </div>
        </details>
      </form>
    </WorkspaceDialog>}
  </div>;
}
createRoot(document.getElementById('root')!).render(<App/>);
