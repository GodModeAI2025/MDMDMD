import { parseUUID, WorkspaceError } from "./validation.ts";

export interface WorkspaceLibraryMetadata {
  libraryID: string;
  title: string;
  role: "viewer" | "editor" | "owner";
}
export interface WorkspaceLibraryMetadataPage {
  libraries: WorkspaceLibraryMetadata[];
  nextAfter: string | null;
}
export const libraryMetadataResponseLimit = 256 * 1024;

/** The sole supported query is one literal UUID position, never authorization. */
export function libraryAfter(rawURL: string): string | undefined {
  const question = rawURL.indexOf("?");
  if (question < 0) return undefined;
  const query = rawURL.slice(question + 1);
  const match = /^after=([0-9a-f-]+)$/i.exec(query);
  if (!match?.[1]) throw new WorkspaceError("invalid");
  return parseUUID(match[1]);
}
