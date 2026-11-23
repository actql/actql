import {prepareInstalledEffectOwnedRequestChild, prepareInstalledEffectRequestChild} from './installed-effect-plan.mjs';
import {prepareInstalledRowCaptureChild} from './installed-row-capture-cleanup.mjs';

import type {SynchronousRuntimeData} from '../host-common/runtime-result.mjs';
import type {prepareInstalledEffectControlConstruction} from './installed-effect-plan.mjs';
import type {InstalledEffectPlanRecipe} from './installed-effect-recipe.mjs';
import type {createInstalledRowEffectCaptureValues} from './installed-row-effect-capture-values.mjs';
import type {createInstalledRowEffectRequests} from './installed-row-effect-members.mjs';
import type {createInstalledRowEffectReadOperations} from './installed-row-effect-physical-read.mjs';

type Values = ReturnType<typeof createInstalledRowEffectCaptureValues>;
type Requests = ReturnType<typeof createInstalledRowEffectRequests>;
type Member = Parameters<Requests['requestEntry']>[0];
type RequestRow = Parameters<Requests['requestEntry']>[1];
type PreparedRequest = (NonNullable<Parameters<Requests['requestEntry']>[2]> & {readonly then?: never}) | null | undefined;
type RequestEntry = ReturnType<Requests['requestEntry']>;
type CreateValues = ReturnType<Values['prepareInstalledCreateRows']>;
type CreateRow = Omit<CreateValues['createRows'][number], 'entry'> & {entry: CreateValues['rows'][number] | RequestEntry};
type OwnedRequest = Parameters<typeof prepareInstalledEffectOwnedRequestChild<PreparedRequest>>[0];
type DirectRequest = Parameters<typeof prepareInstalledEffectRequestChild<PreparedRequest>>[0];
type RetainRequest = Parameters<typeof prepareInstalledRowCaptureChild<PreparedRequest>>[0];
type RequestConstructor = (options: OwnedRequest | DirectRequest) => ReturnType<RetainRequest['create']>;
type ObserveRows = ReturnType<typeof createInstalledRowEffectReadOperations<Member>>['observeRows'];
type Read = Parameters<ObserveRows>[0]['read'];
type Current = Parameters<ObserveRows>[0]['assertCurrent'];
type PhysicalOperations = Parameters<ObserveRows>[0]['physicalOperations'];
type RecoveryEntry = Readonly<{kind?: string; observationCid?: string; wire?: string; then?: never}>;
type ObservedRow = Awaited<ReturnType<ObserveRows>>[number] & Readonly<{versionCid?: string; before?: unknown}>;
type PreviewRow = Readonly<{entry: RequestEntry | CreateRow['entry']; state?: ObservedRow['state'];
  versionCid?: ObservedRow['versionCid']; before?: ObservedRow['before']; identity?: unknown}>;
type RequestContext = Readonly<{
  member: Member; value: unknown; selector: unknown; current: unknown;
  createRowIdentity?: unknown; proposalWire?: string; content: ReturnType<Values['commandContentRow']>;
  signal?: AbortSignal; contentOwner?: unknown; rowIndex?: number; assertCurrent?: Current;
  authorizationForRow?: Read['authorizationForRow'];
}>;
type Owner = Readonly<{
  prepareRequest(context: RequestContext): PreparedRequest;
  prepareRequestChild?(context: RequestContext): ReturnType<OwnedRequest['constructChild']>;
  recheckRequests(facts: Readonly<{member: Member; entries: readonly RequestEntry[]; current: unknown;
    controlConstruction?: ReturnType<typeof prepareInstalledEffectControlConstruction>}>): unknown;
  recoveryEntry?(facts: Readonly<{member: Member; current: unknown;
    entries: readonly RequestEntry[] | undefined}>): RecoveryEntry | undefined;
}>;
type Proposal = Readonly<{changesWire: string; selectorWire?: string}>;
type InputExtent = (proposal: Proposal) => SynchronousRuntimeData;
type Runtime = DirectRequest['run']['runtime'] & Parameters<Values['prepareInstalledCreateRows']>[0];
type Limits = Readonly<{maxRowsPerMember: number; preview: Parameters<Values['prepareInstalledCreateRows']>[2]}>;
type Options = Readonly<{
  member: Member; index: number; owned: Owner; updateWriteSlot?: unknown; description: unknown;
  contentOf?: ReturnType<Values['commandContentBorrower']>;
  moon: Runtime; proposals: readonly (readonly Proposal[])[];
  limits: Limits; recipeOf(member: Member): InstalledEffectPlanRecipe | undefined;
  managedEffect?: DirectRequest['run']; prepared: unknown; identity: unknown; reads: readonly (Read | undefined)[];
  controlConstruction?: ReturnType<typeof prepareInstalledEffectControlConstruction>;
  runInvocationCid: string; dispatches: readonly string[]; signal?: AbortSignal; assertCurrent?: Current;
  contentOwner?: unknown; resourceFields(member: Member): Readonly<{runOriginal?: object}>;
  physicalOperations?: PhysicalOperations; guarded(kind: Member['kind']): boolean; targeted(kind: Member['kind']): boolean;
  requestChildren: RetainRequest['children']; rowsOf: (readonly PreviewRow[] | (() => Promise<RecoveryEntry | undefined>))[];
  observations: (readonly ObservedRow[] | RecoveryEntry | undefined)[];
  prepareInstalledCreateRows: Values['prepareInstalledCreateRows']; commandContentRow: Values['commandContentRow'];
  requestEntry: Requests['requestEntry']; requestsOf: Requests['requestsOf']; observeRows: ObserveRows;
  retireRequestAliases(): boolean; fail(code: string): never;
}>;

export function createInstalledRowEffectCaptureRows({
  member, index, owned, updateWriteSlot, description, contentOf, moon, proposals, limits, recipeOf,
  managedEffect, prepared, identity, reads, controlConstruction, runInvocationCid, dispatches, signal,
  assertCurrent, contentOwner, resourceFields, physicalOperations, guarded, targeted, requestChildren,
  rowsOf, observations, prepareInstalledCreateRows, commandContentRow, requestEntry, requestsOf,
  observeRows, retireRequestAliases, fail,
}: Options) {
  let memberEntries: readonly RequestEntry[] | undefined;
  const constructRows = async () => {
    const selectedCreate = member.kind === 'create'
      ? prepareInstalledCreateRows(moon, proposals[index], limits.preview) : undefined;
    const rows: readonly RequestRow[] = selectedCreate?.rows ?? proposals[index].map(proposal => {
      const changes = JSON.parse(proposal.changesWire);
      return {value: changes.value, selector: targeted(member.kind)
        ? JSON.parse(proposal.selectorWire!) : undefined};
    });
    const createRows: CreateRow[] | undefined = selectedCreate?.createRows;
    let entries: readonly RequestEntry[];
    const recipe = recipeOf(member);
    const constructor = recipe?.requestConstruction;
    if (constructor !== undefined && (managedEffect?.runtime !== moon ||
        managedEffect.prepared !== prepared || managedEffect.request !== identity)) {
      fail('ForeignInstalledEffectManagedRun');
    }
    if (owned.prepareRequestChild !== undefined || constructor !== undefined) {
      const preparedEntries = [];
      for (const [rowIndex, row] of rows.entries()) {
        // Export already bounds the total proposal rows. Member/control
        // children share the same retainer but do not consume a row slot.
        if (rowIndex >= limits.maxRowsPerMember) fail('InstalledRowEffectRowLimit');
        const context = {member, value: row.value, selector: row.selector,
          ...(member.kind === 'create' ? {createRowIdentity: createRows![rowIndex].identity,
            proposalWire: row.proposalWire} : {}),
          current: description, content: commandContentRow(contentOf, rowIndex), signal,
          ...(contentOwner === undefined ? {} : {contentOwner}),
          ...resourceFields(member),
          ...(guarded(member.kind) ? {rowIndex, assertCurrent,
            ...(updateWriteSlot === undefined ?
              {authorizationForRow: () => reads[index]!.authorizationForRow(rowIndex)} : {})} :
            {authorizationForRow: reads[index]?.authorizationForRow})};
        const preparedRequest = await prepareInstalledRowCaptureChild({children: requestChildren,
          create: () => constructor === undefined ? owned.prepareRequestChild!(context) :
            ((owned.prepareRequestChild === undefined ? prepareInstalledEffectRequestChild :
              prepareInstalledEffectOwnedRequestChild) as RequestConstructor)({run: managedEffect!, memberIndex: member.memberIndex,
              rowIndex, operationIndex: constructor.operationIndex,
              operation: recipe!.rowOperations[constructor.operationIndex].operation!,
              ...(constructor.inputExtent === undefined ? {} : {inputExtent: () =>
                controlConstruction!(undefined, constructor.inputExtent as InputExtent, [proposals[index][rowIndex]])}),
              ...(owned.prepareRequestChild === undefined
                ? {construct: () => owned.prepareRequest(context)}
                : {constructChild: () => owned.prepareRequestChild!(context)}),
              requestsRetired: retireRequestAliases}),
          assertCurrent, signal});
        // The Native constructor has returned, but requestFacts can still
        // parse its returned JSON. Use the SAME existing control frame for
        // that synchronous projection, before publishing the row entry.
        preparedEntries.push(controlConstruction === undefined
          ? requestEntry(member, row, preparedRequest)
          : constructor === undefined || controlConstruction.requestProjection === undefined
            ? controlConstruction(undefined, requestEntry, [member, row, preparedRequest])
            : controlConstruction.requestProjection(member.memberIndex, constructor.operationIndex, rowIndex,
              undefined, requestEntry, [member, row, preparedRequest]));
      }
      entries = Object.freeze(preparedEntries);
    } else entries = requestsOf(member, rows, description, contentOf, createRows);
    memberEntries = entries;
    if (member.kind === 'create') {
      // Reuse the SAME Common inventory for Preview and requests.
      for (const [row, entry] of entries.entries()) {
        createRows![row].entry = entry;
        Object.freeze(createRows![row]);
      }
      rowsOf[index] = Object.freeze(createRows!);
      observations[index] = undefined;
      return;
    }
    if (member.kind === 'command') {
      await owned.recheckRequests({member, entries, current: description, controlConstruction, ...resourceFields(member)});
      assertCurrent?.();
      rowsOf[index] = Object.freeze(entries.map(entry => Object.freeze({entry})));
      observations[index] = undefined;
      return;
    }
    const observed: readonly ObservedRow[] = await observeRows({member, entries,
      current: description, read: reads[index]!, signal, assertCurrent, physicalOperations, operationPhase: 'capture',
      runInvocationCid, dispatchRequestCid: dispatches[index]});
    assertCurrent?.();
    observations[index] = observed;
    rowsOf[index] = Object.freeze(entries.map((entry, row) => Object.freeze({
      entry, state: observed[row].state, versionCid: observed[row].versionCid,
      before: observed[row].before})));
  };
  const recoverObservedRows = async () => {
    await constructRows();
    return owned.recoveryEntry?.({member, current: description, entries: memberEntries});
  };

  return {constructRows, recoverObservedRows};
}
