<script setup>
import { ref, computed, watch } from 'vue'
import { useRoute } from 'vue-router'
import { getArrivals } from '../api/client'
import { usePolling } from '../composables/usePolling'
import SortableTable from '../components/SortableTable.vue'
import TeamLink from '../components/TeamLink.vue'
import CheckpointLink from '../components/CheckpointLink.vue'

const route = useRoute()
const arrivals = ref(null)

async function refresh() {
  arrivals.value = await getArrivals(route.params.checkpoint)
}

usePolling(refresh, 10000)
watch(() => route.params.checkpoint, refresh)

const rows = computed(() => Object.values(arrivals.value?.teams ?? {}))

const columns = [
  { key: 'expected_here', label: 'Expected here', value: (row) => row.this_cp_expected_epoch, numeric: true },
  { key: 'team', label: 'Team', value: (row) => row.team_number, numeric: true },
  { key: 'team_name', label: 'Team Name', value: (row) => row.team_name },
  { key: 'unit_district', label: 'Unit, District', value: (row) => `${row.unit} (${row.district})` },
  { key: 'next_cp', label: 'Next Expected Checkpoint', value: (row) => row.next_checkpoint, numeric: true },
  { key: 'finish', label: 'Expected at finish', value: (row) => row.finish_expected_epoch, numeric: true },
]

function rowClass(row) {
  return Number(row.next_checkpoint) === Number(arrivals.value?.cp) ? 'table-success' : null
}
</script>

<template>
  <h1>Checkpoint {{ arrivals?.cp }} Arrivals Board</h1>

  <p>This page shows every team that has yet to reach this checkpoint, and when they're expected here.</p>
  <p>'Expected at finish' will only populate when enough teams have finished the event to make for reasonable estimates for the teams behind them.</p>
  <p>
    You can see all teams and all checkpoints on the general
    <router-link to="/checkpoints">checkpoints page</router-link>, and details for the checkpoint
    on its <CheckpointLink :checkpoint="arrivals?.cp">details page</CheckpointLink>.
  </p>

  <SortableTable
    v-if="arrivals"
    :rows="rows"
    :columns="columns"
    :searchable="false"
    :row-key="(row) => row.team_number"
    :row-class="rowClass"
  >
    <template #expected_here="{ row }">{{ row.this_cp_expected_hhmm }}</template>
    <template #team="{ row }"><TeamLink :team-number="row.team_number" /></template>
    <template #team_name="{ row }"><TeamLink :team-number="row.team_number">{{ row.team_name }}</TeamLink></template>
    <template #next_cp="{ row }">
      <CheckpointLink :checkpoint="row.next_checkpoint" /> ({{ row.next_checkpoint_expected_hhmm }})
    </template>
    <template #finish="{ row }">{{ row.finish_expected_hhmm }}</template>
  </SortableTable>
</template>
