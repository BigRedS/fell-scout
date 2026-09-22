// Teams and entrants share the same two fields for this - completed/retired
// - so one function covers both rather than duplicating the same three-way
// check in each view.
export function teamOrEntrantStatus(row) {
  if (row.retired) return 'Retired'
  if (row.completed) return 'Finished'
  return 'Active'
}
