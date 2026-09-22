<script setup>
import { computed } from 'vue'
import { useSortableTable } from '../composables/useSortableTable'

const props = defineProps({
  rows: { type: Array, required: true },
  columns: { type: Array, required: true },
  rowKey: { type: Function, default: null },
  rowClass: { type: Function, default: null },
  defaultSortColumn: { type: Number, default: 0 },
  defaultSortOrder: { type: String, default: 'asc' },
  searchable: { type: Boolean, default: true },
})

const rows = computed(() => props.rows)

const { sortColumn, sortOrder, searchTerm, searchable, setSort, sortedRows } = useSortableTable(
  rows,
  props.columns,
  {
    defaultSortColumn: props.defaultSortColumn,
    defaultSortOrder: props.defaultSortOrder,
    searchable: props.searchable,
  },
)
</script>

<template>
  <div>
    <input
      v-if="searchable"
      v-model="searchTerm"
      type="search"
      class="form-control form-control-sm mb-2"
      style="max-width: 300px"
      placeholder="Search..."
    />
    <div class="table-responsive">
      <table class="table table-hover table-sm">
        <thead>
          <tr>
            <th
              v-for="(col, i) in columns"
              :key="col.key"
              role="button"
              class="user-select-none"
              @click="setSort(i)"
            >
              {{ col.label }}
              <span v-if="sortColumn === i">{{ sortOrder === 'asc' ? '▲' : '▼' }}</span>
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="(row, idx) in sortedRows"
            :key="rowKey ? rowKey(row) : idx"
            :class="rowClass ? rowClass(row) : null"
          >
            <td v-for="col in columns" :key="col.key">
              <slot :name="col.key" :row="row">{{ col.value(row) }}</slot>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
