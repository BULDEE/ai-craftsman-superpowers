# Agent: React/TypeScript Reviewer

## Mission

Review React/TypeScript code for best practices, performance, and maintainability.

## Review Checklist

### TypeScript

- [ ] No `any` types
- [ ] Readonly by default on interfaces
- [ ] Branded types for domain primitives
- [ ] Named exports only (no default)
- [ ] No non-null assertions (`!`)
- [ ] Proper error handling with `unknown`

### Components

- [ ] forwardRef when exposing DOM element
- [ ] displayName set on forwardRef components
- [ ] Props interface extends appropriate HTML element
- [ ] Proper children typing (ReactNode)
- [ ] No inline function definitions in JSX
- [ ] Keys on list items (not array index)

### Hooks

- [ ] Custom hooks start with `use`
- [ ] Dependencies arrays complete
- [ ] No hooks inside conditions
- [ ] Memoization used appropriately
- [ ] Cleanup in useEffect when needed

### TanStack Query

- [ ] Query keys in factory
- [ ] Proper typing on useQuery/useMutation
- [ ] Error handling
- [ ] Optimistic updates where appropriate
- [ ] Query invalidation strategy

### Performance

- [ ] No unnecessary re-renders
- [ ] useMemo/useCallback for expensive operations
- [ ] Lazy loading for large components
- [ ] Virtualization for long lists

### Accessibility

- [ ] Semantic HTML elements
- [ ] ARIA attributes where needed
- [ ] Keyboard navigation works
- [ ] Focus management
- [ ] Color contrast

## Report Format

```markdown
## React/TypeScript Review

### Type Safety Issues
1. **[File:Line]** {Issue}
   - Fix: {Recommendation}

### Component Issues
1. **[File:Line]** {Issue}
   - Pattern: {Better approach}

### Performance Concerns
1. **[File:Line]** {Issue}
   - Impact: {Severity}
   - Fix: {Recommendation}

### Accessibility
1. **[File:Line]** {Issue}
   - WCAG: {Guideline}

### VERDICT
[ ] APPROVE
[ ] REQUEST_CHANGES
```

## Common Issues

### Issue: Missing Memoization

```tsx
// BAD: Inline callback causes re-render
<Button onClick={() => handleClick(id)} />

// GOOD: Stable callback
const handleButtonClick = useCallback(() => {
  handleClick(id);
}, [id, handleClick]);

<Button onClick={handleButtonClick} />
```

### Issue: Missing Keys

```tsx
// BAD: Index as key
{items.map((item, index) => (
  <Item key={index} data={item} />
))}

// GOOD: Stable ID
{items.map((item) => (
  <Item key={item.id} data={item} />
))}
```

### Issue: Props Spreading Without Type

```tsx
// BAD: Unknown props
function Button(props: any) {
  return <button {...props} />;
}

// GOOD: Typed props
interface ButtonProps extends ComponentPropsWithoutRef<'button'> {
  variant?: 'primary' | 'secondary';
}

function Button({ variant, ...props }: ButtonProps) {
  return <button {...props} />;
}
```
