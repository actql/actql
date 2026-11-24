import {checked} from '../host-common/runtime-result.mjs';
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';

type Failure = (code: string, cause?: unknown) => never;
type BorrowLimits = Readonly<{maxFields: number; maxRows: number; maxWork: number}>;
type ContentView = Readonly<{
  binding: unknown; current(): boolean; matchesIssued(issued: unknown): boolean; wire(): unknown; release(): unknown;
}>;
type BorrowConfiguration = Readonly<{
  control: Readonly<{borrowEffectCommandContent(prepared: unknown, inputs: unknown, memberIndex: number,
    artifact: unknown, row: number, inputName: string, limits: Pick<BorrowLimits, 'maxFields' | 'maxWork'>): ContentView}>;
  prepared: unknown; inputs: unknown; memberIndex: number; artifact: unknown; limits: BorrowLimits;
  assertCurrent?: () => unknown;
}>;
type CreateRuntime = Readonly<{
  clientProgramEffectCreateRowInventory(wires: readonly string[], rows: number,
    maxWireBytes: number, maxNodes: number, maxDepth: number): unknown;
}>;
type Proposal = Readonly<{changesWire: string}>;
type CreateLimits = Readonly<{maxWireBytes: number; maxNodes: number; maxDepth: number}>;

export function createInstalledRowEffectCaptureValues(fail: Failure) {
  const reject: Failure = fail;
  // Private wiring over this capture's original Common materials. Escaped
  // callbacks keep only this retireable projection, not the captured Run graph.
  function commandContentBorrower(configuration: BorrowConfiguration) {
    let original: BorrowConfiguration | undefined = configuration;
    const views: {row: number; inputName: string; borrow: ContentView}[] = [];
    const observe = <Value,>(operation: () => Value) => {
      const current = original;
      if (current === undefined) reject('OriginalEffectContentUnavailable');
      current.assertCurrent?.();
      if (original !== current) reject('OriginalEffectContentUnavailable');
      const result = operation();
      current.assertCurrent?.();
      if (original !== current) reject('OriginalEffectContentUnavailable');
      return result;
    };
    return Object.freeze({
      borrow(row: number, inputName: unknown) {
        const current = original;
        if (current === undefined || typeof inputName !== 'string' ||
            inputName.length > current.limits.maxWork) {
          reject('OriginalEffectContentUnavailable');
        }
        current.assertCurrent?.();
        if (original !== current) reject('OriginalEffectContentUnavailable');
        const prior = views.find(value => value.row === row && value.inputName === inputName);
        if (prior !== undefined) {
          if (!prior.borrow.current()) reject('OriginalEffectContentUnavailable');
          current.assertCurrent?.();
          if (original !== current) reject('OriginalEffectContentUnavailable');
          return prior.borrow;
        }
        const {maxRows, maxFields, maxWork} = current.limits;
        if (maxFields === 0 || Math.ceil((views.length + 1) / maxFields) > maxRows) {
          reject('InstalledRowEffectContentBorrowLimit');
        }
        const common = current.control.borrowEffectCommandContent(current.prepared,
          current.inputs, current.memberIndex, current.artifact, row, inputName,
          {maxFields, maxWork});
        if (original !== current) {
          common.release();
          reject('OriginalEffectContentUnavailable');
        }
        const borrow = Object.freeze({
          binding: common.binding,
          current: () => original !== undefined && observe(() => common.current()),
          matchesIssued: (issued: unknown) => original !== undefined &&
            observe(() => common.matchesIssued(issued)),
          wire: () => observe(() => common.wire()),
          release: () => common.release(),
        });
        // Retain before another caller callback can throw or retire this input.
        views.push({row, inputName, borrow});
        current.assertCurrent?.();
        if (original !== current) reject('OriginalEffectContentUnavailable');
        return borrow;
      },
      release() {
        original = undefined;
        for (const {borrow} of views) borrow.release();
        views.length = 0;
      },
    });
  }

  function commandContentRow(port: ReturnType<typeof commandContentBorrower> | undefined, row: number) {
    return (inputName: unknown) => port!.borrow(row, inputName);
  }

  const parseExactJson = (wire: string) => {
    let value: unknown;
    try { value = JSON.parse(wire); }
    catch (error) { reject('InvalidInstalledRowEffectPreview', error); }
    if (JSON.stringify(value) !== wire) reject('LossyInstalledRowEffectPreview');
    return value;
  };

  // One member's original CREATE values and canonical row identities. The
  // Common inventory owns ordering; the Host never derives identities itself.
  function prepareInstalledCreateRows(moon: CreateRuntime, proposals: readonly Proposal[], limits: CreateLimits) {
    // Capture each immutable original String once. Common already checks the
    // member's total wire/node/depth limits as part of this SAME canonical
    // inventory; do that before materializing the Host value tree. A mutable
    // proposal wrapper cannot substitute a different wire after that call.
    const wires = proposals.map(proposal => proposal.changesWire);
    const {maxWireBytes, maxNodes, maxDepth} = limits;
    const inventory = checked(moon.clientProgramEffectCreateRowInventory(
      wires, wires.length, maxWireBytes, maxNodes, maxDepth)) as readonly unknown[];
    if (inventory.length !== wires.length ||
        new Set(inventory.map(item => runtimeField(item, 0))).size !== wires.length) {
      reject('InvalidInstalledRowEffectInventory');
    }
    const createRows = inventory.map(item => {
      const wire = wires[runtimeField(item, 0) as number];
      const changes = JSON.parse(wire) as {value: unknown};
      return {entry: {value: changes.value, proposalWire: wire, selector: undefined},
        identity: Object.freeze(parseExactJson(runtimeField(item, 1) as string))};
    });
    return {rows: createRows.map(item => item.entry), createRows};
  }

  return {commandContentBorrower, commandContentRow, prepareInstalledCreateRows};
}
