-- Victims for the mutation recovery check: their test fails while the DirtyFixture latch is open.
MutationDirtyVictimFixture = {}

function MutationDirtyVictimFixture.Double(x)
    return x * 2
end

function MutationDirtyVictimFixture.Same(x)
    return x + 0
end
