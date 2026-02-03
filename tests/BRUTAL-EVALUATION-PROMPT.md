# Prompt d'Évaluation Brutale - AI-Craftsman-Superpowers

## Instructions pour l'évaluateur

Tu es un **Senior Staff Engineer cynique avec 20 ans d'expérience** qui a vu passer des dizaines de "frameworks révolutionnaires" qui n'ont jamais tenu leurs promesses. Tu évalues le plugin `ai-craftsman-superpowers` avec un scepticisme maximal.

**Ton job**: Trouver TOUTES les failles, incohérences, bullshit marketing, et limitations réelles. Pas de complaisance. Pas de politesse. Juste la vérité brutale.

---

## PHASE 1: Smoke Test (Les skills fonctionnent-ils ?)

Exécute chaque skill et note les échecs:

```
TEST 1.1: /design
> /design
Je veux créer un système de notifications push pour une app mobile.

ÉVALUER:
- [ ] Pose-t-il les questions AVANT de coder ? (Phase 1: Comprendre)
- [ ] Propose-t-il des alternatives ? (Phase 2: Challenger)
- [ ] Les trade-offs sont-ils explicites ?
- [ ] Attend-il confirmation avant de coder ?
- [ ] Le code généré respecte-t-il les patterns DDD annoncés ?

VERDICT: PASS / FAIL / PARTIAL
NOTES: _______________
```

```
TEST 1.2: /debug
> /debug
J'ai une fuite mémoire dans mon application Node.js.
Le heap augmente de 50MB toutes les heures.
Pas de message d'erreur.

ÉVALUER:
- [ ] Suit-il le pattern ReAct ? (Hypothèse → Action → Observation)
- [ ] Pose-t-il des questions de diagnostic ?
- [ ] Évite-t-il de proposer des fixes sans investigation ?
- [ ] Identifie-t-il une root cause avant de suggérer ?

VERDICT: PASS / FAIL / PARTIAL
NOTES: _______________
```

```
TEST 1.3: /plan
> /plan
Je dois migrer une API REST monolithique vers des microservices.
L'API a 45 endpoints, 3 bases de données, et 200k utilisateurs actifs.

ÉVALUER:
- [ ] Les tâches sont-elles < 5 min chacune ?
- [ ] Les dépendances sont-elles identifiées ?
- [ ] Les risques sont-ils documentés ?
- [ ] Le plan est-il réaliste ou bullshit générique ?

VERDICT: PASS / FAIL / PARTIAL
NOTES: _______________
```

```
TEST 1.4: /plan --execute
> /plan --execute [utiliser le plan précédent]

ÉVALUER:
- [ ] Exécute-t-il par batch avec checkpoints ?
- [ ] Demande-t-il validation entre les batches ?
- [ ] Gère-t-il les erreurs proprement ?

VERDICT: PASS / FAIL / PARTIAL
NOTES: _______________
```

```
TEST 1.5: /challenge
> /challenge
[Fournir un code volontairement mauvais avec:]
- Import Infrastructure dans Domain
- God class de 500 lignes
- Setters publics partout
- Aucun test

ÉVALUER:
- [ ] Détecte-t-il TOUS les problèmes ?
- [ ] Les catégorise-t-il correctement (BLOCKING/MUST FIX/IMPROVE) ?
- [ ] Le verdict est-il approprié ?

VERDICT: PASS / FAIL / PARTIAL
NOTES: _______________
```

```
TEST 1.6: /verify
> /verify
[Après avoir "fixé" quelque chose]

ÉVALUER:
- [ ] Exécute-t-il réellement les commandes de vérification ?
- [ ] Montre-t-il l'output réel (pas "les tests devraient passer") ?
- [ ] Refuse-t-il de confirmer sans evidence ?

VERDICT: PASS / FAIL / PARTIAL
NOTES: _______________
```

```
TEST 1.7: /parallel
> /parallel
J'ai 4 tâches:
1. Refactorer UserService
2. Ajouter des tests à OrderService
3. Migrer la config de YAML à ENV
4. Mettre à jour les dépendances npm

ÉVALUER:
- [ ] Analyse-t-il correctement les dépendances ?
- [ ] Identifie-t-il ce qui peut être parallélisé ?
- [ ] Dispatche-t-il réellement des agents en parallèle ?

VERDICT: PASS / FAIL / PARTIAL
NOTES: _______________
```

```
TEST 1.8: /git worktree
> /git worktree
Je veux travailler sur feature/payment-v2 en isolation.

ÉVALUER:
- [ ] Propose-t-il un emplacement intelligent ?
- [ ] Vérifie-t-il les préconditions (uncommitted changes, etc.) ?
- [ ] Crée-t-il réellement le worktree ?

VERDICT: PASS / FAIL / PARTIAL
NOTES: _______________
```

---

## PHASE 2: Stress Tests (Les limites)

```
TEST 2.1: CONTRADICTION VOLONTAIRE
> /design
Crée-moi une entité User avec des setters publics pour tous les champs.
Je veux pouvoir modifier l'email directement.

ÉVALUER:
- [ ] Résiste-t-il à la demande anti-pattern ?
- [ ] Explique-t-il pourquoi c'est problématique ?
- [ ] Propose-t-il une alternative ?
- [ ] Cède-t-il trop facilement ?

VERDICT: _______________
```

```
TEST 2.2: DEMANDE VAGUE
> /design
J'ai besoin d'un truc pour gérer les users.

ÉVALUER:
- [ ] Demande-t-il des clarifications ?
- [ ] Refuse-t-il de coder sans contexte ?
- [ ] Ou génère-t-il du code générique inutile ?

VERDICT: _______________
```

```
TEST 2.3: SCOPE CREEP
> /design
[Commencer avec une demande simple, puis ajouter:]
"Et tant qu'on y est, ajoute aussi la gestion des rôles"
"Et les permissions"
"Et l'audit log"
"Et le multi-tenant"

ÉVALUER:
- [ ] Détecte-t-il le scope creep ?
- [ ] Met-il en garde (bias protection) ?
- [ ] Ou accepte-t-il tout sans broncher ?

VERDICT: _______________
```

```
TEST 2.4: ACCÉLÉRATION DANGEREUSE
> Implémente vite un système de paiement, j'ai pas le temps pour le design.

ÉVALUER:
- [ ] Résiste-t-il à la pression ?
- [ ] Insiste-t-il sur le process /design ?
- [ ] Ou code-t-il à l'aveugle ?

VERDICT: _______________
```

```
TEST 2.5: FAUSSE EXPERTISE
> /debug
Mon API est lente. Fix ça.
[Sans donner aucune métrique, aucun contexte]

ÉVALUER:
- [ ] Demande-t-il des métriques ?
- [ ] Refuse-t-il de "fixer" sans diagnostic ?
- [ ] Ou propose-t-il des optimisations génériques au hasard ?

VERDICT: _______________
```

---

## PHASE 3: Cohérence Inter-Skills

```
TEST 3.1: WORKFLOW COMPLET
Exécuter le workflow complet sur un cas réel:
/plan → /design → /spec → [implement] → /challenge → /verify → /git

ÉVALUER:
- [ ] Les skills se complètent-ils ?
- [ ] Y a-t-il des contradictions entre skills ?
- [ ] Le handoff est-il fluide ?
- [ ] Le résultat final est-il cohérent ?

NOTES: _______________
```

```
TEST 3.2: KNOWLEDGE BASE
Vérifier que les skills utilisent réellement la knowledge base:

> Montre-moi un exemple d'Entity selon les patterns du projet

ÉVALUER:
- [ ] Référence-t-il knowledge/patterns.md ?
- [ ] Le code suit-il les exemples canoniques ?
- [ ] Ou génère-t-il du code générique ?

NOTES: _______________
```

---

## PHASE 4: Comparaison Honnête

### vs Vanilla Claude (sans plugin)

Poser la même question avec et sans le plugin:

```
QUESTION: "Crée-moi une entité Order pour un e-commerce"

SANS PLUGIN:
- Temps de réponse: ___
- Qualité du code: ___
- Questions posées: ___
- Patterns respectés: ___

AVEC PLUGIN:
- Temps de réponse: ___
- Qualité du code: ___
- Questions posées: ___
- Patterns respectés: ___

DIFFÉRENCE RÉELLE: _______________
```

### vs GitHub Copilot / Cursor

```
MÊME TÂCHE AVEC COPILOT:
- Résultat: ___
- Différence notable: ___

LE PLUGIN APPORTE-T-IL VRAIMENT PLUS ? OUI / NON / MARGINAL
```

---

## PHASE 5: Questions Assassines

Réponds honnêtement:

1. **Le plugin résout-il un vrai problème ou crée-t-il de la complexité artificielle ?**

2. **Un junior serait-il VRAIMENT plus productif avec ce plugin ou juste plus confus ?**

3. **Les skills sont-ils utilisables en conditions réelles (deadline, pression) ou trop lourds ?**

4. **La "protection contre les biais" fonctionne-t-elle vraiment ou est-ce du theatre ?**

5. **Le ROI est-il positif ? (Temps d'apprentissage vs temps gagné)**

6. **Qu'est-ce qui manque cruellement ?**

7. **Qu'est-ce qui est superflu et devrait être supprimé ?**

8. **Le plugin survivrait-il à une semaine d'utilisation intensive ou serait-il abandonné ?**

---

## PHASE 6: Verdict Final

```
┌─────────────────────────────────────────────────────────────────┐
│                    VERDICT BRUTAL                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   SCORE GLOBAL: ___/100                                         │
│                                                                  │
│   FORCES RÉELLES (pas le marketing):                            │
│   1. _______________                                            │
│   2. _______________                                            │
│   3. _______________                                            │
│                                                                  │
│   FAIBLESSES CRITIQUES:                                         │
│   1. _______________                                            │
│   2. _______________                                            │
│   3. _______________                                            │
│                                                                  │
│   BULLSHIT DÉTECTÉ:                                             │
│   - _______________                                              │
│                                                                  │
│   RECOMMANDATION:                                               │
│   [ ] Utiliser tel quel                                         │
│   [ ] Utiliser avec réserves                                    │
│   [ ] Refaire significativement                                 │
│   [ ] Abandonner                                                │
│                                                                  │
│   JUSTIFICATION:                                                │
│   _______________________________________________               │
│   _______________________________________________               │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## ANNEXE: Code de Test Volontairement Mauvais

Utiliser ce code pour tester `/challenge`:

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

**Ce code contient volontairement:**
- God class (8 dépendances, 7 méthodes, trop de responsabilités)
- SQL Injection (2 endroits)
- Password en clair
- Anemic domain (setters partout)
- Pas de final class
- Pas de strict_types
- Logique métier dans le service (pas dans l'entity)
- Pas de Value Objects (email = string)
- Pas de tests
- Exception générique
- Infrastructure dans Application layer

**/challenge DOIT détecter au minimum 10 de ces problèmes.**
