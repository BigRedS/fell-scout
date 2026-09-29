<script setup>
import { ref, computed } from 'vue'
import { getStatus, getRetirements, createRetirement, updateRetirement, deleteRetirement } from '../api/client'
import { usePolling } from '../composables/usePolling'
import SortableTable from '../components/SortableTable.vue'
import TeamLink from '../components/TeamLink.vue'
import CheckpointLink from '../components/CheckpointLink.vue'

const STATUSES = ['Awaiting pickup', 'Assigned', 'Picked up', 'Complete']

const retirements = ref(null)
// Per-row editable vehicle text, kept separate from fetched data so a
// background poll tick can't clobber an in-progress edit - same pattern as
// ScratchTeamsView/AdminView.
const vehicleDrafts = ref({})

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
    featureEnabled.value = !!status.retirements_enabled
    isController.value = !!status.is_controller
  }
  return featureEnabled.value
}

async function refresh() {
  if (!(await checkFeatureEnabled())) return
  const data = await getRetirements()
  retirements.value = data
  for (const id of Object.keys(data)) {
    if (!(id in vehicleDrafts.value)) vehicleDrafts.value[id] = data[id].vehicle ?? ''
  }
}

usePolling(refresh, 10000)

const rows = computed(() => (retirements.value ? Object.values(retirements.value) : []))

const newRetirement = ref({ entrant_code: '', team_number: '', checkpoint_number: '', reason: '' })

async function addRetirement() {
  await createRetirement({
    ...newRetirement.value,
    team_number: newRetirement.value.team_number || null,
    checkpoint_number: newRetirement.value.checkpoint_number || null,
  })
  newRetirement.value = { entrant_code: '', team_number: '', checkpoint_number: '', reason: '' }
  await refresh()
}

async function setStatus(row, status) {
  await updateRetirement(row.id, { ...row, status })
  await refresh()
}

async function saveVehicle(row) {
  await updateRetirement(row.id, { ...row, vehicle: vehicleDrafts.value[row.id] })
  await refresh()
}

async function removeRetirement(row) {
  await deleteRetirement(row.id)
  await refresh()
}

const columns = computed(() => [
  { key: 'id', label: 'ID', value: (row) => row.id, numeric: true },
  { key: 'entrant', label: 'Entrant', value: (row) => row.entrant_code },
  { key: 'team', label: 'Team', value: (row) => row.team_number, numeric: true },
  { key: 'checkpoint', label: 'Checkpoint', value: (row) => row.checkpoint_number, numeric: true },
  { key: 'reason', label: 'Reason', value: (row) => row.reason },
  { key: 'vehicle', label: 'Vehicle', value: (row) => row.vehicle },
  { key: 'status', label: 'Status', value: (row) => row.status },
  { key: 'created_at', label: 'Created', value: (row) => row.created_at },
  ...(isController.value ? [{ key: 'actions', label: '', value: () => '' }] : []),
])
</script>

<template>
  <h1>Retirements</h1>

  <div v-if="featureEnabled === false" class="alert alert-secondary">
    The Retirements feature is currently disabled. A Control admin can turn it back on from the
    <router-link to="/admin">Admin</router-link> page.
  </div>

  <template v-else-if="featureEnabled">
    <p>Tracks entrants who've retired and need picking up - who, from where, and which vehicle's assigned.</p>

    <template v-if="isController">
      <h3>Log a retirement</h3>
      <form class="row g-2 mb-4" style="max-width: 60em" @submit.prevent="addRetirement">
        <div class="col-auto">
          <input v-model="newRetirement.entrant_code" type="text" class="form-control form-control-sm" placeholder="Entrant code" style="width: 8em" required />
        </div>
        <div class="col-auto">
          <input v-model="newRetirement.team_number" type="number" class="form-control form-control-sm" placeholder="Team #" style="width: 6em" />
        </div>
        <div class="col-auto">
          <input v-model="newRetirement.checkpoint_number" type="number" class="form-control form-control-sm" placeholder="CP #" style="width: 6em" />
        </div>
        <div class="col">
          <input v-model="newRetirement.reason" type="text" class="form-control form-control-sm" placeholder="Reason" />
        </div>
        <div class="col-auto">
          <button type="submit" class="btn btn-primary btn-sm">Log retirement</button>
        </div>
      </form>
    </template>
    <p v-else class="text-body-secondary">Only Control can log or change retirements.</p>

    <SortableTable
      v-if="retirements"
      :rows="rows"
      :columns="columns"
      :row-key="(row) => row.id"
      :default-sort-column="7"
      default-sort-order="desc"
      :filterable-keys="['status']"
    >
      <template #team="{ row }">
        <TeamLink v-if="row.team_number" :team-number="row.team_number" />
      </template>
      <template #checkpoint="{ row }">
        <CheckpointLink v-if="row.checkpoint_number" :checkpoint="row.checkpoint_number" />
      </template>
      <template #vehicle="{ row }">
        <div v-if="isController" class="d-flex gap-1">
          <input v-model="vehicleDrafts[row.id]" type="text" class="form-control form-control-sm" style="width: 8em" />
          <button type="button" class="btn btn-outline-secondary btn-sm" @click="saveVehicle(row)">Save</button>
        </div>
        <template v-else>{{ row.vehicle }}</template>
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
        <button type="button" class="btn btn-outline-danger btn-sm" @click="removeRetirement(row)">Delete</button>
      </template>
    </SortableTable>
  </template>
</template>
