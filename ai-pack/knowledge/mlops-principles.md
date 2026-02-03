# MLOps Principles

## What is MLOps?

MLOps = DevOps + ML. It's the practice of deploying and maintaining ML models in production reliably and efficiently.

## The 6 Core Principles

### 1. Automation

**Maturity Levels:**

| Level | Description | Characteristics |
|-------|-------------|-----------------|
| 0 | Manual | Scripts in notebooks, manual deployment |
| 1 | ML Pipeline | Automated training, manual deployment |
| 2 | CI/CD Pipeline | Automated training + deployment |
| 3 | CT (Continuous Training) | Automated retraining on triggers |

**Automation Targets:**
- Data validation
- Model training
- Model evaluation
- Model deployment
- Monitoring & alerting

### 2. Versioning

**What to Version:**

| Asset | Tool | Purpose |
|-------|------|---------|
| Code | Git | Track algorithm changes |
| Data | DVC, Delta Lake | Reproducibility |
| Model | MLflow, W&B | Rollback capability |
| Config | Git + YAML | Environment parity |
| Environment | Docker | Dependency isolation |

**Model Registry Pattern:**
```
models/
├── fraud-detector/
│   ├── v1.0.0/  (production)
│   ├── v1.1.0/  (staging)
│   └── v1.2.0/  (development)
```

### 3. Experiment Tracking

**What to Track:**

| Category | Examples |
|----------|----------|
| Hyperparameters | learning_rate, batch_size, epochs |
| Metrics | accuracy, F1, AUC-ROC, loss |
| Artifacts | model weights, plots, configs |
| Code version | git commit SHA |
| Data version | DVC hash, dataset ID |

**Tools:**
- MLflow (open source, self-hosted)
- Weights & Biases (SaaS, collaboration)
- Neptune.ai (SaaS, enterprise)
- Comet ML (SaaS)

### 4. Testing

**ML Testing Pyramid:**

```
        /\
       /E2E\        Model in production behavior
      /------\
     /Integration\   Pipeline components together
    /-------------\
   /     Unit      \  Individual functions
  /-----------------\
```

| Test Type | What it Tests | Example |
|-----------|---------------|---------|
| Unit | Functions, transformations | `test_normalize_features()` |
| Integration | Pipeline stages | Training → Evaluation flow |
| Model | Predictions, fairness | Accuracy thresholds, bias |
| System | End-to-end | API response with real data |
| Regression | No degradation | Compare to baseline |
| Stress | Load handling | 1000 req/s inference |

**Critical Model Tests:**
- [ ] Accuracy meets threshold
- [ ] No data leakage
- [ ] Fairness across groups
- [ ] Inference latency acceptable
- [ ] Memory usage within limits

### 5. Monitoring

**Monitoring Layers:**

| Layer | Metrics | Tools |
|-------|---------|-------|
| System | CPU, memory, latency | Prometheus, Grafana |
| Model | Accuracy, predictions distribution | Evidently, WhyLabs |
| Data | Schema, statistics, drift | Great Expectations |
| Business | Conversion, revenue impact | Custom dashboards |

**Drift Types:**

| Drift Type | Definition | Detection |
|------------|------------|-----------|
| Data drift | Input distribution changes | KS test, PSI |
| Concept drift | Relationship X→Y changes | Prediction monitoring |
| Label drift | Target distribution changes | Label statistics |

**Alert Triggers:**
- Accuracy drops below threshold
- Prediction distribution shifts
- Latency exceeds SLA
- Data validation failures
- Resource exhaustion

### 6. Reproducibility

**Requirements for Reproducibility:**

| Requirement | Implementation |
|-------------|----------------|
| Same code | Git versioning |
| Same data | Data versioning (DVC) |
| Same environment | Docker containers |
| Same randomness | Fixed seeds everywhere |
| Same config | Version controlled YAML |

**Seed Pattern:**
```python
import random
import numpy as np
import torch

def set_seed(seed: int = 42) -> None:
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    torch.cuda.manual_seed_all(seed)
    torch.backends.cudnn.deterministic = True
```

## MLOps Checklist

### Pre-Production
- [ ] Data versioned (DVC/Delta Lake)
- [ ] Experiments tracked (MLflow/W&B)
- [ ] Model registered with version
- [ ] Tests pass (unit, integration, model)
- [ ] Documentation complete
- [ ] Reproducibility verified

### Production
- [ ] CI/CD pipeline configured
- [ ] Monitoring dashboards live
- [ ] Alerts configured
- [ ] Rollback procedure documented
- [ ] A/B testing or shadow mode ready
- [ ] Data validation in pipeline

### Post-Production
- [ ] Drift monitoring active
- [ ] Retraining triggers defined
- [ ] Performance baselines established
- [ ] Feedback loop implemented
- [ ] Incident runbooks ready

## Anti-Patterns

| Anti-Pattern | Problem | Solution |
|--------------|---------|----------|
| Notebook to production | Unreproducible, untestable | Refactor to modules |
| No versioning | Can't rollback or reproduce | Version everything |
| Manual deployment | Error-prone, slow | Automate CI/CD |
| No monitoring | Silent failures | Implement observability |
| Training-serving skew | Different results | Use same preprocessing |
