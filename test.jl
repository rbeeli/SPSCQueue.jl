
include("clock.jl");

function format_with_commas(n::Integer)
    s = string(n)
    parts = []
    while length(s) > 3
        push!(parts, s[end-2:end])
        s = s[1:end-3]
    end
    push!(parts, s)
    join(reverse(parts), ",")
end

