# Anti-Pattern: Inline / Nested Component Definitions

Source: https://github.com/vercel-labs/agent-skills/blob/main/skills/react-best-practices/AGENTS.md (Rule 5.4)

## Problem

Defining a component inside another component causes React to treat it as a **new component type on every render**. This forces full unmount+remount instead of re-render, destroying state and breaking animations.

```tsx
// ❌ BAD — ListItem is recreated on every render of List
function List({ items }: { readonly items: readonly string[] }): ReactNode {
  // This function is a NEW reference every render
  function ListItem({ text }: { readonly text: string }): ReactNode {
    const [hovered, setHovered] = useState(false); // State lost on every List render
    return (
      <li onMouseEnter={() => setHovered(true)} className={hovered ? 'bg-muted' : ''}>
        {text}
      </li>
    );
  }

  return (
    <ul>
      {items.map((item) => (
        <ListItem key={item} text={item} />
      ))}
    </ul>
  );
}
```

## Why It Breaks

React identifies components by their **reference**. On every `List` render, `ListItem` is a new function reference. React sees an unknown component type, unmounts the old one, and mounts a fresh one — losing all internal state.

## Solution

Define all components **at module level** and pass data as props.

```tsx
// ✅ GOOD — ListItem is defined once, at module level
interface ListItemProps {
  readonly text: string;
}

function ListItem({ text }: ListItemProps): ReactNode {
  const [hovered, setHovered] = useState(false); // State preserved correctly
  return (
    <li onMouseEnter={() => setHovered(true)} className={hovered ? 'bg-muted' : ''}>
      {text}
    </li>
  );
}

function List({ items }: { readonly items: readonly string[] }): ReactNode {
  return (
    <ul>
      {items.map((item) => (
        <ListItem key={item} text={item} />
      ))}
    </ul>
  );
}
```

## Symptoms

- Component state resets unexpectedly on parent re-render
- Animations restart from beginning on each update
- Focus is lost after every keystroke in an input inside the nested component
- Performance profiler shows repeated mount/unmount cycles

## Detection

```bash
# Find function declarations or arrow functions inside component bodies
# Look for `function` or `const X = (` inside another component function body
grep -rn "function.*): ReactNode" src --include="*.tsx" -A 20 | grep -B 5 "function "
```

## Exception

Render functions used as immediate JSX children (not assigned to a variable) are fine for simple cases, but prefer extraction to a named component for anything with state or complexity.
