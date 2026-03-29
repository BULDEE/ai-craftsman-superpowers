# Agent: {{FORM_NAME}} Multi-Step Form

> Template for complex multi-step forms with validation, autosave, and server integration
> Replace {{PLACEHOLDERS}} with actual values

## Mission

Build a production-ready multi-step form for {{FORM_DESCRIPTION}}. The form must handle wizard navigation, per-step validation, optimistic submission, draft autosave, and accessible progress tracking — all with React 19 patterns and strict TypeScript.

## Context Files to Read

1. `frontend/src/domain/{{context}}/` - Domain types and value objects
2. `frontend/src/application/{{context}}/` - Server actions and hooks
3. `frontend/src/presentation/{{context}}/forms/` - Existing form components
4. `frontend/CLAUDE.md` - Frontend rules

## Domain Layer

### Types

```typescript
// frontend/src/domain/{{context}}/types.ts
import { z } from 'zod';

// Branded primitives — never use raw string/number for domain IDs
export type {{Entity}}Id = string & { readonly _brand: '{{Entity}}Id' };

export function make{{Entity}}Id(value: string): {{Entity}}Id {
  return value as {{Entity}}Id;
}

// ── Step schemas ────────────────────────────────────────────────────────────

export const step{{STEP_1_NAME}}Schema = z.object({
  {{#each STEP_1_FIELDS}}
  {{NAME}}: {{ZOD_VALIDATOR}},
  {{/each}}
});

export const step{{STEP_2_NAME}}Schema = z.object({
  {{#each STEP_2_FIELDS}}
  {{NAME}}: {{ZOD_VALIDATOR}},
  {{/each}}
});

export const step{{STEP_3_NAME}}Schema = z.object({
  {{#each STEP_3_FIELDS}}
  {{NAME}}: {{ZOD_VALIDATOR}},
  {{/each}}
});

// Full form schema — intersection of all steps
export const {{entity}}FormSchema = step{{STEP_1_NAME}}Schema
  .merge(step{{STEP_2_NAME}}Schema)
  .merge(step{{STEP_3_NAME}}Schema);

// ── Inferred types ───────────────────────────────────────────────────────────

export type Step{{STEP_1_NAME}}Data = z.infer<typeof step{{STEP_1_NAME}}Schema>;
export type Step{{STEP_2_NAME}}Data = z.infer<typeof step{{STEP_2_NAME}}Schema>;
export type Step{{STEP_3_NAME}}Data = z.infer<typeof step{{STEP_3_NAME}}Schema>;
export type {{Entity}}FormData = z.infer<typeof {{entity}}FormSchema>;

// ── Wizard state ─────────────────────────────────────────────────────────────

export type FormStep = '{{STEP_1_KEY}}' | '{{STEP_2_KEY}}' | '{{STEP_3_KEY}}';

export interface WizardState {
  readonly currentStep: FormStep;
  readonly completedSteps: ReadonlySet<FormStep>;
  readonly formData: Partial<{{Entity}}FormData>;
}

export const FORM_STEPS: readonly FormStep[] = [
  '{{STEP_1_KEY}}',
  '{{STEP_2_KEY}}',
  '{{STEP_3_KEY}}',
];

export interface StepMeta {
  readonly key: FormStep;
  readonly label: string;
  readonly description: string;
}

export const STEP_META: ReadonlyMap<FormStep, StepMeta> = new Map([
  ['{{STEP_1_KEY}}', { key: '{{STEP_1_KEY}}', label: '{{STEP_1_LABEL}}', description: '{{STEP_1_DESC}}' }],
  ['{{STEP_2_KEY}}', { key: '{{STEP_2_KEY}}', label: '{{STEP_2_LABEL}}', description: '{{STEP_2_DESC}}' }],
  ['{{STEP_3_KEY}}', { key: '{{STEP_3_KEY}}', label: '{{STEP_3_LABEL}}', description: '{{STEP_3_DESC}}' }],
]);

// ── File upload ───────────────────────────────────────────────────────────────

export interface UploadedFile {
  readonly id: string;
  readonly name: string;
  readonly size: number;
  readonly type: string;
  readonly previewUrl: string | null;
  readonly uploadedUrl: string | null;
  readonly status: 'pending' | 'uploading' | 'done' | 'error';
  readonly error: string | null;
}

// ── Server action result ──────────────────────────────────────────────────────

export interface FormSubmitResult {
  readonly success: boolean;
  readonly {{entity}}Id: {{Entity}}Id | null;
  readonly error: string | null;
  readonly fieldErrors: Partial<Record<keyof {{Entity}}FormData, readonly string[]>> | null;
}
```

### Server Actions

```typescript
// frontend/src/application/{{context}}/actions.ts
'use server';

import { z } from 'zod';
import { {{entity}}FormSchema, type FormSubmitResult, type {{Entity}}FormData, make{{Entity}}Id } from '@/domain/{{context}}/types';

export async function submit{{Entity}}Form(
  _previousState: FormSubmitResult,
  formData: FormData,
): Promise<FormSubmitResult> {
  const raw = Object.fromEntries(formData.entries());

  const parsed = {{entity}}FormSchema.safeParse(raw);

  if (!parsed.success) {
    const fieldErrors = parsed.error.flatten().fieldErrors as Partial<
      Record<keyof {{Entity}}FormData, readonly string[]>
    >;
    return { success: false, {{entity}}Id: null, error: 'Validation failed', fieldErrors };
  }

  try {
    // Replace with your actual persistence call
    const id = await create{{Entity}}(parsed.data);
    return { success: true, {{entity}}Id: make{{Entity}}Id(id), error: null, fieldErrors: null };
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Unexpected error';
    return { success: false, {{entity}}Id: null, error: message, fieldErrors: null };
  }
}

// Stub — replace with real implementation
async function create{{Entity}}(_data: {{Entity}}FormData): Promise<string> {
  throw new Error('Not implemented: create{{Entity}}');
}
```

## Application Layer

### Form Context (Compound Component Pattern)

```typescript
// frontend/src/application/{{context}}/form-context.ts
'use client';

import { createContext, use } from 'react';
import type { WizardState, FormStep, {{Entity}}FormData } from '@/domain/{{context}}/types';

export interface {{Entity}}FormContextType {
  readonly state: WizardState;
  readonly goToStep: (step: FormStep) => void;
  readonly goNext: () => void;
  readonly goPrev: () => void;
  readonly updateData: (partial: Partial<{{Entity}}FormData>) => void;
  readonly isStepComplete: (step: FormStep) => boolean;
  readonly canNavigateTo: (step: FormStep) => boolean;
  readonly files: readonly import('@/domain/{{context}}/types').UploadedFile[];
  readonly addFile: (file: File) => void;
  readonly removeFile: (id: string) => void;
}

export const {{Entity}}FormContext = createContext<{{Entity}}FormContextType | null>(null);

export function use{{Entity}}Form(): {{Entity}}FormContextType {
  const ctx = use({{Entity}}FormContext);
  if (ctx === null) {
    throw new Error('use{{Entity}}Form must be used within <{{Entity}}FormProvider>');
  }
  return ctx;
}
```

### Form Provider Hook

```typescript
// frontend/src/application/{{context}}/use-form-provider.ts
'use client';

import { useState, useCallback, useEffect, useRef } from 'react';
import type {
  WizardState,
  FormStep,
  {{Entity}}FormData,
  UploadedFile,
} from '@/domain/{{context}}/types';
import { FORM_STEPS } from '@/domain/{{context}}/types';
import type { {{Entity}}FormContextType } from './form-context';

const DRAFT_KEY = '{{entity}}-form-draft';
const AUTOSAVE_DELAY_MS = 800;

function loadDraft(): Partial<{{Entity}}FormData> {
  if (typeof window === 'undefined') return {};
  try {
    const raw = localStorage.getItem(DRAFT_KEY);
    return raw !== null ? (JSON.parse(raw) as Partial<{{Entity}}FormData>) : {};
  } catch {
    return {};
  }
}

function saveDraft(data: Partial<{{Entity}}FormData>): void {
  try {
    localStorage.setItem(DRAFT_KEY, JSON.stringify(data));
  } catch {
    // Storage quota exceeded or private browsing — silently ignore
  }
}

function clearDraft(): void {
  try {
    localStorage.removeItem(DRAFT_KEY);
  } catch {
    // Silently ignore
  }
}

export function use{{Entity}}FormProvider(): {{Entity}}FormContextType & { readonly clearDraft: () => void } {
  const [state, setState] = useState<WizardState>(() => ({
    currentStep: FORM_STEPS[0],
    completedSteps: new Set<FormStep>(),
    formData: loadDraft(),
  }));

  const [files, setFiles] = useState<readonly UploadedFile[]>([]);
  const autosaveTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Debounced autosave
  useEffect(() => {
    if (autosaveTimer.current !== null) {
      clearTimeout(autosaveTimer.current);
    }
    autosaveTimer.current = setTimeout(() => {
      saveDraft(state.formData);
    }, AUTOSAVE_DELAY_MS);

    return () => {
      if (autosaveTimer.current !== null) {
        clearTimeout(autosaveTimer.current);
      }
    };
  }, [state.formData]);

  const goToStep = useCallback((step: FormStep) => {
    setState(prev => ({ ...prev, currentStep: step }));
  }, []);

  const goNext = useCallback(() => {
    setState(prev => {
      const idx = FORM_STEPS.indexOf(prev.currentStep);
      const next = FORM_STEPS[idx + 1];
      if (next === undefined) return prev;
      return {
        ...prev,
        currentStep: next,
        completedSteps: new Set([...prev.completedSteps, prev.currentStep]),
      };
    });
  }, []);

  const goPrev = useCallback(() => {
    setState(prev => {
      const idx = FORM_STEPS.indexOf(prev.currentStep);
      const previous = FORM_STEPS[idx - 1];
      if (previous === undefined) return prev;
      return { ...prev, currentStep: previous };
    });
  }, []);

  const updateData = useCallback((partial: Partial<{{Entity}}FormData>) => {
    setState(prev => ({
      ...prev,
      formData: { ...prev.formData, ...partial },
    }));
  }, []);

  const isStepComplete = useCallback(
    (step: FormStep) => state.completedSteps.has(step),
    [state.completedSteps],
  );

  const canNavigateTo = useCallback(
    (step: FormStep) => {
      const targetIdx = FORM_STEPS.indexOf(step);
      const currentIdx = FORM_STEPS.indexOf(state.currentStep);
      // Can always go back; can only go forward if current is complete
      return targetIdx <= currentIdx || state.completedSteps.has(state.currentStep);
    },
    [state.completedSteps, state.currentStep],
  );

  const addFile = useCallback((file: File) => {
    const id = crypto.randomUUID();
    const previewUrl = file.type.startsWith('image/') ? URL.createObjectURL(file) : null;

    const uploadedFile: UploadedFile = {
      id,
      name: file.name,
      size: file.size,
      type: file.type,
      previewUrl,
      uploadedUrl: null,
      status: 'pending',
      error: null,
    };

    setFiles(prev => [...prev, uploadedFile]);

    // Start upload immediately
    void uploadFile(id, file, setFiles);
  }, []);

  const removeFile = useCallback((id: string) => {
    setFiles(prev => {
      const target = prev.find(f => f.id === id);
      if (target?.previewUrl !== null && target?.previewUrl !== undefined) {
        URL.revokeObjectURL(target.previewUrl);
      }
      return prev.filter(f => f.id !== id);
    });
  }, []);

  return {
    state,
    goToStep,
    goNext,
    goPrev,
    updateData,
    isStepComplete,
    canNavigateTo,
    files,
    addFile,
    removeFile,
    clearDraft,
  };
}

async function uploadFile(
  id: string,
  file: File,
  setFiles: React.Dispatch<React.SetStateAction<readonly UploadedFile[]>>,
): Promise<void> {
  setFiles(prev => prev.map(f => f.id === id ? { ...f, status: 'uploading' } : f));

  try {
    const formData = new FormData();
    formData.append('file', file);

    const response = await fetch('/api/upload', { method: 'POST', body: formData });

    if (!response.ok) {
      throw new Error(`Upload failed: ${response.statusText}`);
    }

    const result = (await response.json()) as { url: string };
    setFiles(prev =>
      prev.map(f =>
        f.id === id ? { ...f, status: 'done', uploadedUrl: result.url } : f,
      ),
    );
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Upload failed';
    setFiles(prev =>
      prev.map(f => f.id === id ? { ...f, status: 'error', error: message } : f),
    );
  }
}
```

## Presentation Layer

### File Structure

```
frontend/src/presentation/{{context}}/forms/{{entity}}/
├── {{Entity}}FormProvider.tsx      ← Context provider wrapping the wizard
├── {{Entity}}FormWizard.tsx        ← Wizard shell (progress + active step)
├── {{Entity}}FormProgress.tsx      ← Accessible step progress indicator
├── {{Entity}}FormErrorBoundary.tsx ← Per-section error boundary
├── steps/
│   ├── Step{{STEP_1_NAME}}.tsx
│   ├── Step{{STEP_2_NAME}}.tsx
│   └── Step{{STEP_3_NAME}}.tsx
├── fields/
│   ├── FileUploadField.tsx
│   └── FormField.tsx
├── {{Entity}}FormWizard.test.tsx
├── steps/Step{{STEP_1_NAME}}.test.tsx
└── index.ts
```

### FormProvider Component

```tsx
// frontend/src/presentation/{{context}}/forms/{{entity}}/{{Entity}}FormProvider.tsx
'use client';

import type { ReactNode } from 'react';
import { {{Entity}}FormContext } from '@/application/{{context}}/form-context';
import { use{{Entity}}FormProvider } from '@/application/{{context}}/use-form-provider';

interface {{Entity}}FormProviderProps {
  readonly children: ReactNode;
}

export function {{Entity}}FormProvider({ children }: {{Entity}}FormProviderProps) {
  const ctx = use{{Entity}}FormProvider();

  return (
    <{{Entity}}FormContext value={ctx}>
      {children}
    </{{Entity}}FormContext>
  );
}
```

### Progress Indicator (Accessible)

```tsx
// frontend/src/presentation/{{context}}/forms/{{entity}}/{{Entity}}FormProgress.tsx
'use client';

import { use{{Entity}}Form } from '@/application/{{context}}/form-context';
import { FORM_STEPS, STEP_META } from '@/domain/{{context}}/types';

export function {{Entity}}FormProgress() {
  const { state, goToStep, isStepComplete, canNavigateTo } = use{{Entity}}Form();

  const currentIndex = FORM_STEPS.indexOf(state.currentStep);
  const totalSteps = FORM_STEPS.length;

  return (
    <nav aria-label="Form progress">
      {/* Screenreader progress summary */}
      <div
        role="progressbar"
        aria-valuenow={currentIndex + 1}
        aria-valuemin={1}
        aria-valuemax={totalSteps}
        aria-label={`Step ${currentIndex + 1} of ${totalSteps}`}
        className="sr-only"
      />

      <ol className="flex items-center gap-4">
        {FORM_STEPS.map((step, index) => {
          const meta = STEP_META.get(step);
          const isCurrent = step === state.currentStep;
          const isComplete = isStepComplete(step);
          const isNavigable = canNavigateTo(step);

          return (
            <li key={step} className="flex items-center gap-2">
              <button
                type="button"
                onClick={() => isNavigable && goToStep(step)}
                disabled={!isNavigable}
                aria-current={isCurrent ? 'step' : undefined}
                aria-label={`${meta?.label ?? step}${isComplete ? ' (completed)' : ''}`}
                className={[
                  'flex h-8 w-8 items-center justify-center rounded-full text-sm font-medium transition-colors',
                  isCurrent ? 'bg-primary text-primary-foreground' : '',
                  isComplete && !isCurrent ? 'bg-primary/20 text-primary' : '',
                  !isComplete && !isCurrent ? 'bg-muted text-muted-foreground' : '',
                  isNavigable ? 'cursor-pointer hover:opacity-80' : 'cursor-not-allowed',
                ].join(' ')}
              >
                {isComplete && !isCurrent ? '✓' : index + 1}
              </button>

              {meta !== undefined && (
                <span
                  className={[
                    'hidden text-sm sm:inline',
                    isCurrent ? 'font-medium text-foreground' : 'text-muted-foreground',
                  ].join(' ')}
                >
                  {meta.label}
                </span>
              )}

              {/* Connector line between steps */}
              {index < totalSteps - 1 && (
                <div
                  aria-hidden="true"
                  className={[
                    'h-px w-8 flex-shrink-0',
                    isComplete ? 'bg-primary' : 'bg-border',
                  ].join(' ')}
                />
              )}
            </li>
          );
        })}
      </ol>
    </nav>
  );
}
```

### Error Boundary (Per Section)

```tsx
// frontend/src/presentation/{{context}}/forms/{{entity}}/{{Entity}}FormErrorBoundary.tsx
'use client';

import { Component, type ReactNode, type ErrorInfo } from 'react';

interface Props {
  readonly children: ReactNode;
  readonly fallback?: ReactNode;
  readonly onError?: (error: Error, info: ErrorInfo) => void;
}

interface State {
  readonly hasError: boolean;
  readonly error: Error | null;
}

export class {{Entity}}FormErrorBoundary extends Component<Props, State> {
  constructor(props: Props) {
    super(props);
    this.state = { hasError: false, error: null };
  }

  static getDerivedStateFromError(error: unknown): State {
    return {
      hasError: true,
      error: error instanceof Error ? error : new Error(String(error)),
    };
  }

  componentDidCatch(error: Error, info: ErrorInfo): void {
    this.props.onError?.(error, info);
    console.error('[{{Entity}}FormErrorBoundary]', error, info.componentStack);
  }

  render(): ReactNode {
    if (this.state.hasError) {
      return this.props.fallback ?? (
        <div role="alert" className="rounded-md border border-destructive/50 bg-destructive/10 p-4">
          <p className="text-sm font-medium text-destructive">
            Something went wrong in this section.
          </p>
          {this.state.error !== null && (
            <p className="mt-1 text-xs text-destructive/70">{this.state.error.message}</p>
          )}
          <button
            type="button"
            onClick={() => this.setState({ hasError: false, error: null })}
            className="mt-2 text-xs underline text-destructive hover:no-underline"
          >
            Try again
          </button>
        </div>
      );
    }
    return this.props.children;
  }
}
```

### Wizard Shell

```tsx
// frontend/src/presentation/{{context}}/forms/{{entity}}/{{Entity}}FormWizard.tsx
'use client';

import { useActionState, useOptimistic, useTransition } from 'react';
import { {{Entity}}FormProgress } from './{{Entity}}FormProgress';
import { {{Entity}}FormErrorBoundary } from './{{Entity}}FormErrorBoundary';
import { use{{Entity}}Form } from '@/application/{{context}}/form-context';
import { submit{{Entity}}Form } from '@/application/{{context}}/actions';
import { Step{{STEP_1_NAME}} } from './steps/Step{{STEP_1_NAME}}';
import { Step{{STEP_2_NAME}} } from './steps/Step{{STEP_2_NAME}}';
import { Step{{STEP_3_NAME}} } from './steps/Step{{STEP_3_NAME}}';
import type { FormSubmitResult } from '@/domain/{{context}}/types';

const INITIAL_STATE: FormSubmitResult = {
  success: false,
  {{entity}}Id: null,
  error: null,
  fieldErrors: null,
};

export function {{Entity}}FormWizard() {
  const { state, files } = use{{Entity}}Form();
  const [isPending, startTransition] = useTransition();

  const [formState, formAction] = useActionState(submit{{Entity}}Form, INITIAL_STATE);

  const [optimisticSubmitted, setOptimisticSubmitted] = useOptimistic(false);

  function handleFinalSubmit(formData: FormData) {
    // Inject file URLs into form data
    files
      .filter(f => f.uploadedUrl !== null)
      .forEach((f, i) => {
        formData.append(`file_${i}`, f.uploadedUrl as string);
      });

    // Inject wizard-accumulated data
    Object.entries(state.formData).forEach(([key, value]) => {
      if (value !== undefined && value !== null) {
        formData.set(key, String(value));
      }
    });

    startTransition(() => {
      setOptimisticSubmitted(true);
      formAction(formData);
    });
  }

  if (formState.success || optimisticSubmitted) {
    return (
      <div role="status" aria-live="polite" className="text-center py-12">
        <p className="text-lg font-medium">
          {optimisticSubmitted && !formState.success
            ? 'Submitting…'
            : '{{SUCCESS_MESSAGE}}'}
        </p>
      </div>
    );
  }

  const stepComponents: Record<string, React.ReactNode> = {
    '{{STEP_1_KEY}}': <Step{{STEP_1_NAME}} />,
    '{{STEP_2_KEY}}': <Step{{STEP_2_NAME}} />,
    '{{STEP_3_KEY}}': <Step{{STEP_3_NAME}} />,
  };

  const activeStep = stepComponents[state.currentStep];

  return (
    <div className="space-y-8">
      <{{Entity}}FormProgress />

      {formState.error !== null && (
        <div role="alert" aria-live="assertive" className="rounded-md border border-destructive/50 bg-destructive/10 p-4">
          <p className="text-sm text-destructive">{formState.error}</p>
        </div>
      )}

      <form action={handleFinalSubmit} noValidate>
        <{{Entity}}FormErrorBoundary>
          {activeStep}
        </{{Entity}}FormErrorBoundary>

        {state.currentStep === '{{STEP_3_KEY}}' && (
          <button
            type="submit"
            disabled={isPending}
            className="mt-6 w-full rounded-md bg-primary px-4 py-2 text-primary-foreground disabled:opacity-50"
          >
            {isPending ? 'Submitting…' : '{{SUBMIT_LABEL}}'}
          </button>
        )}
      </form>
    </div>
  );
}
```

### Step Components

```tsx
// frontend/src/presentation/{{context}}/forms/{{entity}}/steps/Step{{STEP_1_NAME}}.tsx
'use client';

import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { use{{Entity}}Form } from '@/application/{{context}}/form-context';
import {
  step{{STEP_1_NAME}}Schema,
  type Step{{STEP_1_NAME}}Data,
} from '@/domain/{{context}}/types';

export function Step{{STEP_1_NAME}}() {
  const { state, updateData, goNext } = use{{Entity}}Form();

  const {
    register,
    handleSubmit,
    formState: { errors },
  } = useForm<Step{{STEP_1_NAME}}Data>({
    resolver: zodResolver(step{{STEP_1_NAME}}Schema),
    defaultValues: state.formData as Partial<Step{{STEP_1_NAME}}Data>,
    mode: 'onBlur',
  });

  function onValid(data: Step{{STEP_1_NAME}}Data) {
    updateData(data);
    goNext();
  }

  return (
    <section aria-labelledby="step-{{STEP_1_KEY}}-heading">
      <h2 id="step-{{STEP_1_KEY}}-heading" className="text-lg font-semibold mb-4">
        {{STEP_1_LABEL}}
      </h2>

      <form onSubmit={handleSubmit(onValid)} noValidate className="space-y-4">
        {{#each STEP_1_FIELDS}}
        <div>
          <label htmlFor="{{NAME}}" className="block text-sm font-medium mb-1">
            {{LABEL}}
          </label>
          <input
            id="{{NAME}}"
            type="{{INPUT_TYPE}}"
            aria-invalid={errors.{{NAME}} !== undefined}
            aria-describedby={errors.{{NAME}} !== undefined ? '{{NAME}}-error' : undefined}
            className="w-full rounded-md border px-3 py-2 text-sm aria-[invalid=true]:border-destructive"
            {...register('{{NAME}}')}
          />
          {errors.{{NAME}} !== undefined && (
            <p id="{{NAME}}-error" role="alert" className="mt-1 text-xs text-destructive">
              {errors.{{NAME}}.message}
            </p>
          )}
        </div>
        {{/each}}

        <div className="flex justify-end pt-4">
          <button
            type="submit"
            className="rounded-md bg-primary px-4 py-2 text-sm text-primary-foreground"
          >
            Next: {{STEP_2_LABEL}}
          </button>
        </div>
      </form>
    </section>
  );
}
```

### File Upload Field

```tsx
// frontend/src/presentation/{{context}}/forms/{{entity}}/fields/FileUploadField.tsx
'use client';

import { useRef } from 'react';
import { use{{Entity}}Form } from '@/application/{{context}}/form-context';

const ACCEPTED_TYPES = '{{ACCEPTED_FILE_TYPES}}'; // e.g. "image/*,.pdf"
const MAX_SIZE_BYTES = {{MAX_FILE_SIZE_BYTES}}; // e.g. 5 * 1024 * 1024

export function FileUploadField() {
  const { files, addFile, removeFile } = use{{Entity}}Form();
  const inputRef = useRef<HTMLInputElement>(null);

  function handleChange(event: React.ChangeEvent<HTMLInputElement>) {
    const selected = event.target.files;
    if (selected === null) return;

    Array.from(selected).forEach(file => {
      if (file.size > MAX_SIZE_BYTES) {
        // Surface validation error without crashing
        console.warn(`File "${file.name}" exceeds maximum size`);
        return;
      }
      addFile(file);
    });

    // Reset input so the same file can be re-added after removal
    if (inputRef.current !== null) {
      inputRef.current.value = '';
    }
  }

  function handleDrop(event: React.DragEvent<HTMLDivElement>) {
    event.preventDefault();
    Array.from(event.dataTransfer.files).forEach(file => {
      if (file.size <= MAX_SIZE_BYTES) {
        addFile(file);
      }
    });
  }

  return (
    <div className="space-y-3">
      <div
        onDrop={handleDrop}
        onDragOver={e => e.preventDefault()}
        onClick={() => inputRef.current?.click()}
        role="button"
        tabIndex={0}
        aria-label="Upload files — click or drag and drop"
        onKeyDown={e => e.key === 'Enter' && inputRef.current?.click()}
        className="flex cursor-pointer flex-col items-center justify-center rounded-md border-2 border-dashed border-border p-8 transition-colors hover:border-primary"
      >
        <p className="text-sm text-muted-foreground">Click or drag files here</p>
        <p className="mt-1 text-xs text-muted-foreground">
          Accepted: {ACCEPTED_TYPES} — max {Math.round(MAX_SIZE_BYTES / 1024 / 1024)} MB
        </p>
      </div>

      <input
        ref={inputRef}
        type="file"
        multiple
        accept={ACCEPTED_TYPES}
        onChange={handleChange}
        className="sr-only"
        aria-hidden="true"
        tabIndex={-1}
      />

      {files.length > 0 && (
        <ul className="space-y-2" aria-label="Uploaded files">
          {files.map(file => (
            <li key={file.id} className="flex items-center gap-3 rounded-md border p-2 text-sm">
              {file.previewUrl !== null && (
                <img
                  src={file.previewUrl}
                  alt={`Preview of ${file.name}`}
                  className="h-10 w-10 rounded object-cover"
                />
              )}

              <div className="min-w-0 flex-1">
                <p className="truncate font-medium">{file.name}</p>
                <p className="text-xs text-muted-foreground">
                  {(file.size / 1024).toFixed(1)} KB
                  {' · '}
                  {file.status === 'uploading' && <span aria-live="polite">Uploading…</span>}
                  {file.status === 'done' && <span className="text-green-600">Uploaded</span>}
                  {file.status === 'error' && (
                    <span className="text-destructive" role="alert">{file.error}</span>
                  )}
                </p>
              </div>

              <button
                type="button"
                onClick={() => removeFile(file.id)}
                aria-label={`Remove ${file.name}`}
                className="shrink-0 text-muted-foreground hover:text-destructive"
              >
                ✕
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
```

## Tests

### Validation Schema Tests

```typescript
// frontend/src/presentation/{{context}}/forms/{{entity}}/{{Entity}}FormWizard.test.tsx
import { describe, it, expect } from 'vitest';
import {
  step{{STEP_1_NAME}}Schema,
  step{{STEP_2_NAME}}Schema,
  step{{STEP_3_NAME}}Schema,
  {{entity}}FormSchema,
} from '@/domain/{{context}}/types';

describe('{{Entity}} form schemas', () => {
  describe('step{{STEP_1_NAME}}Schema', () => {
    it('passes with valid data', () => {
      const result = step{{STEP_1_NAME}}Schema.safeParse({
        {{#each STEP_1_VALID_DATA}}
        {{KEY}}: {{VALUE}},
        {{/each}}
      });
      expect(result.success).toBe(true);
    });

    {{#each STEP_1_INVALID_CASES}}
    it('rejects when {{FIELD}} is {{CONDITION}}', () => {
      const result = step{{STEP_1_NAME}}Schema.safeParse({ {{FIELD}}: {{VALUE}} });
      expect(result.success).toBe(false);
      if (!result.success) {
        expect(result.error.flatten().fieldErrors.{{FIELD}}).toBeDefined();
      }
    });
    {{/each}}
  });

  describe('{{entity}}FormSchema (full)', () => {
    it('requires all step data to be valid', () => {
      const result = {{entity}}FormSchema.safeParse({});
      expect(result.success).toBe(false);
    });
  });
});
```

### Step Navigation Tests

```typescript
// frontend/src/presentation/{{context}}/forms/{{entity}}/steps/Step{{STEP_1_NAME}}.test.tsx
import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { Step{{STEP_1_NAME}} } from './Step{{STEP_1_NAME}}';
import { {{Entity}}FormContext } from '@/application/{{context}}/form-context';
import type { {{Entity}}FormContextType } from '@/application/{{context}}/form-context';
import { FORM_STEPS } from '@/domain/{{context}}/types';

function makeContext(overrides: Partial<{{Entity}}FormContextType> = {}): {{Entity}}FormContextType {
  return {
    state: {
      currentStep: FORM_STEPS[0],
      completedSteps: new Set(),
      formData: {},
    },
    goToStep: vi.fn(),
    goNext: vi.fn(),
    goPrev: vi.fn(),
    updateData: vi.fn(),
    isStepComplete: () => false,
    canNavigateTo: () => true,
    files: [],
    addFile: vi.fn(),
    removeFile: vi.fn(),
    ...overrides,
  };
}

describe('Step{{STEP_1_NAME}}', () => {
  it('renders all required fields', () => {
    const ctx = makeContext();
    render(
      <{{Entity}}FormContext value={ctx}>
        <Step{{STEP_1_NAME}} />
      </{{Entity}}FormContext>,
    );

    {{#each STEP_1_FIELDS}}
    expect(screen.getByLabelText('{{LABEL}}')).toBeInTheDocument();
    {{/each}}
  });

  it('shows validation errors when submitting empty form', async () => {
    const ctx = makeContext();
    render(
      <{{Entity}}FormContext value={ctx}>
        <Step{{STEP_1_NAME}} />
      </{{Entity}}FormContext>,
    );

    fireEvent.click(screen.getByRole('button', { name: /next/i }));

    await waitFor(() => {
      expect(ctx.goNext).not.toHaveBeenCalled();
    });
  });

  it('calls updateData and goNext with valid input', async () => {
    const ctx = makeContext();
    render(
      <{{Entity}}FormContext value={ctx}>
        <Step{{STEP_1_NAME}} />
      </{{Entity}}FormContext>,
    );

    {{#each STEP_1_FIELDS}}
    fireEvent.change(screen.getByLabelText('{{LABEL}}'), {
      target: { value: '{{TEST_VALUE}}' },
    });
    {{/each}}

    fireEvent.click(screen.getByRole('button', { name: /next/i }));

    await waitFor(() => {
      expect(ctx.updateData).toHaveBeenCalled();
      expect(ctx.goNext).toHaveBeenCalledOnce();
    });
  });
});
```

### Submission Flow Tests

```typescript
// frontend/src/presentation/{{context}}/forms/{{entity}}/submission.test.tsx
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor, act } from '@testing-library/react';
import { {{Entity}}FormProvider } from './{{Entity}}FormProvider';
import { {{Entity}}FormWizard } from './{{Entity}}FormWizard';
import * as actions from '@/application/{{context}}/actions';

vi.mock('@/application/{{context}}/actions', () => ({
  submit{{Entity}}Form: vi.fn(),
}));

describe('{{Entity}}FormWizard submission flow', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('shows success state after successful submission', async () => {
    vi.mocked(actions.submit{{Entity}}Form).mockResolvedValue({
      success: true,
      {{entity}}Id: 'test-id' as import('@/domain/{{context}}/types').{{Entity}}Id,
      error: null,
      fieldErrors: null,
    });

    render(
      <{{Entity}}FormProvider>
        <{{Entity}}FormWizard />
      </{{Entity}}FormProvider>,
    );

    // Navigate through all steps and submit
    // ... fill steps per your actual field structure

    await waitFor(() => {
      expect(screen.getByRole('status')).toHaveTextContent('{{SUCCESS_MESSAGE}}');
    });
  });

  it('displays server error on failure', async () => {
    vi.mocked(actions.submit{{Entity}}Form).mockResolvedValue({
      success: false,
      {{entity}}Id: null,
      error: 'Server error',
      fieldErrors: null,
    });

    render(
      <{{Entity}}FormProvider>
        <{{Entity}}FormWizard />
      </{{Entity}}FormProvider>,
    );

    // ... trigger submission

    await waitFor(() => {
      expect(screen.getByRole('alert')).toHaveTextContent('Server error');
    });
  });

  it('persists draft to localStorage between renders', () => {
    const { unmount } = render(
      <{{Entity}}FormProvider>
        <{{Entity}}FormWizard />
      </{{Entity}}FormProvider>,
    );

    // Simulate data entry and wait for debounced save
    // ... interact with fields

    unmount();

    // Re-mount and verify draft is restored
    render(
      <{{Entity}}FormProvider>
        <{{Entity}}FormWizard />
      </{{Entity}}FormProvider>,
    );

    // ... assert fields pre-filled from draft
  });
});
```

## Entry Point

```tsx
// frontend/src/presentation/{{context}}/forms/{{entity}}/index.ts
export { {{Entity}}FormProvider } from './{{Entity}}FormProvider';
export { {{Entity}}FormWizard } from './{{Entity}}FormWizard';
export { {{Entity}}FormProgress } from './{{Entity}}FormProgress';
export { {{Entity}}FormErrorBoundary } from './{{Entity}}FormErrorBoundary';
```

## Validation Commands

```bash
npm run typecheck
npm run test -- --filter={{entity}}
npm run lint
```

## React 19 Patterns Used

| Pattern | Location | Purpose |
|---|---|---|
| `useActionState` | `{{Entity}}FormWizard` | Server action state + pending tracking |
| `useOptimistic` | `{{Entity}}FormWizard` | Instant success UI before server confirms |
| `useTransition` | `{{Entity}}FormWizard` | Non-blocking submit, keeps UI responsive |
| Context with `use()` | `form-context.ts` | Compound component field access |
| Server Actions | `actions.ts` | Type-safe form submission without API routes |

## Do NOT

- Use `any` — Zod inference gives you exact types
- Use non-null assertion (`!`) — handle null with early returns or optional chaining
- Use default exports — named exports only for tree-shaking and refactor safety
- Mutable properties — all interfaces use `readonly`
- Skip `aria-invalid` / `aria-describedby` on inputs — required for screen reader error association
- Call `URL.createObjectURL` without a corresponding `URL.revokeObjectURL` on removal — memory leak
- Persist sensitive data in localStorage draft — only persist non-sensitive form state
- Skip the `{{Entity}}FormErrorBoundary` wrapper on steps — async step renders can throw
