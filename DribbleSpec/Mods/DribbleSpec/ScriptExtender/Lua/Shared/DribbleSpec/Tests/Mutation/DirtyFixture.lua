-- Shared state for the mutation recovery check: mutant `false` to `true` in Close leaves the latch open.
MutationDirtyFixture = { open = false }

function MutationDirtyFixture.Close()
    MutationDirtyFixture.open = false
end
