# Example: Debug Memory Leak in Node.js

## Prompt

```
/craftsman:debug
I have a memory leak in my Node.js application.
The heap increases by 50MB every hour.
No error messages in logs.
```

## Expected Behavior

### Phase 1: Clarification Questions

Claude MUST ask:

```markdown
## Problem Clarification

1. **Expected behavior:** Stable memory usage around X MB
2. **Observed behavior:** Heap grows 50MB/hour until OOM
3. **Reproduction:** Happens in production only? Dev too?
4. **Timeline:** When did it start? Recent deployments?
5. **Environment:** Node version? Hosting? (Lambda, EC2, K8s?)
```

### Phase 2: Hypotheses

After user provides context:

```markdown
## Hypotheses

| # | Hypothesis | Probability | Why |
|---|------------|-------------|-----|
| 1 | Event listener not removed | 40% | Common in long-running processes |
| 2 | Global cache growing unbounded | 30% | No TTL or size limit |
| 3 | Closure capturing large objects | 20% | Callbacks holding references |
| 4 | External library leak | 10% | Less common but possible |
```

### Phase 3: Investigation (ReAct Loop)

```markdown
## Investigation Log

### Cycle 1
**THOUGHT:** Start with heap snapshot to identify what's growing
**ACTION:** Check if project has memory profiling set up
**OBSERVATION:** No profiling configured
**CONCLUSION:** Need to add --inspect flag and heap snapshots

### Cycle 2
**THOUGHT:** Look for obvious patterns - event listeners, caches
**ACTION:** Search for `.on(` and cache patterns in codebase
**OBSERVATION:** Found Redis client with event listeners in loop
**CONCLUSION:** High probability - listener added on each request

### Cycle 3
**THOUGHT:** Verify this is the cause
**ACTION:** Read the file with Redis client setup
**OBSERVATION:** `redis.on('error')` called inside request handler
**CONCLUSION:** CONFIRMED - new listener added per request
```

### Phase 4: Root Cause

```markdown
## Root Cause

**Location:** src/services/cache.ts:45
**Cause:** `redis.on('error', ...)` inside request handler adds listener per request
**Evidence:** After 1000 requests, `process._getActiveHandles().length` shows 1000+ listeners
**Why it wasn't caught:** No listener leak detection in tests
```

### Phase 5: Fix

```diff
// Before (WRONG)
app.get('/api/data', async (req, res) => {
-  redis.on('error', (err) => console.error(err));
  const data = await redis.get('key');
  res.json(data);
});

// After (CORRECT)
+ redis.on('error', (err) => console.error(err)); // Once at init
app.get('/api/data', async (req, res) => {
  const data = await redis.get('key');
  res.json(data);
});
```

## Test This Example

1. Create a Node.js project with intentional listener leak
2. Run `/craftsman:debug` with the prompt
3. Verify Claude follows ReAct pattern without jumping to fixes
