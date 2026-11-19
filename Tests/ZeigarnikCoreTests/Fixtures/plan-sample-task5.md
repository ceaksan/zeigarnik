# Recipe Box plan excerpt

### Task 5: Recipe CLI and the schema test

**Files:**
- Create: `cli/recipes.py`, `cli/test_recipes.py`, `cli/test_schema_examples.py`

**Interfaces:**
- Consumes: `store.load_recipes`, `shopping.build_list(recipes, servings=2)`, `schema/check_schema.validate`.
- Produces:
  - `recipes.list_recipes(tag: str | None) -> list[dict]`.
  - `recipes.main(argv=None, stdout=None) -> int`. Prints recipes as JSON lines and returns 0, or 2 for an unknown command.

Behaviour:
- **list** prints every recipe, optionally filtered by tag.
- **show** prints one recipe with scaled ingredients.

- [ ] **Step 1: Write the failing tests** in `cli/test_recipes.py` and `cli/test_schema_examples.py`

```python
def test_list_output_matches_schema():
    for line in run(["list"]).splitlines():
        assert validate(json.loads(line), load_schema("recipe")) == []
```

- [ ] **Step 2: Run, expect FAIL** `python3 -I cli/test_recipes.py`.
- [ ] **Step 3: Implement `cli/recipes.py`.**
- [ ] **Step 4: Run, expect PASS** both files.
- [ ] **Step 5: Commit** `git add cli && git commit -m "feat(cli): recipe CLI (list, show) and schema test"`
