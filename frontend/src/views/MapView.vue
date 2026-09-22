<script setup>
import { ref, computed, watch, onUnmounted, nextTick } from 'vue'
import { useRouter } from 'vue-router'
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import '../leafletIcons'
import { getCheckpoints, getMapRoutes } from '../api/client'
import { usePolling } from '../composables/usePolling'
import CheckpointStatusBadge from '../components/CheckpointStatusBadge.vue'

const router = useRouter()
const checkpoints = ref(null)
const routes = ref(null)
const jumpToCheckpoint = ref('')
const mapEl = ref(null)
let leafletMap = null
const markersByCheckpoint = new Map()

const STATUS_COLOURS = { open: '#198754', issue: '#ffc107', closed: '#dc3545' }

async function refresh() {
  const [cps, routeMap] = await Promise.all([getCheckpoints(), getMapRoutes()])
  checkpoints.value = cps
  routes.value = routeMap
}

usePolling(refresh, 10000)

const checkpointIdsSorted = computed(() =>
  Object.keys(checkpoints.value ?? {})
    .map(Number)
    .sort((a, b) => a - b),
)

function coordsOf(cp) {
  const details = checkpoints.value?.[cp]?.details
  if (!details || !details.latitude || !details.longitude) return null
  return [details.latitude, details.longitude]
}

function numberedIcon(cp, status) {
  const colour = STATUS_COLOURS[status] ?? STATUS_COLOURS.open
  const svg = `<svg version="1.2" baseProfile="tiny" xmlns="http://www.w3.org/2000/svg" width="250" height="250"><circle cx="125" cy="125" r="100" fill="${colour}"/><text x="50%" y="50%" text-anchor="middle" fill="white" font-size="100px" font-family="Arial" dy=".3em">${cp}</text></svg>`
  return L.icon({
    iconUrl: 'data:image/svg+xml,' + encodeURIComponent(svg),
    iconSize: [30, 30],
  })
}

function statusOf(cp) {
  return checkpoints.value?.[cp]?.details?.status ?? 'open'
}

function popupHtml(cp) {
  const details = checkpoints.value[cp].details
  const teamsOnPreviousLeg = Object.keys(details.teams?.next ?? {})
    .sort()
    .map((route) => `${route}: ${(details.teams.next[route] ?? []).join(' ')}`)
    .join('<br>')
  return `
    Checkpoint ${cp} (${details.status ?? 'open'})<br>
    <a href="/arrivals/${cp}">Arrivals</a><br>
    <a href="/checkpoint/${cp}">Info</a><br>
    ${details.what3words ?? ''}<br>
    ${details.os_grid ?? ''}<br>
    ${details.manager ?? ''}: <a href="tel:${details.mobile ?? ''}">${details.mobile ?? ''}</a>
    <hr>
    Teams on previous leg:<br>
    ${teamsOnPreviousLeg}
  `
}

// Only build the Leaflet map once real coordinate data is available - none
// of this rebuilds on later polling ticks (checkpoint locations don't move
// mid-event), matching CheckpointView's approach.
watch([checkpoints, routes], ([cps, routeMap]) => {
  if (!cps || !routeMap || leafletMap) return
  const center = checkpointIdsSorted.value.map(coordsOf).find((c) => c)
  if (!center) return

  nextTick(() => {
    leafletMap = L.map(mapEl.value).setView(center, 12)

    for (const routeName of Object.keys(routeMap)) {
      const points = routeMap[routeName].checkpoints.map(coordsOf).filter((c) => c)
      if (points.length < 2) continue
      L.polyline(points, { color: routeMap[routeName].colour })
        .addTo(leafletMap)
        .bindPopup(`Route ${routeName}`)
    }

    for (const cp of checkpointIdsSorted.value) {
      const coords = coordsOf(cp)
      if (!coords) continue
      const marker = L.marker(coords, { icon: numberedIcon(cp, statusOf(cp)) })
        .addTo(leafletMap)
        .bindPopup(popupHtml(cp))
      markersByCheckpoint.set(cp, marker)
    }

    L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 19,
      attribution: '&copy; <a href="http://www.openstreetmap.org/copyright">OpenStreetMap</a>',
    }).addTo(leafletMap)
  })
})

// Coordinates/routes only get drawn once (they don't change mid-event), but
// status can - re-colour existing markers (and refresh their popup text) on
// every poll tick rather than only ever showing whatever it was when the
// map first loaded.
watch(checkpoints, (cps) => {
  if (!cps) return
  for (const [cp, marker] of markersByCheckpoint) {
    marker.setIcon(numberedIcon(cp, statusOf(cp)))
    marker.setPopupContent(popupHtml(cp))
  }
})

onUnmounted(() => {
  if (leafletMap) leafletMap.remove()
})

function goToCheckpoint() {
  if (jumpToCheckpoint.value !== '') router.push(`/checkpoint/${jumpToCheckpoint.value}`)
}
</script>

<template>
  <h1>Map</h1>
  <p>"Checkpoint 99" is the finish.</p>
  <p class="d-flex align-items-center gap-3">
    <CheckpointStatusBadge status="open" />
    <CheckpointStatusBadge status="issue" />
    <CheckpointStatusBadge status="closed" />
  </p>

  <form class="d-flex align-items-center gap-2 mb-3" @submit.prevent="goToCheckpoint">
    <label class="mb-0">View a specific checkpoint's arrivals board:</label>
    <select v-model="jumpToCheckpoint" class="form-select form-select-sm w-auto">
      <option value="">-</option>
      <option v-for="id in checkpointIdsSorted" :key="id" :value="id">{{ id }}</option>
    </select>
    <button type="submit" class="btn btn-primary btn-sm">Go</button>
  </form>

  <div ref="mapEl" style="height: 800px"></div>
  <p v-if="checkpoints && !checkpointIdsSorted.map(coordsOf).some((c) => c)" class="text-body-secondary mt-2">
    No checkpoints have coordinates set yet - nothing to draw on the map.
  </p>
</template>
