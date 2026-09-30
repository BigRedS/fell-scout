<script setup>
defineProps({
  status: { type: String, required: true },
})

const badgeClass = {
  open: 'text-bg-success',
  issue: 'text-bg-warning',
  closed: 'text-bg-danger',
  // Kinds of open and passed respectively, so they share those colours
  unvisited: 'text-bg-success',
  passed: 'text-bg-primary',
  clear: 'text-bg-primary',
}

const label = {
  open: 'Open',
  issue: 'Issue',
  closed: 'Closed',
  unvisited: 'Unvisited',
  passed: 'Passed',
  clear: 'Clear',
}
</script>

<template>
  <span class="badge" :class="badgeClass[status] ?? 'text-bg-secondary'">{{ label[status] ?? status }}</span>
</template>
