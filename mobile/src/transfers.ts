// Transfer helpers shared by the UI (pure functions, unit tested).

type Sized = { id: string; size: number };

/**
 * Overall progress of a multi-file transfer. The core reports progress per
 * file, so the files are weighted by size; files without a report count as 0.
 */
export function aggregateProgress(files: Sized[], fileProgress: Record<string, number>): number {
  if (!files.length) return 0;
  const total = files.reduce((sum, f) => sum + Math.max(0, f.size), 0);
  if (total === 0) return files.reduce((sum, f) => sum + (fileProgress[f.id] ?? 0), 0) / files.length;
  const done = files.reduce((sum, f) => sum + Math.max(0, f.size) * Math.min(1, Math.max(0, fileProgress[f.id] ?? 0)), 0);
  return Math.min(1, done / total);
}

/** Appends newly picked files, skipping ones already selected (same URI). */
export function mergeFiles<T extends { uri: string }>(current: T[], added: T[]): T[] {
  const seen = new Set(current.map(f => f.uri));
  const result = [...current];
  for (const file of added) {
    if (!seen.has(file.uri)) {
      seen.add(file.uri);
      result.push(file);
    }
  }
  return result;
}
