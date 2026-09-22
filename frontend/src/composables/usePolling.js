import { onMounted, onUnmounted, ref, watch } from 'vue'

// One shared on/off flag, so the nav's single "auto refresh" toggle controls
// every page's polling at once, even though each page polls its own data on
// its own interval/callback.
const enabled = ref(true)

// Hand-rolled on purpose for the first page - it's genuinely this small.
// If a third view ends up copy-pasting this same pattern, that's the signal
// to switch to VueUse's useIntervalFn instead of maintaining several copies.
export function usePolling(callback, intervalMs = 10000) {
  let intervalId = null

  function start() {
    stop()
    intervalId = setInterval(callback, intervalMs)
  }

  function stop() {
    if (intervalId !== null) {
      clearInterval(intervalId)
      intervalId = null
    }
  }

  watch(enabled, (isEnabled) => {
    if (isEnabled) {
      callback()
      start()
    } else {
      stop()
    }
  })

  onMounted(() => {
    callback()
    if (enabled.value) start()
  })
  onUnmounted(stop)

  return { enabled }
}

export function toggleGlobalPolling() {
  enabled.value = !enabled.value
}

export function isPollingEnabled() {
  return enabled
}
