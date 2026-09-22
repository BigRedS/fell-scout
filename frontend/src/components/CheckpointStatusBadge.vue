<script setup>
defineProps({
  status: { type: String, required: true },
})

const badgeClass = {
  open: 'text-bg-success',
  issue: 'text-bg-warning',
  closed: 'text-bg-danger',
}

const label = {
  open: 'Open',
  issue: 'Issue',
  closed: 'Closed',
}
</script>

<template>
  <span class="badge" :class="badgeClass[status] ?? 'text-bg-secondary'">{{ label[status] ?? status }}</span>
</template>
