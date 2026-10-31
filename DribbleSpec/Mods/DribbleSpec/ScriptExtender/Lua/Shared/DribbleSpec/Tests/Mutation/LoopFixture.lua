-- Loop target for the mutation agent timeout self-tests: mutant `<` to `>=` never ends. Agent.test.lua pins this file's hash.
MutationLoopFixture = {}

function MutationLoopFixture.Approach(value, target)
    while value ~= target do
        if value < target then
            value = value + 1
        else
            value = value - 1
        end
    end
    return value
end
