# Brutal Evaluation Prompt - AI-Craftsman-Superpowers

## Instructions for the Evaluator

You are a **cynical Senior Staff Engineer with 20 years of experience** who has seen dozens of "revolutionary frameworks" that never delivered on their promises. You evaluate the `ai-craftsman-superpowers` plugin with maximum skepticism.

**Your job**: Find ALL flaws, inconsistencies, marketing bullshit, and real limitations. No complacency. No politeness. Just the brutal truth.

---

## PHASE 1: Smoke Test (Do the skills work?)

Execute each skill and note failures:

```
TEST 1.1: /design
> /design
I want to create a push notification system for a mobile app.

EVALUATE:
- [ ] Does it ask questions BEFORE coding? (Phase 1: Understand)
- [ ] Does it propose alternatives? (Phase 2: Challenge)
- [ ] Are trade-offs explicit?
- [ ] Does it wait for confirmation before coding?
- [ ] Does the generated code respect the announced DDD patterns?

VERDICT: PASS / FAIL / PARTIAL
NOTES: _______________
```

```
TEST 1.2: /debug
> /debug
I have a memory leak in my Node.js application.
The heap increases by 50MB every hour.
No error messages.

EVALUATE:
- [ ] Does it follow the ReAct pattern? (Hypothesis → Action → Observation)
- [ ] Does it ask diagnostic questions?
- [ ] Does it avoid proposing fixes without investigation?
- [ ] Does it identify a root cause before suggesting?

VERDICT: PASS / FAIL / PARTIAL
NOTES: _______________
```

```
TEST 1.3: /plan
> /plan
I need to migrate a monolithic REST API to microservices.
The API has 45 endpoints, 3 databases, and 200k active users.

EVALUATE:
- [ ] Are tasks < 5 min each?
- [ ] Are dependencies identified?
- [ ] Are risks documented?
- [ ] Is the plan realistic or generic bullshit?

VERDICT: PASS / FAIL / PARTIAL
NOTES: _______________
```

```
TEST 1.4: /plan --execute
> /plan --execute [use the previous plan]

EVALUATE:
- [ ] Does it execute in batches with checkpoints?
- [ ] Does it ask for validation between batches?
- [ ] Does it handle errors properly?

VERDICT: PASS / FAIL / PARTIAL
NOTES: _______________
```

```
TEST 1.5: /challenge
> /challenge
[Provide intentionally bad code with:]
- Infrastructure import in Domain
- God class of 500 lines
- Public setters everywhere
- No tests

EVALUATE:
- [ ] Does it detect ALL problems?
- [ ] Does it categorize them correctly (BLOCKING/MUST FIX/IMPROVE)?
- [ ] Is the verdict appropriate?

VERDICT: PASS / FAIL / PARTIAL
NOTES: _______________
```

```
TEST 1.6: /verify
> /verify
[After "fixing" something]

EVALUATE:
- [ ] Does it actually execute verification commands?
- [ ] Does it show real output (not "tests should pass")?
- [ ] Does it refuse to confirm without evidence?

VERDICT: PASS / FAIL / PARTIAL
NOTES: _______________
```

```
TEST 1.7: /parallel
> /parallel
I have 4 tasks:
1. Refactor UserService
2. Add tests to OrderService
3. Migrate config from YAML to ENV
4. Update npm dependencies

EVALUATE:
- [ ] Does it correctly analyze dependencies?
- [ ] Does it identify what can be parallelized?
- [ ] Does it actually dispatch agents in parallel?

VERDICT: PASS / FAIL / PARTIAL
NOTES: _______________
```

```
TEST 1.8: /git worktree
> /git worktree
I want to work on feature/payment-v2 in isolation.

EVALUATE:
- [ ] Does it propose a smart location?
- [ ] Does it check preconditions (uncommitted changes, etc.)?
- [ ] Does it actually create the worktree?

VERDICT: PASS / FAIL / PARTIAL
NOTES: _______________
```

---

## PHASE 2: Stress Tests (The limits)

```
TEST 2.1: DELIBERATE CONTRADICTION
> /design
Create a User entity with public setters for all fields.
I want to be able to modify the email directly.

EVALUATE:
- [ ] Does it resist the anti-pattern request?
- [ ] Does it explain why it's problematic?
- [ ] Does it propose an alternative?
- [ ] Does it give in too easily?

VERDICT: _______________
```

```
TEST 2.2: VAGUE REQUEST
> /design
I need something to manage users.

EVALUATE:
- [ ] Does it ask for clarifications?
- [ ] Does it refuse to code without context?
- [ ] Or does it generate useless generic code?

VERDICT: _______________
```

```
TEST 2.3: SCOPE CREEP
> /design
[Start with a simple request, then add:]
"And while we're at it, add role management"
"And permissions"
"And audit log"
"And multi-tenant"

EVALUATE:
- [ ] Does it detect scope creep?
- [ ] Does it warn (bias protection)?
- [ ] Or does it accept everything without pushback?

VERDICT: _______________
```

```
TEST 2.4: DANGEROUS ACCELERATION
> Implement a payment system quickly, I don't have time for design.

EVALUATE:
- [ ] Does it resist pressure?
- [ ] Does it insist on the /design process?
- [ ] Or does it code blindly?

VERDICT: _______________
```

```
TEST 2.5: FALSE EXPERTISE
> /debug
My API is slow. Fix it.
[Without giving any metrics, any context]

EVALUATE:
- [ ] Does it ask for metrics?
- [ ] Does it refuse to "fix" without diagnosis?
- [ ] Or does it propose generic random optimizations?

VERDICT: _______________
```

---

## PHASE 3: Inter-Skills Coherence

```
TEST 3.1: COMPLETE WORKFLOW
Execute the complete workflow on a real case:
/plan → /design → /spec → [implement] → /challenge → /verify → /git

EVALUATE:
- [ ] Do the skills complement each other?
- [ ] Are there contradictions between skills?
- [ ] Is the handoff smooth?
- [ ] Is the final result coherent?

NOTES: _______________
```

```
TEST 3.2: KNOWLEDGE BASE
Verify that skills actually use the knowledge base:

> Show me an example of an Entity according to project patterns

EVALUATE:
- [ ] Does it reference knowledge/patterns.md?
- [ ] Does the code follow canonical examples?
- [ ] Or does it generate generic code?

NOTES: _______________
```

---

## PHASE 4: Honest Comparison

### vs Vanilla Claude (without plugin)

Ask the same question with and without the plugin:

```
QUESTION: "Create an Order entity for e-commerce"

WITHOUT PLUGIN:
- Response time: ___
- Code quality: ___
- Questions asked: ___
- Patterns respected: ___

WITH PLUGIN:
- Response time: ___
- Code quality: ___
- Questions asked: ___
- Patterns respected: ___

REAL DIFFERENCE: _______________
```

### vs GitHub Copilot / Cursor

```
SAME TASK WITH COPILOT:
- Result: ___
- Notable difference: ___

DOES THE PLUGIN REALLY BRING MORE? YES / NO / MARGINAL
```

---

## PHASE 5: Killer Questions

Answer honestly:

1. **Does the plugin solve a real problem or create artificial complexity?**

2. **Would a junior REALLY be more productive with this plugin or just more confused?**

3. **Are the skills usable in real conditions (deadline, pressure) or too heavy?**

4. **Does "bias protection" really work or is it theater?**

5. **Is the ROI positive? (Learning time vs time saved)**

6. **What is critically missing?**

7. **What is superfluous and should be removed?**

8. **Would the plugin survive a week of intensive use or would it be abandoned?**

---

## PHASE 6: Final Verdict

```
┌─────────────────────────────────────────────────────────────────┐
│                    BRUTAL VERDICT                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   GLOBAL SCORE: ___/100                                         │
│                                                                 │
│   REAL STRENGTHS (not marketing):                               │
│   1. _______________                                            │
│   2. _______________                                            │
│   3. _______________                                            │
│                                                                 │
│   CRITICAL WEAKNESSES:                                          │
│   1. _______________                                            │
│   2. _______________                                            │
│   3. _______________                                            │
│                                                                 │
│   BULLSHIT DETECTED:                                            │
│   - _______________                                             │
│                                                                 │
│   RECOMMENDATION:                                               │
│   [ ] Use as-is                                                 │
│   [ ] Use with reservations                                     │
│   [ ] Significantly redo                                        │
│   [ ] Abandon                                                   │
│                                                                 │
│   JUSTIFICATION:                                                │
│   _______________________________________________               │
│   _______________________________________________               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## APPENDIX: Intentionally Bad Test Code

Use this code to test `/challenge`:

```php
<?php

namespace App\Service;

use Doctrine\ORM\EntityManagerInterface;

class UserService
{
    private $em;
    private $mailer;
    private $logger;
    private $cache;
    private $validator;
    private $eventDispatcher;
    private $security;
    private $translator;

    public function __construct(
        EntityManagerInterface $em,
        $mailer,
        $logger,
        $cache,
        $validator,
        $eventDispatcher,
        $security,
        $translator
    ) {
        $this->em = $em;
        $this->mailer = $mailer;
        $this->logger = $logger;
        $this->cache = $cache;
        $this->validator = $validator;
        $this->eventDispatcher = $eventDispatcher;
        $this->security = $security;
        $this->translator = $translator;
    }

    public function createUser($data)
    {
        $user = new \App\Entity\User();
        $user->setEmail($data['email']);
        $user->setPassword($data['password']); // Plain text!
        $user->setName($data['name']);
        $user->setStatus('active');
        $user->setCreatedAt(new \DateTime());

        // Validation
        if (strlen($data['password']) < 6) {
            throw new \Exception('Password too short');
        }

        // Check if email exists
        $existing = $this->em->getRepository(\App\Entity\User::class)
            ->findOneBy(['email' => $data['email']]);
        if ($existing) {
            throw new \Exception('Email already exists');
        }

        $this->em->persist($user);
        $this->em->flush();

        // Send email
        $this->mailer->send(
            $user->getEmail(),
            'Welcome!',
            'Welcome to our platform, ' . $user->getName()
        );

        // Log
        $this->logger->info('User created: ' . $user->getEmail());

        // Clear cache
        $this->cache->delete('users_list');

        // Dispatch event
        $this->eventDispatcher->dispatch(new \App\Event\UserCreated($user));

        return $user;
    }

    public function updateUser($id, $data)
    {
        $user = $this->em->find(\App\Entity\User::class, $id);

        if (isset($data['email'])) {
            $user->setEmail($data['email']);
        }
        if (isset($data['name'])) {
            $user->setName($data['name']);
        }
        if (isset($data['password'])) {
            $user->setPassword($data['password']);
        }
        if (isset($data['status'])) {
            $user->setStatus($data['status']);
        }

        $this->em->flush();

        return $user;
    }

    public function deleteUser($id)
    {
        $user = $this->em->find(\App\Entity\User::class, $id);
        $this->em->remove($user);
        $this->em->flush();

        $this->logger->info('User deleted: ' . $id);
        $this->cache->delete('users_list');
    }

    public function getUsers($filters = [])
    {
        $qb = $this->em->createQueryBuilder()
            ->select('u')
            ->from(\App\Entity\User::class, 'u');

        if (isset($filters['status'])) {
            $qb->where("u.status = '" . $filters['status'] . "'"); // SQL Injection!
        }

        if (isset($filters['search'])) {
            $qb->andWhere("u.name LIKE '%" . $filters['search'] . "%'"); // SQL Injection!
        }

        return $qb->getQuery()->getResult();
    }

    public function activateUser($id)
    {
        $user = $this->em->find(\App\Entity\User::class, $id);
        $user->setStatus('active');
        $this->em->flush();
    }

    public function deactivateUser($id)
    {
        $user = $this->em->find(\App\Entity\User::class, $id);
        $user->setStatus('inactive');
        $this->em->flush();
    }

    public function banUser($id, $reason)
    {
        $user = $this->em->find(\App\Entity\User::class, $id);
        $user->setStatus('banned');
        $user->setBanReason($reason);
        $this->em->flush();

        $this->mailer->send(
            $user->getEmail(),
            'Account Banned',
            'Your account has been banned. Reason: ' . $reason
        );
    }
}
```

**This code intentionally contains:**
- God class (8 dependencies, 7 methods, too many responsibilities)
- SQL Injection (2 places)
- Plain text password
- Anemic domain (setters everywhere)
- No final class
- No strict_types
- Business logic in service (not in entity)
- No Value Objects (email = string)
- No tests
- Generic Exception
- Infrastructure in Application layer

**/challenge MUST detect at least 10 of these problems.**
