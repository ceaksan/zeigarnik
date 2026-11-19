# Recipe Box Implementation Plan

**Spec:** `docs/superpowers/specs/2026-01-10-recipe-box-design.md` (authority). Parent: `docs/superpowers/specs/2026-01-05-kitchen-tools-design.md` sections 2 and 3.

## Tasks

### Task 1: Recipe schemas and validator

**Files:**
- Create: `schema/v1/recipe.schema.json`, `ingredient.schema.json`, `shopping-list.schema.json`
- Create: `schema/v1/examples/recipe.soup.json`, `recipe.salad.json`, `ingredient.*.json` (one per unit), `shopping-list.ok.json`
- Create: `schema/check_schema.py`, `schema/test_check_schema.py`

**Interfaces:**
- Produces: `load_schema(name: str) -> dict`; `validate(doc, schema: dict) -> list[str]` (errors as `"<json pointer>: <reason>"`, empty when valid).

- [ ] **Step 1: Write the failing tests** in `schema/test_check_schema.py`

```python
def test_examples_validate():
    for p in sorted(EXAMPLES.glob("*.json")):
        assert validate(json.loads(p.read_text("utf-8")), load_schema(p.name.split(".")[0])) == [], p.name

def test_recipe_rejects_extra_property():
    r = example("recipe.soup") | {"extra": True}
    assert any("/extra" in x for x in validate(r, load_schema("recipe")))
```

- [ ] **Step 2: Run, expect FAIL** `python3 -I schema/test_check_schema.py` (validator missing).
- [ ] **Step 3: Write the three schemas** with `additionalProperties: false` on every object, and one example per schema.
- [ ] **Step 4: Implement `schema/check_schema.py`.**
- [ ] **Step 5: Run, expect PASS** `python3 -I schema/test_check_schema.py`.
- [ ] **Step 6: Commit** `git add schema && git commit -m "feat(schema): recipe schemas and validator"`
