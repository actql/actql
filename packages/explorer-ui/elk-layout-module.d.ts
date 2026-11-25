// elkjs 0.12's generic child-index signature does not typecheck under the
// canonical strict compiler. Keep this private static import unknown rather
// than skip library checking or invent a checked third-party module. The real
// upstream runtime/Worker and every original layout-result check are retained.
declare const ELK: unknown;
export default ELK;
