<script setup>
import { computed, onMounted, onUnmounted, ref, watch } from 'vue'
import { useRoute } from 'vue-router'
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

// Mobile hamburger menu. Toggled here rather than with Bootstrap's collapse
// JS (not loaded - only its CSS is), and shut on navigation so tapping a
// link doesn't leave the open menu covering the page.
const menuOpen = ref(false)
const route = useRoute()
watch(() => route.fullPath, () => {
  menuOpen.value = false
  moreOpen.value = false
})

// The "More" dropdown (mid-width screens only, see the <style>). Also its
// own ref instead of Bootstrap's dropdown JS; closes on a click anywhere
// outside it, as a Bootstrap dropdown would.
const moreOpen = ref(false)
const moreEl = ref(null)
function closeMoreOnOutsideClick(event) {
  if (moreEl.value && !moreEl.value.contains(event.target)) moreOpen.value = false
}
onMounted(() => document.addEventListener('click', closeMoreOnOutsideClick))
onUnmounted(() => document.removeEventListener('click', closeMoreOnOutsideClick))

// Incidents/Retirements are behind config toggles (Admin page) - hidden
// from the nav until /api/status positively confirms they're on, rather
// than flashing them and then hiding them once the real value arrives.
const mainLinks = [
  { label: 'Summary', to: '/' },
  { label: 'Late Teams', to: '/laterunners' },
  { label: 'All Teams', to: '/teams' },
  { label: 'Checkpoints', to: '/checkpoints' },
  { label: 'Map', to: '/map' },
  { label: 'Legs', to: '/legs' },
  { label: 'Entrants', to: '/entrants' },
]

// Mostly Control's pages - these are the ones that fold into "More" when
// the bar is short of room.
const extraLinks = computed(() => [
  { label: 'Scratch Teams', to: '/scratch-teams' },
  ...(status.value.incidents_enabled ? [{ label: 'Incidents', to: '/incidents' }] : []),
  ...(status.value.retirements_enabled ? [{ label: 'Retirements', to: '/retirements' }] : []),
  // Hiding the link isn't the real security boundary (the server-side check
  // on each admin route is) - this just keeps a Controller/Viewer from
  // landing on a page that's all 403s for them.
  ...(status.value.is_admin ? [{ label: 'Admin', to: '/admin' }] : []),
])
</script>

<template>
  <nav class="navbar sticky-top navbar-expand-xl bg-body-tertiary border-bottom mb-3">
    <div class="container-fluid">
      <router-link class="navbar-brand d-flex align-items-center gap-2" to="/">
        <img :src="badgeImageUrl" alt="Scout Navigator Badge" style="max-height: 30px" />
        Fell Scout
      </router-link>

      <button
        type="button"
        class="navbar-toggler"
        :aria-expanded="menuOpen"
        aria-label="Toggle navigation"
        @click="menuOpen = !menuOpen"
      >
        <span class="navbar-toggler-icon"></span>
      </button>

      <div class="collapse navbar-collapse" :class="{ show: menuOpen }">
        <ul class="navbar-nav me-auto text-nowrap">
          <li v-for="link in mainLinks" :key="link.to" class="nav-item">
            <router-link class="nav-link" :to="link.to">{{ link.label }}</router-link>
          </li>
          <li v-for="link in extraLinks" :key="link.to" class="nav-item nav-extra-inline">
            <router-link class="nav-link" :to="link.to">{{ link.label }}</router-link>
          </li>
          <li ref="moreEl" class="nav-item dropdown nav-extra-more">
            <button
              type="button"
              class="nav-link dropdown-toggle"
              :aria-expanded="moreOpen"
              @click="moreOpen = !moreOpen"
            >
              More
            </button>
            <ul class="dropdown-menu" :class="{ show: moreOpen }">
              <li v-for="link in extraLinks" :key="link.to">
                <router-link class="dropdown-item" :to="link.to">{{ link.label }}</router-link>
              </li>
            </ul>
          </li>
        </ul>

        <div class="d-flex flex-wrap align-items-center gap-2 pb-2 pb-xl-0">
          <button
            type="button"
            class="btn btn-sm text-nowrap"
            :class="isStale ? 'btn-outline-danger' : 'btn-outline-success'"
            :disabled="syncing"
            @click="syncNow"
          >
            Last sync: {{ syncing ? 'syncing…' : lastSyncedText }}
          </button>

          <button
            type="button"
            class="btn btn-sm text-nowrap"
            :class="pollingEnabled ? 'btn-primary' : 'btn-outline-secondary'"
            @click="toggleGlobalPolling"
          >
            Auto refresh: {{ pollingEnabled ? 'on' : 'off' }}
          </button>

          <button type="button" class="btn btn-sm btn-outline-secondary text-nowrap" @click="toggleDarkMode">
            {{ isDark ? 'Light mode' : 'Dark mode' }}
          </button>
        </div>
      </div>
    </div>
  </nav>
</template>

<style scoped>
/* From xl (where the hamburger gives way to the full bar) up to the width
   where every link and button fits on one line, the extra links fold into
   "More". The upper bound was found by screenshot, not a Bootstrap
   breakpoint: move it if links or buttons are added or renamed. */
.nav-extra-more {
  display: none;
}
@media (min-width: 1200px) and (max-width: 1539.98px) {
  .nav-extra-inline {
    display: none;
  }
  .nav-extra-more {
    display: block;
  }
}
</style>
