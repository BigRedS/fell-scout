<script setup>
import { ref } from 'vue'
import { getConfig, updateConfig, getLogs, triggerSync, clearDatabase } from '../api/client'
import { usePolling } from '../composables/usePolling'

const config = ref(null)
const logs = ref(null)
// Same pattern as ScratchTeamsView: separate editable draft state per config
// name, only ever seeded from fresh data the first time a key is seen, so a
// background poll tick can't clobber an in-progress edit.
const drafts = ref({})

const changes = ref([])
const busy = ref(false)

async function refresh() {
  const [configData, logsData] = await Promise.all([getConfig(), getLogs()])
  config.value = configData
  logs.value = logsData
  for (const name of Object.keys(configData)) {
    if (!(name in drafts.value)) drafts.value[name] = configData[name].value
  }
}

usePolling(refresh, 10000)

async function saveConfig() {
  busy.value = true
  try {
    const result = await updateConfig({ ...drafts.value })
    changes.value = result.changes ?? []
    await refresh()
  } finally {
    busy.value = false
  }
}

async function updateFromFelltrack() {
  busy.value = true
  try {
    await triggerSync()
    changes.value = ['Updated from Felltrack']
    await refresh()
  } finally {
    busy.value = false
  }
}

async function clearTheDatabase() {
  busy.value = true
  try {
    await clearDatabase()
    changes.value = ['Cleared database tables']
    await refresh()
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <h1>Fell Scout Admin</h1>

  <p>This is the admin/config page for FellScout. Here, you can modify the way FellScout displays the information it gets from FellTrack.</p>
  <p>Most of these will only take effect the next time the data is ingested from FellTrack, there's a button at the bottom of the page for that.</p>

  <h2>Config</h2>

  <div v-for="change in changes" :key="change" class="alert alert-success" role="alert">{{ change }}</div>

  <p>
    To configure routes and checkpoints, you will need a CSV and to go to the
    <router-link to="/admin/checkpoints">Checkpoints Admin page</router-link>.
  </p>
  <p>
    For some more explanation of these options, see the
    <a href="https://github.com/BigRedS/fell-scout?tab=readme-ov-file#configuration-options">documentation here</a>.
  </p>

  <form v-if="config" style="max-width: 60em" @submit.prevent="saveConfig">
    <table class="table">
      <tbody>
        <tr v-for="name in Object.keys(config).sort()" :key="name">
          <td>{{ name }}</td>
          <td><input v-model="drafts[name]" type="text" class="form-control" /></td>
          <td>{{ config[name].notes }}</td>
        </tr>
      </tbody>
    </table>
    <button type="submit" class="btn btn-primary" :disabled="busy">Update Config</button>
  </form>

  <hr />
  <h2>Logs</h2>
  <table v-if="logs" class="table">
    <thead>
      <tr>
        <th>Time</th>
        <th>Job</th>
        <th>Message</th>
      </tr>
    </thead>
    <tbody>
      <tr v-for="(log, idx) in logs" :key="idx">
        <td>{{ log.time }} ( {{ log.time_since }} ago )</td>
        <td>{{ log.name }}</td>
        <td>{{ log.message }}</td>
      </tr>
    </tbody>
  </table>

  <hr />
  <h2>Tools</h2>
  <table class="table">
    <tbody>
      <tr>
        <td><button type="button" class="btn btn-outline-primary" :disabled="busy" @click="updateFromFelltrack">Felltrack update</button></td>
        <td>Manually kick off the periodic update from FellTrack</td>
      </tr>
      <tr>
        <td><button type="button" class="btn btn-outline-danger" :disabled="busy" @click="clearTheDatabase">Clear database</button></td>
        <td>
          Clear the local cache of FellTrack, useful when something has changed on FellTrack but
          isn't showing up as changed in FellScout, or when you've updated the routes
          definitions. This will clear Scratch Teams, which will need manual recreation.
        </td>
      </tr>
    </tbody>
  </table>
</template>
