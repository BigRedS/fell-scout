<script setup>
import { computed, onMounted, onUnmounted, ref } from 'vue'
import { getStatus, triggerSync } from '../api/client'
import { usePolling, isPollingEnabled, toggleGlobalPolling } from '../composables/usePolling'
import { useDarkMode } from '../composables/useDarkMode'

// A plain, non-static src would make Vite try to bundle this as a module
// import - it only exists in the backend's public/, not the Vite project.
// Putting it behind a variable keeps the binding dynamic, so Vite leaves it
// as a runtime string instead of trying to resolve it at build time.
const badgeImageUrl = '/scout-navigator-badge.png'

const status = ref({})
const syncing = ref(false)

async function refreshStatus() {
  status.value = await getStatus()
}

usePolling(refreshStatus, 10000)
const pollingEnabled = isPollingEnabled()

async function syncNow() {
  syncing.value = true
  try {
    await triggerSync()
    await refreshStatus()
  } finally {
    syncing.value = false
  }
}

// The "last synced Xm ago" text goes stale the instant it's rendered, so it
// gets its own cheap 1s tick, separate from the (much slower) network poll
// that actually fetches last_sync_epoch.
const now = ref(Date.now())
let clockId = null
onMounted(() => { clockId = setInterval(() => { now.value = Date.now() }, 1000) })
onUnmounted(() => clearInterval(clockId))

const lastSyncedText = computed(() => {
  if (!status.value.last_sync_epoch) return 'never'
  const seconds = Math.max(0, Math.round(now.value / 1000 - status.value.last_sync_epoch))
  if (seconds < 60) return `${seconds}s ago`
  return `${Math.round(seconds / 60)}m ago`
})

const isStale = computed(() => {
  if (!status.value.last_sync_epoch) return true
  const seconds = now.value / 1000 - status.value.last_sync_epoch
  return seconds > (status.value.stale_after_seconds ?? 600)
})

const { isDark, toggle: toggleDarkMode } = useDarkMode()

const navLinks = [
  { label: 'Summary', to: '/' },
  { label: 'Late Teams', to: '/laterunners' },
  { label: 'Scratch Teams', to: '/scratch-teams' },
  { label: 'All Teams', to: '/teams' },
  { label: 'Checkpoints', to: '/checkpoints' },
  { label: 'Map', to: '/map' },
  { label: 'Legs', to: '/legs' },
  { label: 'Entrants', to: '/entrants' },
  { label: 'Admin', to: '/admin' },
]
</script>

<template>
  <nav class="navbar sticky-top navbar-expand-lg bg-body-tertiary border-bottom mb-3">
    <div class="container">
      <router-link class="navbar-brand d-flex align-items-center gap-2" to="/">
        <img :src="badgeImageUrl" alt="Scout Navigator Badge" style="max-height: 30px" />
        Fell Scout
      </router-link>

      <ul class="navbar-nav flex-row flex-wrap gap-3 me-3">
        <li v-for="link in navLinks" :key="link.to" class="nav-item">
          <router-link class="nav-link" :to="link.to">{{ link.label }}</router-link>
        </li>
      </ul>

      <div class="d-flex align-items-center gap-2 ms-auto">
        <button
          type="button"
          class="btn btn-sm"
          :class="isStale ? 'btn-outline-danger' : 'btn-outline-success'"
          :disabled="syncing"
          @click="syncNow"
        >
          Last sync: {{ syncing ? 'syncing…' : lastSyncedText }}
        </button>

        <button
          type="button"
          class="btn btn-sm"
          :class="pollingEnabled ? 'btn-primary' : 'btn-outline-secondary'"
          @click="toggleGlobalPolling"
        >
          Auto refresh: {{ pollingEnabled ? 'on' : 'off' }}
        </button>

        <button type="button" class="btn btn-sm btn-outline-secondary" @click="toggleDarkMode">
          {{ isDark ? 'Light mode' : 'Dark mode' }}
        </button>
      </div>
    </div>
  </nav>
</template>
