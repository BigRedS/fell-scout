<script setup>
import { ref, computed } from 'vue'
import { useRouter } from 'vue-router'
import { getCheckpoints } from '../api/client'
import { usePolling } from '../composables/usePolling'
import TeamLink from '../components/TeamLink.vue'
import CheckpointLink from '../components/CheckpointLink.vue'

const router = useRouter()
const checkpoints = ref(null)
const jumpToCheckpoint = ref('')

async function refresh() {
  checkpoints.value = await getCheckpoints()
}

usePolling(refresh, 10000)

const checkpointIdsSorted = computed(() =>
  Object.keys(checkpoints.value ?? {})
    .map(Number)
    .sort((a, b) => a - b),
)

// Checkpoint 0 is never a leg's destination, so get_checkpoints() never
// gives it routes/past/future/arrivals/departures - only `details`. Default
// everything else to empty so this page doesn't break on it.
function cpRows() {
  return checkpointIdsSorted.value.map((id) => {
    const cp = checkpoints.value[id]
    return {
      id,
      routes: cp.routes ?? [],
      past: cp.past ?? {},
      future: cp.future ?? {},
      arrivals: cp.arrivals ?? [],
      departures: cp.departures ?? [],
    }
  })
}

const rows = computed(() => (checkpoints.value ? cpRows() : []))

function goToCheckpoint() {
  if (jumpToCheckpoint.value !== '') router.push(`/checkpoint/${jumpToCheckpoint.value}`)
}
</script>

<template>
  <h1>Checkpoints</h1>

  <p>
    This is a list of every checkpoint, each team for whom the checkpoint is the next they will
    reach, and each team for whom it is the last they left.
  </p>

  <p>"Checkpoint 99" is the finish.</p>

  <form class="d-flex align-items-center gap-2 mb-3" @submit.prevent="goToCheckpoint">
    <label class="mb-0">View a specific checkpoint's arrivals board:</label>
    <select v-model="jumpToCheckpoint" class="form-select form-select-sm w-auto">
      <option value="">-</option>
      <option v-for="id in checkpointIdsSorted" :key="id" :value="id">{{ id }}</option>
    </select>
    <button type="submit" class="btn btn-primary btn-sm">Go</button>
  </form>

  <div class="table-responsive">
    <table class="table table-hover table-sm">
      <thead>
        <tr>
          <th class="text-center">Checkpoint</th>
          <th class="text-center">Links</th>
          <th class="text-center">Routes</th>
          <th class="text-center">Teams<br />passed</th>
          <th class="text-center">Teams<br />not passed</th>
          <th>Arrivals</th>
          <th>Recent Departures</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="row in rows" :key="row.id">
          <td class="text-center">{{ row.id }}</td>
          <td class="text-center">
            <router-link :to="`/arrivals/${row.id}`">Arrivals</router-link>
            <br />
            <CheckpointLink :checkpoint="row.id">Info</CheckpointLink>
          </td>
          <td class="text-center">
            <div v-for="r in row.routes" :key="r">{{ r }}</div>
          </td>
          <td class="text-center">
            <div v-for="r in row.routes" :key="r">{{ (row.past[r] ?? []).length }}</div>
          </td>
          <td class="text-center">
            <div v-for="r in row.routes" :key="r">{{ (row.future[r] ?? []).length }}</div>
          </td>
          <td>
            <ul class="mb-0">
              <li v-for="team in row.arrivals" :key="team.team_number">
                {{ team.next_checkpoint_expected_hhmm }} (in {{ team.next_checkpoint_expected_in }}):
                <TeamLink :team-number="team.team_number">{{ team.team_number }} {{ team.team_name }}</TeamLink>
                expected from
                <CheckpointLink :checkpoint="team.last_checkpoint" />
              </li>
            </ul>
          </td>
          <td>
            <ul class="mb-0">
              <li v-for="team in row.departures" :key="team.team_number">
                <TeamLink :team-number="team.team_number">{{ team.team_number }} : {{ team.team_name }}</TeamLink>
              </li>
            </ul>
          </td>
        </tr>
      </tbody>
    </table>
  </div>
</template>
