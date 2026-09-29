<script setup>
import { ref } from 'vue'
import { getStatus, getScratchTeams, createScratchTeam, updateScratchTeam, deleteScratchTeam } from '../api/client'
import { usePolling } from '../composables/usePolling'
import TeamLink from '../components/TeamLink.vue'

const scratchTeams = ref(null)
// Per-row editable entrants text, keyed by team_number - kept separate from
// the fetched data so a background poll tick doesn't clobber an in-progress
// edit. Only seeded from fresh data the first time a team is seen.
const drafts = ref({})

const newTeamName = ref('')
const newEntrants = ref('')

// Only controllers can change anything here (the server enforces it; this
// just stops plain users seeing controls that would 403). null = not
// checked yet.
const isController = ref(null)

const successes = ref([])
const errors = ref([])
const warnings = ref([])

async function refresh() {
  if (isController.value === null) isController.value = !!(await getStatus()).is_controller
  const data = await getScratchTeams()
  scratchTeams.value = data
  for (const id of Object.keys(data)) {
    if (!(id in drafts.value)) drafts.value[id] = data[id].entrants
  }
  for (const id of Object.keys(drafts.value)) {
    if (!(id in data)) delete drafts.value[id]
  }
}

usePolling(refresh, 10000)

function applyResult(result) {
  successes.value = result.successes ?? []
  errors.value = result.errors ?? []
  warnings.value = result.warnings ?? []
}

async function addTeam() {
  const result = await createScratchTeam({ teamName: newTeamName.value, entrants: newEntrants.value })
  applyResult(result)
  newTeamName.value = ''
  newEntrants.value = ''
  await refresh()
}

async function updateTeam(id) {
  const result = await updateScratchTeam(id, { entrants: drafts.value[id] })
  applyResult(result)
  await refresh()
}

async function removeTeam(id) {
  const result = await deleteScratchTeam(id)
  applyResult(result)
  await refresh()
}
</script>

<template>
  <h1>Scratch Teams</h1>

  <div v-for="error in errors" :key="error" class="alert alert-warning" role="alert">Error: {{ error }}</div>
  <div v-for="warning in warnings" :key="warning" class="alert alert-info" role="alert">Warning: {{ warning }}</div>
  <div v-for="success in successes" :key="success" class="alert alert-success" role="alert">Success: {{ success }}</div>

  <p>A scratch team is a team made up ad-hoc of members of other teams.</p>
  <p>
    Scratch teams will show up on the normal <router-link to="/teams">teams list</router-link>, they
    all have a team number that is negative.
  </p>
  <p v-if="isController === false" class="text-body-secondary">Only Control can create or change scratch teams.</p>

  <template v-if="isController">
    <p>This page is for creating or modifying them. To do this use the form below. There are two fields:</p>
    <ul>
      <li><b>Team Name</b>: leave empty to get an automatic name, put something in if there's a better meaningful name</li>
      <li>
        <b>Entrants</b>: a space-separated list of entrant IDs, which you can read off the
        <router-link to="/entrants">entrants page</router-link>
      </li>
    </ul>
    <p>
      You can change the entrants in a team below - clearing all the entrants (or the Delete button)
      removes the team. To rename a team, delete it and recreate it with a new name.
    </p>

    <h3>Add a new Scratch Team</h3>
    <form class="mb-4" style="max-width: 30em" @submit.prevent="addTeam">
      <div class="mb-2">
        <label class="form-label">Scratch Team Name (optional)</label>
        <input v-model="newTeamName" type="text" class="form-control" />
      </div>
      <div class="mb-2">
        <label class="form-label">Entrants list</label>
        <input v-model="newEntrants" type="text" class="form-control" />
      </div>
      <button type="submit" class="btn btn-primary btn-sm">Add Scratch Team</button>
    </form>
  </template>

  <h3>{{ isController ? 'Edit existing Scratch Teams' : 'Scratch Teams' }}</h3>
  <table v-if="scratchTeams" class="table" style="max-width: 40em">
    <thead>
      <tr>
        <th>Team Number</th>
        <th>Scratch Team Name</th>
        <th>Entrants</th>
        <th v-if="isController"></th>
      </tr>
    </thead>
    <tbody>
      <tr v-for="id in Object.keys(scratchTeams).sort()" :key="id">
        <td><TeamLink :team-number="-id">-{{ id }}</TeamLink></td>
        <td>{{ scratchTeams[id].team_name }}</td>
        <td v-if="isController"><input v-model="drafts[id]" type="text" class="form-control form-control-sm" /></td>
        <td v-else>{{ scratchTeams[id].entrants }}</td>
        <td v-if="isController" class="text-nowrap">
          <button type="button" class="btn btn-primary btn-sm" @click="updateTeam(id)">Update</button>
          <button type="button" class="btn btn-outline-danger btn-sm ms-1" @click="removeTeam(id)">Delete</button>
        </td>
      </tr>
    </tbody>
  </table>
</template>
