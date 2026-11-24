import {checked} from '../host-common/runtime-result.mjs';
import type {createInferOriginalReadControls} from '../host-common/runtime-infer-original-read-control.mjs';
import {finishNodeInferOriginalReadScopes, retireNodeInferOriginalRead} from './infer-operation.mjs';
import {inferOriginalReadStartupCapacity, selectedInferOriginalCurrentStateCodec,
  selectedInferOriginalPublicationCapacity} from './infer-original-installation.mjs';

type ReadControls = ReturnType<typeof createInferOriginalReadControls>;
type GroupRetirement = Parameters<typeof finishNodeInferOriginalReadScopes>[0];
type Control = GroupRetirement['control'] & Pick<ReadControls, 'checkedClientInferOriginalReadScopeLive' |
  'prepareCheckedClientInferOriginalRead' | 'prepareCheckedClientInferNodeReadLayout'>;
type Installation = Parameters<typeof selectedInferOriginalCurrentStateCodec>[0];
type Plan = Readonly<{compiled: unknown; runDefinition: unknown}>;
type Coordinate = readonly [stage: number, input: number, task: number];
type Selection = Readonly<{
  graph: unknown;
  originalReadInstallation?: Installation;
  currentProvider?(): boolean;
  assertTrustedRuntime?(): void;
  bindTrustedRuntimeScope?(scope: unknown, compiled: unknown, definition: unknown, graph: unknown): unknown;
  assertTrustedRuntimeScope?(...args: Parameters<GroupRetirement['components'][number]['selection']['finishTrustedRuntimeScope']>): void;
}>;
type GroupSelection = Readonly<{
  graph: readonly unknown[]; components: readonly (Selection & GroupRetirement['components'][number]['selection'])[];
  sourceCoordinates?: readonly Coordinate[];
}>;
type Runtime = Readonly<{
  clientProgramAcquisitionCount(prepared: unknown): number;
  clientProgramOpenInstalledManagedSourceFreeComposedInferHost(original: unknown, prepared: unknown,
    request: unknown, registry: unknown, values: string, fragment: string, ordered: string,
    providers: readonly unknown[]): unknown;
  clientProgramOpenInstalledManagedCaptureHost?(original: unknown, prepared: unknown,
    request: unknown, sources: readonly unknown[]): unknown;
}>;
type Capacity = Parameters<ReadControls['prepareCheckedClientInferOriginalRead']>[4] &
  Readonly<{modelRetainedBytes: bigint; modelExecutionBytes: bigint}>;
type Managed = {
  runtime: Runtime; prepared: unknown; request: unknown; value?: unknown;
  model: Member | Group; closed?: boolean;
};
type Member = Plan & {
  control: Control; graph: unknown; prepared: unknown; selection: Selection; managed: Managed;
  scope: unknown; budget: Capacity; component: Readonly<{provider: unknown; bindOriginal(...args: never[]): unknown}>;
  group?: Group; sourceLedger?: unknown; runtimeBorrow?: unknown; originalReadInstallation?: Installation;
  publicationCapacity(): unknown;
  closed?: boolean; scopeFinished?: boolean; taken?: boolean; hostAttempted?: boolean;
  read: unknown; readAttempted?: boolean; readFailure?: unknown;
};
type GroupMember = Member & {group: Group; selection: GroupSelection['components'][number]};
type Group = Plan & {
  control: Control; scope: unknown; graph: GroupSelection['graph']; selection: GroupSelection;
  components: readonly GroupMember[]; scopes: readonly unknown[]; managed: Managed;
  sourceLedger?: unknown; closed?: boolean; scopeFinished?: boolean; taken?: boolean; hostAttempted?: boolean;
};
type Capture = Readonly<{capture: Readonly<{source(): unknown}>}>;
type Acquired = Readonly<{ledger?: unknown; managedRun?: unknown; captured?: Capture}>;
type OriginalRead = Plan & {
  control: Control; scope: unknown; read: unknown; inputBodyRead: unknown; publicationCapacity(): unknown;
  readRetainedBytes: bigint; readExecutionBytes: bigint; modelRetainedBytes: bigint; modelExecutionBytes: bigint;
  nodeInstallation?: Installation['nodeInstallation']; metadataInstallation?: Installation;
};

// Borrow the existing Request's Model Plan and Scope. This is the
// same installed Run; configured providers keep their current/claim/stop owner.
export function sourceFreeModelPreparation(moon: Runtime, control: Control, prepared: unknown,
  plan: Plan, selected: Selection, model: Member, acquired?: Acquired) {
  const group = model?.group;
  const managed = model?.managed, scope = model?.scope, component = model?.component;
  const original = managed?.value, request = managed?.request, graph = selected.graph,
    compiled = plan.compiled, definition = plan.runDefinition, budget = model?.budget,
    publication = model?.publicationCapacity;
  const installation = selected.originalReadInstallation;
  const sourceLedger = acquired?.ledger, captured = acquired?.captured;
  const current = () => {
    if (model === null || typeof model !== 'object' || model.closed || model.scopeFinished ||
        model.prepared !== prepared || model.selection !== selected || model.graph !== graph || selected.graph !== graph ||
        model.control !== control || model.compiled !== compiled || plan.compiled !== compiled ||
        model.runDefinition !== definition || plan.runDefinition !== definition ||
        scope === undefined || model.scope !== scope || model.budget !== budget ||
        component === undefined || model.component !== component ||
        typeof component.bindOriginal !== 'function' ||
        typeof publication !== 'function' || model.publicationCapacity !== publication ||
        model.originalReadInstallation !== installation || model.managed !== managed ||
        installation !== undefined && (group === undefined || acquired !== undefined) ||
        managed?.closed || managed?.model !== (group ?? model) ||
        group !== undefined && (!Array.isArray(group.components) || !group.components.includes(model) ||
          group.closed || group.scopeFinished) || original === undefined ||
        managed.value !== original || managed.request !== request ||
        managed.runtime !== moon || managed.prepared !== prepared ||
        acquired !== undefined && (moon.clientProgramAcquisitionCount(prepared) !== 1 ||
          managed.value !== acquired.managedRun || acquired.ledger !== sourceLedger ||
          model.sourceLedger !== sourceLedger || acquired.captured !== captured)) {
      throw new TypeError('InvalidInstalledRequestModelPreparation');
    }
    if (installation === undefined) return;
    if (selected.currentProvider!() !== true) throw new TypeError('InferTrustedRuntimeViewUnavailable');
    if (model.runtimeBorrow === undefined) {
      selected.assertTrustedRuntime!();
      if (!control.checkedClientInferOriginalReadScopeLive(compiled, definition, graph, scope)) {
        throw new TypeError('InferTrustedRuntimeScopeUnavailable');
      }
    } else selected.assertTrustedRuntimeScope!(scope, model.runtimeBorrow, compiled, definition, graph);
  };
  current();
  if (model.taken || model.readAttempted || model.read !== undefined) {
    throw new TypeError('InvalidInstalledRequestModelPreparation');
  }
  const publicationCapacity = () => {
    current();
    return Reflect.apply(publication, model, []);
  };
  return Object.freeze({selection: selected, control, compiled: plan.compiled, component,
    assertRuntimeCurrent: current,
    runDefinition: plan.runDefinition, scope, publicationCapacity,
    readRetainedBytes: model.budget.readRetainedBytes, readExecutionBytes: model.budget.readExecutionBytes,
    modelRetainedBytes: model.budget.modelRetainedBytes, modelExecutionBytes: model.budget.modelExecutionBytes,
    retain() {
      current();
      if (model.taken || model.readAttempted) throw new TypeError('InvalidInstalledRequestModelPreparation');
      model.taken = true;
    },
    openSourceFreeHost(registry: unknown, values: string, fragment: string, ordered: string, providers: readonly unknown[]) {
      current();
      if (!model.taken || model.hostAttempted || moon.clientProgramAcquisitionCount(prepared) !== 0) {
        throw new TypeError('InvalidInstalledRequestModelPreparation');
      }
      model.hostAttempted = true;
      return checked(moon.clientProgramOpenInstalledManagedSourceFreeComposedInferHost(
        original, prepared, request, registry, values, fragment, ordered, providers));
    },
    ...(acquired === undefined ? {} : {openCapturedHost(captures: readonly Capture[]) {
      current();
      if (!model.taken || model.hostAttempted || !Array.isArray(captures) ||
          captures.length !== 1 || captures[0] !== captured ||
          typeof moon.clientProgramOpenInstalledManagedCaptureHost !== 'function') {
        throw new TypeError('InstalledComposedInferHostUnavailable');
      }
      model.hostAttempted = true;
      return checked(moon.clientProgramOpenInstalledManagedCaptureHost(original,
        prepared, request, captures.map((value: Capture) => value.capture.source())));
    }}),
    prepareRead() {
      current();
      if (model.readAttempted && Object.hasOwn(model, 'readFailure')) throw model.readFailure;
      if (!model.taken || model.readAttempted) throw new TypeError('InvalidInstalledRequestModelPreparation');
      model.readAttempted = true;
      try {
        if (installation === undefined) {
          model.read = control.prepareCheckedClientInferOriginalRead(compiled, definition, graph, scope, budget);
        } else {
          const nodeInstallation = installation.nodeInstallation;
          selectedInferOriginalCurrentStateCodec(installation, nodeInstallation);
          selectedInferOriginalPublicationCapacity(installation, nodeInstallation);
          current();
          // The adopted group already owns this Scope. Retain its runtime
          // borrow before the checked Node read can fail or take custody.
          model.runtimeBorrow = selected.bindTrustedRuntimeScope!(scope, compiled, definition, graph);
          current();
          // The retained DATA keys are forwarded unchanged. Common checks the
          // original layout and its CIDs before reserving the read.
          model.read = control.prepareCheckedClientInferNodeReadLayout(compiled, definition, graph, scope,
            nodeInstallation as Parameters<Control['prepareCheckedClientInferNodeReadLayout']>[4]);
          current();
        }
        const startup = installation === undefined ? budget : inferOriginalReadStartupCapacity(installation);
        const originalRead: OriginalRead = {control, compiled, runDefinition: definition,
          // This installed caller always hands the completed observation to
          // inferTaskPublicationPlan; its existing body owner needs this SAME
          // read. This does not enable retention in raw/private Model consumers.
          scope, read: model.read, inputBodyRead: model.read, publicationCapacity,
          readRetainedBytes: budget.readRetainedBytes, readExecutionBytes: budget.readExecutionBytes,
          modelRetainedBytes: startup.modelRetainedBytes, modelExecutionBytes: startup.modelExecutionBytes};
        if (installation !== undefined) {
          originalRead.nodeInstallation = installation.nodeInstallation;
          originalRead.metadataInstallation = installation;
        }
        return Object.freeze(originalRead);
      } catch (cause) {model.readFailure = cause; throw cause;}
    },
    async retire() {
      if (model.closed && model.scopeFinished) return true;
      current();
      if (installation !== undefined) throw new TypeError('InvalidInstalledRequestModelPreparation');
      retireNodeInferOriginalRead(model);
      model.read = undefined;
      if (control.finishCheckedClientInferOriginalReadScope(plan.compiled,
        plan.runDefinition, selected.graph, scope, true) !== true) return false;
      model.scopeFinished = true;
      // The existing Host registry still owns Run/parent retirement and alias
      // severing. Finishing this Scope does not report whole-Host cleanup.
      model.closed = true;
      return true;
    }});
}

// One original group view on the same installed Run. All component reads and
// scopes retire before its existing Request/Host cleanup; the first pending
// scope never prevents cleanup from reaching the remaining actual children.
export function sourceFreeModelsPreparation(moon: Runtime, control: Control, prepared: unknown,
  plan: Plan, selected: GroupSelection, model: Group, acquired: Acquired | undefined, preparationHolder: unknown) {
  const members = model?.components, scopes = model?.scopes, managed = model?.managed;
  const current = () => {
    if (!Array.isArray(members) || !Object.isFrozen(members) || members.length < 2 ||
        model.components !== members || model.selection !== selected || model.closed || model.scopeFinished ||
        !Array.isArray(scopes) || model.scopes !== scopes || scopes.length !== members.length ||
        model.graph !== selected.graph || model.control !== control || model.compiled !== plan.compiled ||
        model.runDefinition !== plan.runDefinition || managed?.model !== model || managed.closed ||
        model.managed !== managed || managed.value === undefined || managed.prepared !== prepared ||
        acquired !== undefined && (managed.value !== acquired.managedRun || model.sourceLedger !== acquired.ledger) ||
        members.some((member, index) => member.group !== model || member.managed !== managed ||
          member.selection !== selected.components[index] || member.graph !== selected.graph[index] ||
          member.scope !== scopes[index])) throw new TypeError('InvalidInstalledRequestModelPreparation');
  };
  current();
  const originals = Object.freeze(members.map((member, index) =>
    sourceFreeModelPreparation(moon, control, prepared, plan, selected.components[index], member)));
  return Object.freeze({control, compiled: plan.compiled, runDefinition: plan.runDefinition,
    selection: selected, components: originals, preparationHolder, sourceCoordinates: selected.sourceCoordinates,
    retain() {current(); for (const original of originals) original.retain(); model.taken = true;},
    ...(acquired === undefined ? {
    openSourceFreeHost(registry: unknown, values: string, fragment: string, ordered: string, providers: readonly unknown[]) {
      current();
      if (!model.taken || model.hostAttempted || moon.clientProgramAcquisitionCount(prepared) !== 0 ||
          !Array.isArray(providers) || providers.length !== members.length ||
          providers.some((provider: unknown, index: number) => provider !== members[index].component.provider)) {
        throw new TypeError('InvalidInstalledRequestModelPreparation');
      }
      model.hostAttempted = true;
      return checked(moon.clientProgramOpenInstalledManagedSourceFreeComposedInferHost(
        managed.value, prepared, managed.request, registry, values, fragment, ordered, providers));
    },
    } : {openCapturedHost(captures: readonly Capture[]) {
      current();
      if (!model.taken || model.hostAttempted || !Array.isArray(captures) ||
          captures.length !== moon.clientProgramAcquisitionCount(prepared) ||
          typeof moon.clientProgramOpenInstalledManagedCaptureHost !== 'function') {
        throw new TypeError('InstalledComposedInferHostUnavailable');
      }
      model.hostAttempted = true;
      return checked(moon.clientProgramOpenInstalledManagedCaptureHost(managed.value,
        prepared, managed.request, captures.map((value: Capture) => value.capture.source())));
    }}),
    async retire() {
      if (model.closed && model.scopeFinished) return true;
      current();
      for (const member of members) {retireNodeInferOriginalRead(member); member.read = undefined;}
      if (finishNodeInferOriginalReadScopes(model) !== true) return false;
      model.scopeFinished = true; model.closed = true;
      return true;
    }});
}
