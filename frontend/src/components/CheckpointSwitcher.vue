<script setup>
import { computed, ref } from 'vue'
import { useRouter } from 'vue-router'
import { getRoutesCheckpoints } from '../api/client'

// Top-of-page bar on a checkpoint's Info and Arrivals pages: step to the
// previous/next checkpoint, jump to any, or flip between the two views of
// this one - so checkpoint staff and drivers don't have to go back via the
// Checkpoints list.
const props = defineProps({
  checkpoint: { type: [Number, String], required: true },
  view: { type: String, required: true }, // 'checkpoint' or 'arrivals' - the route prefix
})

const router = useRouter()

// Taken from the routes list rather than /api/checkpoints, which carries
// every team at every checkpoint and is ~100x the size. That leaves out the
// start (0), which nobody needs to step to. Fetched once: the set of
// checkpoints doesn't change mid-event.
const ids = ref([])
getRoutesCheckpoints().then((routes) => {
  const all = new Set(Object.values(routes).flat().map(Number))
  ids.value = [...all].sort((a, b) => a - b)
})

const current = computed(() => Number(props.checkpoint))
// Nearest either side rather than by index, so this still works on a
// checkpoint that isn't in the list (e.g. 0).
const prev = computed(() => ids.value.filter((id) => id < current.value).at(-1))
const next = computed(() => ids.value.find((id) => id > current.value))

function label(id) {
  return id === 99 ? 'Finish' : `CP ${id}`
}

function go(id) {
  router.push(`/${props.view}/${id}`)
}
</script>

<template>
  <div class="d-flex flex-wrap align-items-center gap-2 mb-3">
    <div class="input-group w-auto">
      <button type="button" class="btn btn-outline-secondary" :disabled="prev === undefined" @click="go(prev)">
        {{ prev === undefined ? '‹' : `‹ ${label(prev)}` }}
      </button>
      <select
        class="form-select"
        aria-label="Go to checkpoint"
        :value="current"
        @change="go($event.target.value)"
      >
        <option v-if="!ids.includes(current)" :value="current">{{ label(current) }}</option>
        <option v-for="id in ids" :key="id" :value="id">{{ label(id) }}</option>
      </select>
      <button type="button" class="btn btn-outline-secondary" :disabled="next === undefined" @click="go(next)">
        {{ next === undefined ? '›' : `${label(next)} ›` }}
      </button>
    </div>

    <div class="btn-group" role="group">
      <router-link
        :to="`/checkpoint/${current}`"
        class="btn"
        :class="view === 'checkpoint' ? 'btn-secondary' : 'btn-outline-secondary'"
      >
        Info
      </router-link>
      <router-link
        :to="`/arrivals/${current}`"
        class="btn"
        :class="view === 'arrivals' ? 'btn-secondary' : 'btn-outline-secondary'"
      >
        Arrivals
      </router-link>
    </div>
  </div>
</template>
