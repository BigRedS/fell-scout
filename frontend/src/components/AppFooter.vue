<script setup>
// A plain, non-static src would make Vite try to bundle this as a module
// import - it only exists in the backend's public/, not the Vite project.
// Putting it behind a variable keeps the binding dynamic, so Vite leaves it
// as a runtime string instead of trying to resolve it at build time.
const badgeImageUrl = '/scout-navigator-badge.png'
</script>

<template>
  <hr />
  <footer class="text-center p-3">
    <img :src="badgeImageUrl" alt="Scout Navigator Badge" style="max-height: 80px" class="mb-2" />
    <div>
      This is <a href="https://github.com/BigRedS/fell-scout/blob/master/README.md">FellScout</a>,
      a tool for <a href="https://felltrack.com/">FellTrack</a>
    </div>
    <div>
      To ask for changes/features/additions, either find Avi in Central Control or
      <a href="https://github.com/BigRedS/fell-scout/issues">open a bug</a>.
    </div>
  </footer>
</template>
