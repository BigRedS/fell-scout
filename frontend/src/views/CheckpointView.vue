<script setup>
import { ref, computed, watch, onUnmounted, nextTick } from 'vue'
import { useRoute } from 'vue-router'
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import '../leafletIcons'
import { addFullscreenControl } from '../leafletFullscreen'
import { getStatus, getCheckpoint, updateCheckpointStatus } from '../api/client'
import { usePolling } from '../composables/usePolling'
import TeamLink from '../components/TeamLink.vue'
import CheckpointLink from '../components/CheckpointLink.vue'
import CheckpointStatusBadge from '../components/CheckpointStatusBadge.vue'

const route = useRoute()
const checkpoint = ref(null)
const mapEl = ref(null)
let leafletMap = null

// Editable draft state for the status form - kept separate from the
// fetched data (like ScratchTeamsView/AdminView) so a background poll tick
// can't wipe out an in-progress edit. Seeded once per checkpoint, not once
// ever, since this component instance is reused when navigating between
// checkpoints via CheckpointLink.
const draftStatus = ref('open')
const draftNotes = ref('')
const savingStatus = ref(false)
let statusDraftSeeded = false

// Only controllers can change the status (the server enforces it; this
// just stops plain users seeing controls that would 403). null = not
// checked yet.
const isController = ref(null)

async function refresh() {
  if (isController.value === null) isController.value = !!(await getStatus()).is_controller
  checkpoint.value = await getCheckpoint(route.params.checkpoint)
}

usePolling(refresh, 10000)

watch(
  () => route.params.checkpoint,
  () => {
    if (leafletMap) {
      leafletMap.remove()
      leafletMap = null
    }
    statusDraftSeeded = false
    refresh()
  },
)

const details = computed(() => checkpoint.value?.details ?? null)

watch(details, (d) => {
  if (!d) return
  if (!statusDraftSeeded) {
    draftStatus.value = d.status
    draftNotes.value = d.status_notes ?? ''
    statusDraftSeeded = true
  }
  if (!d.latitude || !d.longitude || leafletMap) return
  nextTick(() => {
    leafletMap = L.map(mapEl.value).setView([d.latitude, d.longitude], 13)
    addFullscreenControl(leafletMap)
    L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 19,
      attribution: '&copy; <a href="http://www.openstreetmap.org/copyright">OpenStreetMap</a>',
    }).addTo(leafletMap)
    L.marker([d.latitude, d.longitude]).addTo(leafletMap)
  })
})

async function saveStatus() {
  savingStatus.value = true
  try {
    checkpoint.value.details = await updateCheckpointStatus(route.params.checkpoint, {
      status: draftStatus.value,
      notes: draftNotes.value,
    })
  } finally {
    savingStatus.value = false
  }
}

onUnmounted(() => {
  if (leafletMap) leafletMap.remove()
})

function teamGroups(key) {
  if (!details.value) return []
  return details.value.routes.map((routeName) => ({
    route: routeName,
    teams: details.value.teams[key]?.[routeName] ?? [],
  }))
}
</script>

<template>
  <template v-if="details">
    <h1>Checkpoint {{ details.checkpoint_number }} Details</h1>

    <router-link :to="`/arrivals/${details.checkpoint_number}`">Arrivals Board</router-link>

    <div class="d-flex align-items-center gap-2 flex-wrap my-3">
      <CheckpointStatusBadge :status="details.status" />
      <template v-if="isController">
        <select v-model="draftStatus" class="form-select form-select-sm w-auto">
          <option value="open">Open</option>
          <option value="issue">Issue</option>
          <option value="closed">Closed</option>
        </select>
        <input
          v-model="draftNotes"
          type="text"
          class="form-control form-control-sm"
          style="max-width: 20em"
          placeholder="Notes (e.g. poor signal, heavy load)"
        />
        <button type="button" class="btn btn-primary btn-sm" :disabled="savingStatus" @click="saveStatus">
          {{ savingStatus ? 'Saving…' : 'Save status' }}
        </button>
      </template>
      <span v-else-if="details.status_notes">{{ details.status_notes }}</span>
      <span v-if="details.status_updated_at" class="text-body-secondary small">
        Last updated {{ details.status_updated_at }}
      </span>
    </div>

    <table class="table">
      <tbody>
        <tr>
          <td>Description</td>
          <td>{{ details.description }} ({{ details.type }})</td>
        </tr>
        <tr>
          <td>Manager</td>
          <td>{{ details.manager }} : <a :href="`tel:${details.mobile}`">{{ details.mobile }}</a></td>
        </tr>
        <tr>
          <td>Location</td>
          <td>
            <tt>{{ details.os_grid }}</tt>
            <br />
            <a :href="`https://www.google.com/maps/place/${details.latitude},${details.longitude}`">Google Maps</a>
            <br />
            <a :href="`https://www.bing.com/maps?q=${details.latitude},${details.longitude}&style=s`">OS Maps (Bing)</a>
            <br />
            <a :href="`https://what3words.com/${details.what3words}`">What3Words</a>
          </td>
        </tr>
        <tr>
          <td>Routes</td>
          <td>
            <div v-for="r in details.routes" :key="r">
              {{ r }}:
              <CheckpointLink :checkpoint="details.previous[r]" />
              -> {{ details.checkpoint_number }} ->
              <CheckpointLink :checkpoint="details.next[r]" />
            </div>
          </td>
        </tr>
      </tbody>
    </table>

    <h2>Teams for whom this is the next checkpoint</h2>
    <table class="table">
      <tbody>
        <tr v-for="group in teamGroups('next')" :key="group.route">
          <td>{{ group.route }}</td>
          <td>{{ group.teams.length }}</td>
          <td>
            <TeamLink
              v-for="team in group.teams"
              :key="team"
              :team-number="team"
              class="badge text-bg-primary mb-1 me-1"
              style="min-width: 50px; font-size: 1.1em"
            >
              {{ team }}
            </TeamLink>
          </td>
        </tr>
      </tbody>
    </table>

    <h2>Teams That Have Been Here</h2>
    <table class="table">
      <tbody>
        <tr v-for="group in teamGroups('past')" :key="group.route">
          <td>{{ group.route }}</td>
          <td>{{ group.teams.length }}</td>
          <td>
            <TeamLink
              v-for="team in group.teams"
              :key="team"
              :team-number="team"
              class="badge text-bg-primary mb-1 me-1"
              style="min-width: 50px; font-size: 1.1em"
            >
              {{ team }}
            </TeamLink>
          </td>
        </tr>
      </tbody>
    </table>

    <h2>Teams That Have Not Yet Been Here</h2>
    <table class="table">
      <tbody>
        <tr v-for="group in teamGroups('future')" :key="group.route">
          <td>{{ group.route }}</td>
          <td>{{ group.teams.length }}</td>
          <td>
            <TeamLink
              v-for="team in group.teams"
              :key="team"
              :team-number="team"
              class="badge text-bg-primary mb-1 me-1"
              style="min-width: 50px; font-size: 1.1em"
            >
              {{ team }}
            </TeamLink>
          </td>
        </tr>
      </tbody>
    </table>

    <template v-if="details.latitude && details.longitude">
      <h2>Map</h2>
      <div ref="mapEl" class="map-responsive map-small"></div>
    </template>
  </template>
</template>
