# Example: Support Triage Agent

## Prompt

```
/craftsman:agent-design
I need to build an autonomous agent that triages support tickets into priority buckets based on issue severity, impact, and SLA requirements.
```

## Expected Behavior

The skill fills its Agent Design Template: purpose and capabilities, the tools
with a risk level, one section per 3P phase plus Reflect, the safety
constraints, and an example interaction. Failure modes each get a recovery
path, as the outcome contract requires.

```markdown
# Agent Design: Support Triage

## Purpose
Assign each incoming ticket a priority bucket (P1 to P4) and a queue, from its
severity, its impact and the customer's SLA, so that no SLA-bound ticket waits
unread.

## Capabilities
- [ ] Classify the ticket intent (incident, bug, question, billing, feature request)
- [ ] Extract the affected component, error codes and customer tier
- [ ] Compute a priority from severity, impact and SLA deadline
- [ ] Route the ticket to a queue with a written justification

## Tools Available

| Tool | Purpose | Risk Level |
|------|---------|------------|
| read_ticket | Read the ticket body, metadata and customer tier | Low |
| search_similar_tickets | Retrieve resolved tickets with close symptoms | Low |
| read_status_page | Check whether an incident is already declared | Low |
| set_priority_and_queue | Write the bucket, the queue and the justification | Medium |
| page_on_call | Alert the on-call engineer | High |

No tool can close, reply to or delete a ticket: triage only classifies.

## Workflow

### Perceive
- Inputs: ticket title and body, customer tier, SLA deadline, declared incidents
- Extraction: intent, component, error codes, number of users affected, ambiguities
  (no reproduction steps, conflicting severity words)

### Plan
- Decomposition strategy: read ticket, then similar tickets and status page in
  parallel (independent), then score, then route
- Tool selection criteria: read-only tools first; a write only once the priority
  and its justification exist

### Perform
- Execution strategy: sequential with one parallel step
- Error handling:

| Failure | Recovery |
|---------|----------|
| read_ticket fails | Retry once, then leave the ticket in the untriaged queue and log it |
| search_similar_tickets returns nothing | Score from the ticket alone, mark confidence low |
| read_status_page unavailable | Do not assume "no incident": treat as unknown, route P2 at least |
| Intent or severity ambiguous | Route to the human triage queue with the ambiguity named, never guess |
| set_priority_and_queue rejected | Stop, keep the ticket untriaged, alert the support lead |

### Reflect
- Success criteria: the ticket has a bucket, a queue and a justification before
  its SLA deadline, and the human who picks it up does not re-prioritize it
- Learning: re-prioritizations by humans are recorded as labeled examples for
  the next review of the scoring rules

## Safety Constraints

- [ ] Confirmation required for: page_on_call (a human confirms before anyone is woken up)
- [ ] Rate limits: one write per ticket per run; a ticket already triaged is not re-triaged
- [ ] Sandboxing: the agent's credentials allow reads plus the priority and queue fields only
- [ ] Audit logging: every decision is logged with the inputs and the justification

## Example Interaction

User: "Checkout returns 500 for all our users since 09:10, enterprise plan."

PERCEIVE:
- Intent: incident
- Entities: component checkout, error 500, tier Enterprise, all users affected

PLAN:
1. read_ticket
2. search_similar_tickets and read_status_page in parallel
3. score, then set_priority_and_queue
4. propose page_on_call

PERFORM:
- Tool: read_status_page
- Result: no incident declared for checkout

REFLECT:
- Success: yes, P1 in the incident queue with justification
- Adjustment: page_on_call proposed, waiting for human confirmation

Response: "P1, incident queue: checkout down for all users of an Enterprise
account, no incident declared yet. Paging on-call needs your confirmation."
```

## Key Points

- The deliverable is the skill's Agent Design Template, filled in: purpose,
  capabilities, tools with a risk level, the four phases, safety constraints,
  and an example interaction
- Tools are scoped to the job: reads are low risk, the single write is medium,
  paging a human is high and requires confirmation, and nothing can close or
  answer a ticket
- Every failure mode has a recovery path; an unknown state (status page down,
  ambiguous severity) is never read as the reassuring one
- Perceive flags ambiguities and routes them to a human instead of assuming,
  even though the agent is meant to run unattended
- Reflect defines success in observable terms (bucket set before the SLA
  deadline, not re-prioritized by a human), not as a claimed accuracy figure
