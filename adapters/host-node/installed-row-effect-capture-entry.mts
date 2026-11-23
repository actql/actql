import {checked} from '../host-common/runtime-result.mjs';
import {releaseCompletedRunPreparedPayloads, storeCompletedRunResultSet} from '../host-common/completed-run-publication.mjs';
import {prepareInstalledEffectResultProgress} from './effect-result-work.mjs';
import {releaseInstalledRowCapture} from './installed-row-capture-cleanup.mjs';

import type {createInstalledRowEffectCaptureStage} from './installed-row-effect-capture-stage.mjs';
import type {createInstalledRowEffectRunControls} from './installed-row-effect-run-controls.mjs';
import type {createInstalledRowEffectPhysicalRoute} from './installed-row-effect-physical-route.mjs';

type ResultsInput = Parameters<typeof storeCompletedRunResultSet>[0];
type StoredResults = NonNullable<Awaited<ReturnType<typeof storeCompletedRunResultSet>>>;
type ReleaseOptions = Parameters<typeof releaseInstalledRowCapture>[0];
type CaptureChildren = NonNullable<ReleaseOptions['children']>;
type Release = NonNullable<ReleaseOptions['releaseInputs']>;
type SourceSet = Readonly<{payloads: NonNullable<ReleaseOptions['payloads']>}>;
type ActualStage = Parameters<ReturnType<typeof createInstalledRowEffectCaptureStage>>[0];
type Managed = Parameters<typeof prepareInstalledEffectResultProgress>[0] & NonNullable<ActualStage['managedEffect']>;
type RunOptions = ReturnType<typeof createInstalledRowEffectRunControls>;
type Selection = Parameters<RunOptions['selectionFence']>[3];
type RouteOptions = Parameters<ReturnType<typeof createInstalledRowEffectPhysicalRoute>>[0];
type RunFacts = Readonly<{moon?: Runtime; compilation?: unknown}>;
type PlanInput = Pick<ResultsInput, 'runDefinition' | 'invocation' | 'results' | 'outputLimits' | 'contractLimits'> &
  Readonly<{invocationOwner: unknown}> & ActualStage['plan'];
type EffectUnit = ActualStage['unit'] & Readonly<{effectIds: readonly string[]}>;
type PreviewContext = Readonly<{runDefinition: unknown; runInvocation: unknown; compiledPlan: unknown}>;
type Runtime = Readonly<{
  clientProgramEffectCompilationPlanWire(compilation: unknown): string;
  strategyPublicationAdmit(kind: string, wire: string, bytes: number, nodes: number, depth: number): unknown;
  clientProgramEffectCompilationCompiledPlanWire(compilation: unknown): string;
  clientProgramEffectRequestScope(prepared: unknown, identity: unknown): unknown;
}>;
type CaptureFacts<Control, Plan> = Readonly<{
  moon: Runtime; control: Control; store: ResultsInput['store']; execution: ActualStage['execution'];
  checkedHost: unknown; prepared: unknown; identity: unknown; definition?: unknown; compilation?: unknown;
  signal?: AbortSignal; targetReads?: RouteOptions['targetReads']; contentOwner?: unknown;
  publicationPlan?: Plan; plan?: Plan; previewContext?: PreviewContext; unit?: EffectUnit;
  managedEffect?: Managed; updateTargetSelections?: Selection;
}>;
type StageInputs<Member, Control, Plan> =
  Pick<CaptureFacts<Control, Plan>, 'control' | 'store' | 'execution' | 'checkedHost' | 'prepared' | 'identity'
    | 'signal' | 'targetReads' | 'contentOwner' | 'managedEffect' | 'updateTargetSelections'> & Readonly<{
  plan: Plan; previewContext: PreviewContext; unit: EffectUnit; members: readonly Member[];
  runInvocationCid: string; dispatches: readonly string[]; requestScope: unknown; storedResults: StoredResults;
  assertCurrent?: RouteOptions['assertCurrent'];
  own(sourceSet: SourceSet): void;
  ownChildren(children: CaptureChildren): void;
  ownInputs(release: Release, finish: () => void): void;
}>;
type CaptureControls<Member, Control, Plan, Stage> = Readonly<{
  moon: Runtime;
  assertPrepared(facts: RunFacts): void;
  installedRowEffectUnit(moon: Runtime, compilation: unknown): EffectUnit;
  membersOf(prepared: unknown, unit: EffectUnit, maxMembers: number): readonly Member[];
  runLimits(managed: Managed | undefined): Readonly<{maxMembers: number}>;
  bindRunResources(facts: CaptureFacts<Control, Plan>, members: readonly Member[]): void;
  selectionFence(facts: CaptureFacts<Control, Plan>, members: readonly Member[], stageIndex: number,
    selections: Selection): RouteOptions['assertCurrent'];
  memberDispatch(runInvocationCid: string, member: Member): string;
  captureStage(options: StageInputs<Member, Control, Plan>): Promise<Stage>;
  fail(code: string): never;
}>;

export function createInstalledRowEffectCaptureEntry<Member, Control extends ResultsInput['control'], Plan extends PlanInput, Stage>({
  moon, assertPrepared, installedRowEffectUnit, membersOf, runLimits, bindRunResources, selectionFence,
  memberDispatch, captureStage, fail,
}: CaptureControls<Member, Control, Plan, Stage>) {
  const reject: CaptureControls<Member, Control, Plan, Stage>['fail'] = fail;

  // Capture a completed computation as one Effect Unit and return the stage
  // the common owner applies after the whole-set commit decision.
  // `facts` are the Host's Effect Site facts, or an installation's own
  // capture inputs that already carry the Preview context and Effect Unit.
  async function prepareCaptured(facts: CaptureFacts<Control, Plan>) {
    assertPrepared(facts ?? {});
    const {moon: runMoon, control, store, execution, checkedHost, prepared,
      identity, definition, compilation, signal, targetReads, contentOwner} = facts ?? {};
    const plan = facts?.publicationPlan ?? facts?.plan;
    if (runMoon !== moon || !plan || !execution || !checkedHost ||
        !prepared || !identity || ((definition === undefined ||
          compilation === undefined) && (facts.previewContext === undefined ||
          facts.unit === undefined))) {
      reject('InvalidInstalledEffectCapture');
    }
    signal?.throwIfAborted();
    const previewContext = facts.previewContext ?? {runDefinition: definition,
      runInvocation: plan.invocationOwner,
      compiledPlan: checked(moon.strategyPublicationAdmit('compiled_plan',
        moon.clientProgramEffectCompilationCompiledPlanWire(compilation),
        plan.contractLimits.maxWireBytes, plan.contractLimits.maxNodes,
        plan.contractLimits.maxDepth))};
    const unit = facts.unit ?? installedRowEffectUnit(moon, compilation);
    const members = membersOf(prepared, unit, runLimits(facts.managedEffect).maxMembers);
    bindRunResources(facts, members);
    const updateTargetSelections = facts.updateTargetSelections;
    const assertCurrent = selectionFence(facts, members, unit.stageIndex, updateTargetSelections);
    const runInvocationCid = plan.invocation.identity;
    const dispatches = members.map(member =>
      memberDispatch(runInvocationCid, member));
    const requestScope = moon.clientProgramEffectRequestScope(prepared,
      identity);
    const resultProgress = facts.managedEffect === undefined ? undefined
      : prepareInstalledEffectResultProgress(facts.managedEffect, checkedHost);
    const storedResults = await storeCompletedRunResultSet({execution,
      store, control, runDefinition: plan.runDefinition,
      invocation: plan.invocation, results: plan.results,
      outputLimits: plan.outputLimits, contractLimits: plan.contractLimits,
      signal, resultProgress}) as StoredResults;
    let sourceSet: SourceSet | undefined;
    let releaseInputs: Release | undefined;
    let requestChildren: CaptureChildren | undefined, finishCapture: (() => void) | undefined;
    try {
      try {
        return await captureStage({control, store, execution, checkedHost,
          prepared, identity, plan, previewContext, unit, members,
          runInvocationCid, dispatches, requestScope, storedResults, signal,
          targetReads, contentOwner, managedEffect: facts.managedEffect, updateTargetSelections, assertCurrent, own: value => { sourceSet = value; },
          ownChildren: value => { requestChildren = value; },
          ownInputs: (release, finish) => { releaseInputs = release; finishCapture = finish; }});
      } finally { finishCapture?.(); }
    } catch (error) {
      await releaseInstalledRowCapture({payloads: sourceSet?.payloads,
        children: requestChildren,
        // This owner's false means already released, not pending cleanup.
        releaseResults: async () => { await releaseCompletedRunPreparedPayloads(storedResults, control); },
        releaseInputs, control}, error);
    }
  }

  return prepareCaptured;
}
