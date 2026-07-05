/**
 * CANONICAL EXAMPLE: SOLID Principles in TypeScript/React (v1.0)
 *
 * One idiomatic demonstration per principle. See knowledge/principles.md
 * for the theory and the cross-language mapping table.
 */

/* =============================================================================
 * S - Single Responsibility Principle
 * A component renders; it does not fetch, format, and own business rules too.
 * Extract data-fetching into a hook and formatting into a pure function.
 * ========================================================================== */

// Good: the component only renders; the hook owns fetching, the util owns format.
function useOrders(customerId: CustomerId): readonly Order[] {
  /* fetching lives here, not in the component */ return [];
}
const formatTotal = (cents: number): string => `${(cents / 100).toFixed(2)} EUR`;

/* =============================================================================
 * O - Open/Closed Principle
 * Add a variant without editing existing code. A registry of renderers beats
 * a growing switch on `type`.
 * ========================================================================== */

type NoticeKind = "info" | "warning" | "error";
const NOTICE_RENDERERS: Readonly<Record<NoticeKind, (msg: string) => JSX.Element>> = {
  info: (msg) => <p className="info">{msg}</p>,
  warning: (msg) => <p className="warn">{msg}</p>,
  error: (msg) => <p className="error">{msg}</p>,
};
// Adding a "success" notice = one new entry, no existing branch touched.

/* =============================================================================
 * L - Liskov Substitution Principle
 * Any component accepted as a ButtonLike must honor the same contract; a variant
 * that silently ignores onClick would break every caller that relies on it.
 * ========================================================================== */

interface ButtonLike {
  readonly label: string;
  readonly onClick: () => void;
  readonly disabled?: boolean;
}
const PrimaryButton = ({ label, onClick, disabled }: ButtonLike): JSX.Element => (
  <button className="primary" onClick={onClick} disabled={disabled}>{label}</button>
);

/* =============================================================================
 * I - Interface Segregation Principle
 * Components take narrow props, not a god-object. A read-only row needs only the
 * fields it renders, not the entire domain entity plus every handler.
 * ========================================================================== */

// Bad: <UserRow user={fullUserAggregate} onEdit onDelete onArchive ... />
// Good: pass exactly what this view needs.
interface UserRowProps {
  readonly name: string;
  readonly email: string;
}
const UserRow = ({ name, email }: UserRowProps): JSX.Element => (
  <tr><td>{name}</td><td>{email}</td></tr>
);

/* =============================================================================
 * D - Dependency Inversion Principle
 * High-level components depend on an abstraction (an injected client / context),
 * not on a concrete fetch implementation. This makes them testable with a fake.
 * ========================================================================== */

interface OrderGateway {
  list(customerId: CustomerId): Promise<readonly Order[]>;
}
// The component receives the gateway via props or context; tests inject a fake.
interface OrderListProps {
  readonly gateway: OrderGateway;
  readonly customerId: CustomerId;
}

// --- placeholder domain types so the example type-checks in isolation ---
type CustomerId = string & { readonly __brand: "CustomerId" };
interface Order {
  readonly id: string;
  readonly totalCents: number;
}
