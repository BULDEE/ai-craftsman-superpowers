# Agent: {{DASHBOARD_NAME}} Data Dashboard

> Template for data table dashboards with filters, pagination, export, and visualization
> Replace {{PLACEHOLDERS}} with actual values

## Mission

Build a production-ready data dashboard for `{{ENTITY_PLURAL}}` with server-side pagination, composable filters, multi-column sorting, CSV/JSON export, and Recharts visualizations — all backed by TanStack Query v5 and TanStack Table v8.

## Context Files to Read

1. `frontend/src/domain/{{context}}/` - Domain types and API contracts
2. `frontend/src/application/{{context}}/` - Query hooks and keys
3. `frontend/src/presentation/{{context}}/` - Existing components
4. `frontend/src/shared/components/` - Shared UI primitives (skeleton, empty state, error)
5. `frontend/CLAUDE.md` - Frontend rules

## Domain Layer

### Types

```typescript
// frontend/src/domain/{{context}}/types.ts

export type {{Entity}}Id = Brand<string, '{{Entity}}Id'>;

export interface {{Entity}} {
  readonly id: {{Entity}}Id;
  {{#each FIELDS}}
  readonly {{NAME}}: {{TYPE}};
  {{/each}}
  readonly createdAt: string;
  readonly updatedAt: string;
}

{{#each ENUMS}}
export type {{NAME}} = {{VALUES}};
{{/each}}

export interface {{Entity}}Filters {
  readonly search: string;
  readonly status: {{Entity}}Status | null;
  readonly dateFrom: string | null;
  readonly dateTo: string | null;
  {{#each CUSTOM_FILTERS}}
  readonly {{NAME}}: {{TYPE}} | null;
  {{/each}}
}

export interface {{Entity}}Sort {
  readonly column: keyof {{Entity}};
  readonly direction: 'asc' | 'desc';
}

export interface {{Entity}}Pagination {
  readonly page: number;
  readonly pageSize: number;
}

export interface {{Entity}}TableState {
  readonly filters: {{Entity}}Filters;
  readonly sort: readonly {{Entity}}Sort[];
  readonly pagination: {{Entity}}Pagination;
}

export interface {{Entity}}ChartData {
  readonly label: string;
  readonly value: number;
  {{#each CHART_SERIES}}
  readonly {{NAME}}: number;
  {{/each}}
}
```

### API Types

```typescript
// frontend/src/domain/{{context}}/api.ts

export interface {{Entity}}Response {
  readonly id: string;
  {{#each API_FIELDS}}
  readonly {{NAME}}: {{TYPE}};
  {{/each}}
  readonly createdAt: string;
  readonly updatedAt: string;
}

export interface {{Entity}}ListResponse {
  readonly items: readonly {{Entity}}Response[];
  readonly total: number;
  readonly page: number;
  readonly pageSize: number;
  readonly pageCount: number;
}

export interface {{Entity}}StatsResponse {
  readonly chartData: readonly {{Entity}}ChartData[];
  readonly totals: Record<string, number>;
}

export interface {{Entity}}ListParams {
  readonly search?: string;
  readonly status?: string;
  readonly dateFrom?: string;
  readonly dateTo?: string;
  readonly sortBy?: string;
  readonly sortDir?: 'asc' | 'desc';
  readonly page?: number;
  readonly pageSize?: number;
}

export interface ExportParams extends {{Entity}}ListParams {
  readonly format: 'csv' | 'json';
}
```

### Mappers

```typescript
// frontend/src/domain/{{context}}/mappers.ts

import type { {{Entity}}, {{Entity}}Id, {{Entity}}ChartData } from './types';
import type { {{Entity}}Response, {{Entity}}StatsResponse } from './api';

export function map{{Entity}}(response: {{Entity}}Response): {{Entity}} {
  return {
    id: response.id as {{Entity}}Id,
    {{#each FIELD_MAPPINGS}}
    {{NAME}}: response.{{SOURCE}},
    {{/each}}
    createdAt: response.createdAt,
    updatedAt: response.updatedAt,
  };
}

export function map{{Entity}}ChartData(
  response: {{Entity}}StatsResponse,
): readonly {{Entity}}ChartData[] {
  return response.chartData;
}
```

## Application Layer

### Query Keys

```typescript
// frontend/src/application/{{context}}/keys.ts

import type { {{Entity}}TableState } from '../../domain/{{context}}/types';

export const {{entity}}Keys = {
  all: ['{{entity}}'] as const,
  lists: () => [...{{entity}}Keys.all, 'list'] as const,
  list: (state: {{Entity}}TableState) => [...{{entity}}Keys.lists(), state] as const,
  stats: (filters: {{Entity}}TableState['filters']) =>
    [...{{entity}}Keys.all, 'stats', filters] as const,
  exports: () => [...{{entity}}Keys.all, 'export'] as const,
};
```

### API Client

```typescript
// frontend/src/application/{{context}}/api-client.ts

import type {
  {{Entity}}ListResponse,
  {{Entity}}ListParams,
  {{Entity}}StatsResponse,
  ExportParams,
} from '../../domain/{{context}}/api';

export async function fetch{{Entity}}List(
  params: {{Entity}}ListParams,
): Promise<{{Entity}}ListResponse> {
  const searchParams = new URLSearchParams();

  if (params.search) searchParams.set('search', params.search);
  if (params.status) searchParams.set('status', params.status);
  if (params.dateFrom) searchParams.set('dateFrom', params.dateFrom);
  if (params.dateTo) searchParams.set('dateTo', params.dateTo);
  if (params.sortBy) searchParams.set('sortBy', params.sortBy);
  if (params.sortDir) searchParams.set('sortDir', params.sortDir);
  searchParams.set('page', String(params.page ?? 1));
  searchParams.set('pageSize', String(params.pageSize ?? 25));

  const response = await fetch(`/api/{{entity-plural}}?${searchParams.toString()}`);

  if (!response.ok) {
    throw new Error(`Failed to fetch {{entity-plural}}: ${response.statusText}`);
  }

  return response.json() as Promise<{{Entity}}ListResponse>;
}

export async function fetch{{Entity}}Stats(
  params: Omit<{{Entity}}ListParams, 'page' | 'pageSize' | 'sortBy' | 'sortDir'>,
): Promise<{{Entity}}StatsResponse> {
  const searchParams = new URLSearchParams();

  if (params.search) searchParams.set('search', params.search);
  if (params.status) searchParams.set('status', params.status);
  if (params.dateFrom) searchParams.set('dateFrom', params.dateFrom);
  if (params.dateTo) searchParams.set('dateTo', params.dateTo);

  const response = await fetch(`/api/{{entity-plural}}/stats?${searchParams.toString()}`);

  if (!response.ok) {
    throw new Error(`Failed to fetch {{entity}} stats: ${response.statusText}`);
  }

  return response.json() as Promise<{{Entity}}StatsResponse>;
}

export async function export{{Entity}}Data(params: ExportParams): Promise<Blob> {
  const searchParams = new URLSearchParams();

  if (params.search) searchParams.set('search', params.search);
  if (params.status) searchParams.set('status', params.status);
  if (params.dateFrom) searchParams.set('dateFrom', params.dateFrom);
  if (params.dateTo) searchParams.set('dateTo', params.dateTo);
  searchParams.set('format', params.format);

  const response = await fetch(
    `/api/{{entity-plural}}/export?${searchParams.toString()}`,
    { method: 'GET' },
  );

  if (!response.ok) {
    throw new Error(`Failed to export {{entity-plural}}: ${response.statusText}`);
  }

  return response.blob();
}
```

### Hooks

#### use{{Entity}}List

```typescript
// frontend/src/application/{{context}}/use{{Entity}}List.ts

import { useSuspenseQuery } from '@tanstack/react-query';
import { {{entity}}Keys } from './keys';
import { fetch{{Entity}}List } from './api-client';
import { map{{Entity}} } from '../../domain/{{context}}/mappers';
import type { {{Entity}}TableState } from '../../domain/{{context}}/types';
import type { {{Entity}}ListResponse } from '../../domain/{{context}}/api';

interface {{Entity}}ListResult {
  readonly items: readonly ReturnType<typeof map{{Entity}}>[];
  readonly total: number;
  readonly pageCount: number;
}

function buildParams(state: {{Entity}}TableState): Parameters<typeof fetch{{Entity}}List>[0] {
  const primarySort = state.sort[0];

  return {
    search: state.filters.search || undefined,
    status: state.filters.status ?? undefined,
    dateFrom: state.filters.dateFrom ?? undefined,
    dateTo: state.filters.dateTo ?? undefined,
    sortBy: primarySort?.column as string | undefined,
    sortDir: primarySort?.direction,
    page: state.pagination.page,
    pageSize: state.pagination.pageSize,
  };
}

export function use{{Entity}}List(state: {{Entity}}TableState): {{Entity}}ListResult {
  const { data } = useSuspenseQuery<{{Entity}}ListResponse, Error, {{Entity}}ListResult>({
    queryKey: {{entity}}Keys.list(state),
    queryFn: () => fetch{{Entity}}List(buildParams(state)),
    select: (response) => ({
      items: response.items.map(map{{Entity}}),
      total: response.total,
      pageCount: response.pageCount,
    }),
    staleTime: 30_000,
    placeholderData: (previousData) => previousData,
  });

  return data;
}
```

#### use{{Entity}}Stats

```typescript
// frontend/src/application/{{context}}/use{{Entity}}Stats.ts

import { useSuspenseQuery } from '@tanstack/react-query';
import { {{entity}}Keys } from './keys';
import { fetch{{Entity}}Stats } from './api-client';
import { map{{Entity}}ChartData } from '../../domain/{{context}}/mappers';
import type { {{Entity}}TableState, {{Entity}}ChartData } from '../../domain/{{context}}/types';

export function use{{Entity}}Stats(
  filters: {{Entity}}TableState['filters'],
): readonly {{Entity}}ChartData[] {
  const { data } = useSuspenseQuery({
    queryKey: {{entity}}Keys.stats(filters),
    queryFn: () =>
      fetch{{Entity}}Stats({
        search: filters.search || undefined,
        status: filters.status ?? undefined,
        dateFrom: filters.dateFrom ?? undefined,
        dateTo: filters.dateTo ?? undefined,
      }),
    select: map{{Entity}}ChartData,
    staleTime: 60_000,
  });

  return data;
}
```

#### use{{Entity}}Export

```typescript
// frontend/src/application/{{context}}/use{{Entity}}Export.ts

import { useState } from 'react';
import { export{{Entity}}Data } from './api-client';
import type { {{Entity}}TableState } from '../../domain/{{context}}/types';

interface ExportState {
  readonly isExporting: boolean;
  readonly error: Error | null;
}

interface ExportActions {
  readonly exportCsv: () => Promise<void>;
  readonly exportJson: () => Promise<void>;
}

export function use{{Entity}}Export(
  filters: {{Entity}}TableState['filters'],
): ExportState & ExportActions {
  const [isExporting, setIsExporting] = useState(false);
  const [error, setError] = useState<Error | null>(null);

  async function triggerExport(format: 'csv' | 'json'): Promise<void> {
    setIsExporting(true);
    setError(null);

    try {
      const blob = await export{{Entity}}Data({
        search: filters.search || undefined,
        status: filters.status ?? undefined,
        dateFrom: filters.dateFrom ?? undefined,
        dateTo: filters.dateTo ?? undefined,
        format,
      });

      const url = URL.createObjectURL(blob);
      const anchor = document.createElement('a');
      anchor.href = url;
      anchor.download = `{{entity-plural}}-export-${Date.now()}.${format}`;
      document.body.appendChild(anchor);
      anchor.click();
      document.body.removeChild(anchor);
      URL.revokeObjectURL(url);
    } catch (err) {
      setError(err instanceof Error ? err : new Error('Export failed'));
    } finally {
      setIsExporting(false);
    }
  }

  return {
    isExporting,
    error,
    exportCsv: () => triggerExport('csv'),
    exportJson: () => triggerExport('json'),
  };
}
```

#### use{{Entity}}TableState

```typescript
// frontend/src/application/{{context}}/use{{Entity}}TableState.ts

import { useReducer, useCallback } from 'react';
import type {
  {{Entity}}Filters,
  {{Entity}}Sort,
  {{Entity}}TableState,
} from '../../domain/{{context}}/types';

type TableAction =
  | { readonly type: 'SET_FILTER'; readonly filters: Partial<{{Entity}}Filters> }
  | { readonly type: 'SET_SORT'; readonly sort: {{Entity}}Sort }
  | { readonly type: 'SET_PAGE'; readonly page: number }
  | { readonly type: 'SET_PAGE_SIZE'; readonly pageSize: number }
  | { readonly type: 'RESET_FILTERS' };

const DEFAULT_FILTERS: {{Entity}}Filters = {
  search: '',
  status: null,
  dateFrom: null,
  dateTo: null,
};

const DEFAULT_STATE: {{Entity}}TableState = {
  filters: DEFAULT_FILTERS,
  sort: [],
  pagination: { page: 1, pageSize: 25 },
};

function tableReducer(
  state: {{Entity}}TableState,
  action: TableAction,
): {{Entity}}TableState {
  switch (action.type) {
    case 'SET_FILTER':
      return {
        ...state,
        filters: { ...state.filters, ...action.filters },
        pagination: { ...state.pagination, page: 1 },
      };
    case 'SET_SORT': {
      const existing = state.sort.findIndex((s) => s.column === action.sort.column);
      const newSort =
        existing >= 0
          ? state.sort.map((s, i) => (i === existing ? action.sort : s))
          : [action.sort, ...state.sort.slice(0, 2)];
      return { ...state, sort: newSort };
    }
    case 'SET_PAGE':
      return { ...state, pagination: { ...state.pagination, page: action.page } };
    case 'SET_PAGE_SIZE':
      return {
        ...state,
        pagination: { page: 1, pageSize: action.pageSize },
      };
    case 'RESET_FILTERS':
      return { ...state, filters: DEFAULT_FILTERS, pagination: { ...state.pagination, page: 1 } };
  }
}

interface TableStateActions {
  readonly setFilter: (filters: Partial<{{Entity}}Filters>) => void;
  readonly setSort: (sort: {{Entity}}Sort) => void;
  readonly setPage: (page: number) => void;
  readonly setPageSize: (pageSize: number) => void;
  readonly resetFilters: () => void;
}

export function use{{Entity}}TableState(): [{{Entity}}TableState, TableStateActions] {
  const [state, dispatch] = useReducer(tableReducer, DEFAULT_STATE);

  const setFilter = useCallback(
    (filters: Partial<{{Entity}}Filters>) => dispatch({ type: 'SET_FILTER', filters }),
    [],
  );
  const setSort = useCallback(
    (sort: {{Entity}}Sort) => dispatch({ type: 'SET_SORT', sort }),
    [],
  );
  const setPage = useCallback(
    (page: number) => dispatch({ type: 'SET_PAGE', page }),
    [],
  );
  const setPageSize = useCallback(
    (pageSize: number) => dispatch({ type: 'SET_PAGE_SIZE', pageSize }),
    [],
  );
  const resetFilters = useCallback(() => dispatch({ type: 'RESET_FILTERS' }), []);

  return [state, { setFilter, setSort, setPage, setPageSize, resetFilters }];
}
```

#### use{{Entity}}ColumnVisibility

```typescript
// frontend/src/application/{{context}}/use{{Entity}}ColumnVisibility.ts

import { useState, useCallback } from 'react';
import type { VisibilityState } from '@tanstack/react-table';

const STORAGE_KEY = '{{entity}}-column-visibility';

function readFromStorage(): VisibilityState {
  try {
    const stored = localStorage.getItem(STORAGE_KEY);
    if (stored === null) return {};
    return JSON.parse(stored) as VisibilityState;
  } catch {
    return {};
  }
}

export function use{{Entity}}ColumnVisibility(): [
  VisibilityState,
  (updater: VisibilityState | ((prev: VisibilityState) => VisibilityState)) => void,
] {
  const [visibility, setVisibilityState] = useState<VisibilityState>(readFromStorage);

  const setVisibility = useCallback(
    (updater: VisibilityState | ((prev: VisibilityState) => VisibilityState)) => {
      setVisibilityState((prev) => {
        const next = typeof updater === 'function' ? updater(prev) : updater;
        try {
          localStorage.setItem(STORAGE_KEY, JSON.stringify(next));
        } catch {
          // Storage unavailable — state still updates in memory
        }
        return next;
      });
    },
    [],
  );

  return [visibility, setVisibility];
}
```

## Presentation Layer

### Column Definitions

```typescript
// frontend/src/presentation/{{context}}/columns.tsx

import { createColumnHelper } from '@tanstack/react-table';
import type { {{Entity}} } from '../../domain/{{context}}/types';

const columnHelper = createColumnHelper<{{Entity}}>();

export const {{entity}}Columns = [
  columnHelper.accessor('id', {
    id: 'id',
    header: 'ID',
    cell: (info) => (
      <span className="font-mono text-xs text-muted-foreground">
        {String(info.getValue()).slice(0, 8)}
      </span>
    ),
    enableSorting: false,
    size: 80,
  }),
  {{#each TABLE_COLUMNS}}
  columnHelper.accessor('{{FIELD}}', {
    id: '{{FIELD}}',
    header: '{{LABEL}}',
    cell: (info) => {{CELL_RENDERER}},
    enableSorting: {{SORTABLE}},
    size: {{SIZE}},
  }),
  {{/each}}
  columnHelper.display({
    id: 'actions',
    header: () => <span className="sr-only">Actions</span>,
    cell: (info) => <{{Entity}}RowActions row={info.row} />,
    size: 48,
  }),
] as const;
```

### Filter Components

#### SearchFilter

```tsx
// frontend/src/presentation/{{context}}/filters/SearchFilter.tsx

'use client';

import { useTransition } from 'react';
import { Input } from '@/shared/components/ui/input';
import { SearchIcon } from 'lucide-react';

interface SearchFilterProps {
  readonly value: string;
  readonly onChange: (value: string) => void;
  readonly placeholder?: string;
}

export function SearchFilter({ value, onChange, placeholder = 'Search…' }: SearchFilterProps) {
  const [isPending, startTransition] = useTransition();

  return (
    <div className="relative">
      <SearchIcon
        className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground"
        aria-hidden
      />
      <Input
        type="search"
        value={value}
        onChange={(e) => startTransition(() => onChange(e.target.value))}
        placeholder={placeholder}
        className="pl-9"
        aria-label="Search"
        data-pending={isPending || undefined}
      />
    </div>
  );
}
```

#### DateRangeFilter

```tsx
// frontend/src/presentation/{{context}}/filters/DateRangeFilter.tsx

'use client';

import { Input } from '@/shared/components/ui/input';
import { Label } from '@/shared/components/ui/label';

interface DateRangeFilterProps {
  readonly dateFrom: string | null;
  readonly dateTo: string | null;
  readonly onDateFromChange: (value: string | null) => void;
  readonly onDateToChange: (value: string | null) => void;
}

export function DateRangeFilter({
  dateFrom,
  dateTo,
  onDateFromChange,
  onDateToChange,
}: DateRangeFilterProps) {
  return (
    <div className="flex items-end gap-2">
      <div className="grid gap-1.5">
        <Label htmlFor="date-from" className="text-xs">From</Label>
        <Input
          id="date-from"
          type="date"
          value={dateFrom ?? ''}
          onChange={(e) => onDateFromChange(e.target.value || null)}
          className="w-36"
          max={dateTo ?? undefined}
        />
      </div>
      <div className="grid gap-1.5">
        <Label htmlFor="date-to" className="text-xs">To</Label>
        <Input
          id="date-to"
          type="date"
          value={dateTo ?? ''}
          onChange={(e) => onDateToChange(e.target.value || null)}
          className="w-36"
          min={dateFrom ?? undefined}
        />
      </div>
    </div>
  );
}
```

#### StatusFilter

```tsx
// frontend/src/presentation/{{context}}/filters/StatusFilter.tsx

'use client';

import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/shared/components/ui/select';
import type { {{Entity}}Status } from '../../../domain/{{context}}/types';

interface StatusFilterProps {
  readonly value: {{Entity}}Status | null;
  readonly onChange: (value: {{Entity}}Status | null) => void;
}

const STATUS_OPTIONS: ReadonlyArray<{ readonly value: {{Entity}}Status; readonly label: string }> =
  [
    {{#each STATUS_OPTIONS}}
    { value: '{{VALUE}}', label: '{{LABEL}}' },
    {{/each}}
  ];

export function StatusFilter({ value, onChange }: StatusFilterProps) {
  return (
    <Select
      value={value ?? 'all'}
      onValueChange={(v) => onChange(v === 'all' ? null : (v as {{Entity}}Status))}
    >
      <SelectTrigger className="w-36" aria-label="Filter by status">
        <SelectValue placeholder="All statuses" />
      </SelectTrigger>
      <SelectContent>
        <SelectItem value="all">All statuses</SelectItem>
        {STATUS_OPTIONS.map((opt) => (
          <SelectItem key={opt.value} value={opt.value}>
            {opt.label}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
}
```

### Skeleton Components

```tsx
// frontend/src/presentation/{{context}}/skeletons/{{Entity}}TableSkeleton.tsx

import { Skeleton } from '@/shared/components/ui/skeleton';

interface {{Entity}}TableSkeletonProps {
  readonly rows?: number;
  readonly columns?: number;
}

export function {{Entity}}TableSkeleton({ rows = 10, columns = 6 }: {{Entity}}TableSkeletonProps) {
  return (
    <div className="w-full" aria-busy="true" aria-label="Loading data">
      <div className="flex gap-2 mb-4">
        {Array.from({ length: columns }).map((_, i) => (
          <Skeleton key={i} className="h-4 flex-1" />
        ))}
      </div>
      {Array.from({ length: rows }).map((_, i) => (
        <div key={i} className="flex gap-2 mb-2">
          {Array.from({ length: columns }).map((_, j) => (
            <Skeleton key={j} className="h-10 flex-1" />
          ))}
        </div>
      ))}
    </div>
  );
}
```

```tsx
// frontend/src/presentation/{{context}}/skeletons/{{Entity}}ChartSkeleton.tsx

import { Skeleton } from '@/shared/components/ui/skeleton';

export function {{Entity}}ChartSkeleton() {
  return (
    <div className="w-full" aria-busy="true" aria-label="Loading chart">
      <Skeleton className="h-6 w-48 mb-4" />
      <Skeleton className="h-64 w-full rounded-lg" />
    </div>
  );
}
```

### Empty State

```tsx
// frontend/src/presentation/{{context}}/{{Entity}}EmptyState.tsx

import { {{Entity}}Icon } from 'lucide-react';
import { Button } from '@/shared/components/ui/button';

interface {{Entity}}EmptyStateProps {
  readonly hasFilters: boolean;
  readonly onClearFilters: () => void;
}

export function {{Entity}}EmptyState({ hasFilters, onClearFilters }: {{Entity}}EmptyStateProps) {
  return (
    <div
      className="flex flex-col items-center justify-center py-16 text-center"
      role="status"
      aria-live="polite"
    >
      <{{Entity}}Icon className="h-12 w-12 text-muted-foreground mb-4" aria-hidden />
      <h3 className="text-lg font-semibold mb-1">
        {hasFilters ? 'No results found' : 'No {{entity-plural}} yet'}
      </h3>
      <p className="text-sm text-muted-foreground mb-4">
        {hasFilters
          ? 'Try adjusting your filters or search term.'
          : '{{EMPTY_STATE_DESCRIPTION}}'}
      </p>
      {hasFilters && (
        <Button variant="outline" onClick={onClearFilters}>
          Clear filters
        </Button>
      )}
    </div>
  );
}
```

### Column Visibility Toggle

```tsx
// frontend/src/presentation/{{context}}/{{Entity}}ColumnToggle.tsx

'use client';

import type { Table } from '@tanstack/react-table';
import { Button } from '@/shared/components/ui/button';
import {
  DropdownMenu,
  DropdownMenuCheckboxItem,
  DropdownMenuContent,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/shared/components/ui/dropdown-menu';
import { SlidersHorizontalIcon } from 'lucide-react';
import type { {{Entity}} } from '../../domain/{{context}}/types';

interface {{Entity}}ColumnToggleProps {
  readonly table: Table<{{Entity}}>;
}

export function {{Entity}}ColumnToggle({ table }: {{Entity}}ColumnToggleProps) {
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="outline" size="sm" className="gap-2">
          <SlidersHorizontalIcon className="h-4 w-4" aria-hidden />
          Columns
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-48">
        <DropdownMenuLabel>Toggle columns</DropdownMenuLabel>
        <DropdownMenuSeparator />
        {table
          .getAllColumns()
          .filter((col) => col.getCanHide())
          .map((col) => (
            <DropdownMenuCheckboxItem
              key={col.id}
              checked={col.getIsVisible()}
              onCheckedChange={(value) => col.toggleVisibility(value)}
            >
              {col.id}
            </DropdownMenuCheckboxItem>
          ))}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
```

### Export Button

```tsx
// frontend/src/presentation/{{context}}/{{Entity}}ExportButton.tsx

'use client';

import { Button } from '@/shared/components/ui/button';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/shared/components/ui/dropdown-menu';
import { DownloadIcon, LoaderIcon } from 'lucide-react';
import { use{{Entity}}Export } from '../../application/{{context}}/use{{Entity}}Export';
import type { {{Entity}}TableState } from '../../domain/{{context}}/types';

interface {{Entity}}ExportButtonProps {
  readonly filters: {{Entity}}TableState['filters'];
}

export function {{Entity}}ExportButton({ filters }: {{Entity}}ExportButtonProps) {
  const { isExporting, error, exportCsv, exportJson } = use{{Entity}}Export(filters);

  return (
    <div>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button variant="outline" size="sm" disabled={isExporting} className="gap-2">
            {isExporting ? (
              <LoaderIcon className="h-4 w-4 animate-spin" aria-hidden />
            ) : (
              <DownloadIcon className="h-4 w-4" aria-hidden />
            )}
            Export
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end">
          <DropdownMenuItem onClick={exportCsv}>Export as CSV</DropdownMenuItem>
          <DropdownMenuItem onClick={exportJson}>Export as JSON</DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
      {error !== null && (
        <p role="alert" className="text-xs text-destructive mt-1">
          {error.message}
        </p>
      )}
    </div>
  );
}
```

### Chart Components

```tsx
// frontend/src/presentation/{{context}}/charts/{{Entity}}BarChart.tsx

'use client';

import {
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
} from 'recharts';
import type { {{Entity}}ChartData } from '../../../domain/{{context}}/types';

interface {{Entity}}BarChartProps {
  readonly data: readonly {{Entity}}ChartData[];
  readonly title: string;
}

export function {{Entity}}BarChart({ data, title }: {{Entity}}BarChartProps) {
  if (data.length === 0) {
    return (
      <div className="flex items-center justify-center h-64 text-muted-foreground text-sm">
        No chart data available
      </div>
    );
  }

  return (
    <div>
      <h3 className="text-sm font-medium mb-4">{title}</h3>
      <ResponsiveContainer width="100%" height={256}>
        <BarChart data={data as {{Entity}}ChartData[]} margin={{ top: 0, right: 0, bottom: 0, left: 0 }}>
          <CartesianGrid strokeDasharray="3 3" className="stroke-border" />
          <XAxis
            dataKey="label"
            tick={{ fontSize: 12 }}
            tickLine={false}
            axisLine={false}
          />
          <YAxis tick={{ fontSize: 12 }} tickLine={false} axisLine={false} />
          <Tooltip
            contentStyle={{
              borderRadius: '6px',
              border: '1px solid hsl(var(--border))',
              background: 'hsl(var(--popover))',
              color: 'hsl(var(--popover-foreground))',
            }}
          />
          <Bar dataKey="value" fill="hsl(var(--primary))" radius={[4, 4, 0, 0]} />
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}
```

```tsx
// frontend/src/presentation/{{context}}/charts/{{Entity}}LineChart.tsx

'use client';

import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
} from 'recharts';
import type { {{Entity}}ChartData } from '../../../domain/{{context}}/types';

interface {{Entity}}LineChartProps {
  readonly data: readonly {{Entity}}ChartData[];
  readonly title: string;
  readonly seriesKey?: keyof {{Entity}}ChartData;
}

export function {{Entity}}LineChart({
  data,
  title,
  seriesKey = 'value',
}: {{Entity}}LineChartProps) {
  if (data.length === 0) {
    return (
      <div className="flex items-center justify-center h-64 text-muted-foreground text-sm">
        No chart data available
      </div>
    );
  }

  return (
    <div>
      <h3 className="text-sm font-medium mb-4">{title}</h3>
      <ResponsiveContainer width="100%" height={256}>
        <LineChart data={data as {{Entity}}ChartData[]} margin={{ top: 0, right: 0, bottom: 0, left: 0 }}>
          <CartesianGrid strokeDasharray="3 3" className="stroke-border" />
          <XAxis
            dataKey="label"
            tick={{ fontSize: 12 }}
            tickLine={false}
            axisLine={false}
          />
          <YAxis tick={{ fontSize: 12 }} tickLine={false} axisLine={false} />
          <Tooltip
            contentStyle={{
              borderRadius: '6px',
              border: '1px solid hsl(var(--border))',
              background: 'hsl(var(--popover))',
              color: 'hsl(var(--popover-foreground))',
            }}
          />
          <Line
            type="monotone"
            dataKey={seriesKey as string}
            stroke="hsl(var(--primary))"
            strokeWidth={2}
            dot={false}
          />
        </LineChart>
      </ResponsiveContainer>
    </div>
  );
}
```

### Main Table Component

```tsx
// frontend/src/presentation/{{context}}/{{Entity}}Table.tsx

'use client';

import {
  useReactTable,
  getCoreRowModel,
  flexRender,
  type SortingState,
  type ColumnFiltersState,
} from '@tanstack/react-table';
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/shared/components/ui/table';
import { ArrowUpIcon, ArrowDownIcon, ArrowUpDownIcon } from 'lucide-react';
import { {{entity}}Columns } from './columns';
import { {{Entity}}EmptyState } from './{{Entity}}EmptyState';
import type { {{Entity}}, {{Entity}}Sort } from '../../domain/{{context}}/types';
import type { VisibilityState } from '@tanstack/react-table';

interface {{Entity}}TableProps {
  readonly data: readonly {{Entity}}[];
  readonly total: number;
  readonly sort: readonly {{Entity}}Sort[];
  readonly onSort: (sort: {{Entity}}Sort) => void;
  readonly columnVisibility: VisibilityState;
  readonly onColumnVisibilityChange: (
    updater: VisibilityState | ((prev: VisibilityState) => VisibilityState),
  ) => void;
  readonly hasFilters: boolean;
  readonly onClearFilters: () => void;
}

function SortIcon({ column, sort }: { readonly column: string; readonly sort: readonly {{Entity}}Sort[] }) {
  const active = sort.find((s) => s.column === column);
  if (!active) return <ArrowUpDownIcon className="h-3 w-3 opacity-40" aria-hidden />;
  return active.direction === 'asc' ? (
    <ArrowUpIcon className="h-3 w-3" aria-hidden />
  ) : (
    <ArrowDownIcon className="h-3 w-3" aria-hidden />
  );
}

export function {{Entity}}Table({
  data,
  sort,
  onSort,
  columnVisibility,
  onColumnVisibilityChange,
  hasFilters,
  onClearFilters,
}: {{Entity}}TableProps) {
  const table = useReactTable({
    data: data as {{Entity}}[],
    columns: {{entity}}Columns,
    getCoreRowModel: getCoreRowModel(),
    manualSorting: true,
    manualFiltering: true,
    manualPagination: true,
    state: {
      sorting: sort.map((s) => ({ id: s.column as string, desc: s.direction === 'desc' })) as SortingState,
      columnVisibility,
      columnFilters: [] as ColumnFiltersState,
    },
    onColumnVisibilityChange,
  });

  const rows = table.getRowModel().rows;

  return (
    <div className="overflow-x-auto rounded-md border">
      <Table>
        <TableHeader>
          {table.getHeaderGroups().map((headerGroup) => (
            <TableRow key={headerGroup.id}>
              {headerGroup.headers.map((header) => (
                <TableHead
                  key={header.id}
                  style={{ width: header.getSize() }}
                  className={header.column.getCanSort() ? 'cursor-pointer select-none' : ''}
                  onClick={
                    header.column.getCanSort()
                      ? () => {
                          const existing = sort.find((s) => s.column === header.id);
                          onSort({
                            column: header.id as keyof {{Entity}},
                            direction:
                              existing?.direction === 'asc' ? 'desc' : 'asc',
                          });
                        }
                      : undefined
                  }
                  aria-sort={
                    sort.find((s) => s.column === header.id)?.direction === 'asc'
                      ? 'ascending'
                      : sort.find((s) => s.column === header.id)?.direction === 'desc'
                        ? 'descending'
                        : 'none'
                  }
                >
                  <div className="flex items-center gap-1">
                    {header.isPlaceholder
                      ? null
                      : flexRender(header.column.columnDef.header, header.getContext())}
                    {header.column.getCanSort() && (
                      <SortIcon column={header.id} sort={sort} />
                    )}
                  </div>
                </TableHead>
              ))}
            </TableRow>
          ))}
        </TableHeader>
        <TableBody>
          {rows.length === 0 ? (
            <TableRow>
              <TableCell colSpan={{{entity}}Columns.length} className="p-0">
                <{{Entity}}EmptyState hasFilters={hasFilters} onClearFilters={onClearFilters} />
              </TableCell>
            </TableRow>
          ) : (
            rows.map((row) => (
              <TableRow key={row.id}>
                {row.getVisibleCells().map((cell) => (
                  <TableCell key={cell.id}>
                    {flexRender(cell.column.columnDef.cell, cell.getContext())}
                  </TableCell>
                ))}
              </TableRow>
            ))
          )}
        </TableBody>
      </Table>
    </div>
  );
}
```

### Pagination Component

```tsx
// frontend/src/presentation/{{context}}/{{Entity}}Pagination.tsx

'use client';

import { Button } from '@/shared/components/ui/button';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/shared/components/ui/select';
import {
  ChevronLeftIcon,
  ChevronRightIcon,
  ChevronsLeftIcon,
  ChevronsRightIcon,
} from 'lucide-react';

interface {{Entity}}PaginationProps {
  readonly page: number;
  readonly pageSize: number;
  readonly pageCount: number;
  readonly total: number;
  readonly onPageChange: (page: number) => void;
  readonly onPageSizeChange: (pageSize: number) => void;
}

const PAGE_SIZE_OPTIONS = [10, 25, 50, 100] as const;

export function {{Entity}}Pagination({
  page,
  pageSize,
  pageCount,
  total,
  onPageChange,
  onPageSizeChange,
}: {{Entity}}PaginationProps) {
  const start = (page - 1) * pageSize + 1;
  const end = Math.min(page * pageSize, total);

  return (
    <div className="flex items-center justify-between gap-4 flex-wrap">
      <p className="text-sm text-muted-foreground">
        {total === 0 ? 'No results' : `${start}–${end} of ${total}`}
      </p>

      <div className="flex items-center gap-2">
        <span className="text-sm text-muted-foreground whitespace-nowrap">Rows per page</span>
        <Select
          value={String(pageSize)}
          onValueChange={(v) => onPageSizeChange(Number(v))}
        >
          <SelectTrigger className="w-16 h-8">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {PAGE_SIZE_OPTIONS.map((size) => (
              <SelectItem key={size} value={String(size)}>
                {size}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>

        <div className="flex items-center gap-1">
          <Button
            variant="outline"
            size="icon"
            className="h-8 w-8"
            onClick={() => onPageChange(1)}
            disabled={page <= 1}
            aria-label="First page"
          >
            <ChevronsLeftIcon className="h-4 w-4" aria-hidden />
          </Button>
          <Button
            variant="outline"
            size="icon"
            className="h-8 w-8"
            onClick={() => onPageChange(page - 1)}
            disabled={page <= 1}
            aria-label="Previous page"
          >
            <ChevronLeftIcon className="h-4 w-4" aria-hidden />
          </Button>
          <span className="text-sm tabular-nums px-2">
            {page} / {pageCount}
          </span>
          <Button
            variant="outline"
            size="icon"
            className="h-8 w-8"
            onClick={() => onPageChange(page + 1)}
            disabled={page >= pageCount}
            aria-label="Next page"
          >
            <ChevronRightIcon className="h-4 w-4" aria-hidden />
          </Button>
          <Button
            variant="outline"
            size="icon"
            className="h-8 w-8"
            onClick={() => onPageChange(pageCount)}
            disabled={page >= pageCount}
            aria-label="Last page"
          >
            <ChevronsRightIcon className="h-4 w-4" aria-hidden />
          </Button>
        </div>
      </div>
    </div>
  );
}
```

### Mobile Card List (Responsive)

```tsx
// frontend/src/presentation/{{context}}/{{Entity}}CardList.tsx

'use client';

import type { {{Entity}} } from '../../domain/{{context}}/types';

interface {{Entity}}CardListProps {
  readonly items: readonly {{Entity}}[];
}

interface {{Entity}}CardProps {
  readonly item: {{Entity}};
}

function {{Entity}}Card({ item }: {{Entity}}CardProps) {
  return (
    <div className="rounded-lg border bg-card p-4 shadow-sm">
      {{#each CARD_FIELDS}}
      <div className="flex justify-between items-start mb-2">
        <span className="text-xs text-muted-foreground">{{LABEL}}</span>
        <span className="text-sm font-medium">{String(item.{{FIELD}})}</span>
      </div>
      {{/each}}
    </div>
  );
}

export function {{Entity}}CardList({ items }: {{Entity}}CardListProps) {
  if (items.length === 0) {
    return null;
  }

  return (
    <div className="grid gap-3 sm:hidden">
      {items.map((item) => (
        <{{Entity}}Card key={item.id} item={item} />
      ))}
    </div>
  );
}
```

### Main Dashboard Page

```tsx
// frontend/src/presentation/{{context}}/{{Entity}}DashboardPage.tsx

'use client';

import { Suspense } from 'react';
import { QueryErrorResetBoundary } from '@tanstack/react-query';
import { ErrorBoundary } from 'react-error-boundary';
import { use{{Entity}}TableState } from '../../application/{{context}}/use{{Entity}}TableState';
import { use{{Entity}}ColumnVisibility } from '../../application/{{context}}/use{{Entity}}ColumnVisibility';
import { {{Entity}}TableSection } from './{{Entity}}TableSection';
import { {{Entity}}ChartsSection } from './{{Entity}}ChartsSection';
import { {{Entity}}TableSkeleton } from './skeletons/{{Entity}}TableSkeleton';
import { {{Entity}}ChartSkeleton } from './skeletons/{{Entity}}ChartSkeleton';
import { SearchFilter } from './filters/SearchFilter';
import { DateRangeFilter } from './filters/DateRangeFilter';
import { StatusFilter } from './filters/StatusFilter';
import { {{Entity}}ExportButton } from './{{Entity}}ExportButton';
import { Button } from '@/shared/components/ui/button';
import { XIcon } from 'lucide-react';

function DashboardErrorFallback({
  error,
  resetErrorBoundary,
}: {
  readonly error: Error;
  readonly resetErrorBoundary: () => void;
}) {
  return (
    <div
      role="alert"
      className="flex flex-col items-center gap-4 py-16 text-center"
    >
      <p className="text-sm text-destructive">{error.message}</p>
      <Button variant="outline" onClick={resetErrorBoundary}>
        Try again
      </Button>
    </div>
  );
}

export function {{Entity}}DashboardPage() {
  const [state, actions] = use{{Entity}}TableState();
  const [columnVisibility, setColumnVisibility] = use{{Entity}}ColumnVisibility();

  const hasActiveFilters =
    state.filters.search !== '' ||
    state.filters.status !== null ||
    state.filters.dateFrom !== null ||
    state.filters.dateTo !== null;

  return (
    <div className="space-y-6">
      <div className="flex items-start justify-between gap-4 flex-wrap">
        <h1 className="text-2xl font-semibold tracking-tight">{{DASHBOARD_TITLE}}</h1>
        <{{Entity}}ExportButton filters={state.filters} />
      </div>

      {/* Filters toolbar */}
      <div className="flex items-end gap-3 flex-wrap">
        <SearchFilter
          value={state.filters.search}
          onChange={(search) => actions.setFilter({ search })}
          placeholder="Search {{entity-plural}}…"
        />
        <StatusFilter
          value={state.filters.status}
          onChange={(status) => actions.setFilter({ status })}
        />
        <DateRangeFilter
          dateFrom={state.filters.dateFrom}
          dateTo={state.filters.dateTo}
          onDateFromChange={(dateFrom) => actions.setFilter({ dateFrom })}
          onDateToChange={(dateTo) => actions.setFilter({ dateTo })}
        />
        {hasActiveFilters && (
          <Button
            variant="ghost"
            size="sm"
            onClick={actions.resetFilters}
            className="gap-1 text-muted-foreground"
          >
            <XIcon className="h-4 w-4" aria-hidden />
            Clear filters
          </Button>
        )}
      </div>

      {/* Charts section */}
      <QueryErrorResetBoundary>
        {({ reset }) => (
          <ErrorBoundary onReset={reset} FallbackComponent={DashboardErrorFallback}>
            <Suspense fallback={<{{Entity}}ChartSkeleton />}>
              <{{Entity}}ChartsSection filters={state.filters} />
            </Suspense>
          </ErrorBoundary>
        )}
      </QueryErrorResetBoundary>

      {/* Table section */}
      <QueryErrorResetBoundary>
        {({ reset }) => (
          <ErrorBoundary onReset={reset} FallbackComponent={DashboardErrorFallback}>
            <Suspense fallback={<{{Entity}}TableSkeleton />}>
              <{{Entity}}TableSection
                state={state}
                actions={actions}
                columnVisibility={columnVisibility}
                onColumnVisibilityChange={setColumnVisibility}
                hasActiveFilters={hasActiveFilters}
              />
            </Suspense>
          </ErrorBoundary>
        )}
      </QueryErrorResetBoundary>
    </div>
  );
}
```

### Table Section (Suspense boundary child)

```tsx
// frontend/src/presentation/{{context}}/{{Entity}}TableSection.tsx

'use client';

import { use{{Entity}}List } from '../../application/{{context}}/use{{Entity}}List';
import { {{Entity}}Table } from './{{Entity}}Table';
import { {{Entity}}CardList } from './{{Entity}}CardList';
import { {{Entity}}Pagination } from './{{Entity}}Pagination';
import { {{Entity}}ColumnToggle } from './{{Entity}}ColumnToggle';
import { useReactTable, getCoreRowModel } from '@tanstack/react-table';
import { {{entity}}Columns } from './columns';
import type { {{Entity}}TableState } from '../../domain/{{context}}/types';
import type { VisibilityState } from '@tanstack/react-table';

interface {{Entity}}TableSectionProps {
  readonly state: {{Entity}}TableState;
  readonly actions: {
    readonly setSort: (sort: {{Entity}}TableState['sort'][number]) => void;
    readonly setPage: (page: number) => void;
    readonly setPageSize: (pageSize: number) => void;
    readonly resetFilters: () => void;
  };
  readonly columnVisibility: VisibilityState;
  readonly onColumnVisibilityChange: (
    updater: VisibilityState | ((prev: VisibilityState) => VisibilityState),
  ) => void;
  readonly hasActiveFilters: boolean;
}

export function {{Entity}}TableSection({
  state,
  actions,
  columnVisibility,
  onColumnVisibilityChange,
  hasActiveFilters,
}: {{Entity}}TableSectionProps) {
  const { items, total, pageCount } = use{{Entity}}List(state);

  const table = useReactTable({
    data: items,
    columns: {{entity}}Columns,
    getCoreRowModel: getCoreRowModel(),
    state: { columnVisibility },
    onColumnVisibilityChange,
    manualSorting: true,
    manualPagination: true,
    manualFiltering: true,
  });

  return (
    <div className="space-y-4">
      <div className="flex justify-end">
        <{{Entity}}ColumnToggle table={table} />
      </div>

      {/* Desktop: table */}
      <div className="hidden sm:block">
        <{{Entity}}Table
          data={items}
          total={total}
          sort={state.sort}
          onSort={actions.setSort}
          columnVisibility={columnVisibility}
          onColumnVisibilityChange={onColumnVisibilityChange}
          hasFilters={hasActiveFilters}
          onClearFilters={actions.resetFilters}
        />
      </div>

      {/* Mobile: card list */}
      <{{Entity}}CardList items={items} />

      <{{Entity}}Pagination
        page={state.pagination.page}
        pageSize={state.pagination.pageSize}
        pageCount={pageCount}
        total={total}
        onPageChange={actions.setPage}
        onPageSizeChange={actions.setPageSize}
      />
    </div>
  );
}
```

### Charts Section (Suspense boundary child)

```tsx
// frontend/src/presentation/{{context}}/{{Entity}}ChartsSection.tsx

'use client';

import { use{{Entity}}Stats } from '../../application/{{context}}/use{{Entity}}Stats';
import { {{Entity}}BarChart } from './charts/{{Entity}}BarChart';
import { {{Entity}}LineChart } from './charts/{{Entity}}LineChart';
import type { {{Entity}}TableState } from '../../domain/{{context}}/types';

interface {{Entity}}ChartsSectionProps {
  readonly filters: {{Entity}}TableState['filters'];
}

export function {{Entity}}ChartsSection({ filters }: {{Entity}}ChartsSectionProps) {
  const chartData = use{{Entity}}Stats(filters);

  return (
    <div className="grid gap-6 md:grid-cols-2">
      <div className="rounded-lg border bg-card p-4">
        <{{Entity}}BarChart data={chartData} title="{{BAR_CHART_TITLE}}" />
      </div>
      <div className="rounded-lg border bg-card p-4">
        <{{Entity}}LineChart data={chartData} title="{{LINE_CHART_TITLE}}" />
      </div>
    </div>
  );
}
```

## File Structure

```
frontend/src/
├── domain/{{context}}/
│   ├── types.ts           — {{Entity}}, {{Entity}}Filters, {{Entity}}Sort, {{Entity}}TableState
│   ├── api.ts             — Response/params interfaces
│   └── mappers.ts         — map{{Entity}}, map{{Entity}}ChartData
├── application/{{context}}/
│   ├── keys.ts            — TanStack Query key factory
│   ├── api-client.ts      — fetch functions (list, stats, export)
│   ├── use{{Entity}}List.ts
│   ├── use{{Entity}}Stats.ts
│   ├── use{{Entity}}Export.ts
│   ├── use{{Entity}}TableState.ts
│   └── use{{Entity}}ColumnVisibility.ts
└── presentation/{{context}}/
    ├── columns.tsx
    ├── filters/
    │   ├── SearchFilter.tsx
    │   ├── DateRangeFilter.tsx
    │   └── StatusFilter.tsx
    ├── charts/
    │   ├── {{Entity}}BarChart.tsx
    │   └── {{Entity}}LineChart.tsx
    ├── skeletons/
    │   ├── {{Entity}}TableSkeleton.tsx
    │   └── {{Entity}}ChartSkeleton.tsx
    ├── {{Entity}}Table.tsx
    ├── {{Entity}}TableSection.tsx
    ├── {{Entity}}ChartsSection.tsx
    ├── {{Entity}}CardList.tsx
    ├── {{Entity}}EmptyState.tsx
    ├── {{Entity}}Pagination.tsx
    ├── {{Entity}}ColumnToggle.tsx
    ├── {{Entity}}ExportButton.tsx
    └── {{Entity}}DashboardPage.tsx
```

## Tests

### Filter Logic Tests

```typescript
// frontend/src/application/{{context}}/use{{Entity}}TableState.test.ts

import { renderHook, act } from '@testing-library/react';
import { use{{Entity}}TableState } from './use{{Entity}}TableState';

describe('use{{Entity}}TableState', () => {
  it('resets page to 1 when filter changes', () => {
    const { result } = renderHook(() => use{{Entity}}TableState());
    const [, actions] = result.current;

    act(() => actions.setPage(3));
    expect(result.current[0].pagination.page).toBe(3);

    act(() => actions.setFilter({ search: 'test' }));
    expect(result.current[0].pagination.page).toBe(1);
  });

  it('keeps up to 3 sort columns in multi-sort', () => {
    const { result } = renderHook(() => use{{Entity}}TableState());
    const [, actions] = result.current;

    act(() => actions.setSort({ column: 'createdAt', direction: 'desc' }));
    act(() => actions.setSort({ column: 'updatedAt', direction: 'asc' }));
    act(() => actions.setSort({ column: 'id', direction: 'asc' }));
    act(() => actions.setSort({ column: 'status' as keyof {{Entity}}, direction: 'asc' }));

    expect(result.current[0].sort).toHaveLength(3);
  });

  it('toggles sort direction on second click of same column', () => {
    const { result } = renderHook(() => use{{Entity}}TableState());
    const [, actions] = result.current;

    act(() => actions.setSort({ column: 'createdAt', direction: 'asc' }));
    act(() => actions.setSort({ column: 'createdAt', direction: 'desc' }));

    const sortEntry = result.current[0].sort.find((s) => s.column === 'createdAt');
    expect(sortEntry?.direction).toBe('desc');
  });

  it('resets filters and page on resetFilters', () => {
    const { result } = renderHook(() => use{{Entity}}TableState());
    const [, actions] = result.current;

    act(() => {
      actions.setFilter({ search: 'foo', status: '{{SAMPLE_STATUS}}' as {{Entity}}Status });
      actions.setPage(5);
    });

    act(() => actions.resetFilters());

    expect(result.current[0].filters.search).toBe('');
    expect(result.current[0].filters.status).toBeNull();
    expect(result.current[0].pagination.page).toBe(1);
  });
});
```

### Export Tests

```typescript
// frontend/src/application/{{context}}/use{{Entity}}Export.test.ts

import { renderHook, act } from '@testing-library/react';
import { use{{Entity}}Export } from './use{{Entity}}Export';
import * as apiClient from './api-client';

vi.mock('./api-client');

const mockFilters = {
  search: '',
  status: null,
  dateFrom: null,
  dateTo: null,
};

describe('use{{Entity}}Export', () => {
  beforeEach(() => {
    vi.spyOn(apiClient, 'export{{Entity}}Data').mockResolvedValue(
      new Blob(['col1,col2\nval1,val2'], { type: 'text/csv' }),
    );

    // Stub browser APIs unavailable in jsdom
    URL.createObjectURL = vi.fn().mockReturnValue('blob:mock-url');
    URL.revokeObjectURL = vi.fn();

    const anchor = document.createElement('a');
    vi.spyOn(document, 'createElement').mockReturnValue(anchor);
    vi.spyOn(document.body, 'appendChild').mockImplementation(() => anchor);
    vi.spyOn(document.body, 'removeChild').mockImplementation(() => anchor);
    vi.spyOn(anchor, 'click').mockImplementation(() => undefined);
  });

  it('calls export API with csv format', async () => {
    const { result } = renderHook(() => use{{Entity}}Export(mockFilters));

    await act(() => result.current.exportCsv());

    expect(apiClient.export{{Entity}}Data).toHaveBeenCalledWith(
      expect.objectContaining({ format: 'csv' }),
    );
    expect(result.current.isExporting).toBe(false);
    expect(result.current.error).toBeNull();
  });

  it('sets error state when export fails', async () => {
    vi.spyOn(apiClient, 'export{{Entity}}Data').mockRejectedValue(
      new Error('Network error'),
    );

    const { result } = renderHook(() => use{{Entity}}Export(mockFilters));

    await act(() => result.current.exportJson());

    expect(result.current.error).not.toBeNull();
    expect(result.current.error?.message).toBe('Network error');
  });
});
```

### Column Definition Tests

```typescript
// frontend/src/presentation/{{context}}/columns.test.tsx

import { createColumnHelper } from '@tanstack/react-table';
import { {{entity}}Columns } from './columns';
import type { {{Entity}} } from '../../domain/{{context}}/types';

describe('{{entity}}Columns', () => {
  it('has an actions column that cannot be sorted', () => {
    const actionsCol = {{entity}}Columns.find(
      (col) => 'id' in col && col.id === 'actions',
    );
    expect(actionsCol).toBeDefined();
  });

  it('sortable columns have enableSorting set to true', () => {
    const sortableColumns = {{entity}}Columns.filter(
      (col) => 'enableSorting' in col && col.enableSorting === true,
    );
    expect(sortableColumns.length).toBeGreaterThan(0);
  });

  it('all columns have a defined size', () => {
    {{entity}}Columns.forEach((col) => {
      if ('size' in col) {
        expect(typeof col.size).toBe('number');
      }
    });
  });
});
```

### Column Visibility Persistence Tests

```typescript
// frontend/src/application/{{context}}/use{{Entity}}ColumnVisibility.test.ts

import { renderHook, act } from '@testing-library/react';
import { use{{Entity}}ColumnVisibility } from './use{{Entity}}ColumnVisibility';

const STORAGE_KEY = '{{entity}}-column-visibility';

describe('use{{Entity}}ColumnVisibility', () => {
  beforeEach(() => localStorage.clear());

  it('initializes from localStorage when value exists', () => {
    localStorage.setItem(STORAGE_KEY, JSON.stringify({ id: false }));
    const { result } = renderHook(() => use{{Entity}}ColumnVisibility());
    expect(result.current[0]).toEqual({ id: false });
  });

  it('persists visibility changes to localStorage', () => {
    const { result } = renderHook(() => use{{Entity}}ColumnVisibility());
    act(() => result.current[1]({ id: false }));
    expect(JSON.parse(localStorage.getItem(STORAGE_KEY) ?? '{}')).toEqual({ id: false });
  });

  it('falls back to empty object on corrupt localStorage data', () => {
    localStorage.setItem(STORAGE_KEY, 'not-valid-json{{{');
    const { result } = renderHook(() => use{{Entity}}ColumnVisibility());
    expect(result.current[0]).toEqual({});
  });
});
```

## Validation Commands

```bash
npm run typecheck
npm run test -- --filter={{context}}
npm run lint
```

## Do NOT

- Use `any` — use proper types or `unknown`
- Use non-null assertion `!` — handle null explicitly
- Use default exports — named exports only
- Use `useEffect` for data fetching — use `useSuspenseQuery`
- Fetch data without an `<ErrorBoundary>` + `<Suspense>` wrapper
- Store server state in `useState` — use TanStack Query
- Do client-side pagination on server-fetched data
- Access `localStorage` during SSR without a try/catch guard
- Use `any` in column cell renderers — type the accessor properly
