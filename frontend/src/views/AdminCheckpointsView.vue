<script setup>
import { ref } from 'vue'
import { getStatus, getRoutesCheckpoints, importCheckpointsCsv } from '../api/client'
import { usePolling } from '../composables/usePolling'
import CheckpointLink from '../components/CheckpointLink.vue'

// Same pattern as AdminView: the nav already hides the way here for
// non-admins, but this is reachable by direct URL too.
const isAdmin = ref(null)

async function checkIsAdmin() {
  if (isAdmin.value === null) {
    const status = await getStatus()
    isAdmin.value = !!status.is_admin
  }
  return isAdmin.value
}

const routesCps = ref(null)
const selectedFile = ref(null)
const uploading = ref(false)
const result = ref(null)
const error = ref(null)

async function refresh() {
  if (!(await checkIsAdmin())) return
  routesCps.value = await getRoutesCheckpoints()
}

usePolling(refresh, 10000)

function onFileChange(event) {
  selectedFile.value = event.target.files[0] ?? null
}

async function upload() {
  if (!selectedFile.value) return
  uploading.value = true
  error.value = null
  result.value = null
  try {
    result.value = await importCheckpointsCsv(selectedFile.value)
    await refresh()
  } catch (e) {
    error.value = e.message
  } finally {
    uploading.value = false
  }
}
</script>

<template>
  <h1>Checkpoints Admin</h1>

  <div v-if="isAdmin === false" class="alert alert-secondary">
    You don't have admin access. Ask whoever manages the FellScout admin list to add you.
  </div>

  <template v-else-if="isAdmin">
  <p>Routes are defined as a series of checkpoints; here you can see the current routes and upload a new CSV file to change it.</p>

  <h2>Current routes and checkpoints</h2>
  <p>The start is checkpoint 0, the finish is checkpoint 99.</p>
  <table v-if="routesCps" class="table table-hover">
    <tbody>
      <tr v-for="route in Object.keys(routesCps).sort()" :key="route">
        <td>{{ route }}</td>
        <td>
          <CheckpointLink
            v-for="cp in routesCps[route]"
            :key="cp"
            :checkpoint="cp"
            class="badge text-bg-primary mb-1 me-1"
            style="min-width: 50px; font-size: 1.1em"
          >
            {{ cp }}
          </CheckpointLink>
        </td>
      </tr>
    </tbody>
  </table>

  <h2>Update the routes definition</h2>

  <p>
    After updating this, you will need to do 'Clear Database' and then 'Felltrack Update' on
    <router-link to="/admin">the admin page</router-link> if you've made any changes to which
    checkpoints are on which route; you will lose any scratch teams. You don't need to do this
    when just updating information about checkpoints.
  </p>

  <div v-if="error" class="alert alert-danger" role="alert">{{ error }}</div>
  <div v-if="result" class="alert alert-success" role="alert">
    Imported {{ result.checkpoints }} checkpoints across {{ result.routes }} routes ({{ result.legs }} legs).
  </div>

  <form @submit.prevent="upload">
    <input type="file" accept=".csv" class="form-control mb-2" style="max-width: 30em" @change="onFileChange" />
    <button type="submit" class="btn btn-primary" :disabled="!selectedFile || uploading">
      {{ uploading ? 'Uploading…' : 'Upload' }}
    </button>
  </form>

  <p>This configuration is done via CSV file, the CSV file must have some very specific column names:</p>

  <table class="table table-striped table-hover">
    <tbody>
      <tr><td><tt>cp</tt></td><td>The checkpoint number, either in the form CPxx where xx is a number, or the word 'Start' or 'Finish'</td></tr>
      <tr><td><tt>description</tt></td><td>Perhaps better called 'name'</td></tr>
      <tr><td><tt>checkpoint manager</tt></td><td>The name of the person managing it</td></tr>
      <tr><td><tt>mobile</tt></td><td>The phone number of the person managing it</td></tr>
      <tr><td><tt>type of checkpoint</tt></td><td>Usually 'tent', 'building' etc.; has no meaning inside fellscout, is just displayed verbatim</td></tr>
      <tr><td><tt>what3words</tt></td><td>The What3Words address</td></tr>
      <tr><td><tt>grid reference</tt></td><td>The OS grid ref of the checkpoint</td></tr>
      <tr><td><tt>latitude</tt></td><td>The latitude of the checkpoint, will be used to create a google maps link</td></tr>
      <tr><td><tt>longitude</tt></td><td>The longitude of the checkpoint, will be used to create a google maps link</td></tr>
      <tr>
        <td><tt>[route name] Leg distance</tt></td>
        <td>
          One for each route, this has the distance in km from the previous point in that route
          (so the entry for CP2 will be the distance from CP1 to CP2). It should be empty for
          checkpoints not on the named route. The [route name] must exactly match what FellTrack
          puts in the route column.
        </td>
      </tr>
    </tbody>
  </table>

  <p>This will update the association of checkpoints with routes and any checkpoint details, but not affect any progress data.</p>
  </template>
</template>
