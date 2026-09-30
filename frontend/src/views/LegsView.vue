<script setup>
import { computed, ref } from 'vue'
import { getLegs } from '../api/client'
import { usePolling } from '../composables/usePolling'
import TeamLink from '../components/TeamLink.vue'
import CheckpointLink from '../components/CheckpointLink.vue'
import PageHelp from '../components/PageHelp.vue'

const legs = ref(null)

async function refresh() {
  legs.value = await getLegs()
}

usePolling(refresh, 10000)

const rows = computed(() => (legs.value ? Object.values(legs.value) : []))
</script>

<template>
  <h1>Checkpoint Legs</h1>

  <PageHelp>
    <p>
      A 'leg' is the route between two checkpoints; each route is a series of legs, and since some
      routes skip checkpoints that are found on other routes, not all checkpoints are visited
      sequentially.
    </p>
    <p>This page lists the legs along with the average times taken to complete them, and which teams are on them.</p>
    <p>It will only show those legs for which enough teams have passed to predict the time.</p>
    <p>Checkpoint 99 is the finish.</p>
  </PageHelp>

  <table v-if="legs" class="table table-hover table-sm">
    <thead>
      <tr>
        <th style="min-width: 6em" class="text-center">Leg</th>
        <th class="text-center d-none d-md-table-cell">From</th>
        <th class="text-center d-none d-md-table-cell">To</th>
        <th class="text-center">Average Time To Complete</th>
        <th class="text-center">Teams on leg</th>
      </tr>
    </thead>
    <tbody>
      <tr v-for="leg in rows" :key="leg.leg_name">
        <td class="text-center">{{ leg.leg_name }}</td>
        <td class="text-center d-none d-md-table-cell"><CheckpointLink :checkpoint="leg.from" /></td>
        <td class="text-center d-none d-md-table-cell"><CheckpointLink :checkpoint="leg.to" /></td>
        <td class="text-center">{{ leg.time }}</td>
        <td>
          <TeamLink
            v-for="team in leg.teams ?? []"
            :key="team"
            :team-number="team"
            class="badge text-bg-primary mb-1 me-1"
            style="min-width: 50px; font-size: 1.1em"
          >
            {{ team }}
          </TeamLink>
        </td>
      </tr>
    </tbody>
  </table>
</template>
