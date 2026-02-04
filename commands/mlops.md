---
name: mlops
description: Audit ML projects for production readiness. Use when reviewing ML pipelines, deployments, or infrastructure against MLOps best practices.
---

# /craftsman:mlops - ML Production Readiness Audit

Audit ML projects against production best practices.

## MLOps Maturity Levels

```
Level 0: Manual           - Notebooks, manual deployment
Level 1: ML Pipeline      - Automated training, manual deploy
Level 2: CI/CD for ML     - Automated training + deployment
Level 3: Full MLOps       - Automated retraining, monitoring, feedback
```

## Six Pillars of MLOps

### 1. Data Management

```markdown
## Data Checklist

- [ ] Data versioning (DVC, Delta Lake)
- [ ] Data validation (Great Expectations)
- [ ] Feature store (Feast, Tecton)
- [ ] Data lineage tracking
- [ ] Privacy compliance (PII handling)
```

### 2. Model Development

```markdown
## Development Checklist

- [ ] Experiment tracking (MLflow, W&B)
- [ ] Reproducible training (seeds, configs)
- [ ] Model registry
- [ ] Baseline comparisons
- [ ] Hyperparameter tuning automation
```

### 3. Model Deployment

```markdown
## Deployment Checklist

- [ ] Model serving (TorchServe, TF Serving, FastAPI)
- [ ] Containerization (Docker)
- [ ] Orchestration (K8s, ECS)
- [ ] A/B testing capability
- [ ] Canary deployments
- [ ] Rollback mechanism
```

### 4. Monitoring

```markdown
## Monitoring Checklist

- [ ] Model performance metrics
- [ ] Data drift detection
- [ ] Concept drift detection
- [ ] Prediction latency
- [ ] Resource utilization
- [ ] Alerting thresholds
```

### 5. CI/CD for ML

```markdown
## CI/CD Checklist

- [ ] Automated testing (unit, integration)
- [ ] Model validation gates
- [ ] Automated retraining triggers
- [ ] Shadow deployments
- [ ] Feature flag integration
```

### 6. Governance

```markdown
## Governance Checklist

- [ ] Model documentation
- [ ] Bias/fairness audits
- [ ] Explainability (SHAP, LIME)
- [ ] Audit trail
- [ ] Access control
```

## Audit Template

```markdown
# MLOps Audit: [Project Name]

## Summary
- **Maturity Level:** [0-3]
- **Critical Issues:** [Count]
- **Recommendations:** [Count]

## Pillar Assessment

### 1. Data Management [Score: X/10]

| Aspect | Status | Notes |
|--------|--------|-------|
| Versioning | ✅/⚠️/❌ | |
| Validation | ✅/⚠️/❌ | |
| Feature Store | ✅/⚠️/❌ | |

**Issues:**
- [Issue 1]
- [Issue 2]

**Recommendations:**
- [Recommendation 1]

### 2. Model Development [Score: X/10]
[Same structure]

### 3. Deployment [Score: X/10]
[Same structure]

### 4. Monitoring [Score: X/10]
[Same structure]

### 5. CI/CD [Score: X/10]
[Same structure]

### 6. Governance [Score: X/10]
[Same structure]

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Model drift undetected | High | High | Implement monitoring |
| Data pipeline failure | Medium | High | Add validation |

## Roadmap

### Quick Wins (1-2 weeks)
- [ ] [Action 1]
- [ ] [Action 2]

### Medium Term (1-3 months)
- [ ] [Action 1]
- [ ] [Action 2]

### Long Term (3-6 months)
- [ ] [Action 1]
- [ ] [Action 2]
```

## Common Anti-Patterns

| Anti-Pattern | Problem | Solution |
|--------------|---------|----------|
| Notebook-to-prod | No reproducibility | Pipeline extraction |
| No versioning | Can't reproduce | DVC + MLflow |
| Train/serve skew | Different preprocessing | Feature store |
| No monitoring | Silent failures | Drift detection |
| Manual deployment | Slow, error-prone | CI/CD pipeline |

## Tool Recommendations

| Category | Tools |
|----------|-------|
| Experiment Tracking | MLflow, Weights & Biases, Neptune |
| Data Versioning | DVC, Delta Lake, LakeFS |
| Feature Store | Feast, Tecton, Hopsworks |
| Model Serving | BentoML, Ray Serve, Seldon |
| Monitoring | Evidently, WhyLabs, Arize |
| Orchestration | Kubeflow, Airflow, Prefect |

## Process

1. **Identify current maturity level**
2. **Audit each pillar**
3. **Identify gaps and risks**
4. **Prioritize improvements**
5. **Create actionable roadmap**
