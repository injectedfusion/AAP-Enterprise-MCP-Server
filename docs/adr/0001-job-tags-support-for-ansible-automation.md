# Job Tags Support for Ansible Automation Platform Integration

## Status

accepted

## Context and Problem Statement

The AWX MCP Server enables AI assistants to interact with Ansible Automation Platform (AAP). Users need to run specific subsets of Ansible playbooks by filtering tasks using tags, rather than running entire playbooks every time.

How should the MCP server support Ansible's tag filtering capabilities for both template creation and job execution?

## Decision Drivers

* **Blocking RK1 workflow** - Cannot create phase-specific job templates for 12-phase cluster restoration playbook
* **API incompatibility** - AWX API expects comma-separated strings, MCP server passed Python lists
* **Workflow efficiency** - Running all 100+ tasks when only needing 7 specific tasks is wasteful
* **Template flexibility** - Need to create specialized templates for common operations

## Considered Options

* **Option 1: Fix MCP server to convert lists to comma-separated strings**
* **Option 2: Keep lists, require users to manually format strings**
* **Option 3: Support both lists and strings with type checking**
* **Option 4: Create separate functions for tagged vs untagged execution**

## Decision Outcome

Chosen option: **Option 1: Fix MCP server**, because it provides the best user experience while maintaining API compatibility internally.

### Implementation

**File:** `ansible.py`

**Change 1: `create_job_template` (lines 276-279)**
```python
# Before (broken)
if job_tags:
    payload["job_tags"] = job_tags  # Passes list - API rejects

# After (fixed)
if job_tags:
    payload["job_tags"] = ",".join(job_tags)  # Converts to "tag1,tag2"
if skip_tags:
    payload["skip_tags"] = ",".join(skip_tags)
```

**Change 2: `run_job` (lines 47-54)** - Bonus enhancement
```python
async def run_job(template_id: int, extra_vars: dict = {}, job_tags: list[str] = None) -> Any:
    """Run a job template by ID, optionally with extra_vars and job_tags."""
    payload = {"extra_vars": extra_vars}
    if job_tags:
        payload["job_tags"] = ",".join(job_tags)
    return await make_request(...)
```

### Consequences

* Good, because users pass natural Python lists `job_tags=["tag1", "tag2"]`
* Good, because MCP server handles AWX API string requirement internally
* Good, because enables granular execution control (7 tasks vs 100+)
* Good, because supports both `job_tags` (run only) and `skip_tags` (exclude)
* Good, because runtime tag override via `run_job` parameter
* Good, because consistent `",".join()` pattern across both functions
* Good, because backward compatible (existing calls without tags work)
* Neutral, because empty lists are ignored (correct behavior)
* Bad, because no validation that tags exist in playbook (delegated to Ansible)

## RK1 Use Case: 12-Phase Cluster Restoration

The immediate driver was managing a 12-phase Kubernetes cluster restoration playbook:

```yaml
# ansible/site.yml
roles:
  - role: talos-cluster      # Phase 1
    tags: [talos-cluster]
  - role: networking          # Phase 2
    tags: [cilium]
  - role: coredns            # Phase 3
    tags: [coredns]
  # ... 9 more phases
```

### Before: Monolithic Execution
- Template ID 9: "TuringPi Site Playbook"
- Runs all 12 phases (~100+ tasks)
- No way to run individual phases

### After: Individual Phase Templates
- Template ID 24: "RK1 - 01 Talos Cluster" → `job_tags=["talos-cluster"]`
- Template ID 25: "RK1 - 02 Networking" → `job_tags=["cilium"]`
- Template ID 26: "RK1 - 03 CoreDNS" → `job_tags=["coredns"]`
- ... 9 more phase-specific templates

### Measured Impact

**Job 253 Test Execution:**
- Command: `ansible-playbook -t talos-cluster ansible/site.yml`
- Tasks executed: 7 (filtered)
- Tasks without tags: 100+ (all phases)
- Reduction: 93% fewer tasks
- Result: ✅ Verified tag filtering works end-to-end

## Validation

### Template Creation Test
```python
create_job_template(
    name="RK1 - 01 Talos Cluster Sync",
    project_id=8,
    playbook="ansible/site.yml",
    inventory_id=2,
    job_tags=["talos-cluster"]
)
# Result: Template ID 24 created with job_tags="talos-cluster" ✅
```

### Runtime Override Test
```python
run_job(
    template_id=24,
    job_tags=["talos-cluster", "validate"]  # Override template tags
)
# Result: Job runs with combined tags ✅
```

## Pros and Cons of the Options

### Option 1: Fix MCP server

* Good, because natural Python list interface for users
* Good, because handles AWX quirk internally
* Good, because consistent with MCP patterns
* Bad, because requires MCP server code change

### Option 2: Keep lists, require manual formatting

* Good, because no code changes needed
* Bad, because terrible UX: `job_tags="tag1,tag2"` instead of `["tag1", "tag2"]`
* Bad, because breaks Python conventions

### Option 3: Support both lists and strings

* Good, because maximum flexibility
* Bad, because unnecessary complexity
* Bad, because two ways to do the same thing

### Option 4: Create separate functions

* Good, because explicit separation of concerns
* Bad, because violates DRY principle
* Bad, because increases API surface

## Workflow Pattern Enabled

This fix enables the **Individual Phase Template** pattern:

```
Monolithic Template (Legacy)
├─ Template ID 9: "TuringPi Site Playbook"
└─ Runs all 12 phases (~100+ tasks)

Individual Phase Templates (New)
├─ Template ID 24: "RK1 - 01 Talos Cluster" → tags: ["talos-cluster"]
├─ Template ID 25: "RK1 - 02 Networking"    → tags: ["cilium"]
├─ Template ID 26: "RK1 - 03 CoreDNS"       → tags: ["coredns"]
└─ ... 9 more phase-specific templates
```

**Benefits:**
- Run individual phases without triggering entire playbook
- Clear naming indicates what each template does
- AWX UI shows granular job history per phase
- Future: Compose workflows chaining specific phases

## More Information

- Implementation plan: `docs/plans/2026-01-04-fix-job-tags-in-create-job-template.md`
- Git commit: `049babe` - "fix: convert job_tags and skip_tags to comma-separated strings"
- Testing: AWX Job 253 verified tag filtering works end-to-end
- AWX API docs: [Job Templates API](https://docs.ansible.com/automation-controller/latest/html/controllerapi/api_ref.html#/Job_Templates)
- Related: Future ADR for workflow template composition (chaining individual phases)
- Pattern reference: `run_job:51` already had correct implementation (used as fix template)
