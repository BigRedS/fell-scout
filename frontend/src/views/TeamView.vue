<script setup>
import { ref, computed, watch } from 'vue'
import { useRoute } from 'vue-router'
import { getTeam } from '../api/client'
import { usePolling } from '../composables/usePolling'
import TeamLink from '../components/TeamLink.vue'

const route = useRoute()
const team = ref(null)

async function refresh() {
  team.value = await getTeam(route.params.team)
}

usePolling(refresh, 10000)

// Vue Router reuses this component instance when navigating from one team to
// another (e.g. clicking a cross-linked team), so a mount-only fetch isn't
// enough - refetch whenever the :team param itself changes.
watch(() => route.params.team, refresh)

const isScratchTeam = computed(() => team.value && team.value.team_number < 0)

const remainingCheckpoints = computed(() => {
  if (!team.value?.remaining_checkpoints) return []
  return Object.keys(team.value.remaining_checkpoints)
    .map(Number)
    .sort((a, b) => a - b)
    .map((cp) => ({ cp, ...team.value.remaining_checkpoints[cp] }))
})

const previousCheckpoints = computed(() => {
  if (!team.value?.previous_checkpoints) return []
  return Object.keys(team.value.previous_checkpoints)
    .map(Number)
    .sort((a, b) => a - b)
    .map((cp) => ({ cp, ...team.value.previous_checkpoints[cp] }))
})

const entrants = computed(() => {
  if (!team.value?.entrants) return []
  return Object.keys(team.value.entrants)
    .sort()
    .map((code) => team.value.entrants[code])
})
</script>

<template>
  <template v-if="team">
    <h1 v-if="isScratchTeam">Scratch Team {{ team.team_number }}: {{ team.team_name }}</h1>
    <h1 v-else>Team {{ team.team_number }}: {{ team.team_name }}</h1>

    <div v-if="!team.active_entrants" class="alert alert-warning" role="alert">
      <p>
        This team has no active entrants; see 'Entrants' below to see which have retired or
        joined Scratch Teams.
      </p>
      <p>
        Teams must have at least three members; if too many people retire from a team we join
        them with others to create a 'Scratch Team', and these entrants are to be tracked in that
        team.
      </p>
    </div>

    <table class="table">
      <tbody>
        <tr>
          <td>Route</td>
          <td>{{ team.route }}</td>
        </tr>
        <tr>
          <td>Next Checkpoint</td>
          <td>{{ team.next_checkpoint }}</td>
        </tr>
        <tr>
          <td>Next Checkpoint expected time</td>
          <td>{{ team.next_checkpoint_expected_hhmm }} (in {{ team.next_checkpoint_expected_in }})</td>
        </tr>
        <tr>
          <td>Last Checkpoint</td>
          <td>{{ team.last_checkpoint }} at {{ team.last_checkpoint_time_hhmm }}</td>
        </tr>
        <tr>
          <td>Expected at finish</td>
          <td>{{ team.finish_expected_hhmm }}</td>
        </tr>
        <tr>
          <td>Remaining Checkpoints</td>
          <td>
            <ul class="mb-0">
              <li v-for="rc in remainingCheckpoints" :key="rc.cp">
                <template v-if="rc.expected_hhmm === '-'">{{ rc.cp }}</template>
                <template v-else>{{ rc.cp }} (expected at {{ rc.expected_hhmm }}, in {{ rc.expected_in }})</template>
              </li>
            </ul>
          </td>
        </tr>
        <tr>
          <td>Entrants</td>
          <td>
            <div v-for="entrant in entrants" :key="entrant.code">
              {{ entrant.code }}: {{ entrant.entrant_name }}
              <template v-if="entrant.retired">(retired at checkpoint {{ entrant.retired }})</template>
              <template v-else-if="entrant.completed">(finished)</template>
              <template v-if="isScratchTeam && entrant.previous_team_number">
                (originally of team
                <TeamLink :team-number="entrant.previous_team_number">{{ entrant.previous_team_name }}</TeamLink>)
              </template>
              <template v-if="entrant.scratch_team_number">
                (in scratch team
                <TeamLink :team-number="-entrant.scratch_team_number">
                  -{{ entrant.scratch_team_number }}: {{ entrant.scratch_team_name }}
                </TeamLink>)
              </template>
            </div>
          </td>
        </tr>
        <tr>
          <td>Unit, District</td>
          <td>{{ team.unit }}, {{ team.district }}</td>
        </tr>
        <tr>
          <td>Previous Checkpoints</td>
          <td>
            <ul class="mb-0">
              <li v-for="pc in previousCheckpoints" :key="pc.cp">{{ pc.cp }} at {{ pc.hhmm }}</li>
            </ul>
          </td>
        </tr>
      </tbody>
    </table>
  </template>
</template>
