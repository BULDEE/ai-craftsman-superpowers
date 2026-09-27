# Example: Production Readiness Audit

## Prompt

```
/craftsman:mlops
I have a recommendation engine running in production trained with notebooks and deployed on a single EC2 instance. Audit the MLOps maturity and recommend what to fix first.
```

## Expected Behavior

The skill follows its five-step process and delivers its Audit Template. Every
status comes from a file it inspected; what the repository cannot show is
marked `unknown` and turned into a question, never assumed.

### Step 1: Identify current maturity level

```markdown
# MLOps Audit: Recommendation Engine

Inspected: notebooks/train.ipynb, notebooks/features.ipynb, serve.py,
requirements.txt, deploy/crontab, README.md. Absent: Dockerfile, tests/,
.github/workflows/, dvc.yaml, any MLflow or W&B configuration.

## Summary
- **Maturity Level:** 0 (Manual: notebook training, manual deployment)
- **Critical Issues:** 2
- **Recommendations:** 6
```

### Step 2: Audit each pillar

Statuses: `present`, `partial`, `missing`, `unknown` (not visible in the repository).

```markdown
## Pillar Assessment

### 1. Data Management [Score: 2/10]

| Aspect | Status | Notes |
|--------|--------|-------|
| Versioning | missing | train.ipynb reads s3://.../latest.parquet, no snapshot or DVC |
| Validation | missing | no schema check before training |
| Feature Store | missing | features computed inline in features.ipynb |

**Issues:**
- A training run cannot be reproduced: its input is whatever `latest` is today

**Recommendations:**
- Version the training data (DVC) and record the version with each model

### 2. Model Development [Score: 2/10]

| Aspect | Status | Notes |
|--------|--------|-------|
| Experiment tracking | missing | metrics printed in notebook cells only |
| Reproducible training | missing | no seed set in train.ipynb |
| Model registry | missing | model saved as model.pkl next to serve.py |

**Issues:**
- Two models cannot be compared objectively, and the served one has no lineage

**Recommendations:**
- Extract train.ipynb into a seeded script and log runs to a registry (MLflow)

### 3. Deployment [Score: 1/10]

| Aspect | Status | Notes |
|--------|--------|-------|
| Model serving | partial | serve.py (Flask), started by hand per README.md |
| Containerization | missing | no Dockerfile |
| Rollback mechanism | missing | model.pkl overwritten in place |

**Issues:**
- A bad model replaces the good one with no way back but retraining

**Recommendations:**
- Containerize serve.py with the model version baked into the image tag

### 4. Monitoring [Score: 0/10]

| Aspect | Status | Notes |
|--------|--------|-------|
| Model performance metrics | missing | serve.py logs requests, not outcomes |
| Data drift detection | missing | nothing compares live inputs to training data |
| Alerting thresholds | unknown | EC2 alarms are not in the repository: ask the team |

**Issues:**
- A degrading model fails silently: nothing in the code would notice

**Recommendations:**
- Log predictions with the model version, then add drift detection (Evidently)

### 5. CI/CD [Score: 0/10]

| Aspect | Status | Notes |
|--------|--------|-------|
| Automated testing | missing | no tests/ directory |
| Model validation gates | missing | no check before model.pkl is replaced |
| Automated retraining triggers | partial | deploy/crontab reruns training every 14 days, no gate |

**Recommendations:**
- Add a validation gate: a new model must beat the current one on a held-out set

### 6. Governance [Score: 1/10]

| Aspect | Status | Notes |
|--------|--------|-------|
| Model documentation | partial | README.md describes serving, not the model |
| Audit trail | missing | no record of which data produced which model |
| Access control | unknown | EC2 access is outside the repository: ask the team |

**Recommendations:**
- Write a model card: inputs, training data version, known limits
```

### Step 3: Identify gaps and risks

```markdown
## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Model drift undetected | High | High | Prediction logging, then drift detection |
| Bad model deployed, no rollback | Medium | High | Validation gate and versioned images |
| Training not reproducible | High | Medium | Data versioning, seeded training script |
```

The two critical issues are the two High-impact rows.

### Steps 4 and 5: Prioritize improvements and create the roadmap

```markdown
## Roadmap

### Quick Wins (1-2 weeks)
- [ ] Log every prediction with the model version
- [ ] Keep the previous model.pkl and document the switch back
- [ ] Set a seed and pin requirements.txt

### Medium Term (1-3 months)
- [ ] Extract training into a script, track runs and register models (MLflow)
- [ ] Containerize serve.py, tag images with the model version
- [ ] Add a validation gate to the retraining cron job
- [ ] Version the training data (DVC)

### Long Term (3-6 months)
- [ ] Drift detection with alerting, and retraining triggered by it
```

## Key Points

- Every status cites a file inspected or its absence; what the repository cannot
  show (EC2 alarms, access control) is `unknown` with a question, not a guess
- The maturity level is set by the weakest evidence: notebook training and a
  hand-started server are Level 0 whatever the team intends
- The roadmap is ordered by risk: rollback and prediction logging come before
  a feature store, because a silent failure costs more than a slow one
- Tool names (DVC, MLflow, Evidently) come from the skill's recommendations and
  are options, not requirements
- The Summary counts match the body: two critical issues (the High-impact
  risks), six recommendations (one per pillar)
