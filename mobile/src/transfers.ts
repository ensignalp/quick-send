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

export type FileKind = 'image' | 'video' | 'document' | 'audio' | 'other';

/** Kind of a file from its MIME type (recent activity filters). */
export function kindOf(mimeType: string | undefined): FileKind {
  const m = (mimeType ?? '').toLowerCase();
  if (m.startsWith('image/')) return 'image';
  if (m.startsWith('video/')) return 'video';
  if (m.startsWith('audio/')) return 'audio';
  if (m.startsWith('text/') || m === 'application/pdf' || m.includes('document') || m.includes('msword') || m.includes('sheet')
    || m.includes('excel') || m.includes('presentation') || m.includes('powerpoint') || m.includes('epub') || m.includes('rtf')) return 'document';
  return 'other';
}

/** The distinct kinds of a set of files. */
export function kindsOf(files: Array<{ mimeType?: string }>): FileKind[] {
  return [...new Set(files.map(f => kindOf(f.mimeType)))];
}

/** Start of the day (local time) of [at]. */
export function dayStart(at: number): number {
  const d = new Date(at);
  return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
}
