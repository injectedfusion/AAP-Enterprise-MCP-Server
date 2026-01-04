# Fix job_tags Parameter in create_job_template Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix create_job_template to properly format job_tags and skip_tags as comma-separated strings for AWX API compatibility.

**Architecture:** The AWX API expects job_tags and skip_tags as comma-separated strings (e.g., "tag1,tag2"), but create_job_template currently passes them as Python lists, causing API validation errors. This mirrors the fix already applied to run_job in the same file.

**Tech Stack:** Python 3.11+, FastMCP, AWX REST API

---

## Background

The create_job_template function in `ansible.py:219-283` already accepts `job_tags: list[str]` and `skip_tags: list[str]` parameters, but incorrectly passes them directly to the AWX API payload as lists. The AWX API requires these as comma-separated strings.

**Current bug (lines 276-279):**
```python
if job_tags:
    payload["job_tags"] = job_tags  # Bug: passes list instead of string
if skip_tags:
    payload["skip_tags"] = skip_tags  # Bug: passes list instead of string
```

**Correct pattern from run_job (line 51):**
```python
payload["job_tags"] = ",".join(job_tags)
```

---

## Task 1: Fix job_tags and skip_tags Formatting

**Files:**
- Modify: `/Users/gabriel/repos/awx-mcp-server/ansible.py:276-279`

**Step 1: Locate the bug**

Open `ansible.py` and find the create_job_template function around line 219. Locate lines 276-279:

```python
if job_tags:
    payload["job_tags"] = job_tags
if skip_tags:
    payload["skip_tags"] = skip_tags
```

**Step 2: Apply the fix**

Replace lines 276-279 with:

```python
if job_tags:
    payload["job_tags"] = ",".join(job_tags)
if skip_tags:
    payload["skip_tags"] = ",".join(skip_tags)
```

**Rationale:** Convert Python lists to comma-separated strings matching AWX API expectations, consistent with run_job implementation.

**Step 3: Verify the change**

Run: `grep -A 2 "if job_tags:" /Users/gabriel/repos/awx-mcp-server/ansible.py`

Expected output:
```
if job_tags:
    payload["job_tags"] = ",".join(job_tags)
if skip_tags:
```

**Step 4: Commit the fix**

```bash
cd /Users/gabriel/repos/awx-mcp-server
git add ansible.py
git commit -m "fix: convert job_tags and skip_tags to comma-separated strings in create_job_template

AWX API expects job_tags and skip_tags as comma-separated strings, not lists.
This matches the existing pattern in run_job (line 51).

Fixes: Template creation with job_tags parameter
"
```

---

## Task 2: Test the Fix

**Files:**
- Test: Manual verification via Claude Code MCP integration

**Step 1: Restart Claude Code session**

The MCP server is loaded at Claude Code startup. Exit and restart Claude Code to pick up the changes.

**Step 2: Test create_job_template with job_tags**

In new Claude Code session, run:

```python
mcp__ansible__create_job_template(
    name="Test Template",
    project_id=8,
    playbook="test.yml",
    inventory_id=2,
    job_tags=["test-tag-1", "test-tag-2"]
)
```

Expected: Success response with template created, no validation errors about job_tags.

**Step 3: Verify job_tags in created template**

```python
mcp__ansible__get_job_template(template_id=<id_from_step2>)
```

Expected output should include:
```json
{
  "job_tags": "test-tag-1,test-tag-2",
  ...
}
```

**Step 4: Test skip_tags parameter**

```python
mcp__ansible__create_job_template(
    name="Test Template Skip",
    project_id=8,
    playbook="test.yml",
    inventory_id=2,
    skip_tags=["skip-tag-1", "skip-tag-2"]
)
```

Expected: Success response with skip_tags properly formatted.

**Step 5: Clean up test templates**

Delete the test templates created in steps 2 and 4 via AWX UI or API.

---

## Task 3: Update RK1 Templates with job_tags

**Files:**
- Reference: `/Users/gabriel/repos/injectedfusion/rk1-k8s-apps/ansible/site.yml:149-227`

**Step 1: Recreate or update RK1 job templates**

Now that create_job_template supports job_tags, update the 12 RK1 templates (IDs 10-21) created earlier.

For each template, use the update API or delete/recreate with proper job_tags:

- Template 10: `job_tags=["talos-cluster"]`
- Template 11: `job_tags=["cilium"]`
- Template 12: `job_tags=["coredns"]`
- Template 13: `job_tags=["split-horizon-dns"]`
- Template 14: `job_tags=["cert-manager"]`
- Template 15: `job_tags=["onepassword"]`
- Template 16: `job_tags=["metrics"]`
- Template 17: `job_tags=["rook-ceph"]`
- Template 18: `job_tags=["dragonfly"]`
- Template 19: `job_tags=["argocd"]`
- Template 20: `job_tags=["app-of-apps"]`
- Template 21: `job_tags=["validate", "ipam"]`

**Step 2: Test individual template execution**

Run one template to verify job_tags work correctly:

```python
mcp__ansible__run_job(template_id=10)  # Should only run talos-cluster role
```

Expected: Job runs with `-t talos-cluster` argument, approximately 40-45 tasks instead of 100+.

**Step 3: Commit documentation update**

```bash
cd /Users/gabriel/repos/awx-mcp-server
# Update README or docs to mention job_tags support
git add docs/
git commit -m "docs: document job_tags support in create_job_template"
```

---

## Validation Checklist

- [ ] Code change applied to lines 276-279
- [ ] Commit created with descriptive message
- [ ] Claude Code session restarted to load new MCP server code
- [ ] Test template created successfully with job_tags parameter
- [ ] Verified job_tags stored as comma-separated string in AWX
- [ ] Test template created successfully with skip_tags parameter
- [ ] Test templates cleaned up
- [ ] RK1 templates updated with proper job_tags
- [ ] Individual template execution verified

---

## Success Criteria

1. ✅ create_job_template accepts job_tags as `list[str]` and converts to comma-separated string
2. ✅ create_job_template accepts skip_tags as `list[str]` and converts to comma-separated string
3. ✅ AWX API accepts the formatted job_tags without validation errors
4. ✅ Created templates display job_tags correctly in AWX UI
5. ✅ Running templates with job_tags only executes tagged roles/tasks

---

## Known Issues / Edge Cases

**Empty lists:** If user passes `job_tags=[]`, the `if job_tags:` check will be False, so job_tags won't be added to payload. This is correct behavior.

**None vs empty list:** Function signature uses `job_tags: list[str] = None`, so None is the default. This is handled correctly by the `if job_tags:` check.

**Single tag:** `job_tags=["single"]` becomes `"single"` which is correct (no trailing comma).

**Special characters:** Tags with commas would break the format, but Ansible tags don't allow commas, so this isn't a concern.

---

## References

- AWX API Documentation: Job Templates endpoint expects string for job_tags/skip_tags
- Existing fix in `run_job` (ansible.py:51): `payload["job_tags"] = ",".join(job_tags)`
- AWX MCP server fix plan from 2026-01-04 session (task_plan.md)
