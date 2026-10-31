-- Fixture target for the mutation agent self-tests. Agent.test.lua pins this file's hash.
MutationFixture = {}

function MutationFixture.IsAtLeast(value, min)
    return value >= min
end
