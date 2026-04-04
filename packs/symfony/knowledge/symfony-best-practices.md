# Symfony Best Practices

## Project Structure

Follow default flat structure: `src/`, `config/`, `templates/`, `tests/`, `public/`, `var/`, `migrations/`.

## Configuration Hierarchy

| Type | Use For | Where |
|------|---------|-------|
| Environment variables | Infrastructure (DB, APIs) | `.env` files |
| Secrets | Sensitive data (keys, tokens) | Symfony secrets vault |
| Parameters | App behavior (features, emails) | `config/services.yaml` |
| Constants | Rarely-changing values | PHP class constants |

Prefix parameters with `app.`: `app.contents_dir`, not `dir`.

## Services

- **Autowiring + autoconfiguration** by default
- **All services private** — no `$container->get()`
- **No custom bundles** — use PHP namespaces for organization
- YAML for service configuration

## Controllers

```php
#[Route('/posts/{id}', name: 'post_show')]
public function show(Post $post, PostRepository $repo): Response
{
    // Extend AbstractController for shortcuts
    // Use attributes for routing, caching, security
    // Inject dependencies via constructor or method args
}
```

## Forms

- Define as PHP classes (`PostType extends AbstractType`)
- Add buttons in templates, not form classes
- **Validation on entities/DTOs**, not form fields — enables reuse
- Single action for render + process

## Security

- **Single firewall** — one entry point, multiple authenticators
- `password_hashers: auto` — bcrypt by default
- **Voters** for complex authorization logic, not security expressions

## Doctrine

- PHP attributes for entity mapping
- Repositories extend `ServiceEntityRepository`
- Always use migrations for schema changes

## Testing

- **Smoke test all URLs** with `DataProvider`
- **Hard-code URLs** in functional tests (don't generate from routes)
- Tests reveal broken routes and force redirect management

## Anti-Patterns

| Anti-Pattern | Instead |
|-------------|---------|
| `$container->get()` | Constructor injection |
| Custom bundles for app code | PHP namespaces |
| XML/PHP service config | YAML |
| Validation in form types | Validation on entities |
| Security expressions for complex logic | Voters |
| Generated URLs in tests | Hard-coded URLs |
