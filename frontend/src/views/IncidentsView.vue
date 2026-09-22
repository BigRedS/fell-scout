<script setup>
import { ref, computed } from 'vue'
import { getIncidents, createIncident, updateIncident, deleteIncident } from '../api/client'
import { usePolling } from '../composables/usePolling'
import SortableTable from '../components/SortableTable.vue'
import TeamLink from '../components/TeamLink.vue'
import CheckpointLink from '../components/CheckpointLink.vue'

const INCIDENT_TYPES = ['Medical', 'Lost', 'Behavioural', 'Transport', 'Other']
const STATUSES = ['Open', 'In Progress', 'Resolved']

const incidents = ref(null)

async function refresh() {
  incidents.value = await getIncidents()
}

usePolling(refresh, 10000)

const rows = computed(() => (incidents.value ? Object.values(incidents.value) : []))

const newIncident = ref({
  type: 'Medical',
  description: '',
  checkpoint_number: '',
  team_number: '',
  assigned_to: '',
})

async function addIncident() {
  await createIncident({
    ...newIncident.value,
    checkpoint_number: newIncident.value.checkpoint_number || null,
    team_number: newIncident.value.team_number || null,
  })
  newIncident.value = { type: 'Medical', description: '', checkpoint_number: '', team_number: '', assigned_to: '' }
  await refresh()
}

async function setStatus(row, status) {
  await updateIncident(row.id, { ...row, status })
  await refresh()
}

async function removeIncident(row) {
  await deleteIncident(row.id)
  await refresh()
}

const columns = [
  { key: 'id', label: 'ID', value: (row) => row.id, numeric: true },
  { key: 'type', label: 'Type', value: (row) => row.type },
  { key: 'description', label: 'Description', value: (row) => row.description },
  { key: 'checkpoint', label: 'Checkpoint', value: (row) => row.checkpoint_number, numeric: true },
  { key: 'team', label: 'Team', value: (row) => row.team_number, numeric: true },
  { key: 'assigned_to', label: 'Assigned To', value: (row) => row.assigned_to },
  { key: 'status', label: 'Status', value: (row) => row.status },
  { key: 'created_at', label: 'Created', value: (row) => row.created_at },
  { key: 'actions', label: '', value: () => '' },
]
</script>

<template>
  <h1>Incidents</h1>

  <p>A log of medical, lost-team, behavioural, and transport incidents during the event.</p>

  <h3>Log a new incident</h3>
  <form class="row g-2 mb-4" style="max-width: 60em" @submit.prevent="addIncident">
    <div class="col-auto">
      <select v-model="newIncident.type" class="form-select form-select-sm">
        <option v-for="t in INCIDENT_TYPES" :key="t" :value="t">{{ t }}</option>
      </select>
    </div>
    <div class="col">
      <input v-model="newIncident.description" type="text" class="form-control form-control-sm" placeholder="Description" required />
    </div>
    <div class="col-auto">
      <input v-model="newIncident.checkpoint_number" type="number" class="form-control form-control-sm" placeholder="CP #" style="width: 6em" />
    </div>
    <div class="col-auto">
      <input v-model="newIncident.team_number" type="number" class="form-control form-control-sm" placeholder="Team #" style="width: 6em" />
    </div>
    <div class="col-auto">
      <input v-model="newIncident.assigned_to" type="text" class="form-control form-control-sm" placeholder="Assigned to" />
    </div>
    <div class="col-auto">
      <button type="submit" class="btn btn-primary btn-sm">Log incident</button>
    </div>
  </form>

  <SortableTable
    v-if="incidents"
    :rows="rows"
    :columns="columns"
    :row-key="(row) => row.id"
    :default-sort-column="7"
    default-sort-order="desc"
    :filterable-keys="['status', 'type']"
  >
    <template #checkpoint="{ row }">
      <CheckpointLink v-if="row.checkpoint_number" :checkpoint="row.checkpoint_number" />
    </template>
    <template #team="{ row }">
      <TeamLink v-if="row.team_number" :team-number="row.team_number" />
    </template>
    <template #status="{ row }">
      <select
        class="form-select form-select-sm w-auto"
        :value="row.status"
        @change="setStatus(row, $event.target.value)"
      >
        <option v-for="s in STATUSES" :key="s" :value="s">{{ s }}</option>
      </select>
    </template>
    <template #actions="{ row }">
      <button type="button" class="btn btn-outline-danger btn-sm" @click="removeIncident(row)">Delete</button>
    </template>
  </SortableTable>
</template>
