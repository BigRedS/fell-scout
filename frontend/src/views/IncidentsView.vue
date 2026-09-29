<script setup>
import { ref, computed } from 'vue'
import { getStatus, getIncidents, createIncident, updateIncident, deleteIncident } from '../api/client'
import { usePolling } from '../composables/usePolling'
import SortableTable from '../components/SortableTable.vue'
import TeamLink from '../components/TeamLink.vue'
import CheckpointLink from '../components/CheckpointLink.vue'

const INCIDENT_TYPES = ['Medical', 'Lost', 'Behavioural', 'Transport', 'Other']
const STATUSES = ['Open', 'In Progress', 'Resolved']

const incidents = ref(null)
// Per-row editable owner text, kept separate from fetched data so a
// background poll tick can't clobber an in-progress edit - same pattern as
// RetirementsView's vehicle field. Incidents often outlive a single shift,
// so who owns one needs to change without recreating it - this is free
// text, not a login/user reference (there's no per-person account system,
// and deliberately isn't going to be one - "owner" is whoever currently has
// it, by name, not a picker of registered users).
const ownerDrafts = ref({})

// The nav already hides the link when this feature's off, but someone can
// still navigate here directly (bookmark, back button) - check first rather
// than calling the API and letting its 403 fail silently. null = not
// checked yet, so nothing renders until we actually know either way.
const featureEnabled = ref(null)
// Only controllers can change anything here (the server enforces it; this
// just stops plain users seeing controls that would 403).
const isController = ref(false)

async function checkFeatureEnabled() {
  if (featureEnabled.value === null) {
    const status = await getStatus()
    featureEnabled.value = !!status.incidents_enabled
    isController.value = !!status.is_controller
  }
  return featureEnabled.value
}

async function refresh() {
  if (!(await checkFeatureEnabled())) return
  const data = await getIncidents()
  incidents.value = data
  for (const id of Object.keys(data)) {
    if (!(id in ownerDrafts.value)) ownerDrafts.value[id] = data[id].owner ?? ''
  }
}

usePolling(refresh, 10000)

const rows = computed(() => (incidents.value ? Object.values(incidents.value) : []))

const newIncident = ref({
  type: 'Medical',
  description: '',
  checkpoint_number: '',
  team_number: '',
  owner: '',
})

async function addIncident() {
  await createIncident({
    ...newIncident.value,
    checkpoint_number: newIncident.value.checkpoint_number || null,
    team_number: newIncident.value.team_number || null,
  })
  newIncident.value = { type: 'Medical', description: '', checkpoint_number: '', team_number: '', owner: '' }
  await refresh()
}

async function setStatus(row, status) {
  await updateIncident(row.id, { ...row, status })
  await refresh()
}

async function saveOwner(row) {
  await updateIncident(row.id, { ...row, owner: ownerDrafts.value[row.id] })
  await refresh()
}

async function removeIncident(row) {
  await deleteIncident(row.id)
  await refresh()
}

const columns = computed(() => [
  { key: 'id', label: 'ID', value: (row) => row.id, numeric: true },
  { key: 'type', label: 'Type', value: (row) => row.type },
  { key: 'description', label: 'Description', value: (row) => row.description },
  { key: 'checkpoint', label: 'Checkpoint', value: (row) => row.checkpoint_number, numeric: true },
  { key: 'team', label: 'Team', value: (row) => row.team_number, numeric: true },
  { key: 'owner', label: 'Owner', value: (row) => row.owner },
  { key: 'status', label: 'Status', value: (row) => row.status },
  { key: 'created_at', label: 'Created', value: (row) => row.created_at },
  ...(isController.value ? [{ key: 'actions', label: '', value: () => '' }] : []),
])
</script>

<template>
  <h1>Incidents</h1>

  <div v-if="featureEnabled === false" class="alert alert-secondary">
    The Incidents feature is currently disabled. A Control admin can turn it back on from the
    <router-link to="/admin">Admin</router-link> page.
  </div>

  <template v-else-if="featureEnabled">
    <p>A log of medical, lost-team, behavioural, and transport incidents during the event.</p>

    <template v-if="isController">
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
          <input v-model="newIncident.owner" type="text" class="form-control form-control-sm" placeholder="Owner" />
        </div>
        <div class="col-auto">
          <button type="submit" class="btn btn-primary btn-sm">Log incident</button>
        </div>
      </form>
    </template>
    <p v-else class="text-body-secondary">Only Control can log or change incidents.</p>

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
      <template #owner="{ row }">
        <div v-if="isController" class="d-flex gap-1">
          <input v-model="ownerDrafts[row.id]" type="text" class="form-control form-control-sm" style="width: 10em" />
          <button type="button" class="btn btn-outline-secondary btn-sm" @click="saveOwner(row)">Save</button>
        </div>
        <template v-else>{{ row.owner }}</template>
      </template>
      <template #status="{ row }">
        <select
          v-if="isController"
          class="form-select form-select-sm w-auto"
          :value="row.status"
          @change="setStatus(row, $event.target.value)"
        >
          <option v-for="s in STATUSES" :key="s" :value="s">{{ s }}</option>
        </select>
        <template v-else>{{ row.status }}</template>
      </template>
      <template #actions="{ row }">
        <button type="button" class="btn btn-outline-danger btn-sm" @click="removeIncident(row)">Delete</button>
      </template>
    </SortableTable>
  </template>
</template>
