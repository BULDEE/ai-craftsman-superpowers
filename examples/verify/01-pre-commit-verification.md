# Example: Pre-Commit Verification

## Prompt

```
/craftsman:verify
I just finished the invoice PDF generation feature. Ready to commit.
```

## Expected Behavior

### Phase 1: Evidence Collection

```markdown
## Verification Checklist

### Code Quality
- [x] All modified files have `declare(strict_types=1)`
- [x] All classes are `final`
- [x] No `any` types in TypeScript files
- [ ] PHPStan level 8 passes -- **2 errors found**

### Tests
- [x] New tests added for `GenerateInvoicePdfHandler`
- [x] Test coverage on modified files: 87%
- [ ] Integration test for PDF output -- **missing**

### Architecture
- [x] No domain layer importing infrastructure
- [x] Command/Query separation respected
- [x] Value Objects used for Money and InvoiceId

### Git Hygiene
- [x] No unrelated changes in diff
- [x] No debug statements (`dump()`, `console.log`)
- [x] No credentials or secrets in staged files
```

### Phase 2: Blockers Report

```markdown
## Blockers

### PHPStan Errors (2)
1. `src/Infrastructure/Pdf/DompdfGenerator.php:42` -- Parameter `$html` expects `string`, `string|null` given
2. `src/Infrastructure/Pdf/DompdfGenerator.php:58` -- Method `output()` return type missing

### Missing Test
- No integration test verifying the generated PDF content matches the invoice data
- Recommended: test with a known invoice fixture, assert PDF contains expected strings

## Verdict: NOT READY

Fix the 2 PHPStan errors and add the integration test before committing.
```

### Phase 3: After Fixes

```markdown
## Re-verification

- [x] PHPStan level 8 passes (0 errors)
- [x] Integration test added: `GenerateInvoicePdfIntegrationTest`
- [x] All 47 tests pass

## Verdict: READY TO COMMIT
```

## Test This Example

1. Open Claude Code after completing a feature
2. Run `/craftsman:verify`
3. Describe what you finished
4. Verify Claude checks code quality, tests, architecture, and git hygiene before giving a verdict
