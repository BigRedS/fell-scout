// Teams and entrants share the same two fields for this - completed/retired
// - so one function covers both rather than duplicating the same three-way
// check in each view.
export function teamOrEntrantStatus(row) {
  if (row.retired) return 'Retired'
  if (row.completed) return 'Finished'
  return 'Active'
}

// What a checkpoint's badge shows. The stored status (open/issue/closed) is
// set by hand by Control; while it's plain 'open', show the backend's
// progress instead (unvisited/passed/clear - see _checkpoint_progress in
// FellScout::Data). A manual issue/closed always wins - that's the thing
// Control needs to notice.
export function checkpointDisplayStatus(status, progress) {
  if (status !== 'open') return status
  return progress ?? status
}
