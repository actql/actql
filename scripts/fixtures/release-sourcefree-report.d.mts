// Shape of the retained reports consumed by the independent source-free audits.
type SourcefreeCounts = {
  acceptedRuns: number;
  sourceIo: number;
  sourceReads: number;
  sourceReadSessions: number;
};

type ObservedQuery = {
  name: string;
  ref: unknown;
  submissionRef: unknown;
  observedResults: Readonly<Record<string, {rows: readonly unknown[]}>>;
};

export type SourcefreeTransportReport = {
  mode: string;
  suite: string;
  complete: boolean;
  actualNormal: number;
  actualRefusal: number;
  expectedSuccessNames: readonly string[];
  successNames: readonly string[];
  expectedRefusalNames: readonly string[];
  refusalNames: readonly string[];
  providerObservation: unknown;
  completed: readonly (ObservedQuery & {
    beforeSubmit: SourcefreeCounts;
    beforeRead: SourcefreeCounts;
    afterReplay: SourcefreeCounts;
  })[];
  completedRefusals: readonly {
    name: string;
    submissionRef: unknown;
    outcome: {kind: string; problem: {code: string}; submissionRef: unknown};
    beforeSubmit: SourcefreeCounts;
    afterRefusal: SourcefreeCounts;
  }[];
  freshProcessReread: {
    mode: string;
    suite: string;
    phase: string;
    complete: boolean;
    providerObservation: unknown;
    completed: readonly (ObservedQuery & {
      beforeAcceptedRuns: number;
      afterAcceptedRuns: number;
    })[];
  };
};

export type SourcefreeReleaseReceipt = {
  suite: string;
  complete: boolean;
  artifacts: readonly unknown[];
  records: readonly {code: number; signal: string | null}[];
  transports: readonly SourcefreeTransportReport[];
};
