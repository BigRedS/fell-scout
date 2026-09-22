async function getJSON(path) {
  const res = await fetch(path)
  if (!res.ok) {
    throw new Error(`${path} returned ${res.status}`)
  }
  return res.json()
}

async function sendJSON(method, path, body) {
  const res = await fetch(path, {
    method,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  })
  if (!res.ok) {
    throw new Error(`${method} ${path} returned ${res.status}`)
  }
  return res.json()
}

export function getSummary() {
  return getJSON('/api/summary')
}

export function getStatus() {
  return getJSON('/api/status')
}

export function getTeam(teamNumber) {
  return getJSON(`/api/team/${teamNumber}`)
}

export function getTeams() {
  return getJSON('/api/teams')
}

export function getCheckpoint(checkpoint) {
  return getJSON(`/api/checkpoint/${checkpoint}`)
}

export function getArrivals(checkpoint) {
  return getJSON(`/api/arrivals/${checkpoint}`)
}

export function updateCheckpointStatus(checkpoint, { status, notes }) {
  return sendJSON('PATCH', `/api/checkpoint/${checkpoint}/status`, { status, notes })
}

export function getIncidents() {
  return getJSON('/api/incidents')
}

export function createIncident(fields) {
  return sendJSON('POST', '/api/incidents', fields)
}

export function updateIncident(id, fields) {
  return sendJSON('PUT', `/api/incidents/${id}`, fields)
}

export function deleteIncident(id) {
  return sendJSON('DELETE', `/api/incidents/${id}`)
}

export function getRetirements() {
  return getJSON('/api/retirements')
}

export function createRetirement(fields) {
  return sendJSON('POST', '/api/retirements', fields)
}

export function updateRetirement(id, fields) {
  return sendJSON('PUT', `/api/retirements/${id}`, fields)
}

export function deleteRetirement(id) {
  return sendJSON('DELETE', `/api/retirements/${id}`)
}

export function getCheckpoints() {
  return getJSON('/api/checkpoints')
}

export function getEntrants() {
  return getJSON('/api/entrants')
}

export function getLegs() {
  return getJSON('/api/legs')
}

export function getProblems() {
  return getJSON('/api/problems')
}

export function getMapRoutes() {
  return getJSON('/api/map')
}

export function getScratchTeams() {
  return getJSON('/api/scratch-teams')
}

export function createScratchTeam({ teamName, entrants }) {
  return sendJSON('POST', '/api/scratch-teams', { team_name: teamName, entrants })
}

export function updateScratchTeam(teamNumber, { entrants }) {
  return sendJSON('PUT', `/api/scratch-teams/${teamNumber}`, { entrants })
}

export function deleteScratchTeam(teamNumber) {
  return sendJSON('DELETE', `/api/scratch-teams/${teamNumber}`)
}

export function getConfig() {
  return getJSON('/api/config')
}

export function updateConfig(values) {
  return sendJSON('PATCH', '/api/config', values)
}

export function getLogs() {
  return getJSON('/api/logs')
}

export async function clearDatabase() {
  const res = await fetch('/clear-cache', { method: 'POST' })
  if (!res.ok) {
    throw new Error(`/clear-cache returned ${res.status}`)
  }
}

export function getRoutesCheckpoints() {
  return getJSON('/api/checkpoints/routes')
}

export async function importCheckpointsCsv(file) {
  const formData = new FormData()
  formData.append('csv', file)
  // No Content-Type header here - the browser sets multipart/form-data
  // with the right boundary itself when the body is a FormData object.
  const res = await fetch('/api/checkpoints/import', { method: 'POST', body: formData })
  const result = await res.json()
  if (!res.ok) {
    throw new Error(result.error ?? `import returned ${res.status}`)
  }
  return result
}

export function getLaterunners(threshold) {
  const query = threshold ? `?threshold=${encodeURIComponent(threshold)}` : ''
  return getJSON(`/api/laterunners/${query}`)
}

export async function triggerSync() {
  const res = await fetch('/cron', { method: 'POST' })
  if (!res.ok) {
    throw new Error(`/cron returned ${res.status}`)
  }
}
