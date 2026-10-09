// Equality reads custody without changing it. Keep the assignment token whole
// so its first '=' cannot also match the start of '=='.
export const workspaceCustodyMutation = /workspace\.live\s*[-+]?=(?!=)/u;
