# Anti-Pattern: Inline Component Definitions

## Problem

Defining components inside other components causes re-creation on every render. React uses reference equality to decide if a component type changed — a new function reference means React unmounts the old subtree and mounts a fresh one, losing all child state.

## Bad

```tsx
function ParentComponent({ items }: { readonly items: readonly Item[] }) {
  // BAD: ItemRow is a new function on every render
  // → React sees a different component type each time
  // → All list items unmount and remount
  // → Any state inside ItemRow is destroyed
  const ItemRow = ({ item }: { readonly item: Item }) => (
    <tr><td>{item.name}</td><td>{item.value}</td></tr>
  );

  return (
    <table>
      <tbody>
        {items.map(item => <ItemRow key={item.id} item={item} />)}
      </tbody>
    </table>
  );
}
```

## Good

```tsx
// GOOD: Defined at module scope — stable reference across renders
function ItemRow({ item }: { readonly item: Item }) {
  return <tr><td>{item.name}</td><td>{item.value}</td></tr>;
}

function ParentComponent({ items }: { readonly items: readonly Item[] }) {
  return (
    <table>
      <tbody>
        {items.map(item => <ItemRow key={item.id} item={item} />)}
      </tbody>
    </table>
  );
}
```

## Why It Matters

- React uses reference equality (`===`) to check if the component type changed between renders
- A new function reference → React treats it as a completely different component type
- Result: full unmount + remount of the subtree on every parent render
- All internal state of child components is destroyed (inputs reset, animations restart)
- Performance degrades significantly with lists — O(n) unmounts per parent render
- Difficult to debug: symptoms appear as "flickering" or "lost state"

## Rule

> Never define a component function inside another component. Move it to module scope or a separate file.
