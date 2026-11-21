import type {CheckpointPageModel,ReviewObservation,ReviewReference} from '@actql/explorer-ui/checkpoint-review';
import {useEffect, useMemo, useRef, useState, type ChangeEvent, type FormEvent, type ReactNode} from 'react';
import {createRoot} from 'react-dom/client';
import {PlanExplorer, RunInspector, CancellationPanel, CheckpointPanel} from '@actql/explorer-ui/plan-explorer';
import type {OriginalCancellation, CancellationObservation} from '@actql/explorer-ui/plan-explorer';
import {validCancellationRef, validOperationAttemptRef, validRunRef} from '@actql/client-wire';
import type {RunReference} from '@actql/sdk';
import type {WireCancellationLookup} from '@actql/client-wire';
import type {RunObservationModel} from '@actql/explorer-ui/run-observation';
import type {PlanReadModel, StaticExplanationReadModel, OriginalRunPlanReadModel, OriginalRunPresentationReadModel, SavedExplanationReadModel, ExplanationStoryModel} from '@actql/explorer-ui/read-model';
import {createExplorerBrowserSource} from '@actql/explorer/browser-source';
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

function headlineLabels(labels: string[], locale: ExplanationStoryModel['locale']) {
  const visible = labels.slice(0, 3).map(label=>`"${label}"`);
  const extra = labels.length - visible.length;
  if (extra) visible.push(locale === 'ja' ? `ほか ${extra} 件` : `${extra} more`);
  return new Intl.ListFormat(locale).format(visible);
}

function StoryHeading({story, context}: {story: ExplanationStoryModel; context: StoryContext}) {
  const sources = context.flatMap(({origin})=>origin.kind === 'source' ? [origin.source_view.resource] : []);
  const models = context.flatMap(({origin})=>origin.kind === 'model_task' ? [origin.task_id.replace(/^model-task:/u, '')] : []);
  const outputs = context.flatMap(({origin})=>origin.kind === 'result' ? [origin.name] : []);
  const effects = context.flatMap(({origin})=>origin.kind === 'effect_set' ? [...origin.members] : []);
  const writes = effects.filter(({declaration})=>declaration.contract.kind === 'mapping');
  const commands = effects.length - writes.length;
  const fields = writes.length === 1 && writes[0].declaration.effect_kind === 'update' &&
    writes[0].write_fields.state === 'declared' ? [...writes[0].write_fields.fields] : [];
  const {locale} = story, ja = locale === 'ja';
  const sourceSummary = sources.length && (ja ? `${headlineLabels(sources, locale)}を読む` : `Read ${headlineLabels(sources, locale)}`);
  const modelSummary = models.length && (ja ? `${headlineLabels(models, locale)}を各入力行に適用` :
    `Apply ${headlineLabels(models, locale)} to each input row`);
  const resultSummary = outputs.length && (ja ? `${headlineLabels(outputs, locale)}を返す` : `Return ${headlineLabels(outputs, locale)}`);
  const writeSummary = writes.length && (fields.length ? ja ?
    `${headlineLabels(fields, locale)}の更新を宣言` : `Declare an update to ${headlineLabels(fields, locale)}` :
    ja ? `${writes.length} 件の書き込みを宣言` : `Declare ${writes.length} ${writes.length === 1 ? 'write' : 'writes'}`);
  const commandSummary = commands && (ja ? `${commands} 件のコマンドを宣言` :
    `Declare ${commands} ${commands === 1 ? 'command' : 'commands'}`);
  const summary = [sourceSummary, modelSummary, resultSummary, writeSummary, commandSummary]
    .filter((part): part is string=>!!part)
    .map(part=>part + (ja ? '。' : '.'))
    .join(ja ? '' : ' ');
  return <>
    <h1>{summary ? <StoryText text={summary}/> : 'Original query narrative'}</h1>
    <div className="story-chips">
      {effects.length > 0 && <span className="workspace-chip" data-tone="amber">Effect declared · decision unknown</span>}
      {sources.length > 0 && <span className="workspace-chip" data-tone="teal">{sources.length} declared {sources.length === 1 ? 'source' : 'sources'}</span>}
      {models.length > 0 && <span className="workspace-chip" data-tone="lilac">{models.length} Model {models.length === 1 ? 'task' : 'tasks'} · input rows</span>}
    </div>
  </>;
}

type StepState = 'Planned' | 'Unknown' | 'Observed';

function stepTitle(step: Step) {
  if (step.names.length) return step.title;
  return step.operator?.replaceAll('_', ' ').replace(/^./u, char=>char.toUpperCase()) ?? 'Input / output';
}

function stepState(stepId: string, saved: boolean, boundary?: {stepId: string; state: StepState}): StepState {
  return stepId === boundary?.stepId ? boundary.state : saved ? 'Unknown' : 'Planned';
}

function StoryCard({ordinal, label, title, detail, system, state, open, selected, onToggle, children}: {
  ordinal: number; label: string; title: string; detail?: string; system?: string; state: StepState;
  open: boolean; selected?: boolean; onToggle(): void; children: ReactNode;
}) {
  return <li className="story-row" data-state={state}>
    <span className="step-marker" aria-hidden="true">{ordinal}</span>
    <details className="story-card panel" open={open} data-selected={selected}>
      <summary onClick={event=>{event.preventDefault(); onToggle();}}>
        <span className="step-label">{label}
          {system && <span className="workspace-chip step-system">{system}</span>}
          <span className="workspace-chip step-state" data-state={state}>{state}</span></span>
        <strong><StoryText text={title}/></strong>
        {detail && title !== detail && <span className="step-summary"><StoryText text={detail}/></span>}
      </summary>
      <div className="step-details">{children}</div>
    </details>
  </li>;
}

function StepOrigin({step}: {step: Step}) {
  return <div className="occurrence-origin">
    <strong>{stepTitle(step)}</strong><p><StoryText text={step.explanation.text}/></p>
    <details><summary>Original step and ports</summary>
      <code>{step.stepId}</code>
      <ul>{step.ports.map(port=><li key={port.port_id}>{port.role} · <code>{port.port_id}</code></li>)}</ul>
    </details>
  </div>;
}

function StorySteps({story, context, saved, boundary, selectedStep, selectStep, graph}: {
  story: ExplanationStoryModel; context: StoryContext; saved: boolean;
  boundary?: {stepId: string; state: StepState}; selectedStep?: string;
  selectStep(id: string): void; graph: boolean;
}) {
  const [opened, setOpened] = useState<Record<string, boolean>>({});
  const sources = context.filter(item=>item.origin.kind === 'source');
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
    const current = groups.at(-1);
    if (step.operator === 'join' && current?.[0]?.operator === 'join') current.push(step);
    else groups.push([step]);
  }
  const unobserved = saved ? 'Unknown' : 'Planned';
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
      {!graph && sources.map(({origin,text}, index)=>origin.kind === 'source' && <StoryCard
        key={`source-${origin.stage_input.stage_ordinal}-${origin.stage_input.input_port_ordinal}`}
        {...card(`source-${index}`, !saved && index === 0)}
        label="Read" title={`Read "${origin.source_view.resource}"`} detail={text}
        system={origin.source_view.connector} state={unobserved}>
        <p>Stage {origin.stage_input.stage_ordinal + 1} · input {origin.stage_input.input_port_ordinal + 1}</p>
        <p>Bounded Source data is not available in this view.</p>
        <details><summary>Original Source and links</summary>
          <dl><dt>Contract</dt><dd><code>{origin.source_view.contract_cid}</code></dd>
            <dt>Catalog</dt><dd><code>{origin.source_view.catalog_cid}</code></dd></dl>
          {origin.consuming_ports.length > 0 && <ul aria-label="Original consumers">
            {origin.consuming_ports.map(port=><li key={port.port_id}><code>{port.step_id}</code><br/><code>{port.port_id}</code></li>)}</ul>}
        </details>
      </StoryCard>)}
      {groups.map(group=>{
        const first = group[0];
        const selected = group.find(item=>item.stepId===selectedStep);
        const observed = group.find(item=>item.stepId===boundary?.stepId);
        const step = graph ? selected ?? first : observed ?? selected ?? first;
        const tasks = models.get(step.stepId) ?? [];
        const title = tasks.length === 1 ? tasks[0].text : tasks.length > 1 ? `Ask ${tasks.length} declared model tasks` :
          group.length > 1 && !graph ? `Join inputs · ${group.length} checked joins` : stepTitle(step);
        const controls = card(first.stepId, !saved && ordinal === 0 || observed !== undefined, step.stepId);
        if (graph && !selected) return null;
        return <StoryCard key={first.stepId} {...controls} selected={!!selected}
          label={tasks.length ? 'Ask model' : step.operator === 'join' ? 'Combine' : 'Compute'}
          state={stepState(step.stepId, saved, boundary)} title={title}
          detail={tasks.length ? undefined : step.explanation.text}>
          {saved && <p>Sample data is unavailable for this step.</p>}
          {(graph ? [step] : group).map(item=><StepOrigin key={item.stepId} step={item}/>)}
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
  const [analyzedDraft, keepAnalyzedDraft] = useState<{text: string; format: string}>();
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
  const invalidate = () => {epoch.current++; runSelection.current++; setFollow(false); source.close(); connect(false); enableCancellation(false); busy(false);
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
      enableCancellation(capabilities.cancellation); connect(true);
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
        showOriginalPlan(view); showGraph(true);
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
  const scopeKey = JSON.stringify([epoch.current, selectedRef, map?.compiledPlanCid, map?.logicalMapCid, story?.factsCid]);
  const edited = analyzedDraft !== undefined &&
    (analyzedDraft.text !== programText || analyzedDraft.format !== programFormat);
  const alignedRun = run && map && run.planBinding.compiledPlanCid === map.compiledPlanCid &&
    run.planBinding.logicalMapCid === map.logicalMapCid ? run : undefined;
  const boundaryId = alignedRun?.run.boundary?.step_id;
  const boundary = boundaryId ? {stepId: boundaryId, state: 'Observed' as const} : undefined;
  const selection = selectedStep?.scope === scopeKey ? selectedStep.id : boundaryId ?? (graph ? map?.nodes[0]?.id : undefined);
  const setSelection = (id: string) => selectStep({scope: scopeKey, id});
  const status = run ? run.run.status.replaceAll('_', ' ') : selectedRef ? 'Current status unavailable' :
    map ? 'Plan checked · not run' : 'No Run selected';
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
          <button className="small primary" value="static-explanation" disabled={!connected || pending || !programText}>Explain Effect</button>
          <details className="toolbar-menu query-menu"><summary aria-label="Query options">⋯</summary>
            <div className="panel query-options">
              <label className="query-file">Open query file <input type="file" accept=".sql,.aql,.json" onChange={event=>void openDraft(event)}/></label>
              <label>Format <select name="format" value={programFormat} onChange={event=>setProgramFormat(event.target.value as typeof programFormat)}>
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
          <button className="small" type="button" disabled={!connected || pending} onClick={()=>openDrawer('open-run')}>Open Run</button>
          {selectedRef && <button className="small" type="button" disabled={pending}
            onClick={()=>readOriginal(selectedRef, 'inspect')}>Inspect status</button>}
          <span className="run-status" role="status" data-known={!!run || !selectedRef}><span className="status-dot"/>
            {pending ? 'Reading…' : !connected ? 'Local disconnected' : status}</span>
          {selectedRef && <details className="toolbar-menu terminal-menu"><summary>Terminal</summary>
            <div className="panel terminal-card"><p>Original reference for an authorized CLI on this Host.</p>
              <pre aria-label="Original Run reference">{JSON.stringify(selectedRef, null, 2)}</pre></div>
          </details>}
        </div>
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
              title: story?.occurrences.find(step=>step.stepId === id)?.names.join(', ') || undefined})}}/>}
        {story && <StorySteps key={scopeKey} story={story} context={context} boundary={boundary}
          saved={!!selectedRef} selectedStep={selection} selectStep={setSelection} graph={graph}/>}
        {graph && !map && <p className="workspace-note">Read a Plan or open an original Run to see its Graph.</p>}
        {!graph && !story && map && <p className="workspace-note">This read supplies a logical map. Choose Graph to inspect it.</p>}
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
