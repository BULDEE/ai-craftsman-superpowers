/**
 * CANONICAL EXAMPLE: Compound Component Pattern (v1.0)
 *
 * Source: https://react.dev/reference/react/use (use() for context)
 *         https://react.dev/reference/react/createContext
 *
 * Key characteristics:
 * - createContext + use(Context) — React 19 modern pattern
 * - use(Context) preferred over useContext(): works in conditionals/loops
 * - Named exports only (no default export)
 * - readonly props throughout
 * - No any types
 * - Sub-components access shared state via context, not prop drilling
 */

import { createContext, use, useState, useCallback } from 'react';
import type { ReactNode } from 'react';

// ============================================================
// Context Definition
// Source: https://react.dev/reference/react/use
// use(Context) is the React 19 replacement for useContext().
// It works inside conditionals and loops unlike useContext().
// ============================================================

interface AccordionContextValue {
  readonly openItemId: string | null;
  readonly toggle: (id: string) => void;
}

// null default means "not inside a provider" — caught at runtime
const AccordionContext = createContext<AccordionContextValue | null>(null);

// Helper to enforce provider requirement
function useAccordionContext(): AccordionContextValue {
  // use() can be called inside conditionals/loops — unlike useContext()
  const context = use(AccordionContext);
  if (context === null) {
    throw new Error('useAccordionContext must be used within <Accordion>');
  }
  return context;
}

// ============================================================
// Root Component
// ============================================================

interface AccordionProps {
  readonly children: ReactNode;
  readonly defaultOpenId?: string;
  readonly className?: string;
}

export function Accordion({
  children,
  defaultOpenId = null,
  className,
}: AccordionProps): ReactNode {
  const [openItemId, setOpenItemId] = useState<string | null>(defaultOpenId);

  const toggle = useCallback((id: string) => {
    setOpenItemId((current) => (current === id ? null : id));
  }, []);

  return (
    <AccordionContext value={{ openItemId, toggle }}>
      <div className={className}>{children}</div>
    </AccordionContext>
  );
}

// ============================================================
// Item Component
// ============================================================

interface AccordionItemProps {
  readonly id: string;
  readonly children: ReactNode;
  readonly className?: string;
}

export function AccordionItem({
  id,
  children,
  className,
}: AccordionItemProps): ReactNode {
  return (
    <div className={`border-b ${className ?? ''}`} data-item-id={id}>
      {children}
    </div>
  );
}

// ============================================================
// Trigger Component — reads context, NOT passed as prop
// ============================================================

interface AccordionTriggerProps {
  readonly itemId: string;
  readonly children: ReactNode;
  readonly className?: string;
}

export function AccordionTrigger({
  itemId,
  children,
  className,
}: AccordionTriggerProps): ReactNode {
  const { openItemId, toggle } = useAccordionContext();
  const isOpen = openItemId === itemId;

  return (
    <button
      type="button"
      onClick={() => toggle(itemId)}
      aria-expanded={isOpen}
      className={`flex w-full items-center justify-between py-4 font-medium ${className ?? ''}`}
    >
      {children}
      <ChevronIcon isOpen={isOpen} />
    </button>
  );
}

// ============================================================
// Content Component — conditionally rendered
// ============================================================

interface AccordionContentProps {
  readonly itemId: string;
  readonly children: ReactNode;
  readonly className?: string;
}

export function AccordionContent({
  itemId,
  children,
  className,
}: AccordionContentProps): ReactNode {
  // use(Context) CAN be called inside conditionals — but the hook itself
  // must be called unconditionally. The conditional is on the result.
  const { openItemId } = useAccordionContext();
  const isOpen = openItemId === itemId;

  if (!isOpen) {
    return null;
  }

  return (
    <div
      role="region"
      className={`pb-4 text-sm ${className ?? ''}`}
    >
      {children}
    </div>
  );
}

// ============================================================
// Usage Example
// ============================================================

/*
  // Clean, readable — no prop drilling
  <Accordion defaultOpenId="item-1">
    <AccordionItem id="item-1">
      <AccordionTrigger itemId="item-1">What is React?</AccordionTrigger>
      <AccordionContent itemId="item-1">
        React is a library for building user interfaces.
      </AccordionContent>
    </AccordionItem>

    <AccordionItem id="item-2">
      <AccordionTrigger itemId="item-2">What is TypeScript?</AccordionTrigger>
      <AccordionContent itemId="item-2">
        TypeScript is a typed superset of JavaScript.
      </AccordionContent>
    </AccordionItem>
  </Accordion>
*/

// ============================================================
// Internal helpers (not exported)
// ============================================================

function ChevronIcon({ isOpen }: { readonly isOpen: boolean }): ReactNode {
  return (
    <svg
      className={`h-4 w-4 transition-transform ${isOpen ? 'rotate-180' : ''}`}
      fill="none"
      stroke="currentColor"
      viewBox="0 0 24 24"
    >
      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
    </svg>
  );
}
