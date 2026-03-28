// CANONICAL EXAMPLE: Compound Component pattern (React 19) (v1.0)
//
// This is THE reference for Compound Components.
// Uses React 19's `use(Context)` hook instead of useContext.
//
// Key characteristics:
// - Context with null-check guard (MUST)
// - useXxx() hook for context access — throws if used outside provider (MUST)
// - readonly properties on all interfaces (MUST per TS rules)
// - Named exports only (MUST per TS rules)
// - No default exports (MUST per TS rules)
// - "use client" only if interactivity needed
'use client';

import { createContext, use, useState, type ReactNode } from 'react';

// --- Types ---

interface AccordionContextType {
  readonly openItems: ReadonlySet<string>;
  readonly toggle: (id: string) => void;
}

interface AccordionProps {
  readonly children: ReactNode;
  readonly allowMultiple?: boolean;
}

interface AccordionItemProps {
  readonly id: string;
  readonly title: string;
  readonly children: ReactNode;
}

// --- Context ---

const AccordionContext = createContext<AccordionContextType | null>(null);

// Internal hook — throws on misuse, removes null-check boilerplate from consumers
function useAccordion(): AccordionContextType {
  const context = use(AccordionContext);
  if (context === null) {
    throw new Error('AccordionItem must be used within an Accordion');
  }
  return context;
}

// --- Components ---

export function Accordion({ children, allowMultiple = false }: AccordionProps) {
  const [openItems, setOpenItems] = useState<ReadonlySet<string>>(new Set());

  function toggle(id: string) {
    setOpenItems(prev => {
      // allowMultiple=false → clear all others first
      const next = new Set(allowMultiple ? prev : []);
      if (prev.has(id)) {
        next.delete(id);
      } else {
        next.add(id);
      }
      return next;
    });
  }

  return (
    <AccordionContext value={{ openItems, toggle }}>
      <div role="tablist">{children}</div>
    </AccordionContext>
  );
}

export function AccordionItem({ id, title, children }: AccordionItemProps) {
  const { openItems, toggle } = useAccordion();
  const isOpen = openItems.has(id);

  return (
    <div>
      <button
        role="tab"
        aria-expanded={isOpen}
        onClick={() => toggle(id)}
      >
        {title}
      </button>
      {isOpen && (
        <div role="tabpanel">
          {children}
        </div>
      )}
    </div>
  );
}

// --- Usage example (comment only, not exported) ---
//
// <Accordion allowMultiple>
//   <AccordionItem id="shipping" title="Shipping">...</AccordionItem>
//   <AccordionItem id="returns" title="Returns">...</AccordionItem>
// </Accordion>
