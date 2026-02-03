# Anti-Pattern: Prop Drilling

## What It Is

Passing props through multiple component layers to reach a deeply nested component.

## Why It's Bad

- Makes components tightly coupled
- Hard to refactor (changing prop affects all layers)
- Clutters intermediate components
- Makes code hard to follow

## Example

### BAD: Prop Drilling

```tsx
// Props passed through 4 layers just to reach UserAvatar

function App() {
  const user = useUser();
  return <Dashboard user={user} />;
}

function Dashboard({ user }: { user: User }) {
  return (
    <div>
      <Header user={user} />
      <Content user={user} />
    </div>
  );
}

function Header({ user }: { user: User }) {
  return (
    <header>
      <Logo />
      <Navigation user={user} />
    </header>
  );
}

function Navigation({ user }: { user: User }) {
  return (
    <nav>
      <Links />
      <UserAvatar user={user} /> {/* Finally used here! */}
    </nav>
  );
}

function UserAvatar({ user }: { user: User }) {
  return <img src={user.avatarUrl} alt={user.name} />;
}
```

### GOOD: Context for Shared State

```tsx
// Create context for user
const UserContext = createContext<User | null>(null);

function useCurrentUser() {
  const user = useContext(UserContext);
  if (!user) throw new Error('User not found');
  return user;
}

// Provide at top level
function App() {
  const user = useUser();
  return (
    <UserContext.Provider value={user}>
      <Dashboard />
    </UserContext.Provider>
  );
}

// Intermediate components don't need the prop
function Dashboard() {
  return (
    <div>
      <Header />
      <Content />
    </div>
  );
}

function Header() {
  return (
    <header>
      <Logo />
      <Navigation />
    </header>
  );
}

function Navigation() {
  return (
    <nav>
      <Links />
      <UserAvatar /> {/* Gets user from context */}
    </nav>
  );
}

// Consumer uses context
function UserAvatar() {
  const user = useCurrentUser();
  return <img src={user.avatarUrl} alt={user.name} />;
}
```

### GOOD: Composition Pattern

```tsx
// Pass the component itself, not the data

function App() {
  const user = useUser();
  return (
    <Dashboard
      header={<Header avatar={<UserAvatar user={user} />} />}
    />
  );
}

function Dashboard({ header }: { header: ReactNode }) {
  return (
    <div>
      {header}
      <Content />
    </div>
  );
}

function Header({ avatar }: { avatar: ReactNode }) {
  return (
    <header>
      <Logo />
      <Navigation />
      {avatar}
    </header>
  );
}
```

## When Prop Drilling is OK

1. **2 levels max** - Parent → Child → Grandchild is acceptable
2. **Component-specific data** - Data only used by that subtree
3. **Explicit dependencies** - When you want to see the data flow

## Solutions by Use Case

| Use Case | Solution |
|----------|----------|
| Global state (user, theme) | Context |
| Server state | TanStack Query |
| Form state | React Hook Form |
| Complex UI state | Zustand/Jotai |
| Component composition | children/render props |

## How to Detect

1. Same prop passed through 3+ components
2. Intermediate components don't use the prop
3. Adding a prop requires changing many files
4. Props list getting long in intermediate components
