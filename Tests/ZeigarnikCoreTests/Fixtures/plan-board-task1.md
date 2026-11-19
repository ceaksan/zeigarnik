# Garden Planner Implementation Plan

> **For agentic workers:** steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a bed hold several plantings per season and show them on one board.


## Tasks

### Task 1: Shared models, storage format, ADR opened

**Files:**
- Create: `PlannerKit/Models/Planting.swift`
- Delete: `PlannerKit/Models/Crop.swift`
- Modify: `PlannerKit/Models/Bed.swift`, `PlannerKit/Storage/FileFormat.swift:3-21`, `PlannerKit/Storage/Paths.swift`
- Test: `PlannerKitTests/ModelsTests.swift` (replace `CropTests`)
- Create: `docs/adr/ADR-001-plantings-per-bed.md`, status **Proposed**, Files Changed filled in Task 7

**Interfaces:**
- Produces: `Planting(id: UUID, bedId: UUID, plant: String, sownOn: Date)`; `Bed.plantings: [Planting]`.

- [ ] **Step 1: Write the failing tests** in `PlannerKitTests/ModelsTests.swift`

```swift
@Test func bedKeepsPlantingsInSowingOrder() {
    var bed = Bed(name: "North")
    bed.add(Planting(plant: "Beans", sownOn: day(2)))
    bed.add(Planting(plant: "Peas", sownOn: day(1)))
    #expect(bed.plantings.map(\.plant) == ["Peas", "Beans"])
}
```

- [ ] **Step 2: Run, expect FAIL** `swift test --filter ModelsTests`.
- [ ] **Step 3: Implement** `Planting` and `Bed.add`.
- [ ] **Step 4: Run, expect PASS** `swift test --filter ModelsTests`.
- [ ] **Step 5: Commit** `git add PlannerKit PlannerKitTests docs/adr && git commit -m "feat(models): plantings per bed"`
