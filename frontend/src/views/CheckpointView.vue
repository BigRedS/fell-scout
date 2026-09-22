<script setup>
import { ref, computed, watch, onUnmounted, nextTick } from 'vue'
import { useRoute } from 'vue-router'
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import '../leafletIcons'
import { getCheckpoint } from '../api/client'
import { usePolling } from '../composables/usePolling'
import TeamLink from '../components/TeamLink.vue'
import CheckpointLink from '../components/CheckpointLink.vue'

const route = useRoute()
const checkpoint = ref(null)
const mapEl = ref(null)
let leafletMap = null

async function refresh() {
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
    refresh()
  },
)

const details = computed(() => checkpoint.value?.details ?? null)

watch(details, (d) => {
  if (!d || !d.latitude || !d.longitude || leafletMap) return
  nextTick(() => {
    leafletMap = L.map(mapEl.value).setView([d.latitude, d.longitude], 13)
    L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 19,
      attribution: '&copy; <a href="http://www.openstreetmap.org/copyright">OpenStreetMap</a>',
    }).addTo(leafletMap)
    L.marker([d.latitude, d.longitude]).addTo(leafletMap)
  })
})

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
      <div ref="mapEl" style="height: 300px"></div>
    </template>
  </template>
</template>
