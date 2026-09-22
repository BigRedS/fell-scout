import { ref, computed, unref } from 'vue'

// Replaces the old site's FancyTable (jQuery) click-to-sort-column +
// global-search-box behaviour, used on several list pages. Takes a reactive
// rows array/ref and a column definition array: [{ key, label, value(row),
// numeric? }]. `value(row)` is used for both sorting and searching, so any
// cell can render something richer (a link, a badge) via a scoped slot in
// SortableTable.vue while still sorting/searching on the underlying value.
//
// `filterableKeys` (optional) names a subset of columns to also get a
// dropdown filter (exact-match on `value(row)`, stringified) - opt-in, so
// existing callers that don't pass it are unaffected.
export function useSortableTable(rows, columns, options = {}) {
  const {
    defaultSortColumn = 0,
    defaultSortOrder = 'asc',
    searchable = true,
    filterableKeys = [],
  } = options

  const sortColumn = ref(defaultSortColumn)
  const sortOrder = ref(defaultSortOrder)
  const searchTerm = ref('')
  const filters = ref({}) // column key -> selected value; '' means "All"

  function setSort(index) {
    if (sortColumn.value === index) {
      sortOrder.value = sortOrder.value === 'asc' ? 'desc' : 'asc'
    } else {
      sortColumn.value = index
      sortOrder.value = 'asc'
    }
  }

  const filterableColumns = computed(() => columns.filter((col) => filterableKeys.includes(col.key)))

  // Options are computed from the full row set, not the already-filtered
  // one, so picking a value in one dropdown doesn't make other dropdowns'
  // options disappear.
  const filterOptions = computed(() => {
    const options = {}
    for (const col of filterableColumns.value) {
      const values = new Set(unref(rows).map((row) => String(col.value(row) ?? '')))
      options[col.key] = [...values].sort()
    }
    return options
  })

  const filteredByDropdowns = computed(() => {
    let result = unref(rows)
    for (const col of filterableColumns.value) {
      const selected = filters.value[col.key]
      if (selected) {
        result = result.filter((row) => String(col.value(row) ?? '') === selected)
      }
    }
    return result
  })

  const filteredRows = computed(() => {
    if (!searchable || !searchTerm.value.trim()) return filteredByDropdowns.value
    const term = searchTerm.value.toLowerCase()
    return filteredByDropdowns.value.filter((row) =>
      columns.some((col) => String(col.value(row) ?? '').toLowerCase().includes(term)),
    )
  })

  const sortedRows = computed(() => {
    const col = columns[sortColumn.value]
    if (!col) return filteredRows.value
    const dir = sortOrder.value === 'asc' ? 1 : -1
    return [...filteredRows.value].sort((a, b) => {
      const av = col.value(a)
      const bv = col.value(b)
      if (col.numeric) return ((Number(av) || 0) - (Number(bv) || 0)) * dir
      return String(av ?? '').localeCompare(String(bv ?? '')) * dir
    })
  })

  return {
    sortColumn,
    sortOrder,
    searchTerm,
    searchable,
    setSort,
    sortedRows,
    filters,
    filterableColumns,
    filterOptions,
  }
}
