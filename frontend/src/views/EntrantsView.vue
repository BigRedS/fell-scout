<script setup>
import { computed, ref } from 'vue'
import { getEntrants } from '../api/client'
import { usePolling } from '../composables/usePolling'
import { teamOrEntrantStatus } from '../status'
import SortableTable from '../components/SortableTable.vue'
import TeamLink from '../components/TeamLink.vue'
import StatusBadge from '../components/StatusBadge.vue'

const entrants = ref(null)

async function refresh() {
  entrants.value = await getEntrants()
}

usePolling(refresh, 10000)

const rows = computed(() => (entrants.value ? Object.values(entrants.value) : []))

const columns = [
  { key: 'id', label: 'ID', value: (row) => row.code },
  { key: 'name', label: 'Name', value: (row) => row.entrant_name },
  { key: 'status', label: 'Status', value: (row) => teamOrEntrantStatus(row) },
  { key: 'team', label: 'Team', value: (row) => row.team_name },
  { key: 'unit', label: 'Unit', value: (row) => row.unit },
  { key: 'district', label: 'District', value: (row) => row.district },
  { key: 'route', label: 'Route', value: (row) => row.route },
  { key: 'last_cp', label: 'Last Checkpoint', value: (row) => row.entrant_last_checkpoint, numeric: true },
  { key: 'next_cp', label: 'Next Checkpoint', value: (row) => (row.retired ? '' : row.team_next_checkpoint), numeric: true },
  { key: 'next_cp_in', label: 'Next CP Expected in', value: (row) => (row.retired ? '' : row.expected_in) },
  { key: 'next_cp_at', label: 'Next CP Expected at', value: (row) => (row.retired ? '' : row.expected_hhmm) },
]
</script>

<template>
  <h1>Entrants</h1>

  <p>
    This is a list of all the entrants in the event. For details of their progress, click on
    their team name to get their team's progress.
  </p>
  <p>For any more details about specific entrants, you will need to consult FellTrack directly.</p>

  <div class="mb-3">
    <a href="/api/entrants/export" download class="btn btn-outline-secondary btn-sm">Export CSV</a>
  </div>

  <SortableTable
    v-if="entrants"
    :rows="rows"
    :columns="columns"
    :row-key="(row) => row.code"
    :filterable-keys="['status', 'route']"
  >
    <template #name="{ row }">{{ row.entrant_name }}<template v-if="row.retired > 0"> (retired)</template></template>
    <template #status="{ row }"><StatusBadge :status="teamOrEntrantStatus(row)" /></template>
    <template #team="{ row }"><TeamLink :team-number="row.team_number">{{ row.team_name }}</TeamLink></template>
    <template #next_cp="{ row }"><template v-if="!row.retired">{{ row.team_next_checkpoint }}</template></template>
    <template #next_cp_in="{ row }"><template v-if="!row.retired">{{ row.expected_in }}</template></template>
    <template #next_cp_at="{ row }"><template v-if="!row.retired">{{ row.expected_hhmm }}</template></template>
  </SortableTable>
</template>
