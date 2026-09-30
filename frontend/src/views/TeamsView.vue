<script setup>
import { computed, ref } from 'vue'
import { useRouter } from 'vue-router'
import { getTeams } from '../api/client'
import { usePolling } from '../composables/usePolling'
import { teamOrEntrantStatus } from '../status'
import SortableTable from '../components/SortableTable.vue'
import TeamLink from '../components/TeamLink.vue'
import StatusBadge from '../components/StatusBadge.vue'
import PageHelp from '../components/PageHelp.vue'

const router = useRouter()
const teams = ref(null)
const jumpToTeam = ref('')

async function refresh() {
  teams.value = await getTeams()
}

usePolling(refresh, 10000)

const rows = computed(() => (teams.value ? Object.values(teams.value) : []))

const teamIdsSorted = computed(() =>
  Object.keys(teams.value ?? {})
    .map(Number)
    .sort((a, b) => a - b),
)

function goToTeam() {
  if (jumpToTeam.value !== '') router.push(`/team/${jumpToTeam.value}`)
}

const columns = [
  { key: 'id', label: 'ID', value: (row) => row.team_number, numeric: true },
  { key: 'name', label: 'Name', value: (row) => row.team_name },
  { key: 'status', label: 'Status', value: (row) => teamOrEntrantStatus(row) },
  { key: 'route', label: 'Route', value: (row) => row.route, hideBelow: 'md' },
  { key: 'last_checkin', label: 'Last Checkin', value: (row) => row.last_checkpoint_hhmm, hideBelow: 'md' },
  { key: 'last_cp', label: 'Last CP', value: (row) => row.last_checkpoint, numeric: true },
  { key: 'next_cp', label: 'Next CP', value: (row) => row.next_checkpoint, numeric: true },
  { key: 'next_cp_at', label: 'Next CP at', value: (row) => row.next_checkpoint_expected_hhmm },
  { key: 'next_cp_in', label: 'Next CP in', value: (row) => row.next_checkpoint_expected_in, hideBelow: 'md' },
  { key: 'finish', label: 'Finish expected', value: (row) => row.finish_expected_hhmm, hideBelow: 'md' },
  { key: 'district_unit', label: 'District, Unit', value: (row) => `${row.district} ${row.unit}`, hideBelow: 'md' },
]
</script>

<template>
  <h1>Teams</h1>

  <PageHelp>
    <p>
      Every team in the event; scratch teams have a negative number for an ID and may be edited on
      the <router-link to="/scratch-teams">Scratch Teams</router-link> page.
    </p>
    <p>Checkpoint 99 is the finish, so any teams with a 'Last CP' of 99 have already finished.</p>
    <p>
      'Expected at finish' will be empty until enough teams on a given route have finished for a
      reasonable estimate to be calculated. Similarly, teams towards the front will have no estimate
      for their next checkpoint if not many other teams have already got there.
    </p>
  </PageHelp>

  <div class="d-flex align-items-center gap-3 mb-3 flex-wrap">
    <form class="d-flex align-items-center gap-2" @submit.prevent="goToTeam">
      <label class="mb-0">View a specific team:</label>
      <select v-model="jumpToTeam" class="form-select form-select-sm w-auto">
        <option value="">-</option>
        <option v-for="id in teamIdsSorted" :key="id" :value="id">{{ id }}</option>
      </select>
      <button type="submit" class="btn btn-primary btn-sm">Go</button>
    </form>
    <a href="/api/teams/export" download class="btn btn-outline-secondary btn-sm">Export CSV</a>
  </div>

  <SortableTable
    v-if="teams"
    :rows="rows"
    :columns="columns"
    :row-key="(row) => row.team_number"
    :filterable-keys="['status', 'route']"
  >
    <template #id="{ row }"><TeamLink :team-number="row.team_number" /></template>
    <template #name="{ row }"><TeamLink :team-number="row.team_number">{{ row.team_name }}</TeamLink></template>
    <template #status="{ row }"><StatusBadge :status="teamOrEntrantStatus(row)" /></template>
  </SortableTable>
</template>
