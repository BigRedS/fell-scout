<script setup>
import { ref, computed, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { getLaterunners } from '../api/client'
import { usePolling } from '../composables/usePolling'
import SortableTable from '../components/SortableTable.vue'
import TeamLink from '../components/TeamLink.vue'
import PageHelp from '../components/PageHelp.vue'

const route = useRoute()
const router = useRouter()
const data = ref(null)

async function refresh() {
  data.value = await getLaterunners(route.params.threshold)
}

usePolling(refresh, 10000)
watch(() => route.params.threshold, refresh)

const rows = computed(() => data.value?.laterunners ?? [])

const thresholdOptions = [
  { value: '0', label: '0%' },
  { value: '5pc', label: '5%' },
  { value: '10pc', label: '10%' },
  { value: '20pc', label: '20%' },
  { value: '20m', label: '20 minutes' },
  { value: '40m', label: '40 minutes' },
  { value: '60m', label: '1 hour' },
]

function setThreshold(value) {
  router.push(`/laterunners/${value}`)
}

const columns = [
  { key: 'team', label: 'Team', value: (row) => row.team_number, numeric: true },
  { key: 'team_name', label: 'Team Name', value: (row) => row.team_name },
  { key: 'unit', label: 'Unit', value: (row) => row.unit, hideBelow: 'md' },
  { key: 'district', label: 'District', value: (row) => row.district, hideBelow: 'md' },
  { key: 'route', label: 'Route', value: (row) => row.route, hideBelow: 'md' },
  { key: 'leg', label: 'Leg', value: (row) => row.current_leg, hideBelow: 'md' },
  { key: 'expected', label: 'Next CP Expected', value: (row) => row.next_checkpoint_expected_hhmm },
  { key: 'lateness', label: 'Next CP Lateness', value: (row) => row.next_checkpoint_expected_in },
  { key: 'percent_lateness', label: 'Next CP % Lateness', value: (row) => Number(row.percent_late), numeric: true, hideBelow: 'md' },
]

function rowClass(row) {
  const percentLate = Number(row.percent_late)
  if (percentLate > Number(data.value?.lateness_percent_red)) return 'table-danger'
  if (percentLate > Number(data.value?.lateness_percent_amber)) return 'table-warning'
  return null
}
</script>

<template>
  <h1>Late Teams</h1>

  <PageHelp>
    <p>These are the teams that are running later-than-expected.</p>
    <p>For each 'leg' between two checkpoints we calculate the average time for all teams so far.</p>
    <p>This table is those teams currently running later than that.</p>
  </PageHelp>

  <div class="d-flex align-items-center gap-2 mb-3">
    <label class="mb-0">How late a team has to be in order to be in the list:</label>
    <select
      class="form-select form-select-sm w-auto"
      :value="route.params.threshold ?? '0'"
      @change="setThreshold($event.target.value)"
    >
      <option v-for="opt in thresholdOptions" :key="opt.value" :value="opt.value">{{ opt.label }}</option>
    </select>
  </div>

  <SortableTable
    v-if="data"
    :rows="rows"
    :columns="columns"
    :default-sort-column="8"
    default-sort-order="desc"
    :row-key="(row) => row.team_number"
    :row-class="rowClass"
  >
    <template #team="{ row }"><TeamLink :team-number="row.team_number" /></template>
    <template #team_name="{ row }"><TeamLink :team-number="row.team_number">{{ row.team_name }}</TeamLink></template>
    <template #leg="{ row }">{{ row.current_leg }}<br />({{ row.current_leg_duration }})</template>
    <template #percent_lateness="{ row }">{{ row.percent_late }}%</template>
  </SortableTable>
</template>
