export class ExplorerReadError extends Error {
  declare readonly code:string;
  constructor(code:string) { super(code); this.code = code; }
}

// Presentation bounds refuse the whole original map rather than truncating
// its identity. These are not execution, Host or publication permissions.
export const graphViewLimits = Object.freeze({steps: 256, ports: 1024});
