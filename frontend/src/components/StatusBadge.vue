<script setup>
defineProps({
  status: { type: String, required: true },
})

const badgeClass = {
  Active: 'text-bg-success',
  Finished: 'text-bg-secondary',
  Retired: 'text-bg-danger',
}
</script>

<template>
  <span class="badge" :class="badgeClass[status] ?? 'text-bg-secondary'">{{ status }}</span>
</template>
