import { ref, watch } from 'vue'

const STORAGE_KEY = 'fellscout-dark-mode'

function initialValue() {
  const stored = localStorage.getItem(STORAGE_KEY)
  if (stored !== null) {
    return stored === 'dark'
  }
  return window.matchMedia('(prefers-color-scheme: dark)').matches
}

const isDark = ref(initialValue())

// Bootstrap 5.3+ reads this attribute on <html> to switch its whole
// light/dark palette - it has to live on document.documentElement since no
// Vue component owns the <html> tag itself.
function applyTheme(dark) {
  document.documentElement.setAttribute('data-bs-theme', dark ? 'dark' : 'light')
}
applyTheme(isDark.value)

watch(isDark, (dark) => {
  applyTheme(dark)
  localStorage.setItem(STORAGE_KEY, dark ? 'dark' : 'light')
})

export function useDarkMode() {
  function toggle() {
    isDark.value = !isDark.value
  }

  return { isDark, toggle }
}
